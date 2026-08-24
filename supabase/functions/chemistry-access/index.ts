import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { selectAdaptiveQuestions } from "./adaptive.ts";
import { effectiveReviewRoundLimit, FORMAL_REVIEW_DAILY_QUESTION_CAP, isFormalHighSchoolReview, validFormalReviewQuestionCount, validFormalReviewRoundLimit } from "./review-daily-policy.ts";
import { selectJuniorNextQuestion, type JuniorAdaptiveCandidate, type JuniorAdaptiveHistory, type JuniorRouteKind } from "./junior-adaptive.ts";
import { issuedAssetRefs, issuedSolutionFields, matchingSourceAssetRef, shouldHideLicensedHighSchoolSolution, sourceAssetPhaseStatus, sourceQuestionPhaseStatus } from "./source-security.ts";

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
    "Access-Control-Max-Age": "86400",
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
  const cap = row.delivery_mode === "junior_adaptive" ? 15 : 10;
  return Number.isInteger(value) && value >= 1 && value <= cap ? value : 5;
}

function planRoundLimit(row: Record<string, unknown>) {
  const value = Number(row.round_limit);
  return Number.isInteger(value) && value >= 1 && value <= 8 ? value : 5;
}

type ReviewProfileContext = { gradeBand: string; isDemo: boolean };

function effectivePlanRoundLimit(row: Record<string, unknown>, profile?: ReviewProfileContext) {
  const storedRoundLimit = planRoundLimit(row);
  if (!profile) return storedRoundLimit;
  return effectiveReviewRoundLimit({
    mode: String(row.mode || ""),
    gradeBand: profile.gradeBand,
    isDemo: profile.isDemo,
    questionCount: planQuestionCount(row),
    storedRoundLimit,
  });
}

function formalReviewContext(row: Record<string, unknown>, profile: ReviewProfileContext) {
  return {
    mode: String(row.mode || ""),
    gradeBand: profile.gradeBand,
    isDemo: profile.isDemo,
  };
}

function confirmedHighOneSkillIds(metadata: unknown) {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) return [];
  const raw = (metadata as Record<string, unknown>).confirmedLearnedSkillIds;
  return Array.isArray(raw) ? [...new Set(raw.map(String).map((value) => value.trim()).filter(Boolean))] : [];
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
const planShape = (
  row: Record<string, unknown>,
  attemptRows: Array<Record<string, unknown>> = [],
  juniorSession?: Record<string, unknown>,
  profile?: ReviewProfileContext,
) => {
  const deliveryMode = row.delivery_mode === "junior_adaptive" ? "junior_adaptive" : "legacy_round";
  const attempts = attemptRows
    .filter((attempt) => attempt.plan_day_id === row.id)
    .sort((a, b) => String(a.completed_at).localeCompare(String(b.completed_at)));
  const first = attempts.find((attempt) => attempt.attempt_kind === "scheduled") || attempts[0];
  const latest = attempts.at(-1);
  const questionCount = planQuestionCount(row);
  const roundLimit = effectivePlanRoundLimit(row, profile);
  const latestAnswers = Array.isArray(latest?.chem_attempt_answers)
    ? latest.chem_attempt_answers as Array<Record<string, unknown>>
    : [];
  // With tiered originals, a fully correct first round is evidence to raise
  // difficulty, not a reason to stop. The fastest valid path is L1→L2→L3.
  const maximumLevel = planMaxQuestionLevel(row);
  const isResolved = maximumLevel !== null && latestAnswers.length === questionCount && latestAnswers.every((answer) => {
    const snapshot = answer.question_snapshot as Record<string, unknown> | null;
    return answer.correct === true && answer.uncertain !== true && Number(snapshot?.level || 0) >= maximumLevel;
  });
  const juniorCompleted = deliveryMode === "junior_adaptive" && juniorSession?.status === "completed";
  const isComplete = juniorCompleted || isResolved || attempts.length >= roundLimit;
  return {
    id: row.id, studentId: row.student_id, date: row.plan_date, mode: row.mode, title: row.title,
    skillIds: row.skill_ids || [], targetConceptKeys: planTargetConceptKeys(row),
    knowledgeSummaries: row.knowledge_summaries || [],
    estimatedMinutes: row.estimated_minutes, source: row.source, isScheduled: row.is_scheduled,
    questionCount, roundLimit, maxQuestionLevel: maximumLevel, deliveryMode,
    juniorSessionStatus: deliveryMode === "junior_adaptive" ? String(juniorSession?.status || "not_started") : null,
    hardQuestionCap: deliveryMode === "junior_adaptive" ? 15 : null,
    attemptCount: deliveryMode === "junior_adaptive" && juniorCompleted ? 1 : attempts.length, firstScore: deliveryMode === "junior_adaptive" && juniorSession ? Number(juniorSession.correct_count || 0) : first?.first_score ?? null,
    latestScore: latest?.first_score ?? null, latestCompletedAt: latest?.completed_at ?? null,
    isResolved, isComplete, roundsRemaining: isComplete ? 0 : Math.max(0, roundLimit - attempts.length),
  };
};

function planTargetConceptKeys(row: Record<string, unknown>) {
  if (!Array.isArray(row.target_concept_keys)) return [];
  return (row.target_concept_keys as unknown[]).map((value) => String(value).trim()).filter(Boolean);
}

function questionSourceInfo(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  const title = String(source.title || "").trim();
  const exam = String(source.exam || "").trim();
  const questionNo = String(source.questionNo || "").trim();
  const locator = String(source.locator || "").trim();
  if (!title || !exam || !questionNo || !locator) return null;
  return {
    title,
    exam,
    year: source.year === null || source.year === undefined ? null : String(source.year),
    questionNo,
    locator,
    transcriptionPolicy: source.transcriptionPolicy === "verbatim_normalized"
      ? "verbatim_normalized"
      : "source_image_authoritative",
  };
}

function questionAssetRefs(value: unknown, includeAnalysis = false) {
  if (!Array.isArray(value)) return [];
  return value.flatMap((candidate) => {
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return [];
    const asset = candidate as Record<string, unknown>;
    const path = String(asset.path || "");
    const kind = String(asset.kind || "");
    const alt = String(asset.alt || "").trim();
    const sha256 = String(asset.sha256 || "");
    const width = Number(asset.width);
    const height = Number(asset.height);
    if (
      !/^[a-zA-Z0-9/_-]{16,200}$/.test(path)
      || !["question_image", "formula_fallback", "source_scan", "analysis_image"].includes(kind)
      || (kind === "analysis_image" && !includeAnalysis)
      || !alt
      || !/^[0-9a-f]{64}$/.test(sha256)
      || !Number.isInteger(width)
      || !Number.isInteger(height)
      || width <= 0
      || height <= 0
    ) return [];
    return [{ kind, assetId: path, alt, sha256, width, height }];
  });
}

function hasRequiredReviewSourceAssets(value: unknown) {
  const refs = questionAssetRefs(value, true);
  return refs.some((ref) => ref.kind === "question_image")
    && refs.some((ref) => ref.kind === "analysis_image");
}

function verifiedSourceReleaseId(rows: Array<Record<string, unknown>>, gradeBand: string) {
  const matching = rows.filter((row) =>
    String(row.grade_band) === gradeBand && validUuid(String(row.source_release_id || ""))
  );
  if (matching.length !== 1) {
    throw new RequestError(422, `${gradeBand}当前必须且只能有一个已完成全量图像核验的正式原题版本，已停止下发并通知甘老师。`);
  }
  return String(matching[0].source_release_id);
}

async function activeVerifiedSourceReleaseId(gradeBand: string) {
  const result = await supabase.rpc("chem_active_verified_source_releases");
  if (result.error) throw result.error;
  return verifiedSourceReleaseId((result.data || []) as Array<Record<string, unknown>>, gradeBand);
}

function matchingRawAssetRef(
  value: unknown,
  assetId: string,
  asset: Record<string, unknown>,
) {
  return matchingSourceAssetRef(value, assetId, asset);
}

function sourceIdentity(row: Record<string, unknown> | null | undefined) {
  if (!row) return { sourceItemKey: null as string | null, contentFingerprint: null as string | null };
  const sourceItemKey = String(row.source_item_key || row.sourceItemKey || "").trim() || null;
  const contentFingerprint = String(
    row.content_fingerprint || row.contentFingerprint || "",
  ).trim() || null;
  return { sourceItemKey, contentFingerprint };
}

type SourceAdaptiveQuestion = Record<string, unknown> & {
  id: string;
  mother_id?: string;
  skill_id: string;
  concept_key?: string | null;
  level: number;
  source_item_key?: string | null;
  content_fingerprint?: string | null;
  question_revision_token?: string | null;
};

type SourceAdaptiveHistory = Record<string, unknown> & {
  attempt_id: string;
  question_id: string;
  mother_id?: string | null;
  skill_id?: string | null;
  concept_key?: string | null;
  question_level?: number | null;
  source_item_key?: string | null;
  content_fingerprint?: string | null;
  attempt_sequence?: number | null;
  correct: boolean;
  uncertain?: boolean | null;
  question_snapshot?: unknown;
};

function latestConceptsAtMaximumDifficulty(
  latestAnswers: SourceAdaptiveHistory[],
  questionPool: SourceAdaptiveQuestion[],
  questionCount: number,
) {
  if (latestAnswers.length !== questionCount) return false;
  const maximumByConcept = new Map<string, number>();
  for (const question of questionPool) {
    const conceptKey = String(question.concept_key || "");
    if (!conceptKey) continue;
    maximumByConcept.set(conceptKey, Math.max(maximumByConcept.get(conceptKey) || 0, Number(question.level) || 0));
  }
  return latestAnswers.every((answer) => {
    const conceptKey = String(answer.concept_key || "");
    return answer.correct === true
      && answer.uncertain !== true
      && Boolean(conceptKey)
      && Number(answer.question_level || 0) >= Number(maximumByConcept.get(conceptKey) || Number.POSITIVE_INFINITY);
  });
}

function sourceDistinctQuestionPool<T extends Record<string, unknown>>(
  questions: T[],
  history: Array<Record<string, unknown>>,
): T[] {
  const usedSourceItems = new Set<string>();
  const usedFingerprints = new Set<string>();
  for (const answer of history) {
    const identity = sourceIdentity(answer);
    if (identity.sourceItemKey) usedSourceItems.add(identity.sourceItemKey);
    if (identity.contentFingerprint) usedFingerprints.add(identity.contentFingerprint);
  }
  const candidateSourceItems = new Set<string>();
  const candidateFingerprints = new Set<string>();
  return questions.filter((question) => {
    const identity = sourceIdentity(question);
    if (
      (identity.sourceItemKey && (usedSourceItems.has(identity.sourceItemKey) || candidateSourceItems.has(identity.sourceItemKey)))
      || (identity.contentFingerprint && (usedFingerprints.has(identity.contentFingerprint) || candidateFingerprints.has(identity.contentFingerprint)))
    ) return false;
    if (identity.sourceItemKey) candidateSourceItems.add(identity.sourceItemKey);
    if (identity.contentFingerprint) candidateFingerprints.add(identity.contentFingerprint);
    return true;
  });
}

function isLicensedHighSchoolQuestion(row: Record<string, unknown>) {
  return ["高一", "高二", "高三"].includes(String(row.grade_band)) && row.source_kind === "licensed_local";
}

const questionShape = (row: Record<string, unknown>, secureLicensedHighSchoolReview = false) => {
  const hideSolution = shouldHideLicensedHighSchoolSolution(row, secureLicensedHighSchoolReview);
  return {
    id: row.id, motherId: row.mother_id, skillId: row.skill_id, conceptKey: row.concept_key, level: row.level,
    gradeBand: row.grade_band, stem: row.stem, options: row.options,
    ...issuedSolutionFields(row, hideSolution),
    reviewStatus: row.review_status, scopeStatus: row.scope_status, sourceKind: row.source_kind,
    imageUrl: row.image_url, sourceInfo: hideSolution ? null : questionSourceInfo(row.source_info),
    // Answer-bearing analysis references are issued only by question_feedback
    // after the server has atomically locked the student's first selection.
    assetRefs: issuedAssetRefs(questionAssetRefs(row.asset_refs, true), hideSolution),
    renderMode: ["native", "image_assist", "image_primary"].includes(String(row.render_mode)) ? row.render_mode : "native",
    revisionToken: row.question_revision_token ? String(row.question_revision_token) : null,
  };
};

