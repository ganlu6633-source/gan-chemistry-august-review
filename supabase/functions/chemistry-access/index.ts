import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { selectAdaptiveQuestions } from "./adaptive.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);
const allowedOrigins = new Set([
  "https://ganlu6633-source.github.io",
  "http://localhost:4173",
  "http://localhost:5173",
]);

function cors(req: Request) {
  const requested = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(requested) ? requested : "https://ganlu6633-source.github.io",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-app-session",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  };
}
const reply = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors(req) });

class RequestError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "RequestError";
    this.status = status;
  }
}

function planQuestionCount(row: Record<string, unknown>) {
  const value = Number(row.question_count);
  return Number.isInteger(value) && value >= 1 && value <= 10 ? value : 5;
}

function planRoundLimit(row: Record<string, unknown>) {
  const value = Number(row.round_limit);
  return Number.isInteger(value) && value >= 1 && value <= 8 ? value : 5;
}

function planMaxQuestionLevel(row: Record<string, unknown>) {
  if (row.max_question_level === null || row.max_question_level === undefined) return null;
  const value = Number(row.max_question_level);
  return Number.isInteger(value) && value >= 1 ? value : null;
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
function validUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
const profileShape = (row: Record<string, unknown>) => ({
  id: row.id,
  displayName: row.display_name,
  gradeBand: row.grade_band,
  enrollmentStartDate: row.enrollment_start_date,
  needsInitialDiagnostic: row.needs_initial_diagnostic,
  isDemo: Boolean((row.metadata as Record<string, unknown> | null)?.demo),
});
const skillShape = (row: Record<string, unknown>) => ({
  id: row.id, title: row.title, moduleId: row.module_id, gradeBand: row.grade_band,
  maxLevel: row.max_level, examImportance: row.exam_importance, examDepth: row.exam_depth,
  prerequisites: row.prerequisites || [], levelCriteria: row.level_criteria || [],
});
const stateShape = (row: Record<string, unknown> & { chem_skills?: Record<string, unknown> }) => ({
  studentId: row.student_id, skillId: row.skill_id, verifiedLevel: row.verified_level,
  candidateLevel: row.candidate_level, maxLevel: row.chem_skills?.max_level || 1,
  stability: row.stability, evidence: [], consecutiveErrors: row.consecutive_errors,
  nextReviewAt: row.next_review_at, reviewIntervalIndex: row.review_interval_index,
  lastReviewedAt: row.last_reviewed_at, teacherIntervention: row.teacher_intervention,
});
const planShape = (row: Record<string, unknown>, attemptRows: Array<Record<string, unknown>> = []) => {
  const attempts = attemptRows
    .filter((attempt) => attempt.plan_day_id === row.id)
    .sort((a, b) => String(a.completed_at).localeCompare(String(b.completed_at)));
  const first = attempts.find((attempt) => attempt.attempt_kind === "scheduled") || attempts[0];
  const latest = attempts.at(-1);
  const questionCount = planQuestionCount(row);
  const roundLimit = planRoundLimit(row);
  const latestAnswers = Array.isArray(latest?.chem_attempt_answers)
    ? latest.chem_attempt_answers as Array<Record<string, unknown>>
    : [];
  const isResolved = latestAnswers.length === questionCount && latestAnswers.every((answer) => answer.correct === true && answer.uncertain !== true);
  const isComplete = isResolved || attempts.length >= roundLimit;
  return {
    id: row.id, studentId: row.student_id, date: row.plan_date, mode: row.mode, title: row.title,
    skillIds: row.skill_ids || [], knowledgeSummaries: row.knowledge_summaries || [],
    estimatedMinutes: row.estimated_minutes, source: row.source, isScheduled: row.is_scheduled,
    questionCount, roundLimit, maxQuestionLevel: planMaxQuestionLevel(row),
    attemptCount: attempts.length, firstScore: first?.first_score ?? null,
    latestScore: latest?.first_score ?? null, latestCompletedAt: latest?.completed_at ?? null,
    isResolved, isComplete, roundsRemaining: isComplete ? 0 : Math.max(0, roundLimit - attempts.length),
  };
};
const questionShape = (row: Record<string, unknown>) => ({
  id: row.id, motherId: row.mother_id, skillId: row.skill_id, conceptKey: row.concept_key, level: row.level,
  gradeBand: row.grade_band, stem: row.stem, options: row.options, correctOption: row.correct_option,
  explanation: row.explanation, scaffold: row.scaffold, reviewStatus: row.review_status,
  scopeStatus: row.scope_status, sourceKind: row.source_kind, imageUrl: row.image_url,
});
const cardShape = (row: Record<string, unknown>) => ({
  id: row.id, skillId: row.skill_id, title: row.title, core: row.core, detail: row.detail,
  steps: row.steps || [], commonMistakes: row.common_mistakes || [], microExample: row.micro_example,
  structuredContent: row.structured_content && Object.keys(row.structured_content as Record<string, unknown>).length ? row.structured_content : undefined,
  asset: row.asset, reviewStatus: row.review_status,
});
const videoRecommendationShape = (row: Record<string, unknown>) => ({
  id: row.id,
  studentId: row.student_id,
  studentName: row.student_name,
  skillId: row.skill_id,
  skillTitle: row.skill_title,
  unresolvedOn: row.unresolved_on,
  sourceAttemptId: row.source_attempt_id,
  sourceAlertId: row.source_alert_id,
  title: row.title,
  provider: row.provider,
  url: row.external_url,
  teacherReason: row.teacher_reason,
  trackingCapability: row.tracking_capability,
  status: row.status,
  createdBy: row.created_by,
  reviewedBy: row.reviewed_by,
  reviewedAt: row.reviewed_at,
  publishedBy: row.published_by,
  publishedAt: row.published_at,
  withdrawnBy: row.withdrawn_by,
  withdrawnAt: row.withdrawn_at,
  createdAt: row.created_at,
  progress: {
    openedAt: row.opened_at,
    lastEngagedAt: row.last_engaged_at,
    progressSeconds: Number(row.progress_position_seconds) || 0,
    durationSeconds: row.duration_seconds === null || row.duration_seconds === undefined ? null : Number(row.duration_seconds),
    completionPercent: row.completion_percent === null || row.completion_percent === undefined ? null : Number(row.completion_percent),
    trackingMethod: row.tracking_method,
    completedAt: row.completed_at,
    eventCount: Number(row.event_count) || 0,
  },
});

async function loadVideoRecommendations(studentId: string | null, includeUnpublished = false) {
  const { data, error } = await supabase.rpc("chem_video_list_recommendations", {
    p_student_id: studentId,
    p_include_unpublished: includeUnpublished,
  });
  if (error) throw error;
  const rows = (data || []) as Array<Record<string, unknown>>;
  return rows.map((row) => videoRecommendationShape(row));
}

function formatDuration(value: unknown) {
  const totalSec = Math.max(0, Number(value) || 0);
  const minutes = Math.floor(totalSec / 60);
  const seconds = Math.round(totalSec % 60);
  return minutes ? `${minutes}分${seconds}秒` : `${seconds}秒`;
}

function parentQuizDescription(row: Record<string, unknown>) {
  const theme = String(row.training_theme || "即时小测");
  const wrongTags = Array.isArray(row.wrong_tags) ? row.wrong_tags.map(String).filter(Boolean).slice(0, 3) : [];
  const result = `${theme}：答对 ${Number(row.correct_count) || 0}/${Number(row.total_count) || 0}，用时${formatDuration(row.total_sec)}`;
  return wrongTags.length ? `${result}；需要继续巩固：${wrongTags.join("、")}` : `${result}；本轮没有发现错题。`;
}

function shanghaiDate(value = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(value);
}

function shanghaiWeekRange() {
  const today = shanghaiDate();
  const noon = new Date(`${today}T12:00:00+08:00`);
  const weekday = noon.getUTCDay();
  const mondayOffset = weekday === 0 ? 6 : weekday - 1;
  const start = new Date(noon.getTime() - mondayOffset * 86400000);
  const end = new Date(start.getTime() + 7 * 86400000);
  const startDate = shanghaiDate(start);
  const endDate = shanghaiDate(end);
  return {
    startDate,
    endDate,
    startIso: new Date(`${startDate}T00:00:00+08:00`).toISOString(),
    endIso: new Date(`${endDate}T00:00:00+08:00`).toISOString(),
  };
}

function curriculumSkillScope(gradeBand: string, cohort: string, allSkillIds: string[], confirmedSkillIds: string[] = []) {
  const available = new Set(allSkillIds);
  const confirmed = [...new Set(confirmedSkillIds)].filter((skillId) => available.has(skillId));
  if (confirmed.length) return confirmed;
  if (gradeBand === "高一") {
    const foundation = ["H1_CLASSIFY", "H1_PERIODIC", "H1_MOLE_INTRO", "H1_GAS_MOLAR_VOLUME"];
    if (cohort === "high1_completed") return [...foundation, "H1_REDOX"];
    if (cohort === "high1_current") return foundation;
  }
  if (gradeBand === "初三" || gradeBand === "高二" || gradeBand === "高三") return allSkillIds;
  return [];
}

function learnedSkillIds(
  skills: Array<Record<string, unknown>>,
  states: Array<Record<string, unknown>>,
  plans: Array<Record<string, unknown>>,
  answers: Array<Record<string, unknown>>,
  gradeBand: string,
  cohort: string,
  confirmedSkillIds: string[] = [],
  today = shanghaiDate(),
) {
  const allSkillIds = skills.map((skill) => String(skill.id));
  const allowed = new Set(allSkillIds);
  const learned = new Set(curriculumSkillScope(gradeBand, cohort, allSkillIds, confirmedSkillIds).filter((skillId) => allowed.has(skillId)));
  for (const plan of plans) {
    if (String(plan.plan_date || "") > today) continue;
    for (const skillId of Array.isArray(plan.skill_ids) ? plan.skill_ids : []) {
      if (allowed.has(String(skillId))) learned.add(String(skillId));
    }
  }
  for (const state of states) if (allowed.has(String(state.skill_id))) learned.add(String(state.skill_id));
  for (const answer of answers) if (allowed.has(String(answer.skill_id))) learned.add(String(answer.skill_id));
  return learned;
}

function learningSummary(
  skills: Array<Record<string, unknown>>,
  states: Array<Record<string, unknown>>,
  plans: Array<Record<string, unknown>>,
  answers: Array<Record<string, unknown>>,
  gradeBand: string,
  cohort: string,
  confirmedSkillIds: string[] = [],
  answeredQuestions = 0,
) {
  const learned = learnedSkillIds(skills, states, plans, answers, gradeBand, cohort, confirmedSkillIds);
  const stateBySkill = new Map(states.map((state) => [String(state.skill_id), state]));
  let full = 0;
  let partial = 0;
  let unlit = 0;
  let due = 0;
  let recovered = 0;
  const now = Date.now();
  for (const skill of skills) {
    if (!learned.has(String(skill.id))) continue;
    const state = stateBySkill.get(String(skill.id));
    const verified = Number(state?.verified_level) || 0;
    const maxLevel = Number(skill.max_level) || 1;
    if (verified >= maxLevel) full += 1;
    else if (verified > 0) partial += 1;
    else unlit += 1;
    const nextReview = state?.next_review_at ? new Date(String(state.next_review_at)).getTime() : Number.POSITIVE_INFINITY;
    if (state?.stability === "forgotten" || (verified > 0 && nextReview <= now)) due += 1;
    if (state?.stability === "recovered") recovered += 1;
  }
  return { total: skills.length, learned: learned.size, full, partial, unlit, due, recovered, answeredQuestions };
}

function validQuestionSnapshot(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value) && String((value as Record<string, unknown>).stem || ""));
}

