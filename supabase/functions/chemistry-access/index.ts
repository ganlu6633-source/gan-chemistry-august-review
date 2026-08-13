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

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
const profileShape = (row: Record<string, unknown>) => ({
  id: row.id,
  displayName: row.display_name,
  gradeBand: row.grade_band,
  enrollmentStartDate: row.enrollment_start_date,
  needsInitialDiagnostic: row.needs_initial_diagnostic,
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
  return {
    id: row.id, studentId: row.student_id, date: row.plan_date, mode: row.mode, title: row.title,
    skillIds: row.skill_ids || [], knowledgeSummaries: row.knowledge_summaries || [],
    estimatedMinutes: row.estimated_minutes, source: row.source, isScheduled: row.is_scheduled,
    attemptCount: attempts.length, firstScore: first?.first_score ?? null,
    latestScore: latest?.first_score ?? null, latestCompletedAt: latest?.completed_at ?? null,
  };
};
const questionShape = (row: Record<string, unknown>) => ({
  id: row.id, motherId: row.mother_id, skillId: row.skill_id, level: row.level,
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

async function studentDashboard(studentId: string) {
  const profileResult = await supabase.from("chem_students_v2").select("*").eq("id", studentId).single();
  if (profileResult.error) throw profileResult.error;
  const [planResult, stateResult, skillResult, attemptResult] = await Promise.all([
    supabase.from("chem_learning_plans").select("*").eq("student_id", studentId).order("plan_date"),
    supabase.from("chem_student_skill_state").select("*,chem_skills(max_level)").eq("student_id", studentId),
    supabase.from("chem_skills").select("*").eq("active", true).eq("grade_band", profileResult.data.grade_band).order("module_id"),
    supabase.from("chem_learning_attempts").select("plan_day_id,attempt_kind,sequence,first_score,completed_at").eq("student_id", studentId).order("completed_at"),
  ]);
  for (const result of [planResult, stateResult, skillResult, attemptResult]) if (result.error) throw result.error;
  const states = (stateResult.data || []).map((r) => stateShape(r as never));
  const completed = states.filter((s) => ["verified", "stable", "recovered"].includes(String(s.stability))).length;
  return {
    profile: profileShape(profileResult.data),
    plans: (planResult.data || []).map((plan) => planShape(plan, attemptResult.data || [])),
    skillStates: states,
    skillDefinitions: (skillResult.data || []).map(skillShape),
    todayQuestionCount: 6,
    achievements: completed ? [{ id: "first-evidence", title: "证据点亮", description: `已经用真实作答点亮 ${completed} 项能力。`, earnedAt: new Date().toISOString() }] : [],
  };
}

async function guardianDashboard(studentId: string) {
  const weekStart = new Date(Date.now() - 7 * 86400000).toISOString();
  const linkResult = await supabase.from("chem_quiz_student_links").select("quiz_student_id").eq("chem_student_id", studentId).maybeSingle();
  if (linkResult.error) throw linkResult.error;
  const quizResult = linkResult.data?.quiz_student_id
    ? await supabase.from("quiz_sessions")
      .select("id,round,training_theme,correct_count,total_count,total_sec,wrong_tags,completed_at")
      .eq("student_id", linkResult.data.quiz_student_id)
      .gte("completed_at", weekStart)
      .order("completed_at", { ascending: false })
      .limit(50)
    : { data: [], error: null };
  if (quizResult.error) throw quizResult.error;
  const [profileResult, plansResult, attemptsResult, statesResult, signalsResult, observationsResult] = await Promise.all([
    supabase.from("chem_students_v2").select("display_name,grade_band").eq("id", studentId).single(),
    supabase.from("chem_learning_plans").select("id").eq("student_id", studentId).gte("plan_date", weekStart.slice(0, 10)),
    supabase.from("chem_learning_attempts").select("id,completed_at,mode,first_score").eq("student_id", studentId).gte("completed_at", weekStart).order("completed_at", { ascending: false }),
    supabase.from("chem_student_skill_state").select("stability,teacher_intervention").eq("student_id", studentId),
    supabase.from("chem_behavior_signals").select("*").eq("student_id", studentId).eq("active", true),
    supabase.from("chem_teacher_observations").select("id,course_date,taught_content,guardian_message,created_at").eq("student_id", studentId).order("course_date", { ascending: false }).limit(10),
  ]);
  if (profileResult.error) throw profileResult.error;
  const states = statesResult.data || [];
  const attempts = attemptsResult.data || [];
  const observations = observationsResult.data || [];
  const quizSessions = quizResult.data || [];
  const timeline = [
    ...attempts.map((a) => ({ id: a.id, at: a.completed_at, type: "attempt", title: a.mode === "CLASS_QUIZ" ? "完成课堂小测" : "完成一次复习", description: `本次首轮答对 ${a.first_score} 题。` })),
    ...quizSessions.map((q) => ({ id: `quiz-${q.id}`, at: q.completed_at, type: "attempt", title: `完成即时小测 · 第${q.round}轮`, description: parentQuizDescription(q) })),
    ...observations.map((o) => ({ id: o.id, at: o.created_at, type: "teacher_action", title: o.taught_content, description: o.guardian_message })),
  ].sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 20);
  return {
    student: { displayName: profileResult.data.display_name, gradeBand: profileResult.data.grade_band },
    weeklyCompleted: attempts.length, weeklyPlanned: (plansResult.data || []).length,
    weeklyQuizCompleted: quizSessions.length,
    stableSkillCount: states.filter((s) => ["verified", "stable", "recovered"].includes(s.stability)).length,
    growingSkillCount: states.filter((s) => s.stability === "learning").length,
    forgottenSkillCount: states.filter((s) => s.stability === "forgotten").length,
    teacherAttentionCount: states.filter((s) => s.teacher_intervention).length,
    progress: states.some((s) => ["verified", "stable", "recovered"].includes(s.stability)) ? ["已有能力通过不同题目形成证据。"] : ["系统正在收集第一批可靠证据。"],
    concerns: states.some((s) => s.teacher_intervention) ? ["有能力点已进入教师关注清单。"] : ["当前没有需要立即处理的异常。"],
    behaviorSignals: (signalsResult.data || []).map((s) => ({ kind: s.kind, evidenceCount: s.evidence_count, sessionCount: s.session_count, firstSeenAt: s.first_seen_at, lastSeenAt: s.last_seen_at, guardianCopy: s.guardian_copy })),
    timeline,
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

    const identity = await authenticate(req);
    if (!identity) return reply(req, { error: "登录已失效，请重新输入访问码。" }, 401);
    if (body.action === "student_dashboard" && identity.role === "student" && identity.studentId) return reply(req, { dashboard: await studentDashboard(identity.studentId) });
    if (body.action === "guardian_dashboard" && identity.role === "guardian" && identity.studentId) return reply(req, { dashboard: await guardianDashboard(identity.studentId) });

    if (body.action === "start_plan" && identity.role === "student" && identity.studentId) {
      const { data: plan, error: planError } = await supabase.from("chem_learning_plans").select("*").eq("id", body.data?.planId).eq("student_id", identity.studentId).single();
      if (planError) throw planError;
      const gradeResult = await supabase.from("chem_students_v2").select("grade_band").eq("id", identity.studentId).single();
      if (gradeResult.error) throw gradeResult.error;
      const [cards, questions, attemptCount, states, recentAttempts] = await Promise.all([
        supabase.from("chem_knowledge_cards").select("*").in("skill_id", plan.skill_ids).eq("review_status", "approved"),
        supabase.from("chem_questions").select("*").eq("grade_band", gradeResult.data.grade_band).in("skill_id", plan.skill_ids).eq("review_status", "approved").neq("scope_status", "OUT"),
        supabase.from("chem_learning_attempts").select("id", { count: "exact", head: true }).eq("plan_day_id", plan.id),
        supabase.from("chem_student_skill_state").select("skill_id,verified_level,consecutive_errors,next_review_at").eq("student_id", identity.studentId).in("skill_id", plan.skill_ids),
        supabase.from("chem_learning_attempts").select("id").eq("student_id", identity.studentId).order("completed_at", { ascending: false }).limit(30),
      ]);
      if (cards.error || questions.error || attemptCount.error || states.error || recentAttempts.error) throw cards.error || questions.error || attemptCount.error || states.error || recentAttempts.error;
      const attemptIds = (recentAttempts.data || []).map((attempt) => attempt.id);
      const history = attemptIds.length
        ? await supabase.from("chem_attempt_answers").select("question_id,correct").in("attempt_id", attemptIds).in("skill_id", plan.skill_ids)
        : { data: [], error: null };
      if (history.error) throw history.error;
      const adaptiveQuestions = selectAdaptiveQuestions(questions.data || [], states.data || [], history.data || [], attemptCount.count || 0, 7);
      const cardOrder = new Map((plan.skill_ids as string[]).map((skillId, index) => [skillId, index]));
      const orderedCards = [...(cards.data || [])].sort((a, b) => (cardOrder.get(a.skill_id) ?? 99) - (cardOrder.get(b.skill_id) ?? 99));
      return reply(req, { payload: { plan: planShape(plan), cards: orderedCards.map(cardShape), questions: adaptiveQuestions.map(questionShape), attemptSequence: attemptCount.count || 0 } });
    }

    if (body.action === "submit_attempt" && identity.role === "student" && identity.studentId) {
      const attempt = body.data;
      if (!attempt || attempt.studentId !== identity.studentId || !Array.isArray(attempt.answers) || attempt.answers.length > 10) return reply(req, { error: "提交内容不完整。" }, 400);
      const { error: attemptError } = await supabase.from("chem_learning_attempts").insert({
        id: attempt.id, student_id: identity.studentId, plan_day_id: attempt.planDayId,
        attempt_kind: attempt.attemptKind, sequence: attempt.sequence, mode: attempt.mode,
        started_at: attempt.startedAt, completed_at: attempt.completedAt, first_score: attempt.firstScore,
      });
      if (attemptError) throw attemptError;
      const answers = attempt.answers.map((a: Record<string, unknown>) => ({
        attempt_id: attempt.id, question_id: a.questionId, mother_id: a.motherId, skill_id: a.skillId,
        level: a.level, correct: a.correct, uncertain: a.uncertain, duration_sec: a.durationSec, selected_option: a.selectedOption,
      }));
      const { error: answersError } = await supabase.from("chem_attempt_answers").insert(answers);
      if (answersError) throw answersError;
      for (const answer of attempt.answers) {
        const { data: current } = await supabase.from("chem_student_skill_state").select("*").eq("student_id", identity.studentId).eq("skill_id", answer.skillId).maybeSingle();
        const verified = Math.max(Number(current?.verified_level || 0), answer.correct ? Number(answer.level || 0) : 0);
        await supabase.from("chem_student_skill_state").upsert({
          student_id: identity.studentId, skill_id: answer.skillId, verified_level: verified,
          candidate_level: answer.correct ? answer.level : current?.candidate_level,
          stability: answer.correct ? "verified" : "learning",
          consecutive_errors: answer.correct ? 0 : Number(current?.consecutive_errors || 0) + 1,
          next_review_at: new Date(Date.now() + (answer.correct ? 3 : 1) * 86400000).toISOString(),
          review_interval_index: answer.correct ? Math.min(4, Number(current?.review_interval_index || 0) + 1) : 0,
          last_reviewed_at: new Date().toISOString(), teacher_intervention: !answer.correct && Number(current?.consecutive_errors || 0) >= 2,
        });
      }
      return reply(req, { dashboard: await studentDashboard(identity.studentId), achievements: [] });
    }
    return reply(req, { error: "无权执行该操作。" }, 403);
  } catch (error) {
    console.error(error);
    return reply(req, { error: "服务暂时不可用，请稍后重试。" }, 500);
  }
});
