// Only server-owned plan columns can authorize a source grade different from
// the student's enrollment grade. Client grade hints are never inputs here.
export const TEACHING_GRADES = ["初三", "高一", "高二", "高三"] as const;

export function teachingPlanContext(plan: Record<string, unknown>, studentGrade: string) {
  const managed = plan.teaching_managed === true;
  const sourceGrade = managed ? String(plan.teaching_source_grade || "") : studentGrade;
  if (!TEACHING_GRADES.includes(sourceGrade as typeof TEACHING_GRADES[number])) {
    throw new Error("课程题目来源年段无效，请联系甘老师重新排课。");
  }
  if (managed && (plan.mode !== "REVIEW" || plan.delivery_mode === "junior_adaptive"
    || !Number.isInteger(Number(plan.question_count)) || Number(plan.question_count) < 1 || Number(plan.question_count) > 8
    || Number(plan.round_limit) !== 1)) {
    throw new Error("老师安排的题组配置不完整，请联系甘老师重新排课。");
  }
  return {
    managed,
    sourceGrade,
    sourceKind: sourceGrade === "初三" ? "user_provided_local" : "licensed_local",
    renderMode: sourceGrade === "初三" ? "native" : "image_primary",
    requiresImages: sourceGrade !== "初三",
  };
}

export function teachingAssignmentValid(managed: boolean, assignments: string[] | null, questionCount: number) {
  return !managed || Boolean(assignments && assignments.length === questionCount
    && questionCount >= 1 && questionCount <= 8 && new Set(assignments).size === assignments.length);
}

export function teachingQuestionSourceMatches(
  question: Record<string, unknown>,
  context: ReturnType<typeof teachingPlanContext>,
  activeReleaseId: string,
) {
  return question.grade_band === context.sourceGrade
    && question.source_kind === context.sourceKind
    && question.render_mode === context.renderMode
    && question.source_release_id === activeReleaseId;
}

// Accept only server-read release metadata, never client-provided format hints.
export function teachingReleaseContext(
  context: ReturnType<typeof teachingPlanContext>,
  source: Record<string, unknown>,
) {
  const image = source.source_kind === "licensed_local" && source.render_mode === "image_primary";
  const nativeJunior = context.sourceGrade === "初三"
    && source.source_kind === "user_provided_local" && source.render_mode === "native";
  if (source.grade_band !== context.sourceGrade || (!image && !nativeJunior)) {
    throw new Error("该题组的原题格式与年段不一致，请重新打开课程。");
  }
  return { ...context, sourceKind: String(source.source_kind),
    renderMode: String(source.render_mode), requiresImages: image };
}
