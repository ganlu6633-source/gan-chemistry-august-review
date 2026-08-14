export const SOURCE_INFORMED_CHEM_SKILLS = [
  'H1_MOLE_INTRO',
  'H1_GAS_MOLAR_VOLUME',
  'H1_REDOX',
] as const

export type SourceInformedChemSkillId = typeof SOURCE_INFORMED_CHEM_SKILLS[number]

const supportedSkillIds = new Set<string>(SOURCE_INFORMED_CHEM_SKILLS)

export function supportsSourceInformedChemVisual(skillId: string): skillId is SourceInformedChemSkillId {
  return supportedSkillIds.has(skillId)
}
