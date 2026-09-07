export type ReviewProgram = { startDate: string; endDate: string; participating: boolean };

export function readReviewProgram(metadata: unknown): ReviewProgram | null {
  const value = (metadata as Record<string, unknown> | null)?.reviewProgram as Record<string, unknown> | undefined;
  if (!value) return null;
  const startDate = String(value.startDate || "");
  const endDate = String(value.endDate || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate) || startDate > endDate) {
    return { startDate: "9999-12-31", endDate: "0000-01-01", participating: false };
  }
  return { startDate, endDate, participating: value.participating === true };
}

export function programContainsDate(program: ReviewProgram | null, date: string) {
  return !program || (program.participating && date >= program.startDate && date <= program.endDate);
}

export function programPlanVisible(program: ReviewProgram | null, plan: Record<string, unknown>) {
  if (!program || plan.mode !== "REVIEW") return true;
  return plan.is_scheduled === true && programContainsDate(program, String(plan.plan_date || ""));
}

export function programAllowsJuniorUnit(metadata: unknown, unitId: unknown) {
  const program = (metadata as Record<string, unknown> | null)?.reviewProgram as Record<string, unknown> | undefined;
  if (!program || !("juniorUnitIds" in program)) return true;
  const units = program.juniorUnitIds;
  return Array.isArray(units) && units.length > 0
    && units.every((unit) => typeof unit === "string" && unit.trim().length > 0)
    && typeof unitId === "string" && units.includes(unitId);
}

// Missing or invalid assignments fail closed instead of becoming a random draw.
export function programQuestionIds(metadata: unknown, date: string): string[] | null {
  const config = (metadata as Record<string, unknown> | null)?.reviewProgram as Record<string, unknown> | undefined;
  if (!config || !("questionAssignments" in config)) return null;
  if (!programContainsDate(readReviewProgram(metadata), date)) return [];
  const assignments = config.questionAssignments;
  if (!assignments || typeof assignments !== "object" || Array.isArray(assignments)) return [];
  const ids = (assignments as Record<string, unknown>)[date];
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 8
    || ids.some((id) => typeof id !== "string" || !/^[A-Za-z0-9_-]{1,160}$/.test(id))
    || new Set(ids).size !== ids.length) return [];
  return ids as string[];
}

// The approved practice scope is separate from evidence of past learning.
export function programReviewSkillIds(metadata: unknown): string[] | null {
  const config = (metadata as Record<string, unknown> | null)?.reviewProgram as Record<string, unknown> | undefined;
  if (!config || !("allowedSkillIds" in config)) return null;
  const ids = config.allowedSkillIds;
  if (!Array.isArray(ids) || !ids.length
    || ids.some((id) => typeof id !== "string" || !/^H[123]_[A-Z0-9_]+$/.test(id))
    || new Set(ids).size !== ids.length) return [];
  return ids as string[];
}
