import { Fragment, type ReactNode } from 'react'

const LOWERCASE_AVOGADRO_OCR_TOKEN = `N${String.fromCodePoint(0x2090)}`
const NAMED_SUBSCRIPT_TOKEN = new RegExp(`(N_A|N_a|${LOWERCASE_AVOGADRO_OCR_TOKEN}|V_m|K_?(?:sp|c|p|a|b|w))`, 'g')
const UNIT_EXPONENT = /^(mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?\s*\^?\s*([-−－])\s*(\d+)$/
const POWER_TOKEN = /^(10|c\([A-D]\))\s*\^\s*([-−－]?\s*\d+|[a-d])$/
const EXPLICIT_VOLUME_POWER = /^(cm|dm)\s*\^\s*(3)$/
const EXACT_KELVIN_SUBTRACTION = /^K\s*[-−－]\s*273$/
// Keep one unambiguous standalone decimal together; a long sum still wraps
// between terms. Do not reinterpret letters, dotted versions, or source digits.
const PLAIN_DECIMAL_TOKEN = '(?<![A-Za-z0-9_.])\\d+\\.\\d+(?![A-Za-z0-9_.])'
const PLAIN_DECIMAL_EXACT = /^\d+\.\d+$/
// Enthalpy variables and explicitly abstract A/E reaction placeholders are math.
// Keep their source Unicode subscripts and arithmetic operators on the baseline.
const ENTHALPY_VARIABLE_TOKEN = 'ΔH[₀-₉]*(?:\\s*[+=−－-]\\s*)?'
const ABSTRACT_REACTION_SIDE = '[A-E](?:\\s*\\+\\s*[A-E])*'
const ABSTRACT_PLACEHOLDER_SIDE = '(?:[A-E]\\s*\\+\\s*)*[AE](?:\\s*\\+\\s*[A-E])*'
const ABSTRACT_REACTION_TOKEN = `(?<![A-Za-z0-9₀-₉])(?:${ABSTRACT_PLACEHOLDER_SIDE}\\s*(?:=|→|->)\\s*${ABSTRACT_REACTION_SIDE}|${ABSTRACT_REACTION_SIDE}\\s*(?:=|→|->)\\s*${ABSTRACT_PLACEHOLDER_SIDE})(?![A-Za-z0-9₀-₉])`
const PROTECTED_MATH_TOKEN = `(?:${ENTHALPY_VARIABLE_TOKEN}|${ABSTRACT_REACTION_TOKEN})`
const PROTECTED_MATH_EXACT = new RegExp(`^(?:${PROTECTED_MATH_TOKEN})$`)
// Chemical counts belong to each atom/group, not just the end of a token.
const FORMULA_COUNT = '[0-9₀-₉]*'
const FORMULA_ATOM = `[A-Z][a-z]?${FORMULA_COUNT}`
const FORMULA_GROUP = `(?:\\((?:${FORMULA_ATOM})+\\)|\\[(?:${FORMULA_ATOM})+\\])${FORMULA_COUNT}`
const FORMULA_UNIT = `(?:${FORMULA_ATOM}|${FORMULA_GROUP})`
const FORMULA_BRACKET = `\\[${FORMULA_UNIT}+\\]${FORMULA_COUNT}`
const FORMULA_BODY = `(?:${FORMULA_UNIT}|${FORMULA_BRACKET})+`
// A plain + immediately followed by another reagent stays a reaction separator.
const FORMULA_CHARGE = '(?:\\^\\d*[+-]|[⁰¹²³⁴⁵⁶⁷⁸⁹]*[⁺⁻]|[+-](?!>)(?!\\s*\\d*\\s*(?:[A-Z[(]|e(?:\\^-|⁻))))?'
const FORMULA_TOKEN = `(?<![A-Za-z0-9₀-₉])(?:\\d+)?${FORMULA_BODY}(?:[·∙](?:\\d+)?${FORMULA_BODY})*${FORMULA_CHARGE}`
const SPECIAL_TOKEN = new RegExp(`(?:${PLAIN_DECIMAL_TOKEN})|(?:${PROTECTED_MATH_TOKEN})|(?:\\bK\\s*[-−－]\\s*273(?![A-Za-z0-9.]))|(?:\\b(?:cm|dm)\\s*\\^\\s*3(?![A-Za-z0-9.]))|(?:(?<![A-Za-z0-9])(?:\\d+)?e\\^-(?![A-Za-z0-9]))|(?:\\b(?:10|c\\([A-D]\\))\\s*\\^\\s*(?:[-−－]?\\s*\\d+|[a-d]))|(?:\\b(?:mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?\\s*\\^?\\s*[-−－]\\s*\\d+)|(?:${FORMULA_TOKEN})`, 'g')

function isFormulaToken(value: string) {
  return /[0-9₀-₉⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻+-]/.test(value)
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
    hasAtom = character === '·' || character === '∙' ? false : character === ')' || /[A-Za-z]/.test(character) || hasAtom
    index += 1
  }
  flush()
  return children
}

