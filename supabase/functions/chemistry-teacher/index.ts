import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
const allowedOrigins = new Set(["https://ganlu6633-source.github.io", "http://localhost:4173", "http://localhost:5173"]);
const JUNIOR_SOURCE_KIND = "user_provided_local";
const allowedQuestionSourceKinds = new Set(["teacher_original", "licensed_local", JUNIOR_SOURCE_KIND, "original_variant"]);
function headers(req: Request) {
  const origin = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://ganlu6633-source.github.io",
    "Access-Control-Allow-Headers": "apikey, content-type, x-app-session",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "Vary": "Origin",
  };
}
const reply = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: headers(req) });
function code() { return Array.from(crypto.getRandomValues(new Uint32Array(8)), (n) => String(n % 10)).join(""); }
async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
function validUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function validReviewSourceAssetRef(value: unknown, kind: "question_image" | "analysis_image") {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const ref = value as Record<string, unknown>;
  return ref.kind === kind
    && /^[a-zA-Z0-9/_-]{16,200}$/.test(String(ref.path || ""))
    && String(ref.alt || "").trim().length > 0
    && /^[0-9a-f]{64}$/.test(String(ref.sha256 || ""))
    && Number.isInteger(Number(ref.width))
    && Number(ref.width) > 0
    && Number.isInteger(Number(ref.height))
    && Number(ref.height) > 0;
}
function hasRequiredReviewSourceAssets(value: unknown) {
  if (!Array.isArray(value)) return false;
  return value.some((ref) => validReviewSourceAssetRef(ref, "question_image"))
    && value.some((ref) => validReviewSourceAssetRef(ref, "analysis_image"));
}
function recordValue(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
type BoundedJsonResult =
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; status: 400 | 413; error: string };
async function readBoundedJsonObject(req: Request, maxBytes = 5 * 1024 * 1024): Promise<BoundedJsonResult> {
  const declaredLength = req.headers.get("content-length");
  if (declaredLength !== null) {
    const parsedLength = Number(declaredLength);
    if (!Number.isSafeInteger(parsedLength) || parsedLength < 0) {
      return { ok: false, status: 400, error: "请求长度无效。" };
    }
    if (parsedLength > maxBytes) return { ok: false, status: 413, error: "请求正文超过5 MB限制。" };
  }
  if (!req.body) return { ok: false, status: 400, error: "请求正文不能为空。" };
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return { ok: false, status: 413, error: "请求正文超过5 MB限制。" };
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return { ok: false, status: 400, error: "请求正文不是有效UTF-8。" };
  }
  try {
    const value: unknown = JSON.parse(text);
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return { ok: false, status: 400, error: "请求正文必须是JSON对象。" };
    }
    return { ok: true, value: value as Record<string, unknown> };
  } catch {
    return { ok: false, status: 400, error: "请求正文不是有效JSON。" };
  }
}
function validVideoUrl(provider: string, value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    const label = provider.toLowerCase();
    if (label.includes("bilibili") || label.includes("哔哩") || label.includes("b站")) {
      return host === "b23.tv" || host === "bilibili.com" || host.endsWith(".bilibili.com");
    }
    if (label.includes("niconico") || label.includes("nico")) {
      return host === "nico.ms" || host === "nicovideo.jp" || host.endsWith(".nicovideo.jp");
    }
    return true;
  } catch {
    return false;
  }
}

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

async function listVideoRecommendations(studentId: string | null, includeUnpublished = true) {
  const { data, error } = await admin.rpc("chem_video_list_recommendations", {
    p_student_id: studentId,
    p_include_unpublished: includeUnpublished,
  });
  if (error) throw error;
  const rows = (data || []) as Array<Record<string, unknown>>;
  return rows.map((row) => videoRecommendationShape(row));
}

async function teacher(req: Request) {
  const token = req.headers.get("x-app-session");
  if (!token) return null;
  const { data, error } = await admin.rpc("chem_resolve_app_session", { p_token_hash: await sha256(token) });
  if (error || !data?.length || data[0].access_role !== "teacher") return null;
  return { displayName: data[0].principal_name || "甘老师" };
}

async function readOnlyStudentPreview(
  req: Request,
  action: "student_preview_dashboard" | "preview_start_plan" | "student_learning_record" | "question_asset" | "question_feedback",
  data: unknown,
) {
  const response = await fetch(`${url}/functions/v1/chemistry-access`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": req.headers.get("apikey") || "",
      "x-app-session": req.headers.get("x-app-session") || "",
    },
    body: JSON.stringify({ action, data }),
  });
  const payload = await response.json().catch(() => ({ error: "预览服务暂时不可用。" }));
  return { payload, status: response.status };
}

function shanghaiDayRange() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const date = `${value.year}-${value.month}-${value.day}`;
  const start = new Date(`${date}T00:00:00+08:00`);
  const dateKey = (offsetDays: number) => new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date(start.getTime() + offsetDays * 86400000));
  return {
    date,
    // The funded calendar ends on 2026-09-29; the audited window shrinks as
    // dates pass instead of drifting beyond the capacity-funded horizon.
    readinessEndDate: date < "2026-09-29" ? "2026-09-29" : dateKey(0),
    start: start.toISOString(),
    end: new Date(start.getTime() + 86400000).toISOString(),
  };
}

