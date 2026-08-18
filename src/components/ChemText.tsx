import { Fragment, type ReactNode } from 'react'

const AVOGADRO_TOKEN = 'N_A'
const UNIT_EXPONENT = /^(mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?([-−]\d+)$/
const SPECIAL_TOKEN = /(?:\b(?:mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?[-−]\d+)|(?:\b(?:\d+)?(?:[A-Z][a-z]?|\((?:[A-Z][a-z]?)+\d*\))+(?:\d+)?(?:\^\d*[+-]|[+-])?)/g

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
  return <span className="chem-symbol" key={key} aria-label={value}>{match[1]}<sup>{match[2].replace('-', '−')}</sup></span>
}

function renderChemistryText(value: string) {
  const children: ReactNode[] = []
  let lastIndex = 0
  let match: RegExpExecArray | null
  let tokenIndex = 0

  SPECIAL_TOKEN.lastIndex = 0
  while ((match = SPECIAL_TOKEN.exec(value)) !== null) {
    const token = match[0]
    const unitMatch = UNIT_EXPONENT.exec(token)
    if (!isFormulaToken(token) && !unitMatch) continue

    children.push(value.slice(lastIndex, match.index))
    children.push(unitMatch ? renderUnitToken(token, `unit-${tokenIndex}`) : renderFormulaToken(token, `formula-${tokenIndex}`))
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
  const parts = children.split(AVOGADRO_TOKEN)
  if (parts.length === 1) return <>{renderChemistryText(children)}</>

  return <>{parts.map((part, index) => <Fragment key={`${index}-${part}`}>
    {index > 0 ? <span className="chem-symbol chem-avogadro" aria-label="N 下标 A"><span aria-hidden="true">N</span><sub aria-hidden="true">A</sub></span> : null}
    {renderChemistryText(part)}
  </Fragment>)}</>
}