function splitCharge(value: string) {
  // Preserve Unicode charge codepoints. Their glyphs already sit above baseline.
  const unicode = value.match(/([⁰¹²³⁴⁵⁶⁷⁸⁹]*[⁺⁻])$/)
  if (unicode) return { body: value.slice(0, -unicode[0].length), digits: '', sign: '', rawUnicodeCharge: unicode[0] }
  const explicit = value.match(/\^(\d*)([+-])$/)
  if (explicit) return { body: value.slice(0, -explicit[0].length), digits: explicit[1], sign: explicit[2] }

  const sign = value.match(/([+-])$/)
  if (!sign) return { body: value, digits: '', sign: '' }

  const rawBody = value.slice(0, -sign[0].length)
  const bracketCharge = rawBody.match(/\](\d+)$/)
  if (bracketCharge) return { body: rawBody.slice(0, -bracketCharge[1].length), digits: bracketCharge[1], sign: sign[1] }
  const singleElementCharge = rawBody.match(/^(?:\d+)?(?:[A-Z][a-z]?)(\d+)$/)
  if (singleElementCharge) return { body: rawBody.slice(0, -singleElementCharge[1].length), digits: singleElementCharge[1], sign: sign[1] }
  return { body: rawBody, digits: '', sign: sign[1] }
}

function renderFormulaToken(value: string, key: string) {
  const charge = splitCharge(value)
  const renderedBody = <>{renderFormulaBody(charge.body)}{charge.sign && <sup>{`${charge.digits}${charge.sign}`}</sup>}{'rawUnicodeCharge' in charge ? charge.rawUnicodeCharge : ''}</>

  return <span style={{ display: 'inline-block' }} className="chem-symbol" aria-label={value} key={key}>{renderedBody}</span>
}

function renderUnitToken(value: string, key: string) {
  const match = value.match(UNIT_EXPONENT)
  if (!match) return value
  return <span style={{ display: 'inline-block' }} className="chem-symbol" key={key} aria-label={value}>{match[1]}<sup>{`${match[2].replace(/[−－-]/, '−')}${match[3]}`}</sup></span>
}

function renderExplicitVolumePower(value: string, key: string) {
  const match = value.match(EXPLICIT_VOLUME_POWER)
  if (!match) return value
  return <span style={{ display: 'inline-block' }} className="chem-symbol" key={key} aria-label={value}>{match[1]}<sup>{match[2]}</sup></span>
}

function renderPowerToken(value: string, key: string) {
  const match = value.match(POWER_TOKEN)
  if (!match) return value
  return <span style={{ display: 'inline-block' }} className="chem-symbol" key={key} aria-label={value}>{match[1]}<sup>{match[2].replace(/\s/g, '').replace(/[−－-]/, '−')}</sup></span>
}

function abstractHessSideReferences(value: string) {
  if (!value.includes('ΔH')) return null
  const sides = new Set<string>()
  for (const match of value.matchAll(new RegExp(ABSTRACT_REACTION_TOKEN, 'g'))) {
    for (const side of match[0].split(/=|→|->/)) {
      const compact = side.replace(/\s/g, '')
      if (compact.includes('+')) sides.add(compact)
    }
  }
  if (sides.size === 0) return null
  // Only a side actually declared by this text's A/E abstract reaction can
  // be an intermediate reference. A standalone real C+B is not inferred.
  const alternatives = [...sides].map((side) => side.split('+').join('\\s*\\+\\s*'))
  return `(?<![A-Za-z0-9₀-₉])(?:${alternatives.join('|')})(?![A-Za-z0-9₀-₉])`
}

