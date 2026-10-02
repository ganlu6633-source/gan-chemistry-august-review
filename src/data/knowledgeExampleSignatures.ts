import type { StructuredKnowledgeContent } from '../domain/types'

// Fingerprints of the source hierarchy used when writing the item examples.
// A later card revision may rearrange its sections. In that case, do not
// attach an example by an index that now points at a different knowledge item.
export function knowledgeExampleSignature(content: StructuredKnowledgeContent): number {
  const source = JSON.stringify(content.sections.map((section) => [section.title, section.items.map((item) => item.label)]))
  let hash = 2166136261
  for (let index = 0; index < source.length; index += 1) {
    hash ^= source.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

export const generatedKnowledgeSignatures: Record<string, number> = {
  H1_ELECTROLYTE_INTRO: 1418597640,
  H1_PERIODIC: 3995865924,
  H1_REDOX: 326172647,
  H1_ELECTROLYTE: 6255013,
  H1_MOLE_INTRO: 2362341879,
  H1_MOLE: 2803360476,
  H1_NACL: 181350203,
  H2_THERMO: 1391944365,
  H2_RATE: 644800541,
  H2_EQUIL: 865029243,
  H2_K: 179357057,
  H2_WEAK: 2140777035,
  H2_PH_HYDRO: 1333519313,
  H2_KSP: 2332832440,
  H2_ELECTRO: 4206225751,
  H3_STOICH: 1763194658,
  H3_ION_REDOX: 2584284775,
  H3_INORGANIC: 2803576416,
  H3_THERMO_RATE: 725667661,
  H3_EQUILIBRIUM: 205463839,
  H3_AQ: 264204793,
  H3_ELECTRO: 2021444954,
  H3_EXPERIMENT: 4110086469,
  H3_PROCESS: 3906755500,
  H3_STRUCTURE: 706382984,
  H3_ORGANIC: 3228549983,
}

export const openingKnowledgeSignatures: Record<string, number> = {
  H1_REACTION_CLASSIFICATION: 2324677475,
  H1_SOLUTION_CONCENTRATION: 1720552871,
}

export const specialKnowledgeSignatures: Record<string, number> = {
  H1_GAS_MOLAR_VOLUME: 556377971,
}
