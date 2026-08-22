import { Fragment, type ReactNode } from 'react'

const LOWERCASE_AVOGADRO_OCR_TOKEN = `N${String.fromCodePoint(0x2090)}`
const NAMED_SUBSCRIPT_TOKEN = new RegExp(`(N_A|N_a|${LOWERCASE_AVOGADRO_OCR_TOKEN}|V_m|K_?(?:sp|c|p|a|b|w))`, 'g')
const UNIT_EXPONENT = /^(mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?\s*\^?\s*([-−－])\s*(\d+)$/
const POWER_TOKEN = /^(10|c\([A-D]\))\s*\^\s*([-−－]?\s*\d+|[a-d])$/
const SPECIAL_TOKEN = /(?:\b(?:10|c\([A-D]\))\s*\^\s*(?:[-−－]?\s*\d+|[a-d]))|(?:\b(?:mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?\s*\^?\s*[-−－]\s*\d+)|(?:\b(?:\d+)?(?:[A-Z][a-z]?|\((?:[A-Z][a-z]?)+\d*\))+(?:\d+)?(?:\^\d*[+-]|[+-])?)/g

function isFormulaToken(value: string) {
  return /\d|[+-]/.test(value)
}

function renderFormulaBody(value: string): ReactNode[] {
  const children: ReactNode[] = []
  let text = ''
  let index = 0
  let hasAtom = false

  const flush = () => {
    if (text) {
      children.push(text)
      text = ''
    }
  }

  while (index < value.length) {
    const character = value[index]
    if (/\d/.test(character)) {
      let end = index + 1
      while (end < value.length && /\d/.test(value[end])) end += 1
      const digits = value.slice(index, end)
      if (hasAtom) {
        flush()
        children.push(<sub key={`sub-${index}`}>{digits}</sub>)
      } else {
        text += digits
      }
      index = end
      continue
    }

    text += character
    hasAtom = character === ')' || /[A-Za-z]/.test(character) || hasAtom
    index += 1
  }
  flush()
  return children
}

function splitCharge(value: string) {
  const explicit = value.match(/\^(\d*)([+-])$/)
  if (explicit) return { body: value.slice(0, -explicit[0].length), digits: explicit[1], sign: explicit[2] }

  const sign = value.match(/([+-])$/)
  if (!sign) return { body: value, digits: '', sign: '' }

  const rawBody = value.slice(0, -sign[0].length)
  const singleElementCharge = rawBody.match(/^(?:[A-Z][a-z]?)(\d+)$/)
  if (singleElementCharge) return { body: rawBody.slice(0, -singleElementCharge[1].length), digits: singleElementCharge[1], sign: sign[1] }
  return { body: rawBody, digits: '', sign: sign[1] }
}

function renderFormulaToken(value: string, key: string) {
  const charge = splitCharge(value)
  const renderedBody = <>{renderFormulaBody(charge.body)}{charge.sign && <sup>{`${charge.digits}${charge.sign}`}</sup>}</>

  return <span className="chem-symbol" aria-label={value} key={key}>{renderedBody}</span>
}

function renderUnitToken(value: string, key: string) {
  const match = value.match(UNIT_EXPONENT)
  if (!match) return value
  return <span className="chem-symbol" key={key} aria-label={value}>{match[1]}<sup>{`${match[2].replace(/[−－-]/, '−')}${match[3]}`}</sup></span>
}

function renderPowerToken(value: string, key: string) {
  const match = value.match(POWER_TOKEN)
  if (!match) return value
  return <span className="chem-symbol" key={key} aria-label={value}>{match[1]}<sup>{match[2].replace(/\s/g, '').replace(/[−－-]/, '−')}</sup></span>
}

function renderChemistryText(value: string) {
  const children: ReactNode[] = []
  let lastIndex = 0
  let tokenIndex = 0

  // A fresh matcher per ChemText call avoids sharing mutable lastIndex state
  // across React renders.
  for (const match of value.matchAll(new RegExp(SPECIAL_TOKEN.source, 'g'))) {
    const token = match[0]
    const unitMatch = UNIT_EXPONENT.exec(token)
    const powerMatch = POWER_TOKEN.exec(token)
    if (!isFormulaToken(token) && !unitMatch && !powerMatch) {
      // SPECIAL_TOKEN also sees plain element symbols such as Ca. Consume that
      // match explicitly instead of leaving it for the trailing slice. This
      // keeps the renderer deterministic when many ChemText components render
      // concurrently and guarantees that every regex match advances output.
      children.push(value.slice(lastIndex, match.index))
      children.push(token)
      lastIndex = match.index + token.length
      continue
    }

    children.push(value.slice(lastIndex, match.index))
    children.push(unitMatch
      ? renderUnitToken(token, `unit-${tokenIndex}`)
      : powerMatch
      ? renderPowerToken(token, `power-${tokenIndex}`)
      : renderFormulaToken(token, `formula-${tokenIndex}`))
    tokenIndex += 1
    lastIndex = match.index + token.length
  }
  children.push(value.slice(lastIndex))
  return children
}

/**
 * Chemistry copy is stored as plain text. This renderer keeps the source
 * content intact while restoring the visual notation that plain OCR/database
 * text loses: formula subscripts, ionic charges, and unit exponents.
 */
export function ChemText({ children }: { children: string }) {
  const parts = children.split(NAMED_SUBSCRIPT_TOKEN)
  return <>{parts.map((part, index) => <Fragment key={`${index}-${part}`}>
    {part === 'N_A' || part === 'N_a' || part === LOWERCASE_AVOGADRO_OCR_TOKEN
      ? <span className="chem-symbol chem-avogadro" aria-label="N 下标 A"><span aria-hidden="true">N</span><sub aria-hidden="true">A</sub></span>
      : part === 'V_m'
      ? <span className="chem-symbol chem-molar-volume" aria-label="V 下标 m"><span aria-hidden="true">V</span><sub aria-hidden="true">m</sub></span>
      : /^K_?(?:sp|c|p|a|b|w)$/.test(part)
      ? <span className="chem-symbol chem-equilibrium-constant" aria-label={`K 下标 ${part.replace(/^K_?/, '')}`}><span aria-hidden="true">K</span><sub aria-hidden="true">{part.replace(/^K_?/, '')}</sub></span>
      : renderChemistryText(part)}
  </Fragment>)}</>
}