function historicalQuestion(
  answer: Record<string, unknown>,
  currentQuestion: Record<string, unknown> | undefined,
) {
  const snapshot = validQuestionSnapshot(answer.question_snapshot) ? answer.question_snapshot : null;
  const currentStatus = !currentQuestion
    ? "unavailable"
    : currentQuestion.scope_status === "OUT"
      ? "out_of_scope"
      : currentQuestion.review_status === "approved"
        ? "available"
        : "retired";
  const currentCanFill = currentStatus === "available";
  const source = snapshot || (currentCanFill ? currentQuestion : null);
  if (!source) {
    return {
      stem: "该历史题正文暂不可显示，作答结果仍按原记录保留。",
      options: [] as string[],
      correctOption: -1,
      explanation: "题目已退出当前题库，系统不会用现在的题目内容改写这次历史作答。",
      imageUrl: null as string | null,
      snapshotAvailable: false,
      currentQuestionStatus: currentStatus,
    };
  }
  return {
    stem: String(source.stem),
    options: Array.isArray(source.options) ? source.options.map(String) : [],
    correctOption: Number(source.correctOption ?? source.correct_option),
    explanation: String(source.explanation || "本次作答的解析暂不可显示。"),
    imageUrl: source.imageUrl || source.image_url ? String(source.imageUrl || source.image_url) : null,
    snapshotAvailable: Boolean(snapshot),
    currentQuestionStatus: currentStatus,
  };
}

function cardKnowledgeSections(cards: Array<Record<string, unknown>>) {
  const sections: Array<{ id: string; title: string; summary?: string; points: Array<{ id: string; title: string; rule: string }> }> = [];
  for (const card of cards) {
    const structured = card.structured_content as Record<string, unknown> | null;
    const rawSections = Array.isArray(structured?.sections) ? structured.sections as Array<Record<string, unknown>> : [];
    if (!rawSections.length) {
      const steps = Array.isArray(card.steps) ? card.steps.map(String) : [];
      sections.push({
        id: `${card.id}-main`, title: String(card.title || "本模块主线"),
        points: (steps.length ? steps : [String(card.core || "本模块核心知识")]).map((step, index) => ({
          id: `${card.id}-main-${index + 1}`, title: step, rule: index === 0 ? String(card.core || "") : "",
        })),
      });
      continue;
    }
    rawSections.forEach((section, sectionIndex) => {
      const items = Array.isArray(section.items) ? section.items as Array<Record<string, unknown>> : [];
      sections.push({
        id: `${card.id}-section-${sectionIndex + 1}`,
        title: String(section.title || `知识组 ${sectionIndex + 1}`),
        summary: section.summary ? String(section.summary) : undefined,
        points: items.map((item, itemIndex) => ({
          id: `${card.id}-section-${sectionIndex + 1}-point-${itemIndex + 1}`,
          title: String(item.label || `知识点 ${itemIndex + 1}`),
          rule: String(item.rule || ""),
        })),
      });
    });
  }
  return sections;
}