function questionFeedbackShape(
  row: Record<string, unknown>,
  selectedOption: number,
  answerMeta: { uncertain?: boolean; durationSec?: number } = {},
) {
  const correctOption = Number(row.correct_option);
  return {
    questionId: String(row.id),
    selectedOption,
    uncertain: answerMeta.uncertain === true,
    durationSec: Number.isFinite(answerMeta.durationSec) ? Number(answerMeta.durationSec) : 0,
    correct: selectedOption === correctOption,
    correctOption,
    explanation: String(row.explanation || ""),
    scaffold: row.scaffold ? String(row.scaffold) : null,
    // Students receive the teacher-written, option-by-option explanation only.
    // Original answer-sheet images remain available in the teacher audit view
    // and are never issued to student or guardian payloads.
    analysisAssetRefs: [],
    revisionToken: row.question_revision_token ? String(row.question_revision_token) : null,
  };
}

const KNOWLEDGE_VISUAL_KINDS = new Set(["tree", "flow", "cycle", "compare", "network", "balance"]);

function nonEmptyKnowledgeString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0;
}

function validKnowledgeTreeNode(value: unknown, depth = 0): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value) || depth > 8) return false;
  const node = value as Record<string, unknown>;
  if (!nonEmptyKnowledgeString(node.label) || !nonEmptyKnowledgeString(node.rule)) return false;
  for (const key of ["examples", "visualSteps"] as const) {
    if (node[key] !== undefined
      && (!Array.isArray(node[key]) || !(node[key] as unknown[]).every(nonEmptyKnowledgeString))) return false;
  }
  if (node.caution !== undefined && !nonEmptyKnowledgeString(node.caution)) return false;
  if (node.children !== undefined
    && (!Array.isArray(node.children)
      || !(node.children as unknown[]).every((child) => validKnowledgeTreeNode(child, depth + 1)))) return false;
  return true;
}

function validKnowledgeVisual(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const visual = value as Record<string, unknown>;
  const kind = String(visual.kind || "");
  if (!KNOWLEDGE_VISUAL_KINDS.has(kind) || !nonEmptyKnowledgeString(visual.title)) return false;
  if (kind === "tree") {
    const validTree = (node: unknown, depth = 0): boolean => {
      if (!node || typeof node !== "object" || Array.isArray(node) || depth > 8) return false;
      const branch = node as Record<string, unknown>;
      return nonEmptyKnowledgeString(branch.label)
        && (branch.children === undefined
          || (Array.isArray(branch.children)
            && (branch.children as unknown[]).every((child) => validTree(child, depth + 1))));
    };
    if (!validTree(visual.tree)) return false;
  }
  if (["flow", "cycle"].includes(kind)) {
    if (!Array.isArray(visual.steps) || !visual.steps.length
      || !(visual.steps as unknown[]).every((step) => step && typeof step === "object"
        && !Array.isArray(step) && nonEmptyKnowledgeString((step as Record<string, unknown>).label))) return false;
  }
  if (["compare", "network", "balance"].includes(kind)) {
    if (!Array.isArray(visual.groups) || !visual.groups.length
      || !(visual.groups as unknown[]).every((group) => {
        if (!group || typeof group !== "object" || Array.isArray(group)) return false;
        const row = group as Record<string, unknown>;
        return nonEmptyKnowledgeString(row.label)
          && Array.isArray(row.items) && row.items.length > 0
          && (row.items as unknown[]).every(nonEmptyKnowledgeString);
      })) return false;
  }
  return true;
}

