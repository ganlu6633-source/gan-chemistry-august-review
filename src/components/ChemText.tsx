import { Fragment } from 'react'

const AVOGADRO_TOKEN = 'N_A'

/**
 * Chemistry copy is stored as plain text. N_A is the canonical source token so
 * the A remains uppercase; this renderer gives it the required subscript form.
 */
export function ChemText({ children }: { children: string }) {
  const parts = children.split(AVOGADRO_TOKEN)
  if (parts.length === 1) return <>{children}</>

  return <>{parts.map((part, index) => <Fragment key={`${index}-${part}`}>
    {index > 0 ? <span className="chem-symbol chem-avogadro" aria-label="N 下标 A"><span aria-hidden="true">N</span><sub aria-hidden="true">A</sub></span> : null}
    {part}
  </Fragment>)}</>
}