async function studentLearningRecord(studentId: string) {
  const profile = await supabase.from("chem_students_v2").select("grade_band,metadata").eq("id", studentId).single();
  if (profile.error) throw profile.error;
  const gradeBand = String(profile.data.grade_band);
  const attemptHistoryLimit = 500;
  const answerHistoryLimit = 500;
  const recentQuestionsPerSkillLimit = 20;
  const [skillsResult, statesResult, plansResult, attemptsResult, cardsResult] = await Promise.all([
    supabase.from("chem_skills").select("id,title,module_id,max_level").eq("active", true).eq("grade_band", gradeBand).order("module_id"),
    supabase.from("chem_student_skill_state").select("skill_id,verified_level,candidate_level,stability,next_review_at,last_reviewed_at,teacher_intervention").eq("student_id", studentId),
    supabase.from("chem_learning_plans").select("id,plan_date,title,skill_ids,knowledge_summaries").eq("student_id", studentId).order("plan_date"),
    supabase.from("chem_learning_attempts").select("id,plan_day_id,completed_at", { count: "exact" }).eq("student_id", studentId).order("completed_at", { ascending: false }).limit(attemptHistoryLimit),
    supabase.from("chem_knowledge_cards").select("id,skill_id,title,core,steps,structured_content").eq("review_status", "approved"),
  ]);
  for (const result of [skillsResult, statesResult, plansResult, attemptsResult, cardsResult]) if (result.error) throw result.error;

  const attempts = attemptsResult.data || [];
  const attemptIds = attempts.map((attempt) => attempt.id);
  const answersResult = attemptIds.length
    ? await supabase.from("chem_attempt_answers")
      .select("attempt_id,question_id,mother_id,skill_id,level,correct,uncertain,duration_sec,selected_option,created_at,question_snapshot", { count: "exact" })
      .in("attempt_id", attemptIds).order("created_at", { ascending: false }).limit(answerHistoryLimit)
    : { data: [], error: null, count: 0 };
  if (answersResult.error) throw answersResult.error;
  const answers = answersResult.data || [];
  const questionIds = [...new Set(answers.map((answer) => String(answer.question_id)))];
  const questionsResult = questionIds.length
    ? await supabase.from("chem_questions")
      .select("id,mother_id,skill_id,level,stem,options,correct_option,explanation,image_url,review_status,scope_status")
      .in("id", questionIds)
    : { data: [], error: null };
  if (questionsResult.error) throw questionsResult.error;

  const skills = skillsResult.data || [];
  const states = statesResult.data || [];
  const plans = plansResult.data || [];
  const stateBySkill = new Map(states.map((state) => [String(state.skill_id), state]));
  const questionById = new Map((questionsResult.data || []).map((question) => [String(question.id), question]));
  const cohort = String(profile.data.metadata?.curriculumCohort || "");
  const confirmedSkillIds = Array.isArray(profile.data.metadata?.confirmedLearnedSkillIds)
    ? profile.data.metadata.confirmedLearnedSkillIds.map(String).filter(Boolean)
    : [];
  const learnedIds = learnedSkillIds(skills, states, plans, answers, gradeBand, cohort, confirmedSkillIds);
  const now = Date.now();
  const today = shanghaiDate();

  const recordSkills = skills.map((skill) => {
    const skillId = String(skill.id);
    const state = stateBySkill.get(skillId);
    const verifiedLevel = Number(state?.verified_level) || 0;
    const maxLevel = Number(skill.max_level) || 1;
    const skillAnswers = answers.filter((answer) => String(answer.skill_id) === skillId);
    const allQuestionEvidence = skillAnswers.map((answer) => {
      const question = questionById.get(String(answer.question_id));
      const historical = historicalQuestion(answer, question);
      return [{
        questionId: String(answer.question_id), motherId: String(answer.mother_id || question?.mother_id || ""), level: Number(answer.level),
        stem: historical.stem, options: historical.options,
        selectedOption: Number(answer.selected_option), correctOption: historical.correctOption, explanation: historical.explanation,
        imageUrl: historical.imageUrl, correct: Boolean(answer.correct), uncertain: Boolean(answer.uncertain),
        durationSec: Number(answer.duration_sec) || 0, answeredAt: String(answer.created_at),
        snapshotAvailable: historical.snapshotAvailable, currentQuestionStatus: historical.currentQuestionStatus,
      }];
    }).flat();
    const questionEvidence = allQuestionEvidence.slice(0, recentQuestionsPerSkillLimit);
    const cards = (cardsResult.data || []).filter((card) => String(card.skill_id) === skillId);
    const singleSkillPlans = plans.filter((plan) => String(plan.plan_date) <= today && Array.isArray(plan.skill_ids) && plan.skill_ids.length === 1 && String(plan.skill_ids[0]) === skillId);
    const learnedTopics = [...new Set(singleSkillPlans.flatMap((plan) => (plan.knowledge_summaries || []).map(String)))];
    const nextPlanRow = plans.find((plan) => plan.plan_date >= today && (plan.skill_ids || []).includes(skillId));
    const nextReview = state?.next_review_at ? new Date(String(state.next_review_at)).getTime() : Number.POSITIVE_INFINITY;
    const retentionStatus = state?.stability === "recovered" ? "recovered"
      : state?.stability === "forgotten" || (verifiedLevel > 0 && nextReview <= now) ? "due"
      : state?.stability === "stable" ? "stable"
      : verifiedLevel > 0 || skillAnswers.length ? "forming" : "unknown";
    const attemptCount = new Set(skillAnswers.map((answer) => String(answer.attempt_id))).size;
    return {
      skillId, title: String(skill.title), moduleId: String(skill.module_id), maxLevel, verifiedLevel,
      candidateLevel: state?.candidate_level === null || state?.candidate_level === undefined ? null : Number(state.candidate_level),
      evidenceStatus: verifiedLevel >= maxLevel ? "full" : verifiedLevel > 0 ? "partial" : "unlit",
      exposure: learnedIds.has(skillId) ? "learned" : "future", retentionStatus,
      lastReviewedAt: state?.last_reviewed_at ? String(state.last_reviewed_at) : null,
      nextReviewAt: state?.next_review_at ? String(state.next_review_at) : null,
      teacherIntervention: Boolean(state?.teacher_intervention), attemptCount,
      answeredQuestionCount: skillAnswers.length,
      correctQuestionCount: skillAnswers.filter((answer) => answer.correct).length,
      uniqueMotherCount: new Set(skillAnswers.map((answer) => String(answer.mother_id))).size,
      learnedTopics, knowledgeSections: cardKnowledgeSections(cards), recentQuestions: questionEvidence,
      knowledgeEvidenceScope: "module_directory_only",
      recentQuestionsTruncated: allQuestionEvidence.length > recentQuestionsPerSkillLimit,
      nextPlan: nextPlanRow ? { id: String(nextPlanRow.id), date: String(nextPlanRow.plan_date), title: String(nextPlanRow.title) } : null,
    };
  });
  const attemptsTotal = attemptsResult.count ?? attempts.length;
  const answersTotalInLoadedAttempts = answersResult.count ?? answers.length;
  return {
    generatedAt: new Date().toISOString(),
    evidenceScope: "技能级证据；知识点列表仅说明模块包含什么，不代表每个知识点都已逐项验证。",
    summary: learningSummary(skills, states, plans, answers, gradeBand, cohort, confirmedSkillIds, answersTotalInLoadedAttempts),
    historyWindow: {
      attemptLimit: attemptHistoryLimit,
      answerLimit: answerHistoryLimit,
      recentQuestionsPerSkillLimit,
      loadedAttempts: attempts.length,
      totalAttempts: attemptsTotal,
      loadedAnswers: answers.length,
      totalAnswersInLoadedAttempts: answersTotalInLoadedAttempts,
      attemptsTruncated: attemptsTotal > attempts.length,
      answersTruncated: answersTotalInLoadedAttempts > answers.length,
      hasMore: attemptsTotal > attempts.length || answersTotalInLoadedAttempts > answers.length || recordSkills.some((skill) => skill.recentQuestionsTruncated),
    },
    skills: recordSkills,
  };
}

