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