function validStructuredKnowledgeContent(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const content = value as Record<string, unknown>;
  if (!Number.isInteger(Number(content.version)) || Number(content.version) < 1) return false;
  if (!nonEmptyKnowledgeString(content.intro)) return false;
  if (!Array.isArray(content.sections) || !content.sections.length) return false;
  if (!(content.sections as unknown[]).every((section) => {
    if (!section || typeof section !== "object" || Array.isArray(section)) return false;
    const row = section as Record<string, unknown>;
    return nonEmptyKnowledgeString(row.title)
      && Array.isArray(row.items) && row.items.length > 0
      && (row.items as unknown[]).every((item) => validKnowledgeTreeNode(item));
  })) return false;
  if (content.rootTree !== undefined && !validKnowledgeTreeNode(content.rootTree)) return false;
  if (content.visualSummary !== undefined && !validKnowledgeVisual(content.visualSummary)) return false;
  if (content.overview !== undefined
    && (!Array.isArray(content.overview) || !(content.overview as unknown[]).every(nonEmptyKnowledgeString))) return false;
  if (content.checkpoints !== undefined
    && (!Array.isArray(content.checkpoints) || !(content.checkpoints as unknown[]).every(nonEmptyKnowledgeString))) return false;
  if (content.workedExamples !== undefined
    && (!Array.isArray(content.workedExamples)
      || !(content.workedExamples as unknown[]).every((example) => {
        if (!example || typeof example !== "object" || Array.isArray(example)) return false;
        const row = example as Record<string, unknown>;
        return nonEmptyKnowledgeString(row.substance)
          && nonEmptyKnowledgeString(row.path)
          && Array.isArray(row.labels) && (row.labels as unknown[]).every(nonEmptyKnowledgeString);
      }))) return false;
  return true;
}

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
      sourceKind: null as string | null,
      sourceInfo: null,
      assetRefs: [],
      renderMode: "native",
      revisionToken: null as string | null,
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
    sourceKind: source.sourceKind || source.source_kind ? String(source.sourceKind || source.source_kind) : null,
    // Source citations and original worked-solution scans remain server-side
    // teacher-audit evidence. A learner history record keeps only the cleaned
    // question image plus the system's option-by-option text explanation.
    sourceInfo: null,
    assetRefs: questionAssetRefs(source.assetRefs || source.asset_refs, false),
    renderMode: ["native", "image_assist", "image_primary"].includes(String(source.renderMode || source.render_mode))
      ? String(source.renderMode || source.render_mode)
      : "native",
    revisionToken: source.revisionToken || source.question_revision_token
      ? String(source.revisionToken || source.question_revision_token)
      : null,
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
  const demoProfile = (profile.data.metadata as Record<string, unknown> | null)?.demo === true;
  const attemptHistoryLimit = 500;
  const answerHistoryLimit = 500;
  const recentQuestionsPerSkillLimit = 20;
  const [skillsResult, statesResult, plansResult, attemptsResult, cardsResult] = await Promise.all([
    supabase.from("chem_skills").select("id,title,module_id,max_level").eq("active", true).eq("grade_band", gradeBand).order("module_id"),
    supabase.from("chem_student_skill_state").select("skill_id,verified_level,candidate_level,stability,next_review_at,last_reviewed_at,teacher_intervention").eq("student_id", studentId),
    supabase.from("chem_learning_plans").select("id,plan_date,title,skill_ids,knowledge_summaries").eq("student_id", studentId).order("plan_date"),
    supabase.from("chem_learning_attempts").select("id,plan_day_id,completed_at,mode", { count: "exact" }).eq("student_id", studentId).order("completed_at", { ascending: false }).limit(attemptHistoryLimit),
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
      .select("id,mother_id,skill_id,level,stem,options,correct_option,explanation,image_url,source_kind,source_info,asset_refs,render_mode,content_fingerprint,question_revision_token,review_status,scope_status")
      .in("id", questionIds)
    : { data: [], error: null };
  if (questionsResult.error) throw questionsResult.error;

  const skills = skillsResult.data || [];
  const states = statesResult.data || [];
  const plans = plansResult.data || [];
  const stateBySkill = new Map(states.map((state) => [String(state.skill_id), state]));
  const questionById = new Map((questionsResult.data || []).map((question) => [String(question.id), question]));
  const attemptById = new Map(attempts.map((attempt) => [String(attempt.id), attempt]));
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
      if (demoProfile && historical.sourceKind === "licensed_local") return [];
      return [{
        questionId: String(answer.question_id), motherId: String(answer.mother_id || question?.mother_id || ""), level: Number(answer.level),
        stem: historical.stem, options: historical.options,
        selectedOption: Number(answer.selected_option), correctOption: historical.correctOption, explanation: historical.explanation,
        imageUrl: historical.imageUrl, correct: Boolean(answer.correct), uncertain: Boolean(answer.uncertain),
        sourceKind: historical.sourceKind, sourceInfo: historical.sourceInfo,
        assetRefs: historical.assetRefs, renderMode: historical.renderMode,
        revisionToken: historical.revisionToken,
        mode: String(attemptById.get(String(answer.attempt_id))?.mode || "REVIEW"),
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

function isJuniorAdaptivePlan(row: Record<string, unknown>) {
  return row.delivery_mode === "junior_adaptive";
}

function juniorSourceQuestionIsSafe(row: Record<string, unknown>) {
  const text = [row.stem, ...(Array.isArray(row.options) ? row.options : [])].map(String).join("\n");
  // The actual provenance remains in the protected release and canonical
  // library. A source label must never leak into student wording.
  return !/(?:(?:【|\[)[^】\]]{0,40}(?:20\d{2}|中考|期中|期末|模拟|真题|省|市|县|学校))|(?:20\d{2}\s*年[^\n]{0,36}(?:中考|期中|期末|检测|学校|省|市))/u.test(text);
}

function juniorQuestionShape(row: Record<string, unknown>) {
  if (!juniorSourceQuestionIsSafe(row)) {
    throw new RequestError(422, "初中原题的学生版文字仍含来源标记，已停止下发并通知甘老师。");
  }
  return {
    id: row.id, motherId: row.mother_id, skillId: row.skill_id, conceptKey: row.concept_key || null, level: row.level,
    gradeBand: row.grade_band, stem: row.stem, options: row.options,
    reviewStatus: row.review_status, scopeStatus: row.scope_status, sourceKind: row.source_kind,
    imageUrl: null, sourceInfo: null, assetRefs: [], renderMode: "native",
    revisionToken: row.question_revision_token ? String(row.question_revision_token) : null,
  };
}

function juniorCandidate(row: Record<string, unknown>): JuniorAdaptiveCandidate {
  const candidate: JuniorAdaptiveCandidate = {
    id: String(row.id || ""),
    mother_id: String(row.mother_id || ""),
    skill_id: String(row.skill_id || ""),
    knowledge_id: String(row.knowledge_id || ""),
    same_type_key: String(row.same_type_key || ""),
    source_item_key: String(row.source_item_key || ""),
    parent_source_item_key: String(row.parent_source_item_key || ""),
    content_fingerprint: String(row.content_fingerprint || ""),
    level: Number(row.level),
  };
  if (!candidate.id || !candidate.mother_id || !candidate.skill_id || !candidate.knowledge_id
    || !candidate.same_type_key || candidate.source_item_key.length < 16 || candidate.parent_source_item_key.length < 16
    || !/^[0-9a-f]{64}$/.test(candidate.content_fingerprint) || !Number.isInteger(candidate.level)) {
    throw new RequestError(422, "初中题目缺少可追溯的题源或同类题索引，已停止下发并通知甘老师。");
  }
  return candidate;
}

function juniorStepHistory(row: Record<string, unknown>): JuniorAdaptiveHistory {
  return {
    question_id: String(row.question_id || ""), mother_id: row.mother_id ? String(row.mother_id) : null,
    skill_id: String(row.skill_id || ""), knowledge_id: row.knowledge_id ? String(row.knowledge_id) : null,
    same_type_key: row.same_type_key ? String(row.same_type_key) : null,
    source_item_key: row.source_item_key ? String(row.source_item_key) : null,
    parent_source_item_key: row.parent_source_item_key ? String(row.parent_source_item_key) : null,
    content_fingerprint: String(row.content_fingerprint || "") || null,
    level: Number(row.level) || 1, correct: row.correct === true,
    uncertain: row.uncertain === true, answered_at: row.answered_at ? String(row.answered_at) : null,
    route_kind: row.route_kind as JuniorRouteKind | null,
  };
}

async function juniorDayReadiness(curriculum: Record<string, unknown>) {
  const skillIds = Array.isArray(curriculum.knowledge_skill_ids) ? curriculum.knowledge_skill_ids.map(String) : [];
  if (skillIds.length !== 3) return { ready: false, reason: "当天没有配置恰好三个知识点。", questions: [] as Array<Record<string, unknown>> };
  const result = await supabase.from("chem_questions")
    .select("id,mother_id,skill_id,knowledge_id,same_type_key,source_item_key,parent_source_item_key,content_fingerprint,level,source_release_id")
    .eq("grade_band", "初三").eq("textbook_version", String(curriculum.textbook_version))
    .in("knowledge_id", skillIds).eq("source_kind", "licensed_local")
    .eq("review_status", "approved").eq("scope_status", "IN").eq("usable_for_review", true)
    .not("source_release_id", "is", null).order("id");
  if (result.error) throw result.error;
  const rows = (result.data || []) as Array<Record<string, unknown>>;
  const releaseIds = [...new Set(rows.map((row) => String(row.source_release_id || "")).filter(Boolean))];
  const releases = releaseIds.length
    ? await supabase.schema("app_private").from("chem_question_source_releases").select("id,status,verification_status").in("id", releaseIds)
    : { data: [], error: null };
  if (releases.error) throw releases.error;
  const validReleases = new Set((releases.data || [])
    .filter((row) => row.status === "active" && row.verification_status === "full_visual_verified")
    .map((row) => String(row.id)));
  const usable = rows.filter((row) => validReleases.has(String(row.source_release_id)));
  for (const skillId of skillIds) {
    const candidates = usable.filter((row) => String(row.knowledge_id) === skillId);
    const levels = candidates.map((row) => Number(row.level)).filter(Number.isInteger);
    const foundation = Math.min(...levels);
    if (candidates.length < 7 || candidates.filter((row) => Number(row.level) === foundation).length < 5
      || candidates.filter((row) => Number(row.level) > foundation).length < 2) {
      return { ready: false, reason: `“${skillId}”缺少首日所需的不同原题（至少5道基础、2道中档）。`, questions: usable };
    }
  }
  return { ready: true, reason: "", questions: usable };
}

async function ensureJuniorDailyPlan(studentId: string, profile: Record<string, unknown>) {
  if (String(profile.grade_band) !== "初三" || String(profile.textbook_version) !== "科粤版") return false;
  if ((profile.metadata as Record<string, unknown> | null)?.demo) return false;
  const [curriculumResult, sessionsResult] = await Promise.all([
    supabase.from("chem_junior_curriculum_days").select("*").eq("textbook_version", "科粤版").eq("release_status", "ready").order("day_number"),
    supabase.from("chem_junior_daily_sessions").select("curriculum_day_id,status").eq("student_id", studentId),
  ]);
  if (curriculumResult.error || sessionsResult.error) throw curriculumResult.error || sessionsResult.error;
  const curriculumRows = (curriculumResult.data || []) as Array<Record<string, unknown>>;
  const sessions = sessionsResult.data || [];
  if (sessions.some((session) => session.status === "active")) return false;
  const completed = new Set(sessions.filter((session) => session.status === "completed").map((session) => String(session.curriculum_day_id)));
  const next = curriculumRows.find((row) => !completed.has(String(row.id)));
  if (!next) return false;
  const readiness = await juniorDayReadiness(next);
  if (!readiness.ready) return false;
  const existing = await supabase.from("chem_learning_plans").select("id")
    .eq("student_id", studentId).eq("junior_curriculum_day_id", String(next.id)).maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data) return false;
  const insert = await supabase.from("chem_learning_plans").insert({
    student_id: studentId, plan_date: shanghaiDate(), mode: "REVIEW", title: String(next.title),
    skill_ids: next.knowledge_skill_ids, knowledge_summaries: next.knowledge_summaries,
    estimated_minutes: Number(next.estimated_minutes) || 30, source: "course", is_scheduled: true,
    question_count: 12, round_limit: 1, max_question_level: null,
    delivery_mode: "junior_adaptive", junior_curriculum_day_id: String(next.id),
  });
  if (insert.error && insert.error.code !== "23505") throw insert.error;
  return !insert.error;
}

async function juniorSessionPayload(studentId: string, planId: string): Promise<Record<string, unknown>> {
  const [planResult, profileResult] = await Promise.all([
    supabase.from("chem_learning_plans").select("*").eq("id", planId).eq("student_id", studentId).maybeSingle(),
    supabase.from("chem_students_v2").select("grade_band,textbook_version,metadata").eq("id", studentId).single(),
  ]);
  if (planResult.error || profileResult.error) throw planResult.error || profileResult.error;
  const plan = planResult.data as Record<string, unknown> | null;
  if (!plan || !isJuniorAdaptivePlan(plan) || String(profileResult.data.grade_band) !== "初三" || String(profileResult.data.textbook_version) !== "科粤版") {
    throw new RequestError(409, "这不是可打开的科粤版初中自适应学习计划。");
  }
  if ((profileResult.data.metadata as Record<string, unknown> | null)?.demo) throw new RequestError(403, "演示账号不下发私有原题。");
  const curriculumId = String(plan.junior_curriculum_day_id || "");
  if (!curriculumId) throw new RequestError(422, "该初中计划缺少课程日索引，已停止下发并通知甘老师。");
  const curriculumResult = await supabase.from("chem_junior_curriculum_days").select("*").eq("id", curriculumId).eq("release_status", "ready").maybeSingle();
  if (curriculumResult.error) throw curriculumResult.error;
  const curriculum = curriculumResult.data as Record<string, unknown> | null;
  if (!curriculum) throw new RequestError(422, "当天课程尚未完成审核发布。");
  const skillIds = Array.isArray(curriculum.knowledge_skill_ids) ? curriculum.knowledge_skill_ids.map(String) : [];
  if (skillIds.length !== 3) throw new RequestError(422, "当天课程没有配置恰好三个知识点。");

  let sessionResult = await supabase.from("chem_junior_daily_sessions").select("*").eq("plan_day_id", planId).maybeSingle();
  if (sessionResult.error) throw sessionResult.error;
  if (!sessionResult.data) {
    const created = await supabase.from("chem_junior_daily_sessions").insert({
      student_id: studentId, plan_day_id: planId, curriculum_day_id: curriculumId, study_date: String(plan.plan_date),
      textbook_version: "科粤版", knowledge_skill_ids: skillIds,
    }).select("*").maybeSingle();
    if (created.error && created.error.code !== "23505") throw created.error;
    sessionResult = created.data
      ? created
      : await supabase.from("chem_junior_daily_sessions").select("*").eq("plan_day_id", planId).single();
    if (sessionResult.error) throw sessionResult.error;
  }
  const session = sessionResult.data as Record<string, unknown>;
  const [cardsResult, stepsResult, allSessionsResult, provenanceResult] = await Promise.all([
    supabase.from("chem_knowledge_cards").select("*").in("skill_id", skillIds).eq("review_status", "approved"),
    supabase.from("chem_junior_session_steps").select("*").eq("session_id", String(session.id)).order("sequence"),
    supabase.from("chem_junior_daily_sessions").select("id,curriculum_day_id,status,study_date").eq("student_id", studentId).order("study_date"),
    supabase.schema("app_private").from("chem_junior_knowledge_provenance").select("knowledge_id,verification_status").in("knowledge_id", skillIds),
  ]);
  if (cardsResult.error || stepsResult.error || allSessionsResult.error || provenanceResult.error) {
    throw cardsResult.error || stepsResult.error || allSessionsResult.error || provenanceResult.error;
  }
  const cards = (cardsResult.data || []) as Array<Record<string, unknown>>;
  if (skillIds.some((skillId) => cards.filter((card) => String(card.skill_id) === skillId).length !== 1)
    || skillIds.some((skillId) => !((provenanceResult.data || []) as Array<Record<string, unknown>>)
      .some((row) => String(row.knowledge_id) === skillId && row.verification_status === "verified"))) {
    throw new RequestError(422, "当天三个知识点没有逐项完成教材来源核验，已停止下发。");
  }
  const steps = (stepsResult.data || []) as Array<Record<string, unknown>>;
  const unanswered = steps.find((step) => !step.answered_at);
  const sessionSummary = () => ({
    id: session.id, status: session.status, initialQuestionTarget: 12, hardQuestionCap: 15,
    issuedCount: steps.length, answeredCount: steps.filter((step) => step.answered_at).length,
    correctCount: steps.filter((step) => step.correct === true).length,
  });
  const cardOrder = new Map(skillIds.map((skillId, index) => [skillId, index]));
  const orderedCards = [...cards].sort((a, b) => (cardOrder.get(String(a.skill_id)) ?? 99) - (cardOrder.get(String(b.skill_id)) ?? 99));
  if (session.status === "completed") return { deliveryMode: "junior_adaptive", plan: planShape(plan), cards: orderedCards.map(cardShape), session: sessionSummary(), currentQuestion: null, completed: true };
  if (session.status !== "active") throw new RequestError(422, "这一天的初中学习会话已被暂停，请联系甘老师处理题源容量。");

  if (unanswered) {
    const currentQuestion = await supabase.from("chem_questions").select("*").eq("id", String(unanswered.question_id)).maybeSingle();
    if (currentQuestion.error) throw currentQuestion.error;
    if (!currentQuestion.data || String(currentQuestion.data.question_revision_token || "") !== String((unanswered.question_snapshot as Record<string, unknown> | null)?.revisionToken || "")) {
      await supabase.from("chem_junior_daily_sessions").update({ status: "blocked", updated_at: new Date().toISOString() }).eq("id", String(session.id));
      throw new RequestError(409, "当前原题已更新，系统不会替换正在答的题；请联系甘老师处理。");
    }
    return { deliveryMode: "junior_adaptive", plan: planShape(plan), cards: orderedCards.map(cardShape), session: sessionSummary(), currentStepId: unanswered.id, currentQuestion: juniorQuestionShape(currentQuestion.data), completed: false };
  }

  const allSessions = (allSessionsResult.data || []) as Array<Record<string, unknown>>;
  const allSessionIds = allSessions.map((row) => String(row.id));
  const allStepsResult = allSessionIds.length
    ? await supabase.from("chem_junior_session_steps").select("*").in("session_id", allSessionIds).order("created_at")
    : { data: [], error: null };
  if (allStepsResult.error) throw allStepsResult.error;
  const allSteps = (allStepsResult.data || []) as Array<Record<string, unknown>>;
  const priorSession = [...allSessions].filter((row) => row.status === "completed" && String(row.id) !== String(session.id)).at(-1);
  const priorErrors = priorSession
    ? allSteps.filter((step) => String(step.session_id) === String(priorSession.id) && step.correct !== true).map(juniorStepHistory)
    : [];
  const candidateKnowledgeIds = [...new Set([...skillIds, ...priorErrors.map((row) => String(row.knowledge_id || row.skill_id)).filter(Boolean)])];
  const poolResult = await supabase.from("chem_questions").select("*")
    .eq("grade_band", "初三").eq("textbook_version", "科粤版").in("knowledge_id", candidateKnowledgeIds)
    .eq("source_kind", "licensed_local").eq("review_status", "approved").eq("scope_status", "IN")
    .eq("usable_for_review", true).not("source_release_id", "is", null).order("id");
  if (poolResult.error) throw poolResult.error;
  const poolRows = (poolResult.data || []) as Array<Record<string, unknown>>;
  const releaseIds = [...new Set(poolRows.map((row) => String(row.source_release_id || "")).filter(Boolean))];
  const releaseResult = releaseIds.length
    ? await supabase.schema("app_private").from("chem_question_source_releases").select("id,status,verification_status").in("id", releaseIds)
    : { data: [], error: null };
  if (releaseResult.error) throw releaseResult.error;
  const activeReleaseIds = new Set((releaseResult.data || []).filter((row) => row.status === "active" && row.verification_status === "full_visual_verified").map((row) => String(row.id)));
  const candidates = poolRows.filter((row) => activeReleaseIds.has(String(row.source_release_id))).map(juniorCandidate);
  const selection = selectJuniorNextQuestion({
    candidates, knowledgeSkillIds: skillIds, answered: allSteps.map(juniorStepHistory), issued: steps.map(juniorStepHistory), priorErrors,
    curriculumDayNumber: Number(curriculum.day_number), initialTarget: 12, hardCap: 15,
  });
  if (!selection) {
    if (steps.length >= 12) {
      const finalized = await supabase.rpc("chem_junior_finalize_session", { p_session_id: session.id, p_student_id: studentId });
      if (finalized.error) throw finalized.error;
      return { deliveryMode: "junior_adaptive", plan: planShape(plan), cards: orderedCards.map(cardShape), session: { ...sessionSummary(), status: "completed" }, currentQuestion: null, completed: true };
    }
    await supabase.from("chem_junior_daily_sessions").update({ status: "blocked", updated_at: new Date().toISOString() }).eq("id", String(session.id));
    throw new RequestError(422, "原题池不足以保持“12题起步、不同原题、不自编题”的规则，今天已停止下发并通知甘老师。");
  }
  const selected = poolRows.find((row) => String(row.id) === selection.question.id);
  if (!selected) throw new RequestError(500, "初中题库选择结果异常。");
  const inserted = await supabase.from("chem_junior_session_steps").insert({
    session_id: session.id, sequence: steps.length + 1, question_id: selected.id, mother_id: selected.mother_id,
    skill_id: selected.skill_id, knowledge_id: selected.knowledge_id, same_type_key: selected.same_type_key,
    source_item_key: selected.source_item_key, parent_source_item_key: selected.parent_source_item_key,
    content_fingerprint: selected.content_fingerprint, level: selected.level, route_kind: selection.routeKind,
    route_reason: selection.routeReason,
    question_snapshot: { questionId: selected.id, motherId: selected.mother_id, skillId: selected.skill_id, level: selected.level, stem: selected.stem, options: selected.options, revisionToken: selected.question_revision_token || null },
  }).select("*").maybeSingle();
  if (inserted.error && inserted.error.code !== "23505") throw inserted.error;
  if (!inserted.data) return juniorSessionPayload(studentId, planId);
  steps.push(inserted.data as Record<string, unknown>);
  return { deliveryMode: "junior_adaptive", plan: planShape(plan), cards: orderedCards.map(cardShape), session: sessionSummary(), currentStepId: inserted.data.id, currentQuestion: juniorQuestionShape(selected), completed: false };
}

async function studentDashboard(studentId: string) {
  // The profile used to be awaited before every other dashboard request,
  // adding a full network round trip to every login and refresh. Only the
  // grade-scoped skill catalogue depends on it; all other reads can start at
  // once without weakening row scoping or the student-id checks.
  const [profileResult, planResult, stateResult, attemptResult, videoRecommendations] = await Promise.all([
    supabase.from("chem_students_v2")
      .select("id,display_name,grade_band,textbook_version,enrollment_start_date,needs_initial_diagnostic,metadata")
      .eq("id", studentId)
      .single(),
    supabase.from("chem_learning_plans")
      .select("id,student_id,plan_date,mode,title,skill_ids,target_concept_keys,knowledge_summaries,estimated_minutes,source,is_scheduled,question_count,round_limit,max_question_level,delivery_mode,junior_curriculum_day_id")
      .eq("student_id", studentId)
      .order("plan_date"),
    supabase.from("chem_student_skill_state")
      .select("*,chem_skills(max_level)")
      .eq("student_id", studentId),
    supabase.from("chem_learning_attempts")
      .select("id,plan_day_id,attempt_kind,sequence,first_score,completed_at,chem_attempt_answers(correct,uncertain,question_snapshot)")
      .eq("student_id", studentId)
      .order("completed_at"),
    loadVideoRecommendations(studentId),
  ]);
  if (profileResult.error) throw profileResult.error;
  for (const result of [planResult, stateResult, attemptResult]) if (result.error) throw result.error;
  let plans = (planResult.data || []) as Array<Record<string, unknown>>;
  let juniorSessionByPlanId = new Map<string, Record<string, unknown>>();
  if (String(profileResult.data.grade_band) === "初三" && String(profileResult.data.textbook_version) === "科粤版") {
    await ensureJuniorDailyPlan(studentId, profileResult.data as Record<string, unknown>);
    const [refreshedPlans, juniorSessions] = await Promise.all([
      supabase.from("chem_learning_plans")
        .select("id,student_id,plan_date,mode,title,skill_ids,target_concept_keys,knowledge_summaries,estimated_minutes,source,is_scheduled,question_count,round_limit,max_question_level,delivery_mode,junior_curriculum_day_id")
        .eq("student_id", studentId).order("plan_date"),
      supabase.from("chem_junior_daily_sessions")
        .select("plan_day_id,status")
        .eq("student_id", studentId),
    ]);
    if (refreshedPlans.error || juniorSessions.error) throw refreshedPlans.error || juniorSessions.error;
    plans = (refreshedPlans.data || []) as Array<Record<string, unknown>>;
    juniorSessionByPlanId = new Map((juniorSessions.data || []).map((session) => [String(session.plan_day_id), session as Record<string, unknown>]));
  }
  const skillResult = await supabase.from("chem_skills")
    .select("id,title,module_id,grade_band,max_level,exam_importance,exam_depth,prerequisites,level_criteria")
    .eq("active", true)
    .eq("grade_band", profileResult.data.grade_band)
    .order("module_id");
  if (skillResult.error) throw skillResult.error;
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
  const reviewProfile = { gradeBand: String(profileResult.data.grade_band), isDemo };
  const todayPlan = plans.find((plan) => String(plan.plan_date) === shanghaiDate());
  return {
    profile: {
      ...profileShape(profileResult.data),
      availableDemoGrades: isDemo ? ["高一", "高二", "高三"] : undefined,
    },
    plans: plans.map((plan) => planShape(plan, attemptResult.data || [], juniorSessionByPlanId.get(String(plan.id)), reviewProfile)),
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
  includeAnswerLocks?: boolean;
  /** Student start_plan derives demo/read-only rules from the profile fetched below. */
  studentOpen?: boolean;
};

async function startPlanPayload(studentId: string, planId: string, options: StartPlanOptions = {}) {
  const [planResult, gradeResult, sourceReleasesResult] = await Promise.all([
    supabase
      .from("chem_learning_plans")
      .select("*")
      .eq("id", planId)
      .eq("student_id", studentId)
      .single(),
    supabase.from("chem_students_v2").select("grade_band,metadata").eq("id", studentId).single(),
    // This query does not depend on the student's grade. Starting it with the
    // plan/profile fetch removes one cross-region round trip for high-school REVIEW.
    supabase.rpc("chem_active_verified_source_releases"),
  ]);
  const { data: plan, error: planError } = planResult;
  if (planError) throw planError;
  if (gradeResult.error) throw gradeResult.error;
  const demoProfile = (gradeResult.data.metadata as Record<string, unknown> | null)?.demo === true;
  const effectiveOptions: StartPlanOptions = options.studentOpen
    ? demoProfile
      ? { ...options, allowCompletedPreview: true, includeAnswerLocks: false }
      : { ...options, allowCompletedPreview: false, includeAnswerLocks: true }
    : options;
  if (options.studentOpen && !demoProfile && options.previewRound !== undefined) {
    throw new RequestError(403, "真实学习记录不能指定练习轮次。");
  }
  const reviewProfile = { gradeBand: String(gradeResult.data.grade_band), isDemo: demoProfile };
  const skillIds: string[] = Array.isArray(plan.skill_ids)
    ? (plan.skill_ids as unknown[]).map((skillId) => String(skillId)).filter(Boolean)
    : [];
  if (!skillIds.length) throw new RequestError(422, "当天计划尚未配置可练习的知识模块，请联系甘老师。");
  const questionCount = planQuestionCount(plan);
  const roundLimit = effectivePlanRoundLimit(plan, reviewProfile);
  const highSchoolReview = plan.mode === "REVIEW"
    && ["高一", "高二", "高三"].includes(String(gradeResult.data.grade_band));
  const formalHighSchoolReview = isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile));
  if (highSchoolReview && sourceReleasesResult.error) throw sourceReleasesResult.error;
  const activeSourceReleaseId = highSchoolReview
    ? verifiedSourceReleaseId((sourceReleasesResult.data || []) as Array<Record<string, unknown>>, reviewProfile.gradeBand)
    : null;
  if (
    formalHighSchoolReview
    && effectiveOptions.includeAnswerLocks
    && String(plan.plan_date || "") > shanghaiDate()
  ) {
    throw new RequestError(409, "后续日期的正式复习尚未开放，请在计划当天进入。先完成今天的题组后，系统会据此调整下一步。");
  }
  if (formalHighSchoolReview && reviewProfile.gradeBand === "高一") {
    const confirmedSkills = confirmedHighOneSkillIds(gradeResult.data.metadata);
    if (!confirmedSkills.length || skillIds.some((skillId) => !confirmedSkills.includes(skillId))) {
      throw new RequestError(422, "当天计划包含尚未确认学过的高一知识模块，已停止下发并通知甘老师。");
    }
  }
  if (!validFormalReviewQuestionCount({ ...formalReviewContext(plan, reviewProfile), questionCount })) {
    throw new RequestError(422, `正式复习每天最多下发 ${FORMAL_REVIEW_DAILY_QUESTION_CAP} 道题；当前计划配置超限，已停止下发并通知甘老师。`);
  }
  const maxQuestionLevel = planMaxQuestionLevel(plan);
  const targetConceptKeys = planTargetConceptKeys(plan);
  if (formalHighSchoolReview && roundLimit === 1 && targetConceptKeys.length !== questionCount) {
    throw new RequestError(422, `正式复习当天必须明确配置 ${questionCount} 个细知识点，已停止下发并通知甘老师。`);
  }
  if (plan.mode === "REVIEW" && targetConceptKeys.length) {
    if (targetConceptKeys.length !== questionCount || new Set(targetConceptKeys).size !== targetConceptKeys.length) {
      throw new RequestError(422, `当天必须配置 ${questionCount} 个互不重复的细知识点，请联系甘老师。`);
    }
    if (targetConceptKeys.some((conceptKey) => !skillIds.some((skillId) => conceptKey.startsWith(`${skillId}__`)))) {
      throw new RequestError(422, "当天细知识点与学习模块没有一一对应，已停止下发并通知甘老师。");
    }
    if (skillIds.some((skillId) => !targetConceptKeys.some((conceptKey) => conceptKey.startsWith(`${skillId}__`)))) {
      throw new RequestError(422, "当天学习模块包含没有对应细知识点的项目，已停止下发并通知甘老师。");
    }
  }
  if (effectiveOptions.previewRound !== undefined && (!Number.isInteger(effectiveOptions.previewRound) || effectiveOptions.previewRound < 1 || effectiveOptions.previewRound > roundLimit)) {
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
    .not("mother_id", "is", null);
  if (plan.mode === "REVIEW") eligibleQuestions = eligibleQuestions.not("concept_key", "is", null);
  if (plan.mode === "REVIEW" && targetConceptKeys.length) {
    eligibleQuestions = eligibleQuestions.in("concept_key", targetConceptKeys);
  }
  eligibleQuestions = eligibleQuestions.eq(questionUsageColumn, true);
  if (highSchoolReview) {
    // Every high-school REVIEW surface, including the read-only demo, uses the
    // same verified source-only release. Demo answers remain simulated and are
    // never written to attempts, answer locks or student mastery evidence.
    eligibleQuestions = eligibleQuestions
      .eq("source_kind", "licensed_local")
      .eq("render_mode", "image_primary")
      .eq("source_release_id", activeSourceReleaseId!);
  }
  if (maxQuestionLevel !== null) eligibleQuestions = eligibleQuestions.lte("level", maxQuestionLevel);
  // The adaptive selector uses the source index as its final deterministic
  // tie-breaker. Ordering by the immutable question id keeps the five issued
  // questions reproducible when the server verifies them again on submit.
  eligibleQuestions = eligibleQuestions.order("id");
  const [cards, questions, planAttempts, states, reviewHistory, sameDayReviewPlans] = await Promise.all([
    supabase.from("chem_knowledge_cards").select("*").in("skill_id", skillIds).eq("review_status", "approved"),
    eligibleQuestions,
    supabase.from("chem_learning_attempts").select("id,attempt_kind,sequence,first_score,completed_at").eq("student_id", studentId).eq("plan_day_id", plan.id).order("sequence"),
    supabase.from("chem_student_skill_state").select("skill_id,verified_level,consecutive_errors,next_review_at").eq("student_id", studentId).in("skill_id", skillIds),
    plan.mode === "REVIEW"
      ? supabase.rpc("chem_review_answer_history", { p_student_id: studentId })
      : Promise.resolve({ data: [], error: null }),
    formalHighSchoolReview
      ? supabase.from("chem_learning_plans")
        .select("id,question_count")
        .eq("student_id", studentId)
        .eq("mode", "REVIEW")
        .eq("plan_date", plan.plan_date)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (cards.error || questions.error || planAttempts.error || states.error || reviewHistory.error || sameDayReviewPlans.error) {
    throw cards.error || questions.error || planAttempts.error || states.error || reviewHistory.error || sameDayReviewPlans.error;
  }
  if (formalHighSchoolReview && (
    (sameDayReviewPlans.data || []).length !== 1
    || String(sameDayReviewPlans.data?.[0]?.id || "") !== String(plan.id)
  )) {
    throw new RequestError(422, "同一天只能有一个正式复习题组；当前排程存在重复计划，已停止下发并通知甘老师。");
  }
  if (plan.mode === "REVIEW") {
    const cardRows = (cards.data || []) as Array<Record<string, unknown>>;
    const cardsBySkill = new Map<string, Array<Record<string, unknown>>>();
    for (const card of cardRows) {
      const skillId = String(card.skill_id || "");
      const rows = cardsBySkill.get(skillId) || [];
      rows.push(card);
      cardsBySkill.set(skillId, rows);
    }
    const highSchoolReview = ["高一", "高二", "高三"].includes(String(gradeResult.data.grade_band));
    if (highSchoolReview && skillIds.some((skillId) => (cardsBySkill.get(skillId) || []).length !== 1)) {
      throw new RequestError(422, "当天知识卡没有与学习模块一一对应，已停止下发并通知甘老师。");
    }
    for (const card of cardRows) {
      const structured = card.structured_content;
      const hasStructured = structured && typeof structured === "object" && !Array.isArray(structured)
        && Object.keys(structured as Record<string, unknown>).length > 0;
      if (hasStructured && !validStructuredKnowledgeContent(structured)) {
        throw new RequestError(422, `“${String(card.title || "当天知识卡")}”的展开内容结构不完整，已停止下发并通知甘老师。`);
      }
    }
  }
  const attempts = planAttempts.data || [];
  const actualAttemptCount = attempts.length;
  if (!validFormalReviewRoundLimit({
    ...formalReviewContext(plan, reviewProfile),
    storedRoundLimit: roundLimit,
    planDate: String(plan.plan_date || ""),
    hasExistingAttempt: actualAttemptCount > 0,
  })) {
    throw new RequestError(422, "正式复习必须是每天一个题组；当前计划尚未完成规则升级，已停止下发并通知甘老师。");
  }
  // Source originals never repeat for the same student, including on a later
  // review date. The teacher readiness report must therefore fund every
  // planned revisit with a fresh source item instead of silently recycling it.
  const selectionAttemptIds = attempts.map((attempt) => String(attempt.id));
  const history = plan.mode === "REVIEW"
    ? {
      // Keep the learner's complete REVIEW identity history. A source item can
      // move between skills or concepts when a release is corrected; filtering
      // by today's skill before the four-identity check could then reissue the
      // same original under a different mapping.
      data: (reviewHistory.data || []) as Array<Record<string, unknown>>,
      error: null,
    }
    : selectionAttemptIds.length
    ? await supabase.from("chem_attempt_answers").select("attempt_id,question_id,mother_id,skill_id,concept_key,correct,uncertain,question_snapshot").in("attempt_id", selectionAttemptIds).in("skill_id", skillIds)
    : { data: [], error: null };
  if (history.error) throw history.error;
  // Current snapshots already carry level, concept and stable source identity.
  // Read the question table only for legacy rows that are actually missing
  // one of those fields; otherwise this was an unnecessary extra request on
  // every plan open.
  const historyQuestionIdsNeedingMetadata = [...new Set((history.data || []).flatMap((answer) => {
    const snapshot = validQuestionSnapshot(answer.question_snapshot) ? answer.question_snapshot : null;
    const hasIdentity = Boolean(snapshot?.sourceItemKey || snapshot?.contentFingerprint);
    const hasLevel = Number(snapshot?.level || 0) > 0;
    const hasConcept = Boolean(answer.concept_key || snapshot?.conceptKey);
    return hasIdentity && hasLevel && hasConcept ? [] : [String(answer.question_id)].filter(Boolean);
  }))];
  const historyQuestionMetadata = historyQuestionIdsNeedingMetadata.length
    ? await supabase.from("chem_questions").select("id,level,concept_key,source_item_key,content_fingerprint").in("id", historyQuestionIdsNeedingMetadata)
    : { data: [], error: null };
  if (historyQuestionMetadata.error) throw historyQuestionMetadata.error;
  const historicalIdentityByQuestionId = new Map(
    (historyQuestionMetadata.data || []).map((question) => [String(question.id), sourceIdentity(question)]),
  );
  const sequenceByAttemptId = new Map<string, number>();
  if (plan.mode === "REVIEW") {
    for (const answer of (history.data || [])) {
      sequenceByAttemptId.set(String(answer.attempt_id), Number(answer.history_order));
    }
  } else {
    attempts.forEach((attempt, index) => sequenceByAttemptId.set(String(attempt.id), index));
  }
  const historyRows: SourceAdaptiveHistory[] = (history.data || []).map((answer) => {
    const snapshot = validQuestionSnapshot(answer.question_snapshot) ? answer.question_snapshot : null;
    const currentIdentity = historicalIdentityByQuestionId.get(String(answer.question_id));
    return {
      ...answer,
      source_item_key: String(snapshot?.sourceItemKey || currentIdentity?.sourceItemKey || "") || null,
      content_fingerprint: String(snapshot?.contentFingerprint || currentIdentity?.contentFingerprint || "") || null,
      question_level: Number(snapshot?.level || (historyQuestionMetadata.data || []).find((question) => String(question.id) === String(answer.question_id))?.level || 0) || null,
      attempt_sequence: sequenceByAttemptId.get(String(answer.attempt_id)) ?? null,
    };
  });
  const latestAttemptId = attempts.at(-1)?.id ? String(attempts.at(-1)?.id) : null;
  const latestAnswers = latestAttemptId
    ? historyRows.filter((answer) => String(answer.attempt_id) === latestAttemptId)
    : [];
  const questionPool = (highSchoolReview
    ? (questions.data || []).filter((question) => hasRequiredReviewSourceAssets(question.asset_refs))
    : (questions.data || [])) as SourceAdaptiveQuestion[];
  if (plan.mode === "REVIEW" && !demoProfile && ["高一", "高二", "高三"].includes(String(gradeResult.data.grade_band))) {
    const conceptCounts = new Map<string, number>();
    const conceptOwnerSkills = new Map<string, Set<string>>();
    for (const question of questionPool) {
      const conceptKey = String(question.concept_key || "");
      if (conceptKey) {
        conceptCounts.set(conceptKey, (conceptCounts.get(conceptKey) || 0) + 1);
        const owners = conceptOwnerSkills.get(conceptKey) || new Set<string>();
        owners.add(String(question.skill_id || ""));
        conceptOwnerSkills.set(conceptKey, owners);
      }
    }
    // A formal day needs one fresh source original for every configured fine
    // concept. Difficulty can rise on a later visit when a harder original is
    // available, but a concept is never rejected merely because its audited
    // source set does not contain three artificial level labels. The adaptive
    // selector below performs the decisive whole-history freshness check.
    const expectedConceptKeys = targetConceptKeys.length
      ? targetConceptKeys
      : [...conceptCounts.keys()];
    if (
      (!targetConceptKeys.length && skillIds.length !== 1)
      || (targetConceptKeys.length > 0 && skillIds.length > questionCount)
      || conceptCounts.size !== questionCount
      || expectedConceptKeys.length !== questionCount
      || expectedConceptKeys.some((conceptKey) => !conceptCounts.has(conceptKey))
      || expectedConceptKeys.some((conceptKey) => {
        const owners = conceptOwnerSkills.get(conceptKey);
        return !owners || owners.size !== 1 || !skillIds.includes([...owners][0]);
      })
      || [...conceptCounts.values()].some((count) => count < roundLimit)
    ) {
      throw new RequestError(
        422,
        `当天题组必须覆盖 ${questionCount} 个细知识点，且知识点、模块和已审核原题须一一对应；当前计划或原题池尚未达到要求，已停止下发。`,
      );
    }
  }
  const isResolved = latestConceptsAtMaximumDifficulty(latestAnswers, questionPool, questionCount);
  const reachedRoundLimit = actualAttemptCount >= roundLimit;
  if (!effectiveOptions.allowCompletedPreview && (reachedRoundLimit || isResolved)) {
    throw new RequestError(
      409,
      isResolved
        ? "今天这组问题已经全部解决，可以在战绩中回看。"
        : `今天的 ${roundLimit} 轮已经完成，可以在战绩中回看。`,
    );
  }

  const completedPreview = Boolean(effectiveOptions.allowCompletedPreview && actualAttemptCount > 0 && (reachedRoundLimit || isResolved));
  const selectionSequence = effectiveOptions.previewRound !== undefined
    ? effectiveOptions.previewRound - 1
    : completedPreview
      ? Math.max(0, Math.min(actualAttemptCount, roundLimit) - 1)
      : Math.min(actualAttemptCount, roundLimit - 1);
  const roundNumber = selectionSequence + 1;
  let selectionHistory: SourceAdaptiveHistory[] = historyRows;
  let adaptiveQuestions: SourceAdaptiveQuestion[] = [];
  if (effectiveOptions.previewRound !== undefined) {
    // Preview/demo answers are intentionally not stored. Reconstruct every
    // preceding preview round as virtual unresolved evidence so rounds 2-5
    // still contain completely different questions and mother questions.
    // Earlier review dates remain in the history so a preview cannot make a
    // previously used source original appear new again.
    const currentAttemptIds = new Set(attempts.map((attempt) => String(attempt.id)));
    selectionHistory = historyRows.filter((answer) => !currentAttemptIds.has(String(answer.attempt_id)));
    const previousSequence = selectionHistory.reduce((latest, answer) =>
      Math.max(latest, Number.isInteger(answer.attempt_sequence) ? Number(answer.attempt_sequence) : -1), -1);
    for (let previewIndex = 0; previewIndex <= selectionSequence; previewIndex += 1) {
      adaptiveQuestions = selectAdaptiveQuestions(
        sourceDistinctQuestionPool(questionPool, selectionHistory),
        states.data || [],
        selectionHistory,
        previewIndex,
        questionCount,
        new Date(),
        plan.mode === "REVIEW",
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
            question_level: Number(question.level) || null,
            source_item_key: question.source_item_key ? String(question.source_item_key) : null,
            content_fingerprint: question.content_fingerprint ? String(question.content_fingerprint) : null,
            attempt_sequence: previousSequence + previewIndex + 1,
            correct: false,
            uncertain: true,
          })),
        ];
      }
    }
  } else {
    adaptiveQuestions = selectAdaptiveQuestions(
      sourceDistinctQuestionPool(questionPool, selectionHistory),
      states.data || [],
      selectionHistory,
      selectionSequence,
      questionCount,
      new Date(),
      plan.mode === "REVIEW",
    );
  }
  if (adaptiveQuestions.length !== questionCount) {
    throw new RequestError(
      422,
      `第 ${roundNumber} 轮需要 ${questionCount} 道今天从未出现过的已审核题，但当前只有 ${adaptiveQuestions.length} 道新母题；题库变式不足，本轮已停止并通知甘老师。`,
    );
  }
  let lockedFeedback: Array<Record<string, unknown>> = [];
  if (effectiveOptions.includeAnswerLocks && plan.mode === "REVIEW") {
    const securedIds = adaptiveQuestions
      .filter((question) => isLicensedHighSchoolQuestion(question))
      .map((question) => String(question.id));
    if (securedIds.length) {
      const lockResult = await supabase.rpc("chem_get_question_answer_locks", {
        p_student_id: studentId,
        p_plan_day_id: String(plan.id),
        p_attempt_sequence: selectionSequence,
        p_question_ids: securedIds,
      });
      if (lockResult.error) throw lockResult.error;
      const questionById = new Map(adaptiveQuestions.map((question) => [String(question.id), question]));
      lockedFeedback = ((lockResult.data || []) as Array<Record<string, unknown>>).map((lock) => {
        const question = questionById.get(String(lock.question_id));
        if (!question) throw new RequestError(409, "已锁定答案与当前题组不一致，请联系甘老师处理。");
        const expectedRevisionToken = question.question_revision_token ? String(question.question_revision_token) : null;
        const lockedRevisionToken = lock.revision_token ? String(lock.revision_token) : null;
        if (lockedRevisionToken !== expectedRevisionToken) {
          throw new RequestError(409, "原题在中断期间已经更新，请联系甘老师处理本轮记录。");
        }
        return questionFeedbackShape(question, Number(lock.selected_option), {
          uncertain: lock.uncertain === true,
          durationSec: Number(lock.duration_sec) || 0,
        });
      });
    }
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
    plan: planShape(plan, planAttemptRows, undefined, reviewProfile),
    cards: orderedCards.map(cardShape),
    questions: adaptiveQuestions.map((question) => questionShape(question, plan.mode === "REVIEW")),
    lockedFeedback,
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

    if (body.action === "question_asset") {
      const questionId = String(body.data?.questionId || "");
      const assetId = String(body.data?.assetId || "");
      const phase = String(body.data?.phase || "");
      if (
        !/^[a-zA-Z0-9_-]{1,160}$/.test(questionId)
        || !/^[a-zA-Z0-9/_-]{16,200}$/.test(assetId)
        || !["question", "analysis"].includes(phase)
      ) {
        return reply(req, { error: "原题图片请求无效。" }, 400);
      }

      // Students and guardians are restricted to their bound profile. Demo
      // sessions may target only another demo profile through resolveDemoTarget.
      // Teacher sessions may inspect every licensed high-school source question.
      let assetStudentId = identity.studentId;
      let assetTargetIsDemo = false;
      if (identity.role !== "teacher") {
        if (!identity.studentId) return reply(req, { error: "无权读取该原题图片。" }, 403);
        if (identity.role === "student") {
          assetStudentId = await resolveDemoTarget(
            identity.studentId,
            body.data?.studentId ? String(body.data.studentId) : undefined,
          );
        }
        if (!assetStudentId) return reply(req, { error: "无权读取该原题图片。" }, 403);
        const profile = await supabase
          .from("chem_students_v2")
          .select("grade_band,record_status,metadata")
          .eq("id", assetStudentId)
          .maybeSingle();
        if (profile.error) throw profile.error;
        if (!profile.data || !["高一", "高二", "高三"].includes(String(profile.data.grade_band)) || profile.data.record_status !== "active") {
          return reply(req, { error: "无权读取该原题图片。" }, 403);
        }
        assetTargetIsDemo = (profile.data.metadata as Record<string, unknown> | null)?.demo === true;
      }

      const assetsResult = await supabase.rpc("chem_get_question_assets", { p_asset_paths: [assetId] });
      if (assetsResult.error) throw assetsResult.error;
      const asset = Array.isArray(assetsResult.data)
        ? assetsResult.data[0] as Record<string, unknown> | undefined
        : undefined;
      if (!asset || String(asset.question_id || "") !== questionId) {
        return reply(req, { error: "原题图片不存在。" }, 404);
      }
      const questionResult = await supabase
        .from("chem_questions")
        .select("id,grade_band,scope_status,source_kind,review_status,usable_for_review,render_mode,source_release_id,asset_refs,question_revision_token")
        .eq("id", questionId)
        .maybeSingle();
      if (questionResult.error) throw questionResult.error;
      const question = questionResult.data as Record<string, unknown> | null;
      const currentMatchingRef = question
        ? matchingRawAssetRef(question.asset_refs, assetId, asset)
        : null;
      if (
        !question
        || !["高一", "高二", "高三"].includes(String(question.grade_band))
        || question.source_kind !== "licensed_local"
      ) {
        return reply(req, { error: "原题图片不存在。" }, 404);
      }
      const isAnalysis = String(asset.asset_kind) === "analysis_image";
      const structuralPhaseStatus = sourceAssetPhaseStatus({
        phase,
        assetKind: String(asset.asset_kind),
        role: "teacher",
        hasCompletedAnswer: true,
      });
      if (structuralPhaseStatus !== 200) {
        return reply(req, { error: "原题图片阶段不匹配。" }, 409);
      }
      if (identity.role !== "teacher") {
        // Persisted evidence permits a historical read. Without it, a student
        // question image must belong to the exact set the server just issued;
        // an analysis image requires the server-owned first-answer lock. A
        // guardian never receives current-round assets.
        // Demo profiles never inherit historical evidence. They may read only
        // the exact question image issued by the current verified source release.
        let hasCompletedAnswer = false;
        if (!assetTargetIsDemo) {
          const evidence = await supabase
            .from("chem_attempt_answers")
            .select("id,question_snapshot,chem_learning_attempts!inner(student_id,completed_at)")
            .eq("question_id", questionId)
            .eq("chem_learning_attempts.student_id", assetStudentId)
            .not("chem_learning_attempts.completed_at", "is", null)
            .limit(20);
          if (evidence.error) throw evidence.error;
          hasCompletedAnswer = (evidence.data || []).some((answer) => {
            const snapshot = validQuestionSnapshot(answer.question_snapshot)
              ? answer.question_snapshot
              : null;
            return Boolean(snapshot && matchingRawAssetRef(
              snapshot.assetRefs || snapshot.asset_refs,
              assetId,
              asset,
            ));
          });
        }
        const activeAssetReleaseId = await activeVerifiedSourceReleaseId(String(question.grade_band));
        const currentAssetEligible = Boolean(currentMatchingRef)
          && question.review_status === "approved"
          && question.scope_status === "IN"
          && question.usable_for_review === true
          && question.render_mode === "image_primary"
          && String(question.source_release_id || "") === activeAssetReleaseId;
        let hasLockedAnswer = false;
        if (!hasCompletedAnswer && isAnalysis && identity.role === "student") {
          const planId = String(body.data?.planId || "");
          const attemptSequence = body.data?.attemptSequence;
          const suppliedRevisionToken = body.data?.revisionToken === null || body.data?.revisionToken === undefined
            ? null
            : String(body.data.revisionToken);
          const expectedRevisionToken = question.question_revision_token
            ? String(question.question_revision_token)
            : null;
          if (
            validUuid(planId)
            && Number.isInteger(attemptSequence)
            && attemptSequence >= 0
            && attemptSequence <= 7
            && suppliedRevisionToken === expectedRevisionToken
            && currentAssetEligible
          ) {
            const lockEvidence = await supabase.rpc("chem_has_current_question_answer_lock", {
              p_student_id: assetStudentId,
              p_plan_day_id: planId,
              p_attempt_sequence: attemptSequence,
              p_question_id: questionId,
              p_revision_token: expectedRevisionToken,
            });
            if (lockEvidence.error) throw lockEvidence.error;
            hasLockedAnswer = lockEvidence.data === true;
          }
        }
        const phaseAccessStatus = sourceAssetPhaseStatus({
          phase,
          assetKind: String(asset.asset_kind),
          role: identity.role,
          hasCompletedAnswer,
          hasLockedAnswer,
        });
        if (phaseAccessStatus === 403) {
          return reply(req, { error: isAnalysis ? "原题解析图仅供教师核对。" : "无权读取该原题图片。" }, 403);
        }
        if (!isAnalysis && !hasCompletedAnswer) {
          if (!currentAssetEligible) {
            return reply(req, { error: "原题图片不存在。" }, 404);
          }
          let isExpectedCurrentQuestion = false;
          let revisionMatches = false;
          const planId = String(body.data?.planId || "");
          const attemptSequence = body.data?.attemptSequence;
          const suppliedRevisionToken = body.data?.revisionToken === null || body.data?.revisionToken === undefined
            ? null
            : String(body.data.revisionToken);
          const expectedRevisionToken = question.question_revision_token
            ? String(question.question_revision_token)
            : null;
          revisionMatches = suppliedRevisionToken === expectedRevisionToken;
          if (
            identity.role === "student"
            && validUuid(planId)
            && Number.isInteger(attemptSequence)
            && attemptSequence >= 0
            && attemptSequence <= 7
            && revisionMatches
          ) {
            const previewRound = body.data?.previewRound === undefined ? undefined : Number(body.data.previewRound);
            const demoTarget = await isDemoStudent(assetStudentId!);
            if (previewRound === undefined || demoTarget) {
              try {
                const expectedPayload = await startPlanPayload(
                  assetStudentId!,
                  planId,
                  demoTarget
                    ? { allowCompletedPreview: true, previewRound }
                    : { includeAnswerLocks: true },
                );
                isExpectedCurrentQuestion = expectedPayload.plan.mode === "REVIEW"
                  && Number(expectedPayload.attemptSequence) === Number(attemptSequence)
                  && (expectedPayload.questions as Array<Record<string, unknown>>).some((candidate) =>
                    String(candidate.id) === questionId
                    && String(candidate.revisionToken || "") === String(expectedRevisionToken || "")
                  );
              } catch {
                isExpectedCurrentQuestion = false;
              }
            }
          }
          const questionPhaseStatus = sourceQuestionPhaseStatus({
            role: identity.role,
            hasCompletedAnswer,
            isExpectedCurrentQuestion,
            revisionMatches,
          });
          if (questionPhaseStatus !== 200) {
            return reply(req, { error: "这张原题图不属于当前账号正在作答的本轮题组。" }, 403);
          }
        }
      }
      const mimeType = String(asset.mime_type || "");
      const payloadBase64 = String(asset.payload_base64 || "");
      if (!/^image\/(png|jpeg|webp)$/.test(mimeType) || !payloadBase64) {
        return reply(req, { error: "原题图片数据无效。" }, 500);
      }
      // Never echo asset_path, question_id, local paths, signed URLs, or any
      // other storage locator.  assetId is an opaque request capability only.
      return reply(req, {
        asset: {
          kind: String(asset.asset_kind),
          mimeType,
          dataUrl: `data:${mimeType};base64,${payloadBase64}`,
          sha256: String(asset.sha256),
          width: Number(asset.width),
          height: Number(asset.height),
        },
      });
    }

    if (body.action === "question_feedback") {
      if (identity.role === "guardian") return reply(req, { error: "家长端不能代替学生作答。" }, 403);
      const planId = String(body.data?.planId || "");
      const questionId = String(body.data?.questionId || "");
      const selectedOption = body.data?.selectedOption;
      const submittedRevisionToken = body.data?.revisionToken === null || body.data?.revisionToken === undefined
        ? null
        : String(body.data.revisionToken);
      const previewRound = body.data?.previewRound === undefined ? undefined : Number(body.data.previewRound);
      if (
        !validUuid(planId)
        || !/^[a-zA-Z0-9_-]{1,160}$/.test(questionId)
        || !Number.isInteger(selectedOption)
        || selectedOption < 0
        || selectedOption > 9
      ) return reply(req, { error: "答题反馈请求无效。" }, 400);

      let targetId: string | null = null;
      let readOnlyPreview = false;
      if (identity.role === "teacher") {
        targetId = String(body.data?.studentId || "");
        readOnlyPreview = true;
      } else if (identity.role === "student" && identity.studentId) {
        targetId = await resolveDemoTarget(
          identity.studentId,
          body.data?.studentId ? String(body.data.studentId) : undefined,
        );
        if (targetId) readOnlyPreview = await isDemoStudent(targetId);
        if (previewRound !== undefined && !readOnlyPreview) {
          return reply(req, { error: "真实学习记录不能指定练习轮次。" }, 403);
        }
      }
      if (!targetId || !validUuid(targetId)) return reply(req, { error: "无权提交该题答案。" }, 403);
      const payload = await startPlanPayload(
        targetId,
        planId,
        readOnlyPreview
          ? { allowCompletedPreview: true, previewRound }
          : { includeAnswerLocks: true },
      );
       if (payload.plan.mode !== "REVIEW") return reply(req, { error: "该反馈接口只用于高中原题复习。" }, 409);
      const issuedQuestion = (payload.questions as Array<Record<string, unknown>>)
        .find((candidate) => String(candidate.id) === questionId);
      if (
        !issuedQuestion
         || !["高一", "高二", "高三"].includes(String(issuedQuestion.gradeBand))
        || issuedQuestion.sourceKind !== "licensed_local"
      ) return reply(req, { error: "这道题不属于服务器刚刚生成的本轮原题。" }, 409);
      const issuedOptions = Array.isArray(issuedQuestion.options) ? issuedQuestion.options : [];
      if (selectedOption >= issuedOptions.length) return reply(req, { error: "答案选项无效。" }, 400);
      const expectedRevisionToken = issuedQuestion.revisionToken
        ? String(issuedQuestion.revisionToken)
        : null;
      if (submittedRevisionToken !== expectedRevisionToken) {
        return reply(req, { error: "原题内容已经更新，请重新打开本轮练习后再作答。" }, 409);
      }

      const activeFeedbackReleaseId = await activeVerifiedSourceReleaseId(String(issuedQuestion.gradeBand));
      const questionResult = await supabase
        .from("chem_questions")
        .select("id,grade_band,source_kind,correct_option,explanation,scaffold,asset_refs,question_revision_token")
        .eq("id", questionId)
        .eq("grade_band", issuedQuestion.gradeBand)
        .eq("source_kind", "licensed_local")
        .eq("review_status", "approved")
        .eq("scope_status", "IN")
        .eq("usable_for_review", true)
        .eq("render_mode", "image_primary")
        .eq("source_release_id", activeFeedbackReleaseId)
        .maybeSingle();
      if (questionResult.error) throw questionResult.error;
      if (!questionResult.data) return reply(req, { error: "原题已经退出当前题库，请重新打开本轮练习。" }, 409);
      const currentRevisionToken = questionResult.data.question_revision_token
        ? String(questionResult.data.question_revision_token)
        : null;
      if (currentRevisionToken !== expectedRevisionToken) {
        return reply(req, { error: "原题内容已经更新，请重新打开本轮练习后再作答。" }, 409);
      }

      let lockedOption = selectedOption as number;
      let lockedUncertain = body.data?.uncertain === true;
      const rawFeedbackDuration = Number(body.data?.durationSec);
      let lockedDurationSec = Number.isFinite(rawFeedbackDuration)
        ? Math.min(3600, Math.max(0, Math.round(rawFeedbackDuration)))
        : 0;
      if (!readOnlyPreview) {
        const lockResult = await supabase.rpc("chem_lock_question_answer", {
          p_student_id: targetId,
          p_plan_day_id: planId,
          p_attempt_sequence: Number(payload.attemptSequence),
          p_question_id: questionId,
          p_selected_option: selectedOption,
          p_uncertain: body.data?.uncertain === true,
          p_duration_sec: lockedDurationSec,
          p_revision_token: expectedRevisionToken,
        });
        if (lockResult.error) throw lockResult.error;
        const locked = Array.isArray(lockResult.data)
          ? lockResult.data[0] as Record<string, unknown> | undefined
          : undefined;
        if (!locked) throw new RequestError(500, "答案暂时无法锁定，请稍后重试。");
        lockedOption = Number(locked.selected_option);
        lockedUncertain = locked.uncertain === true;
        lockedDurationSec = Number(locked.duration_sec) || 0;
        const lockedRevisionToken = locked.revision_token ? String(locked.revision_token) : null;
        if (lockedOption !== selectedOption || lockedRevisionToken !== expectedRevisionToken) {
          return reply(req, { error: "这道题已经按第一次提交的选项锁定，不能更换答案。" }, 409);
        }
      }

      return reply(req, {
        feedback: questionFeedbackShape(questionResult.data, lockedOption, {
          uncertain: lockedUncertain,
          durationSec: lockedDurationSec,
        }),
        simulated: readOnlyPreview,
      });
    }

    if (body.action === "junior_open_session" && identity.role === "student" && identity.studentId) {
      const planId = String(body.data?.planId || "");
      if (!validUuid(planId)) return reply(req, { error: "初中学习计划信息无效。" }, 400);
      return reply(req, { payload: await juniorSessionPayload(identity.studentId, planId) });
    }

    if (body.action === "junior_submit_step" && identity.role === "student" && identity.studentId) {
      const planId = String(body.data?.planId || "");
      const stepId = String(body.data?.stepId || "");
      const selectedOption = Number(body.data?.selectedOption);
      const durationSec = Number(body.data?.durationSec);
      const revisionToken = body.data?.revisionToken === null || body.data?.revisionToken === undefined ? null : String(body.data.revisionToken);
      if (!validUuid(planId) || !validUuid(stepId) || !Number.isInteger(selectedOption) || selectedOption < 0 || selectedOption > 9
        || !Number.isFinite(durationSec) || durationSec < 0 || durationSec > 3600) {
        return reply(req, { error: "本题作答信息无效。" }, 400);
      }
      const issued = await juniorSessionPayload(identity.studentId, planId);
      if (issued.completed || String(issued.currentStepId || "") !== stepId || !issued.currentQuestion) {
        return reply(req, { error: "这道题不是当前等待作答的原题；系统不会替换或重复保存答案。" }, 409);
      }
      const currentQuestion = issued.currentQuestion as Record<string, unknown>;
      const options = Array.isArray(currentQuestion.options) ? currentQuestion.options : [];
      if (selectedOption >= options.length || String(currentQuestion.revisionToken || "") !== String(revisionToken || "")) {
        return reply(req, { error: "原题内容已更新，请重新打开当天学习。" }, 409);
      }
      const sessionPayload = issued.session as Record<string, unknown>;
      const questionResult = await supabase.from("chem_questions")
        .select("id,correct_option,explanation,scaffold,asset_refs,question_revision_token")
        .eq("id", String(currentQuestion.id)).eq("grade_band", "初三").eq("source_kind", "licensed_local")
        .eq("review_status", "approved").eq("scope_status", "IN").maybeSingle();
      if (questionResult.error) throw questionResult.error;
      if (!questionResult.data) return reply(req, { error: "这道原题已退出题库，请联系甘老师处理。" }, 409);
      const recorded = await supabase.rpc("chem_junior_record_step", {
        p_session_id: String(sessionPayload.id), p_student_id: identity.studentId, p_step_id: stepId,
        p_selected_option: selectedOption, p_uncertain: body.data?.uncertain === true,
        p_duration_sec: Math.round(durationSec), p_revision_token: revisionToken,
      });
      if (recorded.error) {
        if (recorded.error.message.includes("already locked")) return reply(req, { error: "这道题已经按第一次选择锁定，不能更换答案。" }, 409);
        throw recorded.error;
      }
      const lock = Array.isArray(recorded.data) ? recorded.data[0] as Record<string, unknown> | undefined : undefined;
      if (!lock) throw new RequestError(500, "首次答案未能安全锁定，请稍后重试。");
      const nextPayload = await juniorSessionPayload(identity.studentId, planId);
      return reply(req, {
        feedback: questionFeedbackShape(questionResult.data, Number(lock.selected_option), {
          uncertain: lock.uncertain === true, durationSec: Number(lock.duration_sec) || 0,
        }),
        payload: nextPayload,
        ...(nextPayload.completed ? { dashboard: await studentDashboard(identity.studentId) } : {}),
      });
    }

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
      return reply(req, {
        payload: await startPlanPayload(targetId, planId, { studentOpen: true, previewRound }),
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
        .select("id,student_id,plan_date,mode,skill_ids,target_concept_keys,question_count,round_limit,max_question_level")
        .eq("id", String(attempt.planDayId))
        .eq("student_id", targetId)
        .maybeSingle();
      if (planError) throw planError;
      if (!plan) return reply(req, { error: "无权提交该学习记录。" }, 403);

      const submittedAnswers = attempt.answers as Array<Record<string, unknown>>;
      const questionCount = planQuestionCount(plan);
      const reviewProfile = {
        gradeBand: String(targetProfile.data.grade_band),
        isDemo: (targetProfile.data.metadata as Record<string, unknown> | null)?.demo === true,
      };
      const formalHighSchoolReview = isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile));
      const activeSourceReleaseId = formalHighSchoolReview
        ? await activeVerifiedSourceReleaseId(reviewProfile.gradeBand)
        : null;
      if (formalHighSchoolReview && String(plan.plan_date || "") > shanghaiDate()) {
        return reply(req, { error: "后续日期的正式复习尚未开放，请在计划当天进入。" }, 409);
      }
      const roundLimit = effectivePlanRoundLimit(plan, reviewProfile);
      if (!validFormalReviewQuestionCount({ ...formalReviewContext(plan, reviewProfile), questionCount })) {
        return reply(req, { error: `正式复习每天最多下发 ${FORMAL_REVIEW_DAILY_QUESTION_CAP} 道题；当前计划配置超限，已停止提交并通知甘老师。` }, 422);
      }
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
      if (
        isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile))
        && reviewProfile.gradeBand === "高一"
      ) {
        const confirmedSkills = confirmedHighOneSkillIds(targetProfile.data.metadata);
        if (!confirmedSkills.length || planSkillIds.some((skillId) => !confirmedSkills.includes(skillId))) {
          return reply(req, { error: "当前计划包含尚未确认学过的高一知识模块，已停止提交并通知甘老师。" }, 422);
        }
      }
      const targetConceptKeys = planTargetConceptKeys(plan);
      if (
        isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile))
        && roundLimit === 1
        && targetConceptKeys.length !== questionCount
      ) {
        return reply(req, { error: `正式复习当天必须明确配置 ${questionCount} 个细知识点，已停止提交并通知甘老师。` }, 422);
      }
      if (plan.mode === "REVIEW" && targetConceptKeys.length
        && (targetConceptKeys.length !== questionCount || new Set(targetConceptKeys).size !== targetConceptKeys.length)) {
        return reply(req, { error: "当前学习计划的细知识点配置不完整，请重新打开或联系甘老师。" }, 400);
      }
      const questionUsageColumn = plan.mode === "CLASS_QUIZ"
        ? "usable_for_class_quiz"
        : plan.mode === "EXAM_SPRINT"
          ? "usable_for_exam_sprint"
          : "usable_for_review";
      let questionQuery = supabase
        .from("chem_questions")
        .select("id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,explanation,image_url,review_status,scope_status,source_kind,source_info,asset_refs,render_mode,source_item_key,content_fingerprint,question_revision_token")
        .in("id", questionIds)
        .eq("grade_band", targetProfile.data.grade_band)
        .in("skill_id", planSkillIds)
        .eq("review_status", "approved")
        .eq("scope_status", "IN")
        .not("mother_id", "is", null)
        .eq(questionUsageColumn, true);
      if (plan.mode === "REVIEW") questionQuery = questionQuery.not("concept_key", "is", null);
      if (plan.mode === "REVIEW" && targetConceptKeys.length) {
        questionQuery = questionQuery.in("concept_key", targetConceptKeys);
      }
      if (plan.mode === "REVIEW" && ["高一", "高二", "高三"].includes(String(targetProfile.data.grade_band))) {
        questionQuery = questionQuery
          .eq("source_kind", "licensed_local")
          .eq("render_mode", "image_primary")
          .eq("source_release_id", activeSourceReleaseId!);
      }
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
      if (formalHighSchoolReview && (questionResult.data || []).some((question) =>
        !hasRequiredReviewSourceAssets(question.asset_refs)
      )) {
        return reply(req, { error: "本轮原题缺少经过核验的题面图或解析图，已停止提交并通知甘老师。" }, 422);
      }
      const securedQuestionIds = (questionResult.data || [])
        .filter((question) => plan.mode === "REVIEW" && isLicensedHighSchoolQuestion(question))
        .map((question) => String(question.id));
      const lockedAnswerByQuestionId = new Map<string, Record<string, unknown>>();
      if (securedQuestionIds.length) {
        const lockResult = await supabase.rpc("chem_get_question_answer_locks", {
          p_student_id: targetId,
          p_plan_day_id: String(plan.id),
          p_attempt_sequence: (planAttemptsResult.data || []).length,
          p_question_ids: securedQuestionIds,
        });
        if (lockResult.error) throw lockResult.error;
        for (const lock of (lockResult.data || []) as Array<Record<string, unknown>>) {
          lockedAnswerByQuestionId.set(String(lock.question_id), lock);
        }
        if (lockedAnswerByQuestionId.size !== securedQuestionIds.length) {
          return reply(req, { error: "请先逐题提交并取得服务器反馈，再完成本轮记录。" }, 409);
        }
        const submittedByQuestionId = new Map(
          submittedAnswers.map((answer) => [String(answer.questionId), answer]),
        );
        for (const securedQuestionId of securedQuestionIds) {
          const submitted = submittedByQuestionId.get(securedQuestionId);
          const locked = lockedAnswerByQuestionId.get(securedQuestionId);
          const lockedRevisionToken = locked?.revision_token ? String(locked.revision_token) : null;
          const submittedRevisionToken = submitted?.revisionToken === null || submitted?.revisionToken === undefined
            ? null
            : String(submitted.revisionToken);
          if (
            !submitted
            || !locked
            || Number(submitted.selectedOption) !== Number(locked.selected_option)
            || submittedRevisionToken !== lockedRevisionToken
          ) {
            return reply(req, { error: "本轮答案必须与服务器锁定的第一次选择一致，不能更换后再提交。" }, 409);
          }
        }
      }
      const previousAttempts = planAttemptsResult.data || [];
      const attemptSequence = previousAttempts.length;
      if (!validFormalReviewRoundLimit({
        ...formalReviewContext(plan, reviewProfile),
        storedRoundLimit: roundLimit,
        planDate: String(plan.plan_date || ""),
        hasExistingAttempt: attemptSequence > 0,
      })) {
        return reply(req, { error: "正式复习必须是每天一个题组；当前计划尚未完成规则升级，已停止提交并通知甘老师。" }, 422);
      }
      if (attemptSequence >= roundLimit) {
        return reply(req, {
          error: isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile))
            ? "今天的正式复习题组已经完成；错题和不确定题会优先进入下一次计划。"
            : `今天的 ${roundLimit} 轮已经完成，请返回计划刷新状态。`,
        }, 409);
      }
      if (!Number.isInteger(Number(attempt.sequence)) || Number(attempt.sequence) !== attemptSequence) {
        return reply(req, { error: "学习轮次已经变化，请刷新当天计划后再作答。" }, 409);
      }
      const previousAttemptIds = previousAttempts.map((item) => String(item.id));
      const priorAnswersResult = previousAttemptIds.length
        ? await supabase
          .from("chem_attempt_answers")
          .select("attempt_id,question_id,mother_id,concept_key,correct,uncertain,question_snapshot")
          .in("attempt_id", previousAttemptIds)
        : { data: [], error: null };
      if (priorAnswersResult.error) throw priorAnswersResult.error;
      const priorAnswers = priorAnswersResult.data || [];
      const priorQuestionIds = [...new Set(priorAnswers.map((answer) => String(answer.question_id)).filter(Boolean))];
      const priorQuestionMetadataResult = priorQuestionIds.length
        ? await supabase.from("chem_questions").select("id,source_item_key,content_fingerprint").in("id", priorQuestionIds)
        : { data: [], error: null };
      if (priorQuestionMetadataResult.error) throw priorQuestionMetadataResult.error;
      const priorIdentityByQuestionId = new Map(
        (priorQuestionMetadataResult.data || []).map((question) => [String(question.id), sourceIdentity(question)]),
      );
      const usedQuestionIds = new Set(priorAnswers.map((answer) => String(answer.question_id)));
      const usedMotherIds = new Set(priorAnswers.map((answer) => String(answer.mother_id)).filter(Boolean));
      const usedSourceItemKeys = new Set<string>();
      const usedContentFingerprints = new Set<string>();
      for (const answer of priorAnswers) {
        const snapshot = validQuestionSnapshot(answer.question_snapshot) ? answer.question_snapshot : null;
        const currentIdentity = priorIdentityByQuestionId.get(String(answer.question_id));
        const sourceItemKey = String(snapshot?.sourceItemKey || currentIdentity?.sourceItemKey || "");
        const contentFingerprint = String(snapshot?.contentFingerprint || currentIdentity?.contentFingerprint || "");
        if (sourceItemKey) usedSourceItemKeys.add(sourceItemKey);
        if (contentFingerprint) usedContentFingerprints.add(contentFingerprint);
      }
      const submittedMothers = (questionResult.data || []).map((question) => String(question.mother_id));
      const submittedSourceItems = (questionResult.data || []).map((question) => sourceIdentity(question).sourceItemKey).filter(Boolean) as string[];
      const submittedFingerprints = (questionResult.data || []).map((question) => sourceIdentity(question).contentFingerprint).filter(Boolean) as string[];
      if (
        submittedMothers.some((motherId) => !motherId) ||
        new Set(submittedMothers).size !== submittedMothers.length ||
        new Set(submittedSourceItems).size !== submittedSourceItems.length ||
        new Set(submittedFingerprints).size !== submittedFingerprints.length ||
        (questionResult.data || []).some((question) =>
          usedQuestionIds.has(String(question.id)) || usedMotherIds.has(String(question.mother_id))
          || Boolean(sourceIdentity(question).sourceItemKey && usedSourceItemKeys.has(sourceIdentity(question).sourceItemKey!))
          || Boolean(sourceIdentity(question).contentFingerprint && usedContentFingerprints.has(sourceIdentity(question).contentFingerprint!))
        )
      ) {
        return reply(req, { error: "同一天的后续轮次不能重复题目或同一母题，也不能重复同一来源原题，请重新打开本轮练习。" }, 409);
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
        const lockedAnswer = lockedAnswerByQuestionId.get(String(submitted.questionId));
        const selectedOption = lockedAnswer
          ? Number(lockedAnswer.selected_option)
          : typeof submitted.selectedOption === "number" ? submitted.selectedOption : Number.NaN;
        const options = Array.isArray(question?.options) ? question.options : [];
        if (!question || !Number.isInteger(selectedOption) || selectedOption < 0 || selectedOption >= options.length) {
          return reply(req, { error: "答案选项无效，请重新打开本轮练习。" }, 400);
        }
        const expectedRevisionToken = question.question_revision_token
          ? String(question.question_revision_token)
          : null;
        const submittedRevisionToken = submitted.revisionToken === null || submitted.revisionToken === undefined
          ? null
          : String(submitted.revisionToken);
        if (submittedRevisionToken !== expectedRevisionToken) {
          return reply(req, { error: "原题内容已经更新，请重新打开本轮练习后再提交。" }, 409);
        }
        const rawDuration = Number(lockedAnswer?.duration_sec ?? submitted.durationSec);
        canonicalAnswers.push({
          question_id: String(question.id),
          mother_id: String(question.mother_id),
          skill_id: String(question.skill_id),
          concept_key: question.concept_key ? String(question.concept_key) : null,
          level: Number(question.level),
          correct: selectedOption === Number(question.correct_option),
          uncertain: lockedAnswer ? lockedAnswer.uncertain === true : submitted.uncertain === true,
          duration_sec: Number.isFinite(rawDuration) ? Math.min(3600, Math.max(0, Math.round(rawDuration))) : 0,
          selected_option: selectedOption,
          question_snapshot: {
            version: 3,
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
            // v2 stores stable private descriptors only.  It never stores a
            // base64 payload, a signed URL, or an expiring storage locator.
            imageUrl: null,
            sourceKind: question.source_kind ? String(question.source_kind) : null,
            sourceInfo: questionSourceInfo(question.source_info),
            assetRefs: Array.isArray(question.asset_refs) ? question.asset_refs : [],
            renderMode: ["native", "image_assist", "image_primary"].includes(String(question.render_mode))
              ? String(question.render_mode)
              : "native",
            sourceItemKey: question.source_item_key ? String(question.source_item_key) : null,
            contentFingerprint: question.content_fingerprint ? String(question.content_fingerprint) : null,
            revisionToken: expectedRevisionToken,
            reviewStatus: String(question.review_status),
            scopeStatus: String(question.scope_status),
          },
        });
      }

      let resolvedOnSubmission = false;
      if (
        isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile))
        && attemptSequence + 1 < roundLimit
        && canonicalAnswers.length === questionCount
        && canonicalAnswers.every((answer) => answer.correct && !answer.uncertain && Boolean(answer.concept_key))
      ) {
        let maximumQuery = supabase
          .from("chem_questions")
          .select("concept_key,level,asset_refs")
          .eq("grade_band", targetProfile.data.grade_band)
          .in("skill_id", planSkillIds)
          .in("concept_key", canonicalAnswers.map((answer) => answer.concept_key!))
          .eq("review_status", "approved")
          .eq("scope_status", "IN")
          .eq("usable_for_review", true)
          .eq("source_kind", "licensed_local")
          .eq("render_mode", "image_primary")
          .eq("source_release_id", activeSourceReleaseId!);
        if (maxQuestionLevel !== null) maximumQuery = maximumQuery.lte("level", maxQuestionLevel);
        const maximumResult = await maximumQuery;
        if (maximumResult.error) throw maximumResult.error;
        const maximumLevelByConcept = new Map<string, number>();
        for (const row of (maximumResult.data || []).filter((question) =>
          hasRequiredReviewSourceAssets(question.asset_refs)
        )) {
          const conceptKey = String(row.concept_key || "");
          if (!conceptKey) continue;
          maximumLevelByConcept.set(conceptKey, Math.max(maximumLevelByConcept.get(conceptKey) || 0, Number(row.level) || 0));
        }
        resolvedOnSubmission = canonicalAnswers.every((answer) =>
          Boolean(answer.concept_key)
          && Number(answer.level) >= Number(maximumLevelByConcept.get(answer.concept_key!) || Number.POSITIVE_INFINITY));
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
      const finalization = await supabase.rpc("chem_finalize_learning_attempt", {
        p_attempt_id: attemptId,
        p_student_id: targetId,
        p_plan_day_id: String(plan.id),
        p_attempt_kind: attemptSequence === 0 ? "scheduled" : "review",
        p_sequence: attemptSequence,
        p_mode: String(plan.mode),
        p_started_at: startedAt,
        p_completed_at: completedAtIso,
        p_first_score: canonicalAnswers.filter((answer) => answer.correct).length,
        p_answers: canonicalAnswers.map((answer) => ({
          ...answer,
          revision_token: answer.question_snapshot.revisionToken ?? null,
        })),
        p_skill_states: [...computedStateBySkill.values()],
      });
      if (finalization.error?.code === "23505") {
        return reply(req, { error: "这一轮已经提交，不能重复写入。请返回学习计划刷新状态。" }, 409);
      }
      if (finalization.error) throw finalization.error;
      if (finalization.data !== true) throw new RequestError(500, "本轮记录未能完整保存，请稍后重试。");
      let nextPlanPersonalized = false;
      if (
        isFormalHighSchoolReview(formalReviewContext(plan, reviewProfile))
        && (attemptSequence + 1 >= roundLimit || resolvedOnSubmission)
      ) {
        // Completion is already durable. Personalising tomorrow is a separate
        // server-only step so a temporary planning shortage can never erase or
        // duplicate today's answers. The database function updates only an
        // unstarted next-day REVIEW plan and never touches independent quizzes.
        const queued = await supabase.rpc("chem_enqueue_review_personalization", {
          p_student_id: targetId,
          p_completed_plan_id: String(plan.id),
        });
        if (queued.error || queued.data !== true) {
          console.error("next REVIEW plan personalization enqueue failed", queued.error);
        } else {
          const nextPlanResult = await supabase.rpc("chem_personalize_next_review_plan", {
            p_student_id: targetId,
            p_completed_plan_id: String(plan.id),
            // Kept for the RPC's backwards-compatible signature. The database
            // derives the authoritative completion time from the saved attempt.
            p_completed_at: completedAtIso,
          });
          if (nextPlanResult.error) {
            console.error("next REVIEW plan personalization failed", nextPlanResult.error);
          } else {
            nextPlanPersonalized = nextPlanResult.data === true;
          }
        }
      }
      const completedFeedback = canonicalAnswers.map((answer) => {
        const question = questionById.get(answer.question_id)!;
        return questionFeedbackShape(question, answer.selected_option, {
          uncertain: answer.uncertain,
          durationSec: answer.duration_sec,
        });
      });
      return reply(req, {
        dashboard: await studentDashboard(targetId),
        achievements: [],
        feedback: completedFeedback,
        nextPlanPersonalized,
      });
    }
    return reply(req, { error: "无权执行该操作。" }, 403);
  } catch (error) {
    if (error instanceof RequestError) return reply(req, { error: error.message }, error.status);
    console.error(error);
    return reply(req, { error: "服务暂时不可用，请稍后重试。" }, 500);
  }
});