async function studentDashboard(studentId: string) {
  const profileResult = await supabase.from("chem_students_v2").select("*").eq("id", studentId).single();
  if (profileResult.error) throw profileResult.error;
  const [planResult, stateResult, skillResult, attemptResult, videoRecommendations] = await Promise.all([
    supabase.from("chem_learning_plans").select("*").eq("student_id", studentId).order("plan_date"),
    supabase.from("chem_student_skill_state").select("*,chem_skills(max_level)").eq("student_id", studentId),
    supabase.from("chem_skills").select("*").eq("active", true).eq("grade_band", profileResult.data.grade_band).order("module_id"),
    supabase.from("chem_learning_attempts").select("id,plan_day_id,attempt_kind,sequence,first_score,completed_at,chem_attempt_answers(correct,uncertain)").eq("student_id", studentId).order("completed_at"),
    loadVideoRecommendations(studentId),
  ]);
  for (const result of [planResult, stateResult, skillResult, attemptResult]) if (result.error) throw result.error;
  const rawStates = stateResult.data || [];
  const states = rawStates.map((r) => stateShape(r as never));
  const skillTitleById = new Map((skillResult.data || []).map((skill) => [String(skill.id), String(skill.title)]));
  const achievements = rawStates
    .filter((state) => Number(state.verified_level) > 0 && (state.last_reviewed_at || state.updated_at))
    .sort((a, b) => String(b.last_reviewed_at || b.updated_at).localeCompare(String(a.last_reviewed_at || a.updated_at)))
    .slice(0, 3)
    .map((state) => ({
      id: `evidence-${state.skill_id}`,
      title: `${skillTitleById.get(String(state.skill_id)) || "能力模块"}已形成证据`,
      description: `当前真实作答证据达到 L${Number(state.verified_level) || 0}/${Number(state.chem_skills?.max_level) || 1}。`,
      earnedAt: String(state.last_reviewed_at || state.updated_at),
    }));
  const isDemo = Boolean((profileResult.data.metadata as Record<string, unknown> | null)?.demo);
  const plans = planResult.data || [];
  const todayPlan = plans.find((plan) => String(plan.plan_date) === shanghaiDate());
  return {
    profile: {
      ...profileShape(profileResult.data),
      availableDemoGrades: isDemo ? ["高一", "高二", "高三"] : undefined,
    },
    plans: plans.map((plan) => planShape(plan, attemptResult.data || [])),
    skillStates: states,
    skillDefinitions: (skillResult.data || []).map(skillShape),
    todayQuestionCount: todayPlan ? planQuestionCount(todayPlan) : 5,
    achievements,
    videoRecommendations,
  };
}

async function guardianDashboard(studentId: string) {
  const week = shanghaiWeekRange();
  const linkResult = await supabase.from("chem_quiz_student_links").select("quiz_student_id").eq("chem_student_id", studentId).maybeSingle();
  if (linkResult.error) throw linkResult.error;
  const quizResult = linkResult.data?.quiz_student_id
    ? await supabase.from("quiz_sessions")
      .select("id,round,training_theme,correct_count,total_count,total_sec,wrong_tags,completed_at", { count: "exact" })
      .eq("student_id", linkResult.data.quiz_student_id)
      .gte("completed_at", week.startIso)
      .lt("completed_at", week.endIso)
      .order("completed_at", { ascending: false })
      .limit(50)
    : { data: [], error: null, count: 0 };
  if (quizResult.error) throw quizResult.error;
  const [profileResult, plansResult, attemptsResult, signalsResult, observationsResult, learningRecord, videoRecommendations] = await Promise.all([
    supabase.from("chem_students_v2").select("display_name,grade_band").eq("id", studentId).single(),
    supabase.from("chem_learning_plans").select("id").eq("student_id", studentId).gte("plan_date", week.startDate).lt("plan_date", week.endDate),
    supabase.from("chem_learning_attempts").select("id,plan_day_id,completed_at,mode,first_score").eq("student_id", studentId).gte("completed_at", week.startIso).lt("completed_at", week.endIso).order("completed_at", { ascending: false }),
    supabase.from("chem_behavior_signals").select("*").eq("student_id", studentId).eq("active", true),
    supabase.from("chem_teacher_observations").select("id,course_date,taught_content,guardian_message,created_at").eq("student_id", studentId).order("course_date", { ascending: false }).limit(10),
    studentLearningRecord(studentId),
    loadVideoRecommendations(studentId),
  ]);
  for (const result of [profileResult, plansResult, attemptsResult, signalsResult, observationsResult]) if (result.error) throw result.error;
  if (!profileResult.data) throw new Error("Student profile not found");
  const attempts = attemptsResult.data || [];
  const observations = observationsResult.data || [];
  const quizSessions = quizResult.data || [];
  const currentWeekPlanIds = new Set((plansResult.data || []).map((plan) => String(plan.id)));
  const completedCurrentWeekPlanIds = new Set(
    attempts.map((attempt) => String(attempt.plan_day_id)).filter((planId) => currentWeekPlanIds.has(planId)),
  );
  const teacherAttentionCount = learningRecord.skills.filter((skill) => skill.exposure === "learned" && skill.teacherIntervention).length;
  const timeline = [
    ...attempts.map((a) => ({ id: a.id, at: a.completed_at, type: "attempt", title: a.mode === "CLASS_QUIZ" ? "完成课堂小测" : "完成一次复习", description: "系统已保存本轮真实作答证据，可在学习复盘中展开查看。" })),
    ...quizSessions.map((q) => ({ id: `quiz-${q.id}`, at: q.completed_at, type: "attempt", title: `完成即时小测 · 第${q.round}轮`, description: parentQuizDescription(q) })),
    ...observations.map((o) => ({ id: o.id, at: o.created_at, type: "teacher_action", title: o.taught_content, description: o.guardian_message })),
  ].sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 20);
  return {
    student: { displayName: profileResult.data.display_name, gradeBand: profileResult.data.grade_band },
    weekRange: { startDate: week.startDate, endDateExclusive: week.endDate },
    weeklyCompleted: completedCurrentWeekPlanIds.size,
    weeklyPlanned: currentWeekPlanIds.size,
    weeklyQuizCompleted: quizResult.count ?? quizSessions.length,
    weeklyQuizTimelineTruncated: (quizResult.count ?? quizSessions.length) > quizSessions.length,
    stableSkillCount: learningRecord.summary.full,
    growingSkillCount: learningRecord.summary.partial,
    forgottenSkillCount: learningRecord.summary.unlit,
    teacherAttentionCount,
    progress: learningRecord.summary.full || learningRecord.summary.partial
      ? [`已有 ${learningRecord.summary.full} 个模块完全点亮，${learningRecord.summary.partial} 个模块正在形成证据。`]
      : ["系统正在收集第一批可靠作答证据。"],
    concerns: teacherAttentionCount
      ? [`有 ${teacherAttentionCount} 个模块已进入教师关注清单，后续会优先回看。`]
      : learningRecord.summary.due
        ? [`有 ${learningRecord.summary.due} 个已学模块到了回看时间。`]
        : ["当前没有需要立即处理的学习提醒。"],
    behaviorSignals: (signalsResult.data || []).map((s) => ({ kind: s.kind, evidenceCount: s.evidence_count, sessionCount: s.session_count, firstSeenAt: s.first_seen_at, lastSeenAt: s.last_seen_at, guardianCopy: s.guardian_copy })),
    timeline,
    skillSummary: learningRecord.summary,
    videoRecommendations,
  };
}

async function isDemoStudent(studentId: string) {
  const result = await supabase.from("chem_students_v2").select("metadata").eq("id", studentId).maybeSingle();
  if (result.error) throw result.error;
  return Boolean((result.data?.metadata as Record<string, unknown> | null)?.demo);
}

async function resolveDemoTarget(currentStudentId: string, requestedStudentId: string | undefined) {
  if (!requestedStudentId || requestedStudentId === currentStudentId) return currentStudentId;
  const [current, requested] = await Promise.all([
    supabase.from("chem_students_v2").select("id,metadata").eq("id", currentStudentId).single(),
    supabase.from("chem_students_v2").select("id,metadata").eq("id", requestedStudentId).single(),
  ]);
  if (current.error || requested.error) return null;
  const currentIsDemo = Boolean((current.data.metadata as Record<string, unknown> | null)?.demo);
  const requestedIsDemo = Boolean((requested.data.metadata as Record<string, unknown> | null)?.demo);
  return currentIsDemo && requestedIsDemo ? requested.data.id : null;
}

