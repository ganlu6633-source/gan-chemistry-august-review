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

async function teacher(req: Request) {
  const token = req.headers.get("x-app-session");
  if (!token) return null;
  const { data, error } = await admin.rpc("chem_resolve_app_session", { p_token_hash: await sha256(token) });
  if (error || !data?.length || data[0].access_role !== "teacher") return null;
  return { displayName: data[0].principal_name || "甘老师" };
}

async function readOnlyStudentPreview(req: Request, action: "student_preview_dashboard" | "preview_start_plan", data: unknown) {
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
  return { start: start.toISOString(), end: new Date(start.getTime() + 86400000).toISOString() };
}

async function dashboard() {
  const [students, alerts, report, courseCount, questionCount, guardians, fourWeekPlans, quizStudents, quizLinks] = await Promise.all([
    admin.from("chem_students_v2").select("id,display_name,grade_band,record_status,needs_initial_diagnostic,metadata").order("grade_band").order("display_name"),
    admin.from("chem_teacher_alerts").select("id,student_id,severity,title,reason").is("resolved_at", null).order("created_at", { ascending: false }).limit(20),
    admin.from("chem_daily_reports").select("*").order("report_date", { ascending: false }).limit(1).maybeSingle(),
    admin.from("chem_course_nodes").select("id", { count: "exact", head: true }).eq("teacher_approved", false),
    admin.from("chem_questions").select("id", { count: "exact", head: true }).in("review_status", ["draft", "needs_review"]),
    admin.rpc("chem_list_guardian_contacts"),
    admin.from("chem_learning_plans").select("student_id").gte("plan_date", "2026-08-13").lte("plan_date", "2026-09-09"),
    admin.from("students").select("id,display_name").eq("active", true).order("display_name"),
    admin.from("chem_quiz_student_links").select("quiz_student_id,chem_student_id"),
  ]);
  for (const result of [students, alerts, report, courseCount, questionCount, guardians, fourWeekPlans, quizStudents, quizLinks]) if (result.error) throw result.error;
  const dayRange = shanghaiDayRange();
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
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: headers(req) });
  if (req.method !== "POST") return reply(req, { error: "仅支持 POST 请求。" }, 405);
  try {
    const user = await teacher(req);
    if (!user) return reply(req, { error: "登录已失效，请重新输入姓名和登录码。" }, 401);
    const body = await req.json();
    if (body.action === "teacher_dashboard") return reply(req, { dashboard: await dashboard() });
    if (body.action === "student_preview_dashboard" || body.action === "preview_start_plan") {
      const preview = await readOnlyStudentPreview(req, body.action, body.data);
      return reply(req, preview.payload, preview.status);
    }
    if (body.action === "save_observation") {
      const o = body.data || {};
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
    if (body.action === "reset_access_codes") {
      const studentId = String(body.data?.studentId || "");
      const { data: student } = await admin.from("chem_students_v2").select("id").eq("id", studentId).maybeSingle();
      if (!student) return reply(req, { error: "学生不存在。" }, 404);
      const studentCode = code(); let guardianCode = code();
      while (studentCode === guardianCode) guardianCode = code();
      const first = await admin.rpc("chem_rotate_access_code", { p_student_id: studentId, p_role: "student", p_code: studentCode });
      const second = await admin.rpc("chem_rotate_access_code", { p_student_id: studentId, p_role: "guardian", p_code: guardianCode });
      if (first.error || second.error) throw first.error || second.error;
      return reply(req, { studentCode, guardianCode });
    }
    if (body.action === "list_questions") {
      const { data, error } = await admin.from("chem_questions").select("id,mother_id,skill_id,level,stem,review_status,scope_status").order("updated_at", { ascending: false }).limit(100);
      if (error) throw error;
      return reply(req, { questions: data });
    }
    if (body.action === "review_question") {
      const { id, reviewStatus } = body.data || {};
      if (!["approved", "retired", "needs_review"].includes(reviewStatus)) return reply(req, { error: "审核状态无效。" }, 400);
      const { error } = await admin.from("chem_questions").update({ review_status: reviewStatus }).eq("id", id);
      if (error) throw error;
      return reply(req, { ok: true });
    }
    if (body.action === "list_course_nodes") {
      const { data, error } = await admin.from("chem_course_nodes").select("*").order("grade_band").order("sequence");
      if (error) throw error;
      return reply(req, { nodes: data });
    }
    if (body.action === "approve_course_node") {
      const { error } = await admin.from("chem_course_nodes").update({ teacher_approved: Boolean(body.data?.approved) }).eq("id", body.data?.id);
      if (error) throw error;
      return reply(req, { ok: true });
    }
    return reply(req, { error: "未知操作。" }, 400);
  } catch (error) {
    console.error(error);
    return reply(req, { error: "教师服务暂时不可用。" }, 500);
  }
});