async function dashboard() {
  const dayRange = shanghaiDayRange();
  // Reconcile the narrow finalize→enqueue gap first. Safe compensation is
  // rate-limited inside the retry RPC; persistent capacity/scope failures stay
  // visible below instead of being retried every ten seconds.
  const reconcilePersonalization = await admin.rpc("chem_reconcile_missing_review_personalization_jobs");
  if (reconcilePersonalization.error) console.error("REVIEW personalization reconciliation failed", reconcilePersonalization.error);
  const retryPersonalization = await admin.rpc("chem_retry_pending_review_personalization", { p_limit: 5 });
  if (retryPersonalization.error) console.error("REVIEW personalization retry failed", retryPersonalization.error);
  const [students, alerts, report, courseCount, questionCount, guardians, fourWeekPlans, readinessPlans, quizStudents, quizLinks, videoRecommendations, conceptCatalog, personalizationJobs, capacityShortages] = await Promise.all([
    admin.from("chem_students_v2").select("id,display_name,grade_band,record_status,needs_initial_diagnostic,metadata").order("grade_band").order("display_name"),
    admin.from("chem_teacher_alerts").select("id,student_id,severity,title,reason").is("resolved_at", null).order("created_at", { ascending: false }).limit(20),
    admin.from("chem_daily_reports").select("*").order("report_date", { ascending: false }).limit(1).maybeSingle(),
    admin.from("chem_course_nodes").select("id", { count: "exact", head: true }).eq("teacher_approved", false),
    admin.from("chem_questions").select("id", { count: "exact", head: true }).in("review_status", ["draft", "needs_review"]),
    admin.rpc("chem_list_guardian_contacts"),
    admin.from("chem_learning_plans").select("student_id").eq("mode", "REVIEW").gte("plan_date", "2026-08-17"),
    admin.from("chem_learning_plans")
      .select("id,student_id,plan_date,skill_ids,target_concept_keys,knowledge_summaries,question_count,round_limit")
      .eq("mode", "REVIEW")
      .gte("plan_date", dayRange.date)
      .lte("plan_date", dayRange.readinessEndDate),
    admin.from("students").select("id,display_name").eq("active", true).order("display_name"),
    admin.from("chem_quiz_student_links").select("quiz_student_id,chem_student_id"),
    listVideoRecommendations(null, true),
    admin.rpc("chem_review_concept_catalog_rows"),
    admin.rpc("chem_review_personalization_job_rows"),
    admin.rpc("chem_review_capacity_shortage_rows"),
  ]);
  for (const result of [students, alerts, report, courseCount, questionCount, guardians, fourWeekPlans, readinessPlans, quizStudents, quizLinks, conceptCatalog, personalizationJobs, capacityShortages]) if (result.error) throw result.error;
  const activeVerifiedSourceReleases = await admin.rpc("chem_active_verified_source_releases");
  if (activeVerifiedSourceReleases.error) throw activeVerifiedSourceReleases.error;
  const activeReleaseByGrade = new Map<string, string>();
  for (const gradeBand of ["高一", "高二", "高三"]) {
    const matching = (activeVerifiedSourceReleases.data || []).filter((row) =>
      String(row.grade_band) === gradeBand && validUuid(String(row.source_release_id || ""))
    );
    if (matching.length !== 1) {
      throw new Error(`${gradeBand}当前必须且只能有一个已完成全量图像核验的正式原题版本。`);
    }
    activeReleaseByGrade.set(gradeBand, String(matching[0].source_release_id));
  }
  const activeVerifiedReleaseIds = [...activeReleaseByGrade.values()];
  const activeQuizIds = (quizStudents.data || []).map((student) => student.id);
  const quizSessions = activeQuizIds.length
    ? await admin.from("quiz_sessions")
      .select("id,student_id,round,training_theme,correct_count,total_count,total_sec,wrong_tags,slow_tags,completed_at")
      .in("student_id", activeQuizIds)
      .gte("completed_at", dayRange.start)
      .lt("completed_at", dayRange.end)
      .order("completed_at", { ascending: false })
      .limit(250)
    : { data: [], error: null };
  if (quizSessions.error) throw quizSessions.error;
  const guardianNames = new Map<string, string[]>();
  for (const contact of guardians.data || []) guardianNames.set(contact.student_id, [...(guardianNames.get(contact.student_id) || []), contact.display_name]);
  const planDays = new Map<string, number>();
  for (const plan of fourWeekPlans.data || []) planDays.set(plan.student_id, (planDays.get(plan.student_id) || 0) + 1);
  const quizNames = new Map((quizStudents.data || []).map((student) => [student.id, student.display_name]));
  const chemIds = new Map((quizLinks.data || []).map((link) => [link.quiz_student_id, link.chem_student_id]));
  const liveQuizRows = quizSessions.data || [];
  const quizCompletedStudentCount = new Set(liveQuizRows.map((session) => session.student_id)).size;
  const pendingVideoCount = videoRecommendations.filter((item) => item.status === "draft").length;
  const studentNameById = new Map((students.data || []).map((student) => [String(student.id), String(student.display_name)]));
  const capacityReasonText = (reasonCode: string) => {
    if (reasonCode === "no_upgrade_original") return "答对后没有更高难度、且未做过的同知识点原题";
    if (reasonCode === "no_non_escalating_original") return "错题或不确定题缺少同级或更低难度的新原题";
    if (reasonCode === "source_original_exhausted") return "该知识点可用且未做过的原题已经用完";
    if (reasonCode === "high1_confirmed_scope_missing") return "高一已学范围尚未确认";
    if (reasonCode.includes("scope")) return "计划知识点超出该学生已确认的学习范围";
    return "未来计划的无重复原题容量或映射尚未通过核验";
  };
  const planningAlerts = [
    ...(personalizationJobs.data || []).flatMap((job) => {
      if (job.status !== "pending" && job.status !== "blocked") return [];
      return [{
        id: `personalization:${String(job.completed_plan_id)}`,
        kind: "personalization",
        studentName: studentNameById.get(String(job.student_id)) || "正式学生",
        planDate: job.next_plan_date ? String(job.next_plan_date) : null,
        message: job.status === "blocked"
          ? "后续某日题组已经被提前打开，系统为保护已下发原题没有重排；请甘老师核对日期与学生路径后人工处理。"
          : "个性化计划尚未安全生成；原计划已保留，系统会限次重试，仍失败时请核对原题容量与已学范围。",
        createdAt: String(job.updated_at),
      }];
    }),
    ...(capacityShortages.data || []).map((shortage) => {
      const detail = shortage.detail && typeof shortage.detail === "object"
        ? shortage.detail as Record<string, unknown>
        : {};
      const conceptLabel = String(detail.conceptLabel || "").trim();
      return {
        id: `capacity:${String(shortage.student_id)}:${String(shortage.anchor_date)}:${String(shortage.reason_code)}`,
        kind: "capacity",
        studentName: studentNameById.get(String(shortage.student_id)) || "正式学生",
        planDate: shortage.anchor_date ? String(shortage.anchor_date) : null,
        message: `${capacityReasonText(String(shortage.reason_code))}${conceptLabel ? `：${conceptLabel}` : ""}。系统没有改写该学生计划，请补充材料或调整范围后重试。`,
        createdAt: String(shortage.created_at),
      };
    }),
  ].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  const activeFormalHighSchoolIds = new Set((students.data || []).flatMap((student) =>
    student.record_status === "active"
      && ["高一", "高二", "高三"].includes(String(student.grade_band))
      && student.metadata?.demo !== true
      ? [String(student.id)]
      : []));
  const formalGradeByStudent = new Map((students.data || []).flatMap((student) =>
    activeFormalHighSchoolIds.has(String(student.id))
      ? [[String(student.id), String(student.grade_band)] as const]
      : []));
  const catalogByConcept = new Map((conceptCatalog.data || []).map((row) => [String(row.concept_key), {
    gradeBand: String(row.grade_band),
    skillId: String(row.skill_id),
    title: String(row.concept_title),
    sequenceNo: Number(row.sequence_no),
  }]));
  const catalogCountBySkill = new Map<string, number>();
  for (const row of conceptCatalog.data || []) {
    const skillId = String(row.skill_id);
    catalogCountBySkill.set(skillId, (catalogCountBySkill.get(skillId) || 0) + 1);
  }
  const allowedSkillsByStudent = new Map<string, Set<string>>();
  for (const student of students.data || []) {
    const studentId = String(student.id);
    if (!activeFormalHighSchoolIds.has(studentId)) continue;
    const gradeBand = String(student.grade_band);
    if (gradeBand === "高一") {
      const raw = student.metadata?.confirmedLearnedSkillIds;
      allowedSkillsByStudent.set(studentId, new Set(Array.isArray(raw) ? raw.map(String).filter(Boolean) : []));
    } else {
      allowedSkillsByStudent.set(studentId, new Set((conceptCatalog.data || [])
        .filter((row) => String(row.grade_band) === gradeBand)
        .map((row) => String(row.skill_id))));
    }
  }
  const readinessRows = (readinessPlans.data || []).filter((plan) => activeFormalHighSchoolIds.has(String(plan.student_id)));
  for (const plan of readinessRows) {
    const skillIds = Array.isArray(plan.skill_ids) ? plan.skill_ids.map(String).filter(Boolean) : [];
    if (skillIds.length) continue;
    planningAlerts.push({
      id: `readiness-empty-skill:${String(plan.id)}`,
      kind: "capacity",
      studentName: studentNameById.get(String(plan.student_id)) || "正式学生",
      planDate: String(plan.plan_date),
      message: "计划没有配置可对应的学习模块，系统会停止下发；请先完成知识点、模块和原题的一一映射。",
      createdAt: `${String(plan.plan_date)}T00:00:00+08:00`,
    });
  }
  const plannedSkillIds = [...new Set(readinessRows.flatMap((plan) =>
    Array.isArray(plan.skill_ids) ? plan.skill_ids.map((skillId) => String(skillId)).filter(Boolean) : []))];
  const [readinessSkills, readinessQuestions] = plannedSkillIds.length
    ? await Promise.all([
      admin.from("chem_skills").select("id,title,grade_band").in("id", plannedSkillIds),
      admin.from("chem_questions")
        .select("skill_id,concept_key,source_item_key,content_fingerprint,mother_id,level,grade_band,source_release_id,asset_refs")
        .in("skill_id", plannedSkillIds)
        .eq("review_status", "approved")
        .eq("scope_status", "IN")
        .eq("usable_for_review", true)
        .eq("source_kind", "licensed_local")
        .eq("render_mode", "image_primary")
        .in("source_release_id", activeVerifiedReleaseIds)
        .limit(5000),
    ])
    : [{ data: [], error: null }, { data: [], error: null }];
  if (readinessSkills.error || readinessQuestions.error) throw readinessSkills.error || readinessQuestions.error;
  const skillInfo = new Map((readinessSkills.data || []).map((skill) => [String(skill.id), skill]));
  const sourceUsage = activeFormalHighSchoolIds.size
    ? await admin.rpc("chem_review_active_source_usage_counts", { p_student_ids: [...activeFormalHighSchoolIds] })
    : { data: [], error: null };
  if (sourceUsage.error) throw sourceUsage.error;
  const usedCountByStudentConcept = new Map((sourceUsage.data || []).map((row) => [
    `${String(row.student_id)}:${String(row.concept_key)}`,
    Number(row.used_count) || 0,
  ]));
  type ConceptPool = { sources: Set<string>; fingerprints: Set<string>; mothers: Set<string>; levels: Set<number>; title: string };
  const conceptPools = new Map<string, Map<string, ConceptPool>>();
  for (const question of readinessQuestions.data || []) {
    const skillId = String(question.skill_id || "");
    const conceptKey = String(question.concept_key || "");
    const sourceKey = String(question.source_item_key || "");
    const fingerprint = String(question.content_fingerprint || "");
    const motherId = String(question.mother_id || "");
    const expectedReleaseId = activeReleaseByGrade.get(String(question.grade_band || ""));
    if (
      !skillId || !conceptKey || !sourceKey || !fingerprint || !motherId
      || String(question.source_release_id || "") !== expectedReleaseId
      || !hasRequiredReviewSourceAssets(question.asset_refs)
    ) continue;
    const byConcept = conceptPools.get(skillId) || new Map<string, ConceptPool>();
    const catalogEntry = catalogByConcept.get(conceptKey);
    const pool = byConcept.get(conceptKey) || {
      sources: new Set<string>(), fingerprints: new Set<string>(), mothers: new Set<string>(), levels: new Set<number>(),
      title: catalogEntry?.title || conceptKey,
    };
    pool.sources.add(sourceKey);
    pool.fingerprints.add(fingerprint);
    pool.mothers.add(motherId);
    if (Number.isFinite(Number(question.level))) pool.levels.add(Number(question.level));
    byConcept.set(conceptKey, pool);
    conceptPools.set(skillId, byConcept);
  }
  const plannedSkillStats = new Map<string, {
    students: Set<string>;
    dates: Set<string>;
    visitsByStudentConcept: Map<string, number>;
    targetConcepts: Set<string>;
    expectedConceptCount: number;
    invalidDailyPackageCount: number;
  }>();
  for (const plan of readinessRows) {
    const studentId = String(plan.student_id);
    const studentGradeBand = formalGradeByStudent.get(studentId) || "";
    const studentAllowedSkills = allowedSkillsByStudent.get(studentId) || new Set<string>();
    const skillIds = Array.isArray(plan.skill_ids) ? plan.skill_ids.map((skillId) => String(skillId)).filter(Boolean) : [];
    const explicitTargets = Array.isArray(plan.target_concept_keys)
      ? plan.target_concept_keys.map((conceptKey) => String(conceptKey)).filter(Boolean)
      : [];
    const knowledgeSummaries = Array.isArray(plan.knowledge_summaries)
      ? plan.knowledge_summaries.map((summary) => String(summary).trim()).filter(Boolean)
      : [];
    for (const skillId of [...new Set(skillIds)]) {
      const stat = plannedSkillStats.get(skillId) || {
        students: new Set<string>(), dates: new Set<string>(), visitsByStudentConcept: new Map<string, number>(),
        targetConcepts: new Set<string>(),
        expectedConceptCount: catalogCountBySkill.get(skillId) || 0, invalidDailyPackageCount: 0,
      };
      stat.students.add(studentId);
      stat.dates.add(String(plan.plan_date));
      const skillTargets = explicitTargets.filter((conceptKey) => conceptKey.startsWith(`${skillId}__`));
      const uniqueTargets = new Set(explicitTargets);
      const targetsOwnedByPlan = explicitTargets.every((conceptKey) => {
        const catalogEntry = catalogByConcept.get(conceptKey);
        return Boolean(catalogEntry
          && catalogEntry.gradeBand === studentGradeBand
          && skillIds.includes(catalogEntry.skillId)
          && studentAllowedSkills.has(catalogEntry.skillId));
      });
      const everySkillHasTarget = skillIds.every((listedSkill) => explicitTargets.some((conceptKey) =>
        catalogByConcept.get(conceptKey)?.skillId === listedSkill));
      const summariesMatchCatalog = knowledgeSummaries.length === explicitTargets.length
        && explicitTargets.every((conceptKey, index) => catalogByConcept.get(conceptKey)?.title === knowledgeSummaries[index]);
      const invalidDailyPackage = (
        Number(plan.round_limit) !== 1
        || Number(plan.question_count) < 1
        || Number(plan.question_count) > 8
        || skillIds.length < 1
        || new Set(skillIds).size !== skillIds.length
        || explicitTargets.length !== Number(plan.question_count)
        || uniqueTargets.size !== explicitTargets.length
        || !targetsOwnedByPlan
        || !everySkillHasTarget
        || !summariesMatchCatalog
      );
      if (invalidDailyPackage) stat.invalidDailyPackageCount += 1;
      if (explicitTargets.length) {
        for (const conceptKey of skillTargets) {
          stat.targetConcepts.add(conceptKey);
          const visitKey = `${studentId}:${conceptKey}`;
          stat.visitsByStudentConcept.set(visitKey, (stat.visitsByStudentConcept.get(visitKey) || 0) + 1);
        }
      } else {
        const visitKey = `${studentId}:*`;
        stat.visitsByStudentConcept.set(visitKey, (stat.visitsByStudentConcept.get(visitKey) || 0) + 1);
      }
      plannedSkillStats.set(skillId, stat);
    }
  }
  const sourcePoolWarnings = [...plannedSkillStats.entries()].flatMap(([skillId, stat]) => {
    const byConcept = conceptPools.get(skillId) || new Map<string, ConceptPool>();
    const allPools = [...byConcept.values()];
    const availableCount = (pool: ConceptPool) => Math.min(pool.sources.size, pool.fingerprints.size, pool.mothers.size);
    const allCounts = allPools.map(availableCount);
    const allDifficultyLevelCounts = allPools.map((pool) => pool.levels.size);
    const conceptCount = byConcept.size;
    const minimumQuestionsPerConcept = allCounts.length ? Math.min(...allCounts) : 0;
    const minimumDifficultyLevelsPerConcept = allDifficultyLevelCounts.length ? Math.min(...allDifficultyLevelCounts) : 0;
    const maxVisitsPerStudent = Math.max(0, ...stat.visitsByStudentConcept.values());
    const requiredForDailyPackage = 1;
    const relevantConceptKeys = stat.targetConcepts.size ? [...stat.targetConcepts] : [...byConcept.keys()];
    let maximumPreviouslyUsedPerConcept = 0;
    let requiredForCrossDateNoRepeat = 0;
    const requiredByConcept = new Map<string, number>();
    for (const studentId of stat.students) {
      for (const conceptKey of relevantConceptKeys) {
        const visits = stat.visitsByStudentConcept.get(`${studentId}:${conceptKey}`)
          ?? stat.visitsByStudentConcept.get(`${studentId}:*`)
          ?? 0;
        const previouslyUsed = usedCountByStudentConcept.get(`${studentId}:${conceptKey}`) || 0;
        maximumPreviouslyUsedPerConcept = Math.max(maximumPreviouslyUsedPerConcept, previouslyUsed);
        const required = previouslyUsed + visits;
        requiredByConcept.set(conceptKey, Math.max(requiredByConcept.get(conceptKey) || 0, required));
        requiredForCrossDateNoRepeat = Math.max(requiredForCrossDateNoRepeat, required);
      }
    }
    const conceptDetails = relevantConceptKeys.map((conceptKey) => {
      const pool = byConcept.get(conceptKey) || { sources: new Set<string>(), fingerprints: new Set<string>(), mothers: new Set<string>(), levels: new Set<number>(), title: conceptKey };
      const requiredQuestions = requiredByConcept.get(conceptKey) || requiredForDailyPackage;
      const availableQuestions = availableCount(pool);
      return {
        conceptKey,
        conceptTitle: pool.title,
        availableQuestions,
        requiredQuestions,
        missingQuestions: Math.max(0, requiredQuestions - availableQuestions),
        difficultyLevels: pool.levels.size,
      };
    });
    const isBlocking = stat.invalidDailyPackageCount > 0
      || relevantConceptKeys.some((conceptKey) => (byConcept.get(conceptKey) ? availableCount(byConcept.get(conceptKey)!) : 0) < requiredForDailyPackage);
    const lacksDifficultyProgression = relevantConceptKeys.some((conceptKey) => (byConcept.get(conceptKey)?.levels.size || 0) < 2);
    const lacksCrossDateCapacity = conceptDetails.some((detail) => detail.missingQuestions > 0);
    const info = skillInfo.get(skillId);
    const skillTitle = String(info?.title || skillId);
    const gradeBand = String(info?.grade_band || "高一");
    const shared = {
      gradeBand, skillId, skillTitle,
      plannedStudentCount: stat.students.size,
      plannedDateCount: stat.dates.size,
      maxVisitsPerStudent,
      conceptCount,
      expectedConceptCount: stat.expectedConceptCount,
      minimumQuestionsPerConcept,
      minimumDifficultyLevelsPerConcept,
      maximumPreviouslyUsedPerConcept,
      requiredForDailyPackage,
      requiredForCrossDateNoRepeat,
      conceptDetails,
    };
    const warnings = [];
    if (isBlocking) warnings.push({
      ...shared,
      id: `${gradeBand}:${skillId}:blocking`,
      severity: "blocking",
      message: `截至9月29日的计划会用到“${skillTitle}”。其中${stat.invalidDailyPackageCount}个计划未满足“每天一个题组、1—8道、知识点与题目一一对应”；已排知识点每次至少需要${requiredForDailyPackage}道未做过的原题。未补足前系统必须停止下发。`,
    });
    if (lacksCrossDateCapacity) warnings.push({
      ...shared,
      id: `${gradeBand}:${skillId}:capacity`,
      severity: "capacity",
      message: `截至9月29日，同一学生最多安排“${skillTitle}”${maxVisitsPerStudent}天；已做原题也计入占用。按跨日完全不重复口径，缺口细知识点最多需${requiredForCrossDateNoRepeat}道原题（已有学生最多用过${maximumPreviouslyUsedPerConcept}道）。下面逐项列出实际缺口。`,
    });
    if (lacksDifficultyProgression) warnings.push({
      ...shared,
      id: `${gradeBand}:${skillId}:progression`,
      severity: "progression",
      message: `“${skillTitle}”当前至少有一个已排细知识点只有一个难度层级，答对后没有更难原题可升级。请补充或重新核定该细点的分层原题。`,
    });
    return warnings;
  }).sort((a, b) => {
    const rank = (value: string) => value === "blocking" ? 0 : value === "progression" ? 1 : 2;
    return rank(a.severity) === rank(b.severity)
      ? a.gradeBand.localeCompare(b.gradeBand)
      : rank(a.severity) - rank(b.severity);
  });
  planningAlerts.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  return {
    students: (students.data || []).map((s) => ({
      id: s.id,
      displayName: s.display_name,
      gradeBand: s.grade_band,
      status: s.record_status,
      needsInitialDiagnostic: s.needs_initial_diagnostic,
      guardianNames: s.metadata?.demo ? [] : guardianNames.get(s.id) || [],
      curriculumCohort: s.metadata?.curriculumCohort || null,
      planDays: planDays.get(s.id) || 0,
    })),
    alerts: (alerts.data || []).map((a) => ({ id: a.id, studentId: a.student_id, severity: a.severity, title: a.title, reason: a.reason })),
    dailySummary: {
      generatedAt: new Date().toISOString(),
      classQuizCount: liveQuizRows.length,
      quizCompletedStudentCount,
      quizRosterCount: activeQuizIds.length,
      reviewCount: report.data?.review_count || 0,
      interventionCount: report.data?.intervention_count || 0,
      pendingVideoCount,
      publishedVideoCount: videoRecommendations.filter((item) => item.status === "published").length,
    },
    recentQuizSessions: liveQuizRows.map((session) => ({
      id: session.id,
      studentId: chemIds.get(session.student_id) || null,
      studentName: quizNames.get(session.student_id) || "未识别学生",
      round: session.round,
      trainingTheme: session.training_theme || "即时小测",
      correctCount: session.correct_count,
      totalCount: session.total_count,
      totalSec: session.total_sec,
      wrongTags: session.wrong_tags || [],
      slowTags: session.slow_tags || [],
      completedAt: session.completed_at,
    })),
    pendingCourseNodes: courseCount.count || 0, pendingQuestions: questionCount.count || 0,
    recentVideoRecommendations: videoRecommendations.slice(0, 20),
    sourcePoolWarnings,
    planningAlerts,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: headers(req) });
  if (req.method !== "POST") return reply(req, { error: "仅支持 POST 请求。" }, 405);
  try {
    const user = await teacher(req);
    if (!user) return reply(req, { error: "登录已失效，请重新输入姓名和登录码。" }, 401);
    const parsedBody = await readBoundedJsonObject(req);
    if (!parsedBody.ok) return reply(req, { error: parsedBody.error }, parsedBody.status);
    const body = parsedBody.value;
    const action = typeof body.action === "string" ? body.action : "";
    const bodyData = recordValue(body.data);

    if (action === "teacher_dashboard") return reply(req, { dashboard: await dashboard() });
    if (
      action === "student_preview_dashboard"
      || action === "preview_start_plan"
      || action === "student_learning_record"
      || action === "question_asset"
      || action === "question_feedback"
    ) {
      const preview = await readOnlyStudentPreview(req, action, bodyData);
      return reply(req, preview.payload, preview.status);
    }
    if (action === "list_video_recommendations") {
      const requestedStudentId = bodyData.studentId ? String(bodyData.studentId) : null;
      const requestedStatus = bodyData.status ? String(bodyData.status) : null;
      const requestedDate = bodyData.date ? String(bodyData.date) : null;
      if (requestedStudentId && !validUuid(requestedStudentId)) return reply(req, { error: "学生信息无效。" }, 400);
      if (requestedStatus && !["draft", "published", "withdrawn"].includes(requestedStatus)) {
        return reply(req, { error: "视频审核状态无效。" }, 400);
      }
      if (requestedDate && !/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)) return reply(req, { error: "筛选日期无效。" }, 400);
      const recommendations = await listVideoRecommendations(requestedStudentId, true);
      return reply(req, {
        recommendations: recommendations.filter((item) => (
          (!requestedStatus || item.status === requestedStatus)
          && (!requestedDate || item.unresolvedOn === requestedDate)
        )),
      });
    }
    if (action === "create_video_recommendation") {
      const data = bodyData;
      const studentId = String(data.studentId || "");
      const skillId = String(data.skillId || "").trim();
      const title = String(data.title || "").trim();
      const provider = String(data.provider || "");
      const url = String(data.url || "").trim();
      const teacherReason = String(data.teacherReason || "").trim();
      const trackingCapability = String(data.trackingCapability || "self_reported");
      const unresolvedOn = data.unresolvedOn || data.unresolvedDate ? String(data.unresolvedOn || data.unresolvedDate) : null;
      const sourceAttemptId = data.sourceAttemptId ? String(data.sourceAttemptId) : null;
      const sourceAlertId = data.sourceAlertId ? String(data.sourceAlertId) : null;
      if (!validUuid(studentId) || !skillId || title.length < 1 || title.length > 160 || teacherReason.length < 1 || teacherReason.length > 1000) {
        return reply(req, { error: "请完整填写学生、知识点、视频标题和推荐说明。" }, 400);
      }
      if (!provider || provider.length > 60 || !validVideoUrl(provider, url)) {
        return reply(req, { error: "视频来源或 HTTPS 链接无效。" }, 400);
      }
      if (!["link_open_only", "self_reported", "player_tracked"].includes(trackingCapability)) {
        return reply(req, { error: "观看记录方式无效。" }, 400);
      }
      if (trackingCapability === "player_tracked" && !provider.includes("甘老师")) {
        return reply(req, { error: "外部网页不能声明为播放器自动追踪，请选择“学生自报进度”或“仅记录打开”。" }, 400);
      }
      if (unresolvedOn && !/^\d{4}-\d{2}-\d{2}$/.test(unresolvedOn)) return reply(req, { error: "待解决日期无效。" }, 400);
      if ((sourceAttemptId && !validUuid(sourceAttemptId)) || (sourceAlertId && !validUuid(sourceAlertId))) {
        return reply(req, { error: "关联的学习证据无效。" }, 400);
      }
      const created = await admin.rpc("chem_video_create_recommendation", {
        p_student_id: studentId,
        p_skill_id: skillId,
        p_title: title,
        p_provider: provider,
        p_external_url: url,
        p_teacher_reason: teacherReason,
        p_tracking_capability: trackingCapability,
        p_unresolved_on: unresolvedOn,
        p_source_attempt_id: sourceAttemptId,
        p_source_alert_id: sourceAlertId,
        p_actor_name: user.displayName,
      });
      if (created.error) {
        console.warn("video recommendation rejected", created.error.message);
        return reply(req, { error: "推荐未保存：请确认学生、知识点和关联的未解决记录一致。" }, 400);
      }
      const recommendations = await listVideoRecommendations(studentId, true);
      return reply(req, { recommendation: recommendations.find((item) => item.id === created.data) || null }, 201);
    }
    if (["publish_video_recommendation", "withdraw_video_recommendation"].includes(action)) {
      const recommendationId = String(bodyData.recommendationId || "");
      if (!validUuid(recommendationId)) return reply(req, { error: "视频推荐信息无效。" }, 400);
      const targetStatus = action === "publish_video_recommendation" ? "published" : "withdrawn";
      const changed = await admin.rpc("chem_video_set_recommendation_status", {
        p_recommendation_id: recommendationId,
        p_target_status: targetStatus,
        p_actor_name: user.displayName,
      });
      if (changed.error) {
        console.warn("video status change rejected", changed.error.message);
        return reply(req, {
          error: targetStatus === "published"
            ? "当前状态不能发布，请刷新审核列表后重试。"
            : "当前状态不能执行这一步，请刷新审核列表后重试。",
        }, 409);
      }
      if (!changed.data) return reply(req, { error: "视频推荐不存在。" }, 404);
      const recommendations = await listVideoRecommendations(null, true);
      return reply(req, { recommendation: recommendations.find((item) => item.id === recommendationId) || null });
    }
    if (action === "save_observation") {
      const o = bodyData;
      if (!o.studentId || !o.courseDate || !o.taughtContent || !o.observedEvidence) return reply(req, { error: "课堂记录信息不完整。" }, 400);
      const { data, error } = await admin.from("chem_teacher_observations").insert({
        student_id: o.studentId, course_date: o.courseDate, taught_content: o.taughtContent,
        observed_evidence: o.observedEvidence, internal_note: o.internalNote || "",
        student_message: o.studentMessage || "", guardian_message: o.guardianMessage || "",
        visibility: "internal",
      }).select().single();
      if (error) throw error;
      return reply(req, { observation: { id: data.id, studentId: data.student_id, courseDate: data.course_date, taughtContent: data.taught_content, observedEvidence: data.observed_evidence, internalNote: data.internal_note, studentMessage: data.student_message, guardianMessage: data.guardian_message, visibility: data.visibility } });
    }
    if (action === "reset_access_codes") {
      const studentId = String(bodyData.studentId || "");
      const { data: student } = await admin.from("chem_students_v2").select("id").eq("id", studentId).maybeSingle();
      if (!student) return reply(req, { error: "学生不存在。" }, 404);
      const studentCode = code(); let guardianCode = code();
      while (studentCode === guardianCode) guardianCode = code();
      const first = await admin.rpc("chem_rotate_access_code", { p_student_id: studentId, p_role: "student", p_code: studentCode });
      const second = await admin.rpc("chem_rotate_access_code", { p_student_id: studentId, p_role: "guardian", p_code: guardianCode });
      if (first.error || second.error) throw first.error || second.error;
      return reply(req, { studentCode, guardianCode });
    }
    if (action === "list_questions") {
      const gradeBand = bodyData.gradeBand ? String(bodyData.gradeBand) : null;
      const reviewStatus = bodyData.reviewStatus ? String(bodyData.reviewStatus) : null;
      const sourceKind = bodyData.sourceKind ? String(bodyData.sourceKind) : null;
      const page = Math.max(1, Number(bodyData.page) || 1);
      const pageSize = Math.min(50, Math.max(5, Number(bodyData.pageSize) || 20));
      if (gradeBand && !["初三", "高一", "高二", "高三"].includes(gradeBand)) return reply(req, { error: "年级筛选无效。" }, 400);
      if (reviewStatus && !["draft", "needs_review", "approved", "retired"].includes(reviewStatus)) return reply(req, { error: "审核状态筛选无效。" }, 400);
      if (sourceKind && !allowedQuestionSourceKinds.has(sourceKind)) return reply(req, { error: "题目来源筛选无效。" }, 400);
      let query = admin.from("chem_questions").select(
        "id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,explanation,scaffold,review_status,scope_status,source_kind,source_info,asset_refs,render_mode,content_fingerprint,source_release_id,usable_for_review,textbook_version,knowledge_id,same_type_key,source_item_key,parent_source_item_key,updated_at",
        { count: "exact" },
      );
      if (gradeBand) query = query.eq("grade_band", gradeBand);
      if (reviewStatus) query = query.eq("review_status", reviewStatus);
      if (sourceKind) query = query.eq("source_kind", sourceKind);
      const start = (page - 1) * pageSize;
      const { data, error, count } = await query
        .order("updated_at", { ascending: false })
        .order("id")
        .range(start, start + pageSize - 1);
      if (error) throw error;
      return reply(req, { questions: data || [], page, pageSize, total: count || 0 });
    }
    if (action === "review_question") {
      const id = String(bodyData.id || "");
      const reviewStatus = String(bodyData.reviewStatus || "");
      if (!["approved", "retired", "needs_review"].includes(reviewStatus)) return reply(req, { error: "审核状态无效。" }, 400);
      const questionResult = await admin.from("chem_questions").select(
        "id,grade_band,options,correct_option,scope_status,source_kind,source_info,asset_refs,render_mode,source_item_key,content_fingerprint,source_release_id",
      ).eq("id", id).maybeSingle();
      if (questionResult.error) throw questionResult.error;
      if (!questionResult.data) return reply(req, { error: "题目不存在。" }, 404);
      const question = questionResult.data as Record<string, unknown>;
      if (question.source_release_id) {
        return reply(req, {
          error: "这是完整原题版本中的题目，不能单题修改。请校对并发布一个完整的新版本。",
        }, 409);
      }
      if (reviewStatus === "approved" && question.grade_band === "初三"
        && ["licensed_local", JUNIOR_SOURCE_KIND].includes(String(question.source_kind))) {
        return reply(req, {
          error: "初三原题必须连同教材版本、知识点来源和整套发布清单一起审核，不能单题批准。",
        }, 409);
      }
      if (reviewStatus === "approved" && question.source_kind === "licensed_local") {
        const source = question.source_info as Record<string, unknown> | null;
        const refs = Array.isArray(question.asset_refs) ? question.asset_refs as Array<Record<string, unknown>> : [];
        const options = Array.isArray(question.options) ? question.options : [];
        const requiredSource = ["title", "exam", "questionNo", "locator"].every((key) => String(source?.[key] || "").trim());
        if (
          question.grade_band !== "高三"
          || question.scope_status !== "IN"
          || !requiredSource
          || !["native", "image_assist", "image_primary"].includes(String(question.render_mode))
          || (question.render_mode !== "native" && refs.length === 0)
          || options.length !== 4
          || !Number.isInteger(Number(question.correct_option))
          || Number(question.correct_option) < 0
          || Number(question.correct_option) >= options.length
          || String(question.source_item_key || "").length < 16
          || !/^[0-9a-f]{64}$/.test(String(question.content_fingerprint || ""))
        ) return reply(req, { error: "原题的题面、答案、福建范围、来源或图片信息还不完整，不能批准。" }, 409);
        const paths = refs.map((asset) => String(asset.path || "")).filter(Boolean);
        const assets = await admin.rpc("chem_get_question_assets", { p_asset_paths: paths });
        if (assets.error) throw assets.error;
        const assetByPath = new Map(((assets.data || []) as Array<Record<string, unknown>>).map((asset) => [String(asset.asset_path), asset]));
        const assetMismatch = refs.some((ref) => {
          const asset = assetByPath.get(String(ref.path || ""));
          return !asset
            || String(asset.question_id) !== String(question.id)
            || String(asset.sha256) !== String(ref.sha256 || "")
            || Number(asset.width) !== Number(ref.width)
            || Number(asset.height) !== Number(ref.height);
        });
        if (assetMismatch || assetByPath.size !== new Set(paths).size) {
          return reply(req, { error: "原题图片缺失或哈希不一致，不能批准。" }, 409);
        }
      }
      const updates: Record<string, unknown> = { review_status: reviewStatus };
      if (reviewStatus !== "approved") updates.usable_for_review = false;
      const { error } = await admin.from("chem_questions").update(updates).eq("id", id);
      if (error) throw error;
      return reply(req, { ok: true });
    }
    if (action === "list_course_nodes") {
      const { data, error } = await admin.from("chem_course_nodes").select("*").order("grade_band").order("sequence");
      if (error) throw error;
      return reply(req, { nodes: data });
    }
    if (action === "approve_course_node") {
      const { error } = await admin.from("chem_course_nodes").update({ teacher_approved: Boolean(bodyData.approved) }).eq("id", bodyData.id);
      if (error) throw error;
      return reply(req, { ok: true });
    }
    return reply(req, { error: "未知操作。" }, 400);
  } catch (error) {
    console.error(error);
    return reply(req, { error: "教师服务暂时不可用。" }, 500);
  }
});
