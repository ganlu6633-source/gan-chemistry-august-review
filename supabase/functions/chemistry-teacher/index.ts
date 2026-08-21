import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
const allowedOrigins = new Set(["https://ganlu6633-source.github.io", "http://localhost:4173", "http://localhost:5173"]);
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
    readinessEndDate: dateKey(13),
    start: start.toISOString(),
    end: new Date(start.getTime() + 86400000).toISOString(),
  };
}

async function dashboard() {
  const dayRange = shanghaiDayRange();
  const [students, alerts, report, courseCount, questionCount, guardians, fourWeekPlans, readinessPlans, quizStudents, quizLinks, videoRecommendations] = await Promise.all([
    admin.from("chem_students_v2").select("id,display_name,grade_band,record_status,needs_initial_diagnostic,metadata").order("grade_band").order("display_name"),
    admin.from("chem_teacher_alerts").select("id,student_id,severity,title,reason").is("resolved_at", null).order("created_at", { ascending: false }).limit(20),
    admin.from("chem_daily_reports").select("*").order("report_date", { ascending: false }).limit(1).maybeSingle(),
    admin.from("chem_course_nodes").select("id", { count: "exact", head: true }).eq("teacher_approved", false),
    admin.from("chem_questions").select("id", { count: "exact", head: true }).in("review_status", ["draft", "needs_review"]),
    admin.rpc("chem_list_guardian_contacts"),
    admin.from("chem_learning_plans").select("student_id").eq("mode", "REVIEW").gte("plan_date", "2026-08-17"),
    admin.from("chem_learning_plans")
      .select("student_id,plan_date,skill_ids,question_count,round_limit")
      .eq("mode", "REVIEW")
      .gte("plan_date", dayRange.date)
      .lte("plan_date", dayRange.readinessEndDate),
    admin.from("students").select("id,display_name").eq("active", true).order("display_name"),
    admin.from("chem_quiz_student_links").select("quiz_student_id,chem_student_id"),
    listVideoRecommendations(null, true),
  ]);
  for (const result of [students, alerts, report, courseCount, questionCount, guardians, fourWeekPlans, readinessPlans, quizStudents, quizLinks]) if (result.error) throw result.error;
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
  const activeFormalHighSchoolIds = new Set((students.data || []).flatMap((student) =>
    student.record_status === "active"
      && ["高一", "高二", "高三"].includes(String(student.grade_band))
      && student.metadata?.demo !== true
      ? [String(student.id)]
      : []));
  const readinessRows = (readinessPlans.data || []).filter((plan) => activeFormalHighSchoolIds.has(String(plan.student_id)));
  const plannedSkillIds = [...new Set(readinessRows.flatMap((plan) =>
    Array.isArray(plan.skill_ids) ? plan.skill_ids.map((skillId) => String(skillId)).filter(Boolean) : []))];
  const [readinessSkills, readinessQuestions] = plannedSkillIds.length
    ? await Promise.all([
      admin.from("chem_skills").select("id,title,grade_band").in("id", plannedSkillIds),
      admin.from("chem_questions")
        .select("skill_id,concept_key,source_item_key,mother_id,level")
        .in("skill_id", plannedSkillIds)
        .eq("review_status", "approved")
        .eq("scope_status", "IN")
        .eq("usable_for_review", true)
        .eq("source_kind", "licensed_local")
        .eq("render_mode", "image_primary")
        .limit(5000),
    ])
    : [{ data: [], error: null }, { data: [], error: null }];
  if (readinessSkills.error || readinessQuestions.error) throw readinessSkills.error || readinessQuestions.error;
  const skillInfo = new Map((readinessSkills.data || []).map((skill) => [String(skill.id), skill]));
  const conceptPools = new Map<string, Map<string, { sources: Set<string>; levels: Set<number> }>>();
  for (const question of readinessQuestions.data || []) {
    const skillId = String(question.skill_id || "");
    const conceptKey = String(question.concept_key || "");
    const sourceKey = String(question.source_item_key || question.mother_id || "");
    if (!skillId || !conceptKey || !sourceKey) continue;
    const byConcept = conceptPools.get(skillId) || new Map<string, { sources: Set<string>; levels: Set<number> }>();
    const pool = byConcept.get(conceptKey) || { sources: new Set<string>(), levels: new Set<number>() };
    pool.sources.add(sourceKey);
    if (Number.isFinite(Number(question.level))) pool.levels.add(Number(question.level));
    byConcept.set(conceptKey, pool);
    conceptPools.set(skillId, byConcept);
  }
  const plannedSkillStats = new Map<string, {
    students: Set<string>;
    dates: Set<string>;
    visitsByStudent: Map<string, number>;
    expectedConceptCount: number;
    roundLimit: number;
  }>();
  for (const plan of readinessRows) {
    const studentId = String(plan.student_id);
    const skillIds = Array.isArray(plan.skill_ids) ? plan.skill_ids.map((skillId) => String(skillId)).filter(Boolean) : [];
    for (const skillId of skillIds) {
      const stat = plannedSkillStats.get(skillId) || {
        students: new Set<string>(), dates: new Set<string>(), visitsByStudent: new Map<string, number>(),
        expectedConceptCount: 5, roundLimit: 5,
      };
      stat.students.add(studentId);
      stat.dates.add(String(plan.plan_date));
      stat.visitsByStudent.set(studentId, (stat.visitsByStudent.get(studentId) || 0) + 1);
      stat.expectedConceptCount = Math.max(stat.expectedConceptCount, Number(plan.question_count) || 5);
      stat.roundLimit = Math.max(stat.roundLimit, Number(plan.round_limit) || 5);
      plannedSkillStats.set(skillId, stat);
    }
  }
  const sourcePoolWarnings = [...plannedSkillStats.entries()].flatMap(([skillId, stat]) => {
    const pools = [...(conceptPools.get(skillId)?.values() || [])];
    const counts = pools.map((pool) => pool.sources.size);
    const difficultyLevelCounts = pools.map((pool) => pool.levels.size);
    const conceptCount = counts.length;
    const minimumQuestionsPerConcept = counts.length ? Math.min(...counts) : 0;
    const minimumDifficultyLevelsPerConcept = difficultyLevelCounts.length ? Math.min(...difficultyLevelCounts) : 0;
    const maxVisitsPerStudent = Math.max(0, ...stat.visitsByStudent.values());
    const requiredForFiveRounds = stat.roundLimit;
    const requiredForCrossDateNoRepeat = stat.roundLimit * maxVisitsPerStudent;
    const isBlocking = conceptCount !== stat.expectedConceptCount || minimumQuestionsPerConcept < requiredForFiveRounds;
    const lacksDifficultyProgression = conceptCount === stat.expectedConceptCount && minimumDifficultyLevelsPerConcept < 2;
    const lacksCrossDateCapacity = minimumQuestionsPerConcept < requiredForCrossDateNoRepeat;
    if (!isBlocking && !lacksDifficultyProgression && !lacksCrossDateCapacity) return [];
    const info = skillInfo.get(skillId);
    const skillTitle = String(info?.title || skillId);
    const gradeBand = String(info?.grade_band || "高一");
    return [{
      id: `${gradeBand}:${skillId}`,
      gradeBand,
      skillId,
      skillTitle,
      severity: isBlocking ? "blocking" : lacksDifficultyProgression ? "progression" : "capacity",
      plannedStudentCount: stat.students.size,
      plannedDateCount: stat.dates.size,
      maxVisitsPerStudent,
      conceptCount,
      expectedConceptCount: stat.expectedConceptCount,
      minimumQuestionsPerConcept,
      minimumDifficultyLevelsPerConcept,
      requiredForFiveRounds,
      requiredForCrossDateNoRepeat,
      message: isBlocking
        ? `未来14天计划会用到“${skillTitle}”，当前有${conceptCount}个细知识点（应为${stat.expectedConceptCount}个），每个细知识点最少${minimumQuestionsPerConcept}道原题（当天五轮至少${requiredForFiveRounds}道）。未补足前系统必须停止下发。`
        : lacksDifficultyProgression
        ? `“${skillTitle}”当前至少有一个细知识点的原题全部处在同一难度，答对后无法真正升级。请补充或重新核定该细点的基础题与提高题。`
        : `未来14天同一学生最多安排“${skillTitle}”${maxVisitsPerStudent}天；若跨日也完全不重复，每个细知识点需${requiredForCrossDateNoRepeat}道原题，当前最少${minimumQuestionsPerConcept}道，还差${Math.max(0, requiredForCrossDateNoRepeat - minimumQuestionsPerConcept)}道。`,
    }];
  }).sort((a, b) => {
    const rank = (value: string) => value === "blocking" ? 0 : value === "progression" ? 1 : 2;
    return rank(a.severity) === rank(b.severity)
      ? a.gradeBand.localeCompare(b.gradeBand)
      : rank(a.severity) - rank(b.severity);
  });
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
      if (sourceKind && !["teacher_original", "licensed_local", "original_variant"].includes(sourceKind)) return reply(req, { error: "题目来源筛选无效。" }, 400);
      let query = admin.from("chem_questions").select(
        "id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,explanation,scaffold,review_status,scope_status,source_kind,source_info,asset_refs,render_mode,content_fingerprint,source_release_id,usable_for_review,updated_at",
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