function renderChemistryText(value: string) {
  const children: ReactNode[] = []
  let lastIndex = 0
  let tokenIndex = 0

  const hessReferences = abstractHessSideReferences(value)
  const hessReferenceExact = hessReferences ? new RegExp(`^(?:${hessReferences})$`) : null
  const matcherSource = hessReferences ? `(?:${hessReferences})|(?:${SPECIAL_TOKEN.source})` : SPECIAL_TOKEN.source

  // A fresh matcher per ChemText call avoids sharing mutable lastIndex state
  // across React renders.
  for (const match of value.matchAll(new RegExp(matcherSource, 'g'))) {
    const token = match[0]
    if (PLAIN_DECIMAL_EXACT.test(token)) {
      children.push(value.slice(lastIndex, match.index), <span className="chem-plain-decimal" style={{ display: 'inline-block', fontFamily: 'inherit', fontStyle: 'inherit' }} aria-label={token} key={`decimal-${tokenIndex}`}>{token}</span>)
      tokenIndex += 1
      lastIndex = match.index + token.length
      continue
    }
    if (PROTECTED_MATH_EXACT.test(token) || hessReferenceExact?.test(token)) {
      // The actual page notation observer skips .chem-symbol. It must not
      // reinterpret an arithmetic plus/minus as the charge of a fake ion.
      children.push(value.slice(lastIndex, match.index), <span className="chem-symbol" style={{ display: 'inline-block', fontFamily: 'inherit', fontStyle: 'inherit' }} aria-label={token} key={`math-${tokenIndex}`}>{token}</span>)
      tokenIndex += 1
      lastIndex = match.index + token.length
      continue
    }
    // This one implicit K-273 form is a temperature subtraction, not a unit power.
    // Explicit K^-273 and other implicit K-1 forms keep their existing semantics.
    if (EXACT_KELVIN_SUBTRACTION.test(token) && !/[A-Za-z0-9.]/.test(value[match.index + token.length] ?? '')) {
      // The page's legacy notation observer skips .chem-symbol text. Protect
      // this literal subtraction so it cannot be reinterpreted as a power.
      children.push(value.slice(lastIndex, match.index), <span className="chem-symbol" style={{ display: 'inline-block', fontFamily: 'inherit', fontStyle: 'inherit' }} aria-label={token} key={`plain-${tokenIndex}`}>{token}</span>)
      tokenIndex += 1
      lastIndex = match.index + token.length
      continue
    }
    const volumeMatch = EXPLICIT_VOLUME_POWER.exec(token)
    const unitMatch = UNIT_EXPONENT.exec(token)
    const powerMatch = POWER_TOKEN.exec(token)
    if (!isFormulaToken(token) && !unitMatch && !powerMatch && !volumeMatch) {
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
    children.push(volumeMatch
      ? renderExplicitVolumePower(token, `volume-${tokenIndex}`)
      : unitMatch
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
      ? <span style={{ display: 'inline-block' }} className="chem-symbol chem-avogadro" aria-label="N 下标 A"><span aria-hidden="true">N</span><sub aria-hidden="true">A</sub></span>
      : part === 'V_m'
      ? <span style={{ display: 'inline-block' }} className="chem-symbol chem-molar-volume" aria-label="V 下标 m"><span aria-hidden="true">V</span><sub aria-hidden="true">m</sub></span>
      : /^K_?(?:sp|c|p|a|b|w)$/.test(part)
      ? <span style={{ display: 'inline-block' }} className="chem-symbol chem-equilibrium-constant" aria-label={`K 下标 ${part.replace(/^K_?/, '')}`}><span aria-hidden="true">K</span><sub aria-hidden="true">{part.replace(/^K_?/, '')}</sub></span>
      : renderChemistryText(part)}
  </Fragment>)}</>
}
