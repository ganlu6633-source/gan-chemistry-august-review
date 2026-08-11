import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL")!;
const publishable = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
const allowedOrigins = new Set(["https://ganlu6633-source.github.io", "http://localhost:4173", "http://localhost:5173"]);
function headers(req: Request) {
  const origin = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://ganlu6633-source.github.io",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "Vary": "Origin",
  };
}
const reply = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: headers(req) });
function code() { return Array.from(crypto.getRandomValues(new Uint32Array(8)), (n) => String(n % 10)).join(""); }

async function teacher(req: Request) {
  const authorization = req.headers.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) return null;
  const client = createClient(url, publishable, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const { data, error } = await client.auth.getUser(authorization.slice(7));
  if (error || !data.user?.email) return null;
  const allowed = await admin.rpc("chem_teacher_is_allowed", { p_email: data.user.email });
  if (allowed.error || allowed.data !== true) return null;
  return data.user;
}

async function dashboard() {
  const [students, alerts, report, courseCount, questionCount] = await Promise.all([
    admin.from("chem_students_v2").select("id,display_name,grade_band,record_status,needs_initial_diagnostic").order("grade_band").order("display_name"),
    admin.from("chem_teacher_alerts").select("id,student_id,severity,title,reason").is("resolved_at", null).order("created_at", { ascending: false }).limit(20),
    admin.from("chem_daily_reports").select("*").order("report_date", { ascending: false }).limit(1).maybeSingle(),
    admin.from("chem_course_nodes").select("id", { count: "exact", head: true }).eq("teacher_approved", false),
    admin.from("chem_questions").select("id", { count: "exact", head: true }).in("review_status", ["draft", "needs_review"]),
  ]);
  for (const result of [students, alerts, courseCount, questionCount]) if (result.error) throw result.error;
  return {
    students: (students.data || []).map((s) => ({ id: s.id, displayName: s.display_name, gradeBand: s.grade_band, status: s.record_status, needsInitialDiagnostic: s.needs_initial_diagnostic })),
    alerts: (alerts.data || []).map((a) => ({ id: a.id, studentId: a.student_id, severity: a.severity, title: a.title, reason: a.reason })),
    dailySummary: { generatedAt: report.data?.generated_at || null, classQuizCount: report.data?.class_quiz_count || 0, reviewCount: report.data?.review_count || 0, interventionCount: report.data?.intervention_count || 0 },
    pendingCourseNodes: courseCount.count || 0, pendingQuestions: questionCount.count || 0,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: headers(req) });
  if (req.method !== "POST") return reply(req, { error: "仅支持 POST 请求。" }, 405);
  try {
    const user = await teacher(req);
    if (!user) return reply(req, { error: "教师身份未获授权。" }, 403);
    const body = await req.json();
    if (body.action === "teacher_dashboard") return reply(req, { dashboard: await dashboard() });
    if (body.action === "save_observation") {
      const o = body.data || {};
      if (!o.studentId || !o.courseDate || !o.taughtContent || !o.observedEvidence) return reply(req, { error: "课堂记录信息不完整。" }, 400);
      const { data, error } = await admin.from("chem_teacher_observations").insert({
        student_id: o.studentId, course_date: o.courseDate, taught_content: o.taughtContent,
        observed_evidence: o.observedEvidence, internal_note: o.internalNote || "",
        student_message: o.studentMessage || "", guardian_message: o.guardianMessage || "",
        visibility: "internal", created_by: user.id,
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
