create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create table if not exists public.chem_students_v2 (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  grade_band text not null check (grade_band in ('初三','高一','高二','高三')),
  record_status text not null default 'active' check (record_status in ('active','legacy','pending')),
  enrollment_start_date date not null default current_date,
  school_class text,
  textbook_version text not null default '待确认' check (textbook_version in ('苏教版','人教版','通用','待确认')),
  needs_initial_diagnostic boolean not null default true,
  missing_fields text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chem_student_aliases (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  alias text not null,
  unique(student_id, alias)
);

create table if not exists public.chem_student_sources (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  source_type text not null check (source_type in ('teacher_note','quiz_report','course_record','legacy_import')),
  observed_at timestamptz,
  summary text not null,
  evidence_status text not null check (evidence_status in ('confirmed','conflict','missing','unknown')),
  source_ref text,
  created_at timestamptz not null default now()
);

create table if not exists public.chem_student_conflicts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  field_name text not null,
  conflicting_values jsonb not null,
  resolution text not null default 'unresolved' check (resolution in ('teacher_confirmation_required','newest_verified_source','unresolved')),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.chem_skills (
  id text primary key,
  title text not null,
  module_id text not null,
  grade_band text not null check (grade_band in ('初三','高一','高二','高三')),
  max_level smallint not null check (max_level between 1 and 8),
  exam_importance smallint not null check (exam_importance between 1 and 5),
  exam_depth smallint not null check (exam_depth between 1 and 5),
  prerequisites text[] not null default '{}',
  level_criteria jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chem_student_skill_state (
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  skill_id text not null references public.chem_skills(id) on delete cascade,
  verified_level smallint not null default 0,
  candidate_level smallint,
  stability text not null default 'unknown' check (stability in ('unknown','learning','verified','stable','forgotten','recovered')),
  consecutive_errors integer not null default 0,
  next_review_at timestamptz,
  review_interval_index smallint not null default 0,
  last_reviewed_at timestamptz,
  teacher_intervention boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(student_id, skill_id)
);

create table if not exists public.chem_knowledge_cards (
  id text primary key,
  skill_id text not null references public.chem_skills(id) on delete cascade,
  title text not null,
  core text not null,
  detail text not null,
  steps jsonb not null default '[]'::jsonb,
  common_mistakes jsonb not null default '[]'::jsonb,
  micro_example text not null,
  asset jsonb,
  review_status text not null default 'approved' check (review_status in ('draft','needs_review','approved','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chem_course_nodes (
  id text primary key,
  grade_band text not null check (grade_band in ('初三','高一','高二','高三')),
  textbook_version text not null,
  chapter text not null,
  title text not null,
  skill_ids text[] not null default '{}',
  prerequisite_skill_ids text[] not null default '{}',
  sequence integer not null,
  teacher_approved boolean not null default false,
  unique(grade_band, textbook_version, sequence)
);

create table if not exists public.chem_questions (
  id text primary key,
  mother_id text not null,
  skill_id text not null references public.chem_skills(id) on delete restrict,
  level smallint not null check (level between 1 and 8),
  grade_band text not null check (grade_band in ('初三','高一','高二','高三')),
  stem text not null,
  options jsonb not null,
  correct_option smallint not null,
  explanation text not null,
  scaffold text,
  review_status text not null default 'needs_review' check (review_status in ('draft','needs_review','approved','retired')),
  scope_status text not null check (scope_status in ('IN','CTX-IN','POSTPONE','OUT')),
  source_kind text not null check (source_kind in ('teacher_original','licensed_local','original_variant')),
  image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(mother_id, id)
);

create table if not exists public.chem_learning_plans (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  plan_date date not null,
  mode text not null check (mode in ('REVIEW','CLASS_QUIZ','EXAM_SPRINT')),
  title text not null,
  skill_ids text[] not null default '{}',
  estimated_minutes smallint not null check (estimated_minutes between 1 and 60),
  source text not null check (source in ('course','exam','memory','mastery','mixed')),
  is_scheduled boolean not null default true,
  created_at timestamptz not null default now(),
  unique(student_id, plan_date, mode, title)
);

create table if not exists public.chem_learning_attempts (
  id uuid primary key,
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  plan_day_id uuid not null references public.chem_learning_plans(id) on delete cascade,
  attempt_kind text not null check (attempt_kind in ('scheduled','review')),
  sequence integer not null default 0,
  mode text not null check (mode in ('REVIEW','CLASS_QUIZ','EXAM_SPRINT')),
  started_at timestamptz not null,
  completed_at timestamptz not null,
  first_score integer not null default 0,
  created_at timestamptz not null default now(),
  unique(plan_day_id, attempt_kind, sequence)
);

create table if not exists public.chem_attempt_answers (
  id bigint generated always as identity primary key,
  attempt_id uuid not null references public.chem_learning_attempts(id) on delete cascade,
  question_id text not null references public.chem_questions(id) on delete restrict,
  mother_id text not null,
  skill_id text not null references public.chem_skills(id) on delete restrict,
  level smallint not null,
  correct boolean not null,
  uncertain boolean not null default false,
  duration_sec integer not null default 0 check (duration_sec >= 0),
  selected_option smallint not null,
  created_at timestamptz not null default now(),
  unique(attempt_id, question_id)
);

create table if not exists public.chem_teacher_observations (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  course_date date not null,
  taught_content text not null,
  observed_evidence text not null,
  internal_note text not null,
  student_message text not null,
  guardian_message text not null,
  visibility text not null default 'internal' check (visibility in ('student','guardian','teacher','internal')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.chem_behavior_signals (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  kind text not null check (kind in ('pace_fast','pace_slow','unstable','uncertain','guessing')),
  evidence_count integer not null check (evidence_count >= 3),
  session_count integer not null check (session_count >= 3),
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  guardian_copy text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.chem_teacher_alerts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  severity text not null check (severity in ('info','attention','urgent')),
  title text not null,
  reason text not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.chem_daily_reports (
  report_date date primary key,
  generated_at timestamptz not null default now(),
  class_quiz_count integer not null default 0,
  review_count integer not null default 0,
  intervention_count integer not null default 0,
  payload jsonb not null default '{}'::jsonb
);

create table if not exists public.chem_import_audit (
  id uuid primary key default gen_random_uuid(),
  import_kind text not null,
  source_ref text not null,
  record_count integer not null,
  checksum text not null,
  notes text,
  imported_at timestamptz not null default now()
);

create table if not exists app_private.chem_access_codes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  role text not null check (role in ('student','guardian')),
  code_hash text not null,
  active boolean not null default true,
  failed_count integer not null default 0,
  locked_until timestamptz,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  rotated_at timestamptz not null default now(),
  unique(student_id, role)
);

create table if not exists app_private.chem_app_sessions (
  id uuid primary key default gen_random_uuid(),
  access_code_id uuid not null references app_private.chem_access_codes(id) on delete cascade,
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  role text not null check (role in ('student','guardian')),
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table if not exists app_private.chem_login_attempts (
  id bigint generated always as identity primary key,
  fingerprint_hash text not null,
  succeeded boolean not null,
  attempted_at timestamptz not null default now()
);

create table if not exists app_private.chem_teacher_allowlist (
  email text primary key,
  active boolean not null default true,
  added_at timestamptz not null default now()
);

create index if not exists chem_learning_plans_student_date_idx on public.chem_learning_plans(student_id, plan_date);
create index if not exists chem_attempts_student_completed_idx on public.chem_learning_attempts(student_id, completed_at desc);
create index if not exists chem_answers_skill_idx on public.chem_attempt_answers(skill_id, created_at desc);
create index if not exists chem_observations_student_date_idx on public.chem_teacher_observations(student_id, course_date desc);
create index if not exists chem_signals_student_active_idx on public.chem_behavior_signals(student_id) where active;
create index if not exists chem_alerts_open_idx on public.chem_teacher_alerts(student_id) where resolved_at is null;
create index if not exists chem_sessions_token_idx on app_private.chem_app_sessions(token_hash) where revoked_at is null;
create index if not exists chem_login_attempts_fingerprint_idx on app_private.chem_login_attempts(fingerprint_hash, attempted_at desc);

do $$
declare t text;
begin
  foreach t in array array[
    'chem_students_v2','chem_student_aliases','chem_student_sources','chem_student_conflicts',
    'chem_skills','chem_student_skill_state','chem_knowledge_cards','chem_course_nodes','chem_questions',
    'chem_learning_plans','chem_learning_attempts','chem_attempt_answers','chem_teacher_observations',
    'chem_behavior_signals','chem_teacher_alerts','chem_daily_reports','chem_import_audit'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;

create or replace function app_private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists chem_students_v2_touch on public.chem_students_v2;
create trigger chem_students_v2_touch before update on public.chem_students_v2
for each row execute function app_private.touch_updated_at();
drop trigger if exists chem_skills_touch on public.chem_skills;
create trigger chem_skills_touch before update on public.chem_skills
for each row execute function app_private.touch_updated_at();
drop trigger if exists chem_cards_touch on public.chem_knowledge_cards;
create trigger chem_cards_touch before update on public.chem_knowledge_cards
for each row execute function app_private.touch_updated_at();
drop trigger if exists chem_questions_touch on public.chem_questions;
create trigger chem_questions_touch before update on public.chem_questions
for each row execute function app_private.touch_updated_at();

create or replace function app_private.generate_daily_report(target_date date default ((now() at time zone 'Asia/Shanghai')::date - 1))
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.chem_daily_reports(report_date, generated_at, class_quiz_count, review_count, intervention_count, payload)
  select target_date, now(),
    count(*) filter (where a.mode = 'CLASS_QUIZ'),
    count(*) filter (where a.mode = 'REVIEW'),
    (select count(*) from public.chem_student_skill_state s where s.teacher_intervention),
    jsonb_build_object('completed_attempts', count(*), 'timeZone', 'Asia/Shanghai')
  from public.chem_learning_attempts a
  where (a.completed_at at time zone 'Asia/Shanghai')::date = target_date
  on conflict (report_date) do update set
    generated_at = excluded.generated_at,
    class_quiz_count = excluded.class_quiz_count,
    review_count = excluded.review_count,
    intervention_count = excluded.intervention_count,
    payload = excluded.payload;
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'chemistry-daily-report-v2') then
    perform cron.unschedule('chemistry-daily-report-v2');
  end if;
  perform cron.schedule('chemistry-daily-report-v2', '0 17 * * *', $job$select app_private.generate_daily_report();$job$);
end $$;

insert into public.chem_skills(id,title,module_id,grade_band,max_level,exam_importance,exam_depth,prerequisites,level_criteria)
values
('J09_ATOM','原子结构与元素','J09','初三',4,4,3,'{}','[{"level":1,"studentFacingGoal":"能区分原子、分子和离子","requiredAbility":"识别微粒"},{"level":2,"studentFacingGoal":"能读懂原子结构示意图","requiredAbility":"结构判断"}]'),
('H1_PERIODIC','元素周期律','H1-F02','高一',6,5,5,'{}','[{"level":1,"studentFacingGoal":"能看懂周期表位置","requiredAbility":"定位"},{"level":2,"studentFacingGoal":"能由结构判断位置","requiredAbility":"结构与位置"},{"level":3,"studentFacingGoal":"能比较性质递变","requiredAbility":"规律迁移"}]'),
('H1_REDOX','氧化还原反应','H1-F03','高一',7,5,5,'{}','[{"level":1,"studentFacingGoal":"能标化合价","requiredAbility":"化合价"},{"level":2,"studentFacingGoal":"能判断氧化还原","requiredAbility":"概念判断"},{"level":3,"studentFacingGoal":"能配平基础方程式","requiredAbility":"守恒"}]'),
('H1_ELECTROLYTE','电解质与离子反应','H1-F04','高一',7,5,5,'{}','[{"level":1,"studentFacingGoal":"能判断电解质","requiredAbility":"概念边界"},{"level":2,"studentFacingGoal":"能正确拆写","requiredAbility":"拆写规则"},{"level":3,"studentFacingGoal":"能判断离子共存","requiredAbility":"反应条件"}]'),
('H1_MOLE','物质的量','H1-F05','高一',7,5,5,'{}','[{"level":1,"studentFacingGoal":"能理解宏观量与微粒数","requiredAbility":"量纲理解"},{"level":2,"studentFacingGoal":"能完成基本换算","requiredAbility":"关系式"}]'),
('H1_NACL','钠和氯','H1-F06','高一',6,5,4,array['H1_REDOX','H1_ELECTROLYTE','H1_MOLE'],'[{"level":1,"studentFacingGoal":"能说出典型性质","requiredAbility":"事实与现象"},{"level":2,"studentFacingGoal":"能写核心反应","requiredAbility":"方程式"}]'),
('H2_RATE','化学反应速率与限度','H2-E01','高二',7,5,5,array['H1_MOLE'],'[{"level":1,"studentFacingGoal":"能判断速率变化","requiredAbility":"变量识别"},{"level":2,"studentFacingGoal":"能解释影响因素","requiredAbility":"模型解释"}]'),
('H3_EQUILIBRIUM','化学平衡综合','H3-E02','高三',8,5,5,array['H2_RATE'],'[{"level":1,"studentFacingGoal":"能识别平衡状态","requiredAbility":"特征判断"},{"level":2,"studentFacingGoal":"能判断移动方向","requiredAbility":"条件与响应"}]')
on conflict (id) do update set title=excluded.title,module_id=excluded.module_id,grade_band=excluded.grade_band,max_level=excluded.max_level,exam_importance=excluded.exam_importance,exam_depth=excluded.exam_depth,prerequisites=excluded.prerequisites,level_criteria=excluded.level_criteria,updated_at=now();

insert into public.chem_knowledge_cards(id,skill_id,title,core,detail,steps,common_mistakes,micro_example,review_status)
values
('CARD_PERIODIC_01','H1_PERIODIC','周期律：先结构，再位置，再性质','最外层电子数决定主族元素的主要化学倾向。','同周期核电荷递增而电子层数不变；同主族最外层电子数相同而电子层数递增。','["写核外电子排布","定位周期和主族","沿周期或主族比较"]','["只背结论不看比较方向","把原子半径与离子半径混为一谈"]','比较 Na、Mg 的原子半径：同周期从左到右减小，所以 Na 大于 Mg。','approved'),
('CARD_REDOX_01','H1_REDOX','氧化还原：电子转移是主线','化合价升高失电子，被氧化；化合价降低得电子，被还原。','先找变价元素，再建立升失氧、降得还的对应关系，最后用电子守恒检查。','["标出反应前后化合价","确定升降与电子数","用守恒校验"]','["把氧化剂与被氧化物混淆","只看是否有氧元素"]','Fe + Cu²⁺ → Fe²⁺ + Cu：Fe 是还原剂，Cu²⁺ 是氧化剂。','approved'),
('CARD_ION_01','H1_ELECTROLYTE','离子方程式：四步不断线','写、拆、删、查；每一步都要守恒。','强酸、强碱和可溶盐拆成离子，单质、氧化物、弱电解质、沉淀和气体保留化学式。','["写分子方程式","正确拆写","删相同离子","查原子、电荷和条件"]','["把弱酸拆开","漏掉电荷守恒"]','HCl + NaOH → NaCl + H₂O 的净离子式为 H⁺ + OH⁻ → H₂O。','approved')
on conflict (id) do update set title=excluded.title,core=excluded.core,detail=excluded.detail,steps=excluded.steps,common_mistakes=excluded.common_mistakes,micro_example=excluded.micro_example,review_status=excluded.review_status,updated_at=now();

insert into public.chem_questions(id,mother_id,skill_id,level,grade_band,stem,options,correct_option,explanation,scaffold,review_status,scope_status,source_kind)
values
('Q_PERIODIC_A','M_PERIODIC_POS','H1_PERIODIC',1,'高一','某主族元素原子有三个电子层，最外层有1个电子。它位于哪一位置？','["第二周期ⅠA族","第三周期ⅠA族","第三周期ⅡA族","第四周期ⅠA族"]',1,'电子层数对应周期数，最外层电子数1对应ⅠA族。','先数电子层，再看最外层电子数。','approved','IN','teacher_original'),
('Q_PERIODIC_B','M_PERIODIC_RADIUS','H1_PERIODIC',2,'高一','同周期主族元素从左到右，原子半径总体如何变化？','["逐渐增大","逐渐减小","保持不变","先减小后增大"]',1,'核电荷递增而电子层数相同，有效核吸引增强，半径总体减小。',null,'approved','IN','original_variant'),
('Q_REDOX_A','M_REDOX_ROLE','H1_REDOX',1,'高一','反应 Fe + CuSO₄ → FeSO₄ + Cu 中，作氧化剂的是？','["Fe","Cu²⁺","SO₄²⁻","Fe²⁺"]',1,'Cu²⁺得电子生成Cu，化合价降低，是氧化剂。','找化合价降低的微粒。','approved','IN','teacher_original'),
('Q_REDOX_B','M_REDOX_ESSENCE','H1_REDOX',2,'高一','判断一个反应是否为氧化还原反应的本质依据是？','["是否有氧参加","是否有单质生成","是否有电子转移","是否放热"]',2,'氧化还原反应的本质是电子转移，表征为元素化合价变化。',null,'approved','IN','original_variant'),
('Q_ION_A','M_ION_WRITE','H1_ELECTROLYTE',2,'高一','稀盐酸与氢氧化钠溶液反应的离子方程式是？','["H⁺+OH⁻→H₂O","HCl+OH⁻→Cl⁻+H₂O","Na⁺+Cl⁻→NaCl","2H⁺+2OH⁻→2H₂O"]',0,'强酸强碱完全电离，旁观离子删去后得到 H⁺+OH⁻→H₂O。','按写、拆、删、查完成。','approved','IN','teacher_original'),
('Q_MOLE_A','M_MOLE_PARTICLE','H1_MOLE',1,'高一','1 mol 任意微粒所含微粒数约为？','["6.02×10²³","3.01×10²³","22.4","1"]',0,'1 mol 微粒含阿伏加德罗常数个微粒，约6.02×10²³。',null,'approved','IN','teacher_original')
on conflict (id) do update set stem=excluded.stem,options=excluded.options,correct_option=excluded.correct_option,explanation=excluded.explanation,scaffold=excluded.scaffold,review_status=excluded.review_status,scope_status=excluded.scope_status,updated_at=now();

insert into public.chem_course_nodes(id,grade_band,textbook_version,chapter,title,skill_ids,prerequisite_skill_ids,sequence,teacher_approved)
values
('SJ_H1_F02','高一','苏教版','专题1','元素周期律',array['H1_PERIODIC'],'{}',20,true),
('SJ_H1_F03','高一','苏教版','专题1','氧化还原反应',array['H1_REDOX'],'{}',30,true),
('SJ_H1_F04','高一','苏教版','专题1','电解质与离子方程式',array['H1_ELECTROLYTE'],'{}',40,true),
('SJ_H1_F05','高一','苏教版','专题1','物质的量基础',array['H1_MOLE'],'{}',50,true),
('SJ_H1_F06','高一','苏教版','专题2','钠和氯',array['H1_NACL'],array['H1_REDOX','H1_ELECTROLYTE','H1_MOLE'],60,true)
on conflict (id) do update set title=excluded.title,skill_ids=excluded.skill_ids,prerequisite_skill_ids=excluded.prerequisite_skill_ids,sequence=excluded.sequence,teacher_approved=excluded.teacher_approved;

-- A non-personal demo record keeps automated and acceptance testing independent from real students.
insert into public.chem_students_v2(id,display_name,grade_band,record_status,enrollment_start_date,textbook_version,needs_initial_diagnostic,metadata)
values('00000000-0000-4000-8000-000000000001','演示学生','高一','active',current_date,'苏教版',false,'{"demo":true}'::jsonb)
on conflict (id) do update set display_name=excluded.display_name,grade_band=excluded.grade_band,textbook_version=excluded.textbook_version,metadata=excluded.metadata;

insert into app_private.chem_access_codes(student_id,role,code_hash)
values
('00000000-0000-4000-8000-000000000001','student',crypt('11111111',gen_salt('bf',12))),
('00000000-0000-4000-8000-000000000001','guardian',crypt('22222222',gen_salt('bf',12)))
on conflict (student_id,role) do nothing;

insert into public.chem_student_skill_state(student_id,skill_id,verified_level,stability,next_review_at)
values
('00000000-0000-4000-8000-000000000001','H1_PERIODIC',2,'verified',now()),
('00000000-0000-4000-8000-000000000001','H1_REDOX',1,'learning',now()),
('00000000-0000-4000-8000-000000000001','H1_ELECTROLYTE',1,'learning',now() + interval '3 days')
on conflict (student_id,skill_id) do nothing;

insert into public.chem_learning_plans(student_id,plan_date,mode,title,skill_ids,estimated_minutes,source,is_scheduled)
select '00000000-0000-4000-8000-000000000001', current_date + delta, mode, title, skills, mins, source, true
from (values
  (0,'REVIEW','周期律规律回想',array['H1_PERIODIC'],7,'memory'),
  (1,'CLASS_QUIZ','氧化还原概念检验',array['H1_REDOX'],8,'course'),
  (3,'REVIEW','离子反应基础回收',array['H1_ELECTROLYTE'],8,'mixed'),
  (5,'REVIEW','物质的量关系式',array['H1_MOLE'],8,'course')
) as v(delta,mode,title,skills,mins,source)
on conflict (student_id,plan_date,mode,title) do nothing;

select app_private.generate_daily_report();