async function demoStudentForGrade(currentStudentId: string, gradeBand: string) {
  if (!["高一", "高二", "高三"].includes(gradeBand)) return null;
  const current = await supabase.from("chem_students_v2").select("metadata").eq("id", currentStudentId).single();
  if (current.error || !(current.data.metadata as Record<string, unknown> | null)?.demo) return null;
  const target = await supabase
    .from("chem_students_v2")
    .select("id")
    .eq("grade_band", gradeBand)
    .contains("metadata", { demo: true })
    .order("id")
    .limit(1)
    .maybeSingle();
  if (target.error || !target.data) return null;
  return target.data.id as string;
}

type StartPlanOptions = {
  allowCompletedPreview?: boolean;
  previewRound?: number;
};

async function startPlanPayload(studentId: string, planId: string, options: StartPlanOptions = {}) {
  const { data: plan, error: planError } = await supabase
    .from("chem_learning_plans")
    .select("*")
    .eq("id", planId)
    .eq("student_id", studentId)
    .single();
  if (planError) throw planError;
  const gradeResult = await supabase.from("chem_students_v2").select("grade_band").eq("id", studentId).single();
  if (gradeResult.error) throw gradeResult.error;
  const skillIds: string[] = Array.isArray(plan.skill_ids)
    ? (plan.skill_ids as unknown[]).map((skillId) => String(skillId)).filter(Boolean)
    : [];
  if (!skillIds.length) throw new RequestError(422, "当天计划尚未配置可练习的知识模块，请联系甘老师。");
  const questionCount = planQuestionCount(plan);
  const roundLimit = planRoundLimit(plan);
  const maxQuestionLevel = planMaxQuestionLevel(plan);
  if (options.previewRound !== undefined && (!Number.isInteger(options.previewRound) || options.previewRound < 1 || options.previewRound > roundLimit)) {
    throw new RequestError(400, `预览轮次必须在 1—${roundLimit} 之间。`);
  }
  const questionUsageColumn = plan.mode === "CLASS_QUIZ"
    ? "usable_for_class_quiz"
    : plan.mode === "EXAM_SPRINT"
      ? "usable_for_exam_sprint"
      : "usable_for_review";
  let eligibleQuestions = supabase
    .from("chem_questions")
    .select("*")
    .eq("grade_band", gradeResult.data.grade_band)
    .in("skill_id", skillIds)
    .eq("review_status", "approved")
    .eq("scope_status", "IN")
    .not("mother_id", "is", null)
    .eq(questionUsageColumn, true);
  if (plan.mode === "REVIEW") eligibleQuestions = eligibleQuestions.not("concept_key", "is", null);
  if (maxQuestionLevel !== null) eligibleQuestions = eligibleQuestions.lte("level", maxQuestionLevel);
  // The adaptive selector uses the source index as its final deterministic
  // tie-breaker. Ordering by the immutable question id keeps the five issued
  // questions reproducible when the server verifies them again on submit.
  eligibleQuestions = eligibleQuestions.order("id");
  const [cards, questions, planAttempts, states] = await Promise.all([
    supabase.from("chem_knowledge_cards").select("*").in("skill_id", skillIds).eq("review_status", "approved"),
    eligibleQuestions,
    supabase.from("chem_learning_attempts").select("id,attempt_kind,sequence,first_score,completed_at").eq("student_id", studentId).eq("plan_day_id", plan.id).order("sequence"),
    supabase.from("chem_student_skill_state").select("skill_id,verified_level,consecutive_errors,next_review_at").eq("student_id", studentId).in("skill_id", skillIds),
  ]);
  if (cards.error || questions.error || planAttempts.error || states.error) {
    throw cards.error || questions.error || planAttempts.error || states.error;
  }
  const attempts = planAttempts.data || [];
  const actualAttemptCount = attempts.length;
  // Questions may reappear on a later spaced-review date, but never during
  // another round of the same plan day.
  const attemptIds = attempts.map((attempt) => String(attempt.id));
  const history = attemptIds.length
    ? await supabase.from("chem_attempt_answers").select("attempt_id,question_id,mother_id,skill_id,concept_key,correct,uncertain").in("attempt_id", attemptIds).in("skill_id", skillIds)
    : { data: [], error: null };
  if (history.error) throw history.error;
  const sequenceByAttemptId = new Map(attempts.map((attempt) => [String(attempt.id), Number(attempt.sequence)]));
  const historyRows = (history.data || []).map((answer) => ({
    ...answer,
    attempt_sequence: sequenceByAttemptId.get(String(answer.attempt_id)) ?? null,
  }));
  const latestAttemptId = attempts.at(-1)?.id ? String(attempts.at(-1)?.id) : null;
  const latestAnswers = latestAttemptId
    ? historyRows.filter((answer) => String(answer.attempt_id) === latestAttemptId)
    : [];
  const isResolved = latestAnswers.length === questionCount && latestAnswers.every((answer) => answer.correct === true && answer.uncertain !== true);
  const reachedRoundLimit = actualAttemptCount >= roundLimit;
  if (!options.allowCompletedPreview && (reachedRoundLimit || isResolved)) {
    throw new RequestError(
      409,
      isResolved
        ? "今天这组问题已经全部解决，可以在战绩中回看。"
        : `今天的 ${roundLimit} 轮已经完成，可以在战绩中回看。`,
    );
  }

  const completedPreview = Boolean(options.allowCompletedPreview && actualAttemptCount > 0 && (reachedRoundLimit || isResolved));
  const selectionSequence = options.previewRound !== undefined
    ? options.previewRound - 1
    : completedPreview
      ? Math.max(0, Math.min(actualAttemptCount, roundLimit) - 1)
      : Math.min(actualAttemptCount, roundLimit - 1);
  const roundNumber = selectionSequence + 1;
  let selectionHistory = historyRows;
  let adaptiveQuestions;
  if (options.previewRound !== undefined) {
    // Preview/demo answers are intentionally not stored. Reconstruct every
    // preceding preview round as virtual unresolved evidence so rounds 2-5
    // still contain completely different questions and mother questions.
    selectionHistory = [];
    adaptiveQuestions = [];
    for (let previewIndex = 0; previewIndex <= selectionSequence; previewIndex += 1) {
      adaptiveQuestions = selectAdaptiveQuestions(
        questions.data || [],
        states.data || [],
        selectionHistory,
        previewIndex,
        questionCount,
      );
      if (adaptiveQuestions.length !== questionCount) break;
      if (previewIndex < selectionSequence) {
        selectionHistory = [
          ...selectionHistory,
          ...adaptiveQuestions.map((question) => ({
            attempt_id: `preview-${previewIndex}`,
            question_id: String(question.id),
            mother_id: question.mother_id ? String(question.mother_id) : null,
            skill_id: String(question.skill_id),
            concept_key: question.concept_key ? String(question.concept_key) : null,
            attempt_sequence: previewIndex,
            correct: false,
            uncertain: true,
          })),
        ];
      }
    }
  } else {
    adaptiveQuestions = selectAdaptiveQuestions(
      questions.data || [],
      states.data || [],
      selectionHistory,
      selectionSequence,
      questionCount,
    );
  }
  if (adaptiveQuestions.length !== questionCount) {
    throw new RequestError(
      422,
      `第 ${roundNumber} 轮需要 ${questionCount} 道今天从未出现过的已审核题，但当前只有 ${adaptiveQuestions.length} 道新母题；题库变式不足，本轮已停止并通知甘老师。`,
    );
  }
  const cardOrder = new Map(skillIds.map((skillId, index) => [skillId, index]));
  const orderedCards = [...(cards.data || [])].sort((a, b) => (cardOrder.get(a.skill_id) ?? 99) - (cardOrder.get(b.skill_id) ?? 99));
  const planAttemptRows = attempts.map((attempt) => ({
    ...attempt,
    plan_day_id: plan.id,
    chem_attempt_answers: (history.data || [])
      .filter((answer) => String(answer.attempt_id) === String(attempt.id))
      .map((answer) => ({ correct: answer.correct, uncertain: answer.uncertain })),
  }));
  return {
    plan: planShape(plan, planAttemptRows),
    cards: orderedCards.map(cardShape),
    questions: adaptiveQuestions.map(questionShape),
    attemptSequence: selectionSequence,
    roundNumber,
    roundLimit,
    questionCount,
    isResolved,
    isComplete: isResolved || reachedRoundLimit,
    roundsRemaining: isResolved || reachedRoundLimit ? 0 : Math.max(0, roundLimit - actualAttemptCount),
  };
}

async function authenticate(req: Request) {
  const token = req.headers.get("x-app-session");
  if (!token) return null;
  const { data, error } = await supabase.rpc("chem_resolve_app_session", { p_token_hash: await sha256(token) });
  if (error || !data?.length) return null;
  return { studentId: data[0].student_id as string | null, role: data[0].access_role as "student" | "guardian" | "teacher", expiresAt: data[0].expires_at as string, principalName: data[0].principal_name as string };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return reply(req, { error: "仅支持 POST 请求。" }, 405);
  try {
    const body = await req.json();
    if (body.action === "login") {
      const name = String(body.name || "").trim();
      const code = String(body.code || "").trim();
      const rawFingerprint = `${req.headers.get("x-forwarded-for") || "unknown"}|${req.headers.get("user-agent") || "unknown"}`;
      const token = randomToken();
      const expiresAt = new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString();
      const { data, error } = await supabase.rpc("chem_exchange_access_code", {
        p_name: name, p_code: code, p_fingerprint_hash: await sha256(rawFingerprint), p_token_hash: await sha256(token), p_expires_at: expiresAt,
      });
      if (error) throw error;
      if (!data?.length) return reply(req, { error: "姓名或登录码不正确，或尝试过于频繁。" }, 401);
      const identity = data[0];
      if (identity.access_role === "teacher") {
        const session = { role: "teacher", token, displayName: identity.principal_name || "甘老师", expiresAt };
        return reply(req, { session });
      }
      const { data: student, error: profileError } = await supabase.from("chem_students_v2").select("display_name").eq("id", identity.student_id).single();
      if (profileError) throw profileError;
      const session = { role: identity.access_role, token, displayName: identity.principal_name || student.display_name, expiresAt };
      const dashboard = identity.access_role === "guardian" ? await guardianDashboard(identity.student_id) : await studentDashboard(identity.student_id);
      return reply(req, { session, dashboard });
    }

    if (body.action === "recover_access_code") {
      const name = String(body.data?.name || "").trim();
      const recoverySecret = String(body.data?.recoverySecret || "").trim();
      const newCode = String(body.data?.newCode || "").trim();
      const rawFingerprint = `${req.headers.get("x-forwarded-for") || "unknown"}|${req.headers.get("user-agent") || "unknown"}`;
      const { data, error } = await supabase.rpc("chem_recover_access_code", {
        p_name: name,
        p_recovery_secret: recoverySecret,
        p_new_code: newCode,
        p_fingerprint_hash: await sha256(rawFingerprint),
      });
      if (error) throw error;
      if (!data) return reply(req, { error: "姓名或找回信息不匹配，或尝试过于频繁。" }, 400);
      return reply(req, { ok: true });
    }

    const identity = await authenticate(req);
    if (!identity) return reply(req, { error: "登录已失效，请重新输入访问码。" }, 401);
    if (body.action === "student_dashboard" && identity.role === "student" && identity.studentId) return reply(req, { dashboard: await studentDashboard(identity.studentId) });
    if (body.action === "guardian_dashboard" && identity.role === "guardian" && identity.studentId) return reply(req, { dashboard: await guardianDashboard(identity.studentId) });

    if (body.action === "record_video_engagement" && identity.role === "student" && identity.studentId) {
      if (await isDemoStudent(identity.studentId)) return reply(req, { error: "演示账号为只读账号。" }, 403);
      const recommendationId = String(body.data?.recommendationId || "");
      const event = String(body.data?.event || "");
      if (!validUuid(recommendationId) || !["open", "progress", "complete"].includes(event)) {
        return reply(req, { error: "视频学习记录信息无效。" }, 400);
      }
      const progressSeconds = event === "open" || body.data?.progressSeconds === undefined
        ? null
        : Number(body.data.progressSeconds);
      const durationSeconds = event === "open" || body.data?.durationSeconds === undefined
        ? null
        : Number(body.data.durationSeconds);
      const trackingMethod = event === "open" ? "link_open_only" : String(body.data?.trackingMethod || "");
      if (
        (event === "progress" && !Number.isInteger(progressSeconds))
        || (progressSeconds !== null && !Number.isInteger(progressSeconds))
        || (durationSeconds !== null && !Number.isInteger(durationSeconds))
      ) {
        return reply(req, { error: "请提供有效的观看位置；视频总时长可以留空。" }, 400);
      }
      const engagement = await supabase.rpc("chem_video_record_engagement", {
        p_recommendation_id: recommendationId,
        p_student_id: identity.studentId,
        p_event_type: event,
        p_progress_position_seconds: progressSeconds,
        p_duration_seconds: durationSeconds,
        p_tracking_method: trackingMethod,
      });
      if (engagement.error) {
        console.warn("video engagement rejected", engagement.error.message);
        return reply(req, { error: "该视频的观看进度无法按所选方式验证，请重新打开后再试。" }, 400);
      }
      if (!engagement.data) return reply(req, { error: "该讲解视频不存在、尚未发布或已撤回。" }, 404);
      const recommendations = await loadVideoRecommendations(identity.studentId);
      return reply(req, { recommendation: recommendations.find((item) => item.id === recommendationId) || null });
    }

    if (body.action === "learning_record" && identity.role === "student" && identity.studentId) {
      const requestedStudentId = body.data?.studentId ? String(body.data.studentId) : undefined;
      const targetId = await resolveDemoTarget(identity.studentId, requestedStudentId);
      if (!targetId) return reply(req, { error: "无权查看该学习档案。" }, 403);
      return reply(req, { record: await studentLearningRecord(targetId) });
    }

    if (body.action === "learning_record" && identity.role === "guardian" && identity.studentId) {
      const requestedStudentId = body.data?.studentId ? String(body.data.studentId) : identity.studentId;
      if (requestedStudentId !== identity.studentId) return reply(req, { error: "无权查看该学习档案。" }, 403);
      return reply(req, { record: await studentLearningRecord(identity.studentId) });
    }

    if (body.action === "demo_dashboard" && identity.role === "student" && identity.studentId) {
      const targetId = await demoStudentForGrade(identity.studentId, String(body.data?.gradeBand || ""));
      if (!targetId) return reply(req, { error: "该演示年级不可用。" }, 403);
      return reply(req, { dashboard: await studentDashboard(targetId) });
    }

    if (body.action === "student_preview_dashboard" && identity.role === "teacher") {
      const targetId = String(body.data?.studentId || "");
      if (!targetId) return reply(req, { error: "请选择要预览的学生。" }, 400);
      return reply(req, { dashboard: await studentDashboard(targetId) });
    }

    if (body.action === "student_learning_record" && identity.role === "teacher") {
      const targetId = String(body.data?.studentId || "");
      if (!targetId) return reply(req, { error: "请选择要预览的学生。" }, 400);
      return reply(req, { record: await studentLearningRecord(targetId) });
    }

    if (body.action === "preview_start_plan" && identity.role === "teacher") {
      const targetId = String(body.data?.studentId || "");
      const planId = String(body.data?.planId || "");
      if (!targetId || !planId) return reply(req, { error: "预览信息不完整。" }, 400);
      const previewRound = body.data?.previewRound === undefined ? undefined : Number(body.data.previewRound);
      return reply(req, { payload: await startPlanPayload(targetId, planId, { allowCompletedPreview: true, previewRound }) });
    }

    if (body.action === "change_own_code" && identity.role === "student") {
      if (!identity.studentId || await isDemoStudent(identity.studentId)) return reply(req, { error: "演示账号为只读账号。" }, 403);
      const token = req.headers.get("x-app-session") || "";
      const { data, error } = await supabase.rpc("chem_change_own_access_code", {
        p_token_hash: await sha256(token),
        p_current_code: String(body.data?.currentCode || "").trim(),
        p_new_code: String(body.data?.newCode || "").trim(),
      });
      if (error) throw error;
      if (!data) return reply(req, { error: "当前登录码不正确，或新登录码不符合要求。" }, 400);
      return reply(req, { ok: true });
    }

    if (body.action === "set_recovery_secret" && identity.role === "student") {
      if (!identity.studentId || await isDemoStudent(identity.studentId)) return reply(req, { error: "演示账号为只读账号。" }, 403);
      const token = req.headers.get("x-app-session") || "";
      const { data, error } = await supabase.rpc("chem_set_recovery_secret", {
        p_token_hash: await sha256(token),
        p_current_code: String(body.data?.currentCode || "").trim(),
        p_recovery_secret: String(body.data?.recoverySecret || "").trim(),
      });
      if (error) throw error;
      if (!data) return reply(req, { error: "当前登录码不正确，或找回短语不符合要求。" }, 400);
      return reply(req, { ok: true });
    }

    if (body.action === "start_plan" && identity.role === "student" && identity.studentId) {
      const targetId = await resolveDemoTarget(identity.studentId, body.data?.studentId ? String(body.data.studentId) : undefined);
      if (!targetId) return reply(req, { error: "无权打开该学习计划。" }, 403);
      const planId = String(body.data?.planId || "");
      if (!planId) return reply(req, { error: "学习计划信息不完整。" }, 400);
      const previewRound = body.data?.previewRound === undefined ? undefined : Number(body.data.previewRound);
      const demo = await isDemoStudent(targetId);
      if (previewRound !== undefined && !demo) return reply(req, { error: "真实学习记录不能指定练习轮次。" }, 403);
      return reply(req, {
        payload: await startPlanPayload(targetId, planId, demo ? { allowCompletedPreview: true, previewRound } : {}),
      });
    }

    if (body.action === "submit_attempt" && identity.role === "student" && identity.studentId) {
      const attempt = body.data;
      if (
        !attempt ||
        !attempt.studentId ||
        !attempt.planDayId ||
        !Array.isArray(attempt.answers) ||
        attempt.answers.length > 10
      ) return reply(req, { error: "提交内容不完整。" }, 400);
      const targetId = await resolveDemoTarget(identity.studentId, String(attempt.studentId));
      if (!targetId) return reply(req, { error: "无权提交该学习记录。" }, 403);
      const targetProfile = await supabase.from("chem_students_v2").select("grade_band,metadata").eq("id", targetId).single();
      if (targetProfile.error) throw targetProfile.error;
      if ((targetProfile.data.metadata as Record<string, unknown> | null)?.demo) {
        return reply(req, { dashboard: await studentDashboard(targetId), achievements: [], simulated: true });
      }

      const { data: plan, error: planError } = await supabase
        .from("chem_learning_plans")
        .select("id,student_id,mode,skill_ids,question_count,round_limit,max_question_level")
        .eq("id", String(attempt.planDayId))
        .eq("student_id", targetId)
        .maybeSingle();
      if (planError) throw planError;
      if (!plan) return reply(req, { error: "无权提交该学习记录。" }, 403);

      const submittedAnswers = attempt.answers as Array<Record<string, unknown>>;
      const questionCount = planQuestionCount(plan);
      const roundLimit = planRoundLimit(plan);
      const maxQuestionLevel = planMaxQuestionLevel(plan);
      if (submittedAnswers.length !== questionCount) {
        return reply(req, { error: `每轮必须完整提交 ${questionCount} 道题，请重新打开本轮练习。` }, 400);
      }
      const questionIds = submittedAnswers.map((answer) => String(answer.questionId || ""));
      if (questionIds.some((id) => !id) || new Set(questionIds).size !== questionIds.length) {
        return reply(req, { error: "题目记录无效，请重新打开本轮练习。" }, 400);
      }
      const planSkillIds = Array.isArray(plan.skill_ids) ? plan.skill_ids.map(String) : [];
      if (!planSkillIds.length) return reply(req, { error: "当前学习计划没有可提交的题目。" }, 400);
      const questionUsageColumn = plan.mode === "CLASS_QUIZ"
        ? "usable_for_class_quiz"
        : plan.mode === "EXAM_SPRINT"
          ? "usable_for_exam_sprint"
          : "usable_for_review";
      let questionQuery = supabase
        .from("chem_questions")
        .select("id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,explanation,image_url,review_status,scope_status")
        .in("id", questionIds)
        .eq("grade_band", targetProfile.data.grade_band)
        .in("skill_id", planSkillIds)
        .eq("review_status", "approved")
        .eq("scope_status", "IN")
        .not("mother_id", "is", null)
        .eq(questionUsageColumn, true);
      if (plan.mode === "REVIEW") questionQuery = questionQuery.not("concept_key", "is", null);
      if (maxQuestionLevel !== null) questionQuery = questionQuery.lte("level", maxQuestionLevel);
      const [questionResult, planAttemptsResult] = await Promise.all([
        questionQuery,
        supabase
          .from("chem_learning_attempts")
          .select("id,sequence")
          .eq("student_id", targetId)
          .eq("plan_day_id", plan.id)
          .order("sequence"),
      ]);
      if (questionResult.error || planAttemptsResult.error) throw questionResult.error || planAttemptsResult.error;
      if ((questionResult.data || []).length !== questionIds.length) {
        return reply(req, { error: "本轮包含未审核、超出范围或高于当前难度上限的题目，请重新打开练习。" }, 400);
      }
      const previousAttempts = planAttemptsResult.data || [];
      const attemptSequence = previousAttempts.length;
      if (attemptSequence >= roundLimit) {
        return reply(req, { error: `今天的 ${roundLimit} 轮已经完成，不能再写入新的学习记录。` }, 409);
      }
      if (!Number.isInteger(Number(attempt.sequence)) || Number(attempt.sequence) !== attemptSequence) {
        return reply(req, { error: "学习轮次已经变化，请刷新当天计划后再作答。" }, 409);
      }
      const previousAttemptIds = previousAttempts.map((item) => String(item.id));
      const priorAnswersResult = previousAttemptIds.length
        ? await supabase
          .from("chem_attempt_answers")
          .select("attempt_id,question_id,mother_id,concept_key,correct,uncertain")
          .in("attempt_id", previousAttemptIds)
        : { data: [], error: null };
      if (priorAnswersResult.error) throw priorAnswersResult.error;
      const priorAnswers = priorAnswersResult.data || [];
      const usedQuestionIds = new Set(priorAnswers.map((answer) => String(answer.question_id)));
      const usedMotherIds = new Set(priorAnswers.map((answer) => String(answer.mother_id)).filter(Boolean));
      const submittedMothers = (questionResult.data || []).map((question) => String(question.mother_id));
      if (
        submittedMothers.some((motherId) => !motherId) ||
        new Set(submittedMothers).size !== submittedMothers.length ||
        (questionResult.data || []).some((question) =>
          usedQuestionIds.has(String(question.id)) || usedMotherIds.has(String(question.mother_id))
        )
      ) {
        return reply(req, { error: "同一天的后续轮次不能重复题目或同一母题，请重新打开本轮练习。" }, 409);
      }
      const latestAttemptId = previousAttempts.at(-1)?.id ? String(previousAttempts.at(-1)?.id) : null;
      if (latestAttemptId) {
        const latestAnswers = priorAnswers.filter((answer) => String(answer.attempt_id) === latestAttemptId);
        if (latestAnswers.length === questionCount && latestAnswers.every((answer) => answer.correct === true && answer.uncertain !== true)) {
          return reply(req, { error: "今天这组问题已经全部解决，不能再写入新的学习记录。" }, 409);
        }
      }

      if (plan.mode === "REVIEW") {
        // Never trust a client to substitute five other eligible questions.
        // Rebuild the exact adaptive set for the current round from the
        // server-owned plan, skill state and answer history, then compare it
        // as an unordered set with what the student actually received.
        const expectedPayload = await startPlanPayload(targetId, String(plan.id));
        const expectedQuestionIds = (expectedPayload.questions as Array<{ id: unknown }>).map((question) => String(question.id));
        const expectedQuestionIdSet = new Set(expectedQuestionIds);
        if (
          Number(expectedPayload.attemptSequence) !== attemptSequence ||
          expectedQuestionIds.length !== questionIds.length ||
          questionIds.some((questionId) => !expectedQuestionIdSet.has(questionId))
        ) {
          return reply(req, { error: "本轮题目已经变化或不属于系统刚刚生成的自适应题组，请重新打开本轮练习。" }, 409);
        }
      }

      const questionById = new Map((questionResult.data || []).map((question) => [String(question.id), question]));
      const canonicalAnswers: Array<{
        question_id: string;
        mother_id: string;
        skill_id: string;
        concept_key: string | null;
        level: number;
        correct: boolean;
        uncertain: boolean;
        duration_sec: number;
        selected_option: number;
        question_snapshot: Record<string, unknown>;
      }> = [];
      for (const submitted of submittedAnswers) {
        const question = questionById.get(String(submitted.questionId));
        const selectedOption = typeof submitted.selectedOption === "number" ? submitted.selectedOption : Number.NaN;
        const options = Array.isArray(question?.options) ? question.options : [];
        if (!question || !Number.isInteger(selectedOption) || selectedOption < 0 || selectedOption >= options.length) {
          return reply(req, { error: "答案选项无效，请重新打开本轮练习。" }, 400);
        }
        const rawDuration = Number(submitted.durationSec);
        canonicalAnswers.push({
          question_id: String(question.id),
          mother_id: String(question.mother_id),
          skill_id: String(question.skill_id),
          concept_key: question.concept_key ? String(question.concept_key) : null,
          level: Number(question.level),
          correct: selectedOption === Number(question.correct_option),
          uncertain: submitted.uncertain === true,
          duration_sec: Number.isFinite(rawDuration) ? Math.min(3600, Math.max(0, Math.round(rawDuration))) : 0,
          selected_option: selectedOption,
          question_snapshot: {
            version: 1,
            source: "submission",
            capturedAt: new Date().toISOString(),
            questionId: String(question.id),
            motherId: String(question.mother_id),
            skillId: String(question.skill_id),
            conceptKey: question.concept_key ? String(question.concept_key) : null,
            level: Number(question.level),
            gradeBand: String(question.grade_band),
            stem: String(question.stem),
            options: options.map(String),
            correctOption: Number(question.correct_option),
            explanation: String(question.explanation),
            imageUrl: question.image_url ? String(question.image_url) : null,
            reviewStatus: String(question.review_status),
            scopeStatus: String(question.scope_status),
          },
        });
      }

      const canonicalSkillIds = [...new Set(canonicalAnswers.map((answer) => answer.skill_id))];
      const currentStatesResult = await supabase
        .from("chem_student_skill_state")
        .select("skill_id,verified_level,candidate_level,consecutive_errors,review_interval_index")
        .eq("student_id", targetId)
        .in("skill_id", canonicalSkillIds);
      if (currentStatesResult.error) throw currentStatesResult.error;
      const currentStateBySkill = new Map((currentStatesResult.data || []).map((state) => [String(state.skill_id), state]));
      const computedStateBySkill = new Map<string, Record<string, unknown>>();
      const completedAt = new Date();
      const completedAtIso = completedAt.toISOString();
      for (const answer of canonicalAnswers) {
        const current = computedStateBySkill.get(answer.skill_id) || currentStateBySkill.get(answer.skill_id);
        const previousErrors = Number(current?.consecutive_errors || 0);
        const confidentlyCorrect = answer.correct && !answer.uncertain;
        computedStateBySkill.set(answer.skill_id, {
          student_id: targetId,
          skill_id: answer.skill_id,
          verified_level: Math.max(Number(current?.verified_level || 0), confidentlyCorrect ? answer.level : 0),
          candidate_level: confidentlyCorrect ? answer.level : current?.candidate_level ?? null,
          stability: confidentlyCorrect ? "verified" : "learning",
          consecutive_errors: confidentlyCorrect ? 0 : previousErrors + 1,
          next_review_at: new Date(completedAt.getTime() + (confidentlyCorrect ? 3 : 1) * 86400000).toISOString(),
          review_interval_index: confidentlyCorrect ? Math.min(4, Number(current?.review_interval_index || 0) + 1) : 0,
          last_reviewed_at: completedAtIso,
          teacher_intervention: !confidentlyCorrect && previousErrors >= 2,
          updated_at: completedAtIso,
        });
      }

      const submittedStartedAt = new Date(String(attempt.startedAt || ""));
      const startedAt = Number.isFinite(submittedStartedAt.getTime()) && submittedStartedAt <= completedAt
        ? submittedStartedAt.toISOString()
        : completedAtIso;
      const attemptId = String(attempt.id || "");
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(attemptId)) {
        return reply(req, { error: "提交标识无效，请重新打开本轮练习。" }, 400);
      }
      const { error: attemptError } = await supabase.from("chem_learning_attempts").insert({
        id: attemptId,
        student_id: targetId,
        plan_day_id: plan.id,
        attempt_kind: attemptSequence === 0 ? "scheduled" : "review",
        sequence: attemptSequence,
        mode: plan.mode,
        started_at: startedAt,
        completed_at: completedAtIso,
        first_score: canonicalAnswers.filter((answer) => answer.correct).length,
      });
      if (attemptError?.code === "23505") {
        return reply(req, { error: "这一轮已经提交，不能重复写入。请返回学习计划刷新状态。" }, 409);
      }
      if (attemptError) throw attemptError;
      const answers = canonicalAnswers.map((answer) => ({ attempt_id: attemptId, ...answer }));
      const { error: answersError } = await supabase.from("chem_attempt_answers").insert(answers);
      if (answersError) {
        await supabase.from("chem_learning_attempts").delete().eq("id", attemptId).eq("student_id", targetId);
        throw answersError;
      }
      const skillStateResult = await supabase
        .from("chem_student_skill_state")
        .upsert([...computedStateBySkill.values()], { onConflict: "student_id,skill_id" });
      if (skillStateResult.error) {
        await supabase.from("chem_learning_attempts").delete().eq("id", attemptId).eq("student_id", targetId);
        throw skillStateResult.error;
      }
      return reply(req, { dashboard: await studentDashboard(targetId), achievements: [] });
    }
    return reply(req, { error: "无权执行该操作。" }, 403);
  } catch (error) {
    if (error instanceof RequestError) return reply(req, { error: error.message }, error.status);
    console.error(error);
    return reply(req, { error: "服务暂时不可用，请稍后重试。" }, 500);
  }
});
