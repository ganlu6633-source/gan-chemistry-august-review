-- Repair only the still-unstarted part of the 40-day high-school REVIEW calendar.
--
-- Invariants:
--   * 2026-08-20 and every earlier plan stay byte-for-byte unchanged.
--   * On 2026-08-21 only title and knowledge_summaries may change; the plan
--     id, selected skill, five-question start contract and attempts do not.
--   * Existing plan ids and every attempt/answer row stay unchanged.
--   * One day means one taught skill, five concepts and five source originals
--     per concept, which is the contract enforced by chemistry-access v17.
--   * Real answer evidence wins over profile notes.  Profile notes win over the
--     deterministic grade schedule.  No random assignment is used.
--   * The two current High-1 learners whose confirmed scope contains REDOX get
--     an honest REDOX-only plan every day, as requested by the teacher.

begin;

create temporary table _future_review_students (
  student_id uuid primary key,
  grade_band text not null,
  cohort text not null,
  demo boolean not null,
  profile_notes text not null,
  allowed_skills text[] not null,
  redox_every_day boolean not null
) on commit drop;

insert into _future_review_students (
  student_id, grade_band, cohort, demo, profile_notes, allowed_skills, redox_every_day
)
select
  s.id,
  s.grade_band,
  coalesce(s.metadata->>'curriculumCohort', ''),
  coalesce(s.metadata->'demo' = 'true'::jsonb, false),
  coalesce(s.metadata->>'profileNotes', ''),
  case s.grade_band
    when '高一' then array(
      select learned.skill_id
      from jsonb_array_elements_text(
        case
          when jsonb_typeof(s.metadata->'confirmedLearnedSkillIds') = 'array'
            then s.metadata->'confirmedLearnedSkillIds'
          else '[]'::jsonb
        end
      ) with ordinality as learned(skill_id, position)
      where learned.skill_id in (
        'H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME','H1_REDOX'
      )
      order by learned.position
    )
    when '高二' then array[
      'H2_THERMO','H2_RATE','H2_EQUIL','H2_K',
      'H2_WEAK','H2_PH_HYDRO','H2_KSP','H2_ELECTRO'
    ]::text[]
    else array[
      'H3_STOICH','H3_ION_REDOX','H3_INORGANIC','H3_THERMO_RATE',
      'H3_EQUILIBRIUM','H3_AQ','H3_ELECTRO','H3_EXPERIMENT',
      'H3_PROCESS','H3_STRUCTURE','H3_ORGANIC'
    ]::text[]
  end,
  s.grade_band = '高一'
    and coalesce(s.metadata->>'curriculumCohort', '') = 'high1_current'
    and coalesce(s.metadata->'confirmedLearnedSkillIds', '[]'::jsonb) ? 'H1_REDOX'
from public.chem_students_v2 s
where s.record_status = 'active'
  and s.grade_band in ('高一','高二','高三');

do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from _future_review_students t
  where cardinality(t.allowed_skills) = 0;
  if v_bad <> 0 then
    raise exception 'future REVIEW repair stopped: % active High-1 profiles have no confirmed learned scope', v_bad;
  end if;
end $$;

-- Everything outside the explicit future REVIEW window is a preservation
-- boundary.  These snapshots turn that statement into a transaction-level
-- assertion instead of relying on reviewer intent.
create temporary table _preserved_plan_snapshot on commit drop as
select p.id, to_jsonb(p) as row_data
from public.chem_learning_plans p
where not exists (
  select 1
  from _future_review_students t
  where t.student_id = p.student_id
    and p.mode = 'REVIEW'
    and p.plan_date between date '2026-08-21' and date '2026-09-25'
);

create temporary table _today_plan_snapshot on commit drop as
select p.id, p.student_id, to_jsonb(p) as row_data
from public.chem_learning_plans p
join _future_review_students t on t.student_id = p.student_id
where p.mode = 'REVIEW'
  and p.plan_date = date '2026-08-21';

create temporary table _today_formal_start_contract on commit drop as
select
  p.id,
  p.student_id,
  p.mode,
  p.skill_ids,
  p.question_count,
  p.round_limit,
  p.max_question_level,
  p.is_scheduled
from public.chem_learning_plans p
join _future_review_students t on t.student_id = p.student_id
where not t.demo
  and p.mode = 'REVIEW'
  and p.plan_date = date '2026-08-21';

create temporary table _attempt_snapshot on commit drop as
select a.id, to_jsonb(a) as row_data
from public.chem_learning_attempts a;

create temporary table _answer_snapshot on commit drop as
select a.id, to_jsonb(a) as row_data
from public.chem_attempt_answers a;

create temporary table _future_skill_catalog (
  grade_band text not null,
  skill_id text primary key,
  display_name text not null,
  sequence integer not null
) on commit drop;

insert into _future_skill_catalog (grade_band, skill_id, display_name, sequence) values
  ('高一','H1_CLASSIFY','物质的分类',1),
  ('高一','H1_PERIODIC','元素周期律',2),
  ('高一','H1_MOLE_INTRO','物质的量与阿伏加德罗常数',3),
  ('高一','H1_GAS_MOLAR_VOLUME','气体摩尔体积',4),
  ('高一','H1_REDOX','氧化还原反应',5),
  ('高二','H2_THERMO','反应热',1),
  ('高二','H2_RATE','化学反应速率',2),
  ('高二','H2_EQUIL','化学平衡',3),
  ('高二','H2_K','化学平衡常数',4),
  ('高二','H2_WEAK','弱电解质的电离',5),
  ('高二','H2_PH_HYDRO','水的电离、pH与盐类水解',6),
  ('高二','H2_KSP','沉淀溶解平衡',7),
  ('高二','H2_ELECTRO','电化学',8),
  ('高三','H3_STOICH','化学计量与守恒',1),
  ('高三','H3_ION_REDOX','离子反应与氧化还原',2),
  ('高三','H3_INORGANIC','元素化合物',3),
  ('高三','H3_THERMO_RATE','热化学与反应速率',4),
  ('高三','H3_EQUILIBRIUM','化学平衡',5),
  ('高三','H3_AQ','水溶液中的离子平衡',6),
  ('高三','H3_ELECTRO','电化学',7),
  ('高三','H3_EXPERIMENT','化学实验',8),
  ('高三','H3_PROCESS','无机工艺流程',9),
  ('高三','H3_STRUCTURE','物质结构与性质',10),
  ('高三','H3_ORGANIC','有机化学基础',11);

-- The first screen names the same five concepts that round one will actually
-- test.  Labels come from the active, visually verified original-question
-- release, so title, concept and source question cannot drift independently.
create temporary table _future_skill_summaries on commit drop as
select
  c.grade_band,
  c.skill_id,
  array_agg(labels.concept_label order by labels.concept_key) as summaries
from _future_skill_catalog c
join (
  select
    q.grade_band,
    q.skill_id,
    q.concept_key,
    min(nullif(btrim(q.source_info->>'conceptLabel'), '')) as concept_label
  from public.chem_questions q
  where q.source_kind = 'licensed_local'
    and q.review_status = 'approved'
    and q.scope_status = 'IN'
    and q.usable_for_review
  group by q.grade_band, q.skill_id, q.concept_key
) labels
  on labels.grade_band = c.grade_band
 and labels.skill_id = c.skill_id
group by c.grade_band, c.skill_id;

create temporary table _future_review_dates (
  plan_date date primary key,
  day_index integer not null,
  priority_slot integer
) on commit drop;

insert into _future_review_dates (plan_date, day_index, priority_slot)
select
  d::date,
  (d::date - date '2026-08-22')::integer,
  case (d::date - date '2026-08-22')::integer
    when 0 then 1
    when 4 then 2
    when 9 then 3
    when 14 then 4
    when 20 then 5
    when 27 then 6
    when 34 then 7
    else null
  end
from generate_series(date '2026-08-22', date '2026-09-25', interval '1 day') d;

create temporary table _future_h2_schedule (
  day_index integer primary key,
  skill_id text not null
) on commit drop;

-- H2_FUTURE_SCHEDULE_BEGIN
insert into _future_h2_schedule (day_index, skill_id)
select (item.position - 1)::integer, item.skill_id
from unnest(array[
  'H2_THERMO','H2_RATE','H2_EQUIL','H2_K','H2_WEAK',
  'H2_PH_HYDRO','H2_KSP','H2_ELECTRO','H2_RATE','H2_EQUIL',
  'H2_K','H2_THERMO','H2_PH_HYDRO','H2_WEAK','H2_KSP',
  'H2_ELECTRO','H2_EQUIL','H2_K','H2_PH_HYDRO','H2_ELECTRO',
  'H2_THERMO','H2_RATE','H2_WEAK','H2_KSP','H2_ELECTRO',
  'H2_EQUIL','H2_K','H2_PH_HYDRO','H2_THERMO','H2_RATE',
  'H2_WEAK','H2_KSP','H2_ELECTRO','H2_EQUIL','H2_K'
]::text[]) with ordinality as item(skill_id, position);
-- H2_FUTURE_SCHEDULE_END

create temporary table _future_h3_schedule (
  day_index integer primary key,
  skill_id text not null
) on commit drop;

-- H3_FUTURE_SCHEDULE_BEGIN
insert into _future_h3_schedule (day_index, skill_id)
select (item.position - 1)::integer, item.skill_id
from unnest(array[
  'H3_AQ','H3_ELECTRO','H3_EXPERIMENT','H3_PROCESS','H3_ION_REDOX',
  'H3_STOICH','H3_EXPERIMENT','H3_ION_REDOX','H3_STOICH','H3_INORGANIC',
  'H3_THERMO_RATE','H3_EQUILIBRIUM','H3_AQ','H3_ELECTRO','H3_PROCESS',
  'H3_EXPERIMENT','H3_STRUCTURE','H3_ORGANIC','H3_STOICH','H3_ION_REDOX',
  'H3_EQUILIBRIUM','H3_AQ','H3_ELECTRO','H3_INORGANIC','H3_PROCESS',
  'H3_THERMO_RATE','H3_EXPERIMENT','H3_STRUCTURE','H3_ORGANIC','H3_STOICH',
  'H3_ION_REDOX','H3_EQUILIBRIUM','H3_AQ','H3_ELECTRO','H3_EXPERIMENT'
]::text[]) with ordinality as item(skill_id, position);
-- H3_FUTURE_SCHEDULE_END

-- Real submitted REVIEW answers are the strongest available evidence.  A
-- concept counts as unresolved only when its latest submitted state is wrong
-- or uncertain.  An older error that was later answered correctly and
-- confidently is closed and must not keep following the student.
create temporary table _future_answer_priority on commit drop as
with answer_history as (
  select
    t.student_id,
    aa.skill_id,
    coalesce(
      nullif(aa.concept_key, ''),
      nullif(aa.question_snapshot->>'conceptKey', ''),
      q.concept_key,
      aa.skill_id || '__LEGACY_UNKNOWN'
    ) as concept_key,
    aa.correct,
    aa.uncertain,
    a.completed_at,
    a.sequence,
    aa.id as answer_id,
    row_number() over (
      partition by
        t.student_id,
        aa.skill_id,
        coalesce(
          nullif(aa.concept_key, ''),
          nullif(aa.question_snapshot->>'conceptKey', ''),
          q.concept_key,
          aa.skill_id || '__LEGACY_UNKNOWN'
        )
      order by a.completed_at desc, a.sequence desc, aa.id desc
    )::integer as latest_rank
  from _future_review_students t
  join public.chem_learning_attempts a
    on a.student_id = t.student_id
   and a.mode = 'REVIEW'
   and a.completed_at < timestamptz '2026-08-22 00:00:00+08'
  join public.chem_attempt_answers aa
    on aa.attempt_id = a.id
   and aa.skill_id = any(t.allowed_skills)
  left join public.chem_questions q on q.id = aa.question_id
), scores as (
  select
    history.student_id,
    history.skill_id,
    count(*) as unresolved_concepts,
    count(*) filter (where not history.correct) as wrong_count,
    count(*) filter (where history.uncertain) as uncertain_count,
    max(history.completed_at) as last_unresolved_at
  from answer_history history
  where history.latest_rank = 1
    and (not history.correct or history.uncertain)
  group by history.student_id, history.skill_id
)
select
  scores.*,
  row_number() over (
    partition by scores.student_id
    order by scores.unresolved_concepts desc,
      scores.wrong_count desc,
      scores.uncertain_count desc,
      scores.last_unresolved_at desc,
      scores.skill_id
  )::integer as priority_rank,
  count(*) over (partition by scores.student_id)::integer as priority_count
from scores;

-- When no real answer exists, use only the existing profile and skill-state
-- evidence.  Keyword rules are grade-scoped and deterministic; a zero score
-- leaves the student on the standard diagnostic sequence instead of inventing
-- a personal weakness.
create temporary table _future_profile_priority on commit drop as
with scored as (
  select
    t.student_id,
    c.skill_id,
    c.sequence,
    (
      case
        when c.skill_id = 'H1_CLASSIFY' then
          case when t.profile_notes ~* '分类|分散系|胶体|氧化物|酸碱盐' then 40 else 0 end
        when c.skill_id = 'H1_PERIODIC' then
          case when t.profile_notes ~* '周期表|周期律|电子排布|原子结构' then 40 else 0 end
        when c.skill_id = 'H1_MOLE_INTRO' then
          case when t.profile_notes ~* '物质的量|阿伏加德罗|摩尔质量|粒子倍数|微粒|多步换算' then 40 else 0 end
        when c.skill_id = 'H1_GAS_MOLAR_VOLUME' then
          case when t.profile_notes ~* '气体|体积|密度' then 40 else 0 end
        when c.skill_id = 'H1_REDOX' then
          case when t.profile_notes ~* '氧化还原|电子守恒|化合价|配平|得失电子' then 40 else 0 end
        when c.skill_id = 'H2_THERMO' then
          case when t.profile_notes ~* '反应热|热化学|焓|盖斯|键能' then 40 else 0 end
        when c.skill_id = 'H2_RATE' then
          case when t.profile_notes ~* '反应速率|速率|有效碰撞|活化能' then 40 else 0 end
        when c.skill_id = 'H2_EQUIL' then
          case when t.profile_notes ~* '平衡标志|平衡条件|平衡移动|惰性气体|恒温|恒压|压缩|平衡图像' then 40 else 0 end
        when c.skill_id = 'H2_K' then
          case when t.profile_notes ~* '三段式|Q/K|平衡常数|平衡浓度|转化率' then 40 else 0 end
        when c.skill_id = 'H2_WEAK' then
          case when t.profile_notes ~* '弱电解质|Ka|Kb|电离平衡' then 40 else 0 end
        when c.skill_id = 'H2_PH_HYDRO' then
          case when t.profile_notes ~* '水的电离|盐类水解|pH|Kw|三大守恒|中和滴定|滴定' then 40 else 0 end
        when c.skill_id = 'H2_KSP' then
          case when t.profile_notes ~* 'Ksp|沉淀溶解|沉淀转化' then 40 else 0 end
        when c.skill_id = 'H2_ELECTRO' then
          case when t.profile_notes ~* '电化学|原电池|电解池|电极|腐蚀|电子方向' then 40 else 0 end
        when c.skill_id = 'H3_STOICH' then
          case when t.profile_notes ~* '阿伏加德罗|化学计量|质量守恒|纯度|溶液浓度|计算' then 40 else 0 end
        when c.skill_id = 'H3_ION_REDOX' then
          case when t.profile_notes ~* '离子|氧化还原|电子守恒|共存|Ca\(HCO' then 40 else 0 end
        when c.skill_id = 'H3_INORGANIC' then
          case when t.profile_notes ~* '元素化合物|无机|分散系|转化网络' then 40 else 0 end
        when c.skill_id = 'H3_THERMO_RATE' then
          case when t.profile_notes ~* '热化学|反应热|反应速率|速率' then 40 else 0 end
        when c.skill_id = 'H3_EQUILIBRIUM' then
          case when t.profile_notes ~* '化学平衡|平衡移动|转化率|选择性|平衡图像' then 40 else 0 end
        when c.skill_id = 'H3_AQ' then
          case when t.profile_notes ~* 'Ka|Kb|Ksp|水溶液|水解|滴定|pH' then 40 else 0 end
        when c.skill_id = 'H3_ELECTRO' then
          case when t.profile_notes ~* '电化学|电池|电极|腐蚀' then 40 else 0 end
        when c.skill_id = 'H3_EXPERIMENT' then
          case when t.profile_notes ~* '实验|装置|操作|误差' then 40 else 0 end
        when c.skill_id = 'H3_PROCESS' then
          case when t.profile_notes ~* '流程|工艺|工业制备' then 40 else 0 end
        when c.skill_id = 'H3_STRUCTURE' then
          case when t.profile_notes ~* '结构|晶体|配位' then 40 else 0 end
        when c.skill_id = 'H3_ORGANIC' then
          case when t.profile_notes ~* '有机|官能团|异构' then 40 else 0 end
        else 0
      end
      + case coalesce(state.stability, 'unknown')
          when 'forgotten' then 30
          when 'learning' then 15
          when 'recovered' then 5
          else 0
        end
      + least(30, 10 * coalesce(state.consecutive_errors, 0))
    )::integer as profile_score
  from _future_review_students t
  join _future_skill_catalog c
    on c.grade_band = t.grade_band
   and c.skill_id = any(t.allowed_skills)
  left join public.chem_student_skill_state state
    on state.student_id = t.student_id
   and state.skill_id = c.skill_id
  where not exists (
    select 1 from _future_answer_priority evidence
    where evidence.student_id = t.student_id
  )
), ranked as (
  select
    scored.*,
    row_number() over (
      partition by scored.student_id
      order by scored.profile_score desc, scored.sequence, scored.skill_id
    )::integer as priority_rank,
    count(*) over (partition by scored.student_id)::integer as priority_count
  from scored
  where scored.profile_score > 0
)
select * from ranked;

create temporary table _future_base_assignment on commit drop as
select
  t.student_id,
  t.grade_band,
  t.cohort,
  t.demo,
  t.allowed_skills,
  t.redox_every_day,
  d.plan_date,
  d.day_index,
  d.priority_slot,
  case t.grade_band
    when '高一' then t.allowed_skills[1 + mod(d.day_index, cardinality(t.allowed_skills))]
    when '高二' then h2.skill_id
    else h3.skill_id
  end as base_skill
from _future_review_students t
cross join _future_review_dates d
left join _future_h2_schedule h2
  on t.grade_band = '高二' and h2.day_index = d.day_index
left join _future_h3_schedule h3
  on t.grade_band = '高三' and h3.day_index = d.day_index;

create temporary table _future_final_assignment on commit drop as
select
  base.*,
  case
    when base.redox_every_day then 'H1_REDOX'
    when base.priority_slot is not null and evidence.skill_id is not null then evidence.skill_id
    when base.priority_slot is not null and profile.skill_id is not null then profile.skill_id
    else base.base_skill
  end as selected_skill,
  case
    when base.redox_every_day then 'daily_redox'
    when base.priority_slot is not null and evidence.skill_id is not null then 'answer_evidence'
    when base.priority_slot is not null and profile.skill_id is not null then 'profile_evidence'
    else 'grade_sequence'
  end as assignment_reason
from _future_base_assignment base
left join _future_answer_priority evidence
  on evidence.student_id = base.student_id
 and base.priority_slot is not null
 and evidence.priority_rank = 1 + mod(base.priority_slot - 1, evidence.priority_count)
left join _future_profile_priority profile
  on profile.student_id = base.student_id
 and base.priority_slot is not null
 and profile.priority_rank = 1 + mod(base.priority_slot - 1, profile.priority_count);

-- Preconditions: update in place only.  A missing or duplicate day is not
-- silently repaired because that could create a second source of truth.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from (
    select t.student_id, count(p.id) as plan_count
    from _future_review_students t
    left join public.chem_learning_plans p
      on p.student_id = t.student_id
     and p.mode = 'REVIEW'
     and p.plan_date = date '2026-08-21'
    group by t.student_id
    having count(p.id) <> 1
  ) broken_today;
  if v_bad <> 0 then
    raise exception 'today REVIEW title repair stopped: % active students are missing or duplicated', v_bad;
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join _future_review_students t on t.student_id = p.student_id
  left join _future_skill_catalog c
    on c.grade_band = t.grade_band
   and c.skill_id = p.skill_ids[1]
  where p.mode = 'REVIEW'
    and p.plan_date = date '2026-08-21'
    and (
      cardinality(p.skill_ids) <> 1
      or c.skill_id is null
      or not (p.skill_ids[1] = any(t.allowed_skills))
      or p.question_count <> 5
      or p.round_limit <> 5
    );
  if v_bad <> 0 then
    raise exception 'today REVIEW title repair stopped: % plans do not already satisfy the start contract', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select t.student_id, d.plan_date, count(p.id) as plan_count
    from _future_review_students t
    cross join _future_review_dates d
    left join public.chem_learning_plans p
      on p.student_id = t.student_id
     and p.mode = 'REVIEW'
     and p.plan_date = d.plan_date
    group by t.student_id, d.plan_date
    having count(p.id) <> 1
  ) broken_days;
  if v_bad <> 0 then
    raise exception 'future REVIEW repair stopped: % student-days are missing or duplicated', v_bad;
  end if;

  select count(*) into v_bad
  from _future_final_assignment f
  join _future_review_students t on t.student_id = f.student_id
  left join _future_skill_catalog c
    on c.grade_band = f.grade_band and c.skill_id = f.selected_skill
  where c.skill_id is null or not (f.selected_skill = any(t.allowed_skills));
  if v_bad <> 0 then
    raise exception 'future REVIEW repair stopped: % assignments violate grade or confirmed learned scope', v_bad;
  end if;
end $$;

-- Fix the user-visible promise on 2026-08-21 without changing what was
-- actually assigned.  This is intentionally a separate two-column update.
do $$
declare
  v_expected integer;
  v_updated integer;
begin
  select count(*) into v_expected from _today_plan_snapshot;

  update public.chem_learning_plans p
  set
    title = '今日复习｜' || catalog.display_name,
    knowledge_summaries = summaries.summaries
  from _future_review_students t
  join _future_skill_catalog catalog
    on catalog.grade_band = t.grade_band
  join _future_skill_summaries summaries
    on summaries.grade_band = catalog.grade_band
   and summaries.skill_id = catalog.skill_id
  where p.student_id = t.student_id
    and p.mode = 'REVIEW'
    and p.plan_date = date '2026-08-21'
    and catalog.skill_id = p.skill_ids[1];

  get diagnostics v_updated = row_count;
  if v_updated <> v_expected then
    raise exception 'today REVIEW title repair updated % rows; expected %', v_updated, v_expected;
  end if;
end $$;

do $$
declare
  v_expected integer;
  v_updated integer;
begin
  select count(*) into v_expected from _future_final_assignment;

  update public.chem_learning_plans p
  set
    title = case
      when f.redox_every_day then '氧化还原反应｜每日五个知识点复习'
      when f.grade_band = '高三' and f.plan_date < date '2026-08-27'
        then '8·27质检前｜' || catalog.display_name
      when f.grade_band = '高三' and f.plan_date = date '2026-08-27'
        then '8·27质检当天｜' || catalog.display_name || '轻回看'
      when f.grade_band = '高三' and f.assignment_reason in ('answer_evidence','profile_evidence')
        then '质检后优先巩固｜' || catalog.display_name
      when f.grade_band = '高三'
        then '质检后间隔巩固｜' || catalog.display_name
      when f.assignment_reason = 'answer_evidence'
        then '今天优先巩固｜' || catalog.display_name
      when f.assignment_reason = 'profile_evidence'
        then '按学习档案巩固｜' || catalog.display_name
      else '五个知识点复习｜' || catalog.display_name
    end,
    skill_ids = array[f.selected_skill],
    knowledge_summaries = summaries.summaries,
    estimated_minutes = case
      when f.grade_band = '高三' and f.plan_date = date '2026-08-27' then 10
      when f.grade_band = '高一' then 15
      when f.grade_band = '高二' then 18
      else 20
    end,
    source = case
      when f.assignment_reason in ('answer_evidence','profile_evidence') then 'mastery'
      else 'course'
    end,
    is_scheduled = true,
    question_count = 5,
    round_limit = 5,
    max_question_level = case when f.grade_band = '高三' then null else 3 end
  from _future_final_assignment f
  join _future_skill_catalog catalog
    on catalog.grade_band = f.grade_band
   and catalog.skill_id = f.selected_skill
  join _future_skill_summaries summaries
    on summaries.grade_band = f.grade_band
   and summaries.skill_id = f.selected_skill
  where p.student_id = f.student_id
    and p.mode = 'REVIEW'
    and p.plan_date = f.plan_date;

  get diagnostics v_updated = row_count;
  if v_updated <> v_expected then
    raise exception 'future REVIEW repair updated % rows; expected %', v_updated, v_expected;
  end if;
end $$;

-- Postconditions: every future day can satisfy the deployed start_plan
-- contract for both real accounts and copyright-safe demo accounts.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from public.chem_learning_plans p
  join _future_review_students t on t.student_id = p.student_id
  join _future_skill_catalog c
    on c.grade_band = t.grade_band and c.skill_id = p.skill_ids[1]
  join _future_skill_summaries summaries
    on summaries.grade_band = t.grade_band and summaries.skill_id = p.skill_ids[1]
  where p.mode = 'REVIEW'
    and p.plan_date between date '2026-08-22' and date '2026-09-25'
    and (
      cardinality(p.skill_ids) <> 1
      or not (p.skill_ids[1] = any(t.allowed_skills))
      or p.question_count <> 5
      or p.round_limit <> 5
      or (t.grade_band in ('高一','高二') and p.max_question_level is distinct from 3)
      or (t.grade_band = '高三' and p.max_question_level is not null)
      or not p.is_scheduled
      or p.title not like '%' || c.display_name || '%'
      or cardinality(p.knowledge_summaries) <> 5
      or p.knowledge_summaries is distinct from summaries.summaries
    );
  if v_bad <> 0 then
    raise exception 'future REVIEW plan-shape assertion failed: % rows', v_bad;
  end if;

  select count(*) into v_bad
  from _future_skill_catalog c
  left join _future_skill_summaries s
    on s.grade_band = c.grade_band and s.skill_id = c.skill_id
  where s.skill_id is null
    or cardinality(s.summaries) <> 5
    or array_position(s.summaries, null) is not null;
  if v_bad <> 0 then
    raise exception 'future REVIEW concept-summary assertion failed: % skills', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select
      selected.demo,
      selected.grade_band,
      selected.skill_id,
      count(q.id) as question_count,
      count(distinct q.concept_key) as concept_count,
      count(distinct q.id) as distinct_questions,
      count(distinct q.mother_id) as distinct_mothers,
      count(distinct q.source_item_key) filter (where not selected.demo) as distinct_source_items,
      count(distinct q.content_fingerprint) filter (where not selected.demo) as distinct_fingerprints,
      count(*) filter (
        where not selected.demo
          and q.render_mode = 'image_primary'
          and q.source_release_id is not null
          and jsonb_typeof(q.asset_refs) = 'array'
          and jsonb_array_length(q.asset_refs) = 2
          and exists (
            select 1 from jsonb_array_elements(q.asset_refs) ref
            where ref->>'kind' = 'question_image'
          )
      ) as licensed_visual_count
    from (
      select distinct t.demo, f.grade_band, f.selected_skill as skill_id
      from _future_final_assignment f
      join _future_review_students t on t.student_id = f.student_id
    ) selected
    left join public.chem_questions q
      on q.grade_band = selected.grade_band
     and q.skill_id = selected.skill_id
     and q.review_status = 'approved'
     and q.scope_status = 'IN'
     and q.concept_key is not null
     and (
       (not selected.demo
         and q.source_kind = 'licensed_local'
         and q.usable_for_review)
       or
       (selected.demo
         and q.source_kind = 'teacher_original'
         and q.usable_for_demo)
     )
    group by selected.demo, selected.grade_band, selected.skill_id
  ) pool
  where pool.question_count <> 25
    or pool.concept_count <> 5
    or pool.distinct_questions <> 25
    or pool.distinct_mothers <> 25
    or (not pool.demo and pool.distinct_source_items <> 25)
    or (not pool.demo and pool.distinct_fingerprints <> 25)
    or (not pool.demo and pool.licensed_visual_count <> 25);
  if v_bad <> 0 then
    raise exception 'future REVIEW source-pool assertion failed: % grade/skill/account pools', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select
      selected.demo,
      selected.grade_band,
      selected.skill_id,
      q.concept_key,
      count(q.id) as question_count
    from (
      select distinct t.demo, f.grade_band, f.selected_skill as skill_id
      from _future_final_assignment f
      join _future_review_students t on t.student_id = f.student_id
    ) selected
    join public.chem_questions q
      on q.grade_band = selected.grade_band
     and q.skill_id = selected.skill_id
     and q.review_status = 'approved'
     and q.scope_status = 'IN'
     and q.concept_key is not null
     and (
       (not selected.demo
         and q.source_kind = 'licensed_local'
         and q.usable_for_review)
       or
       (selected.demo
         and q.source_kind = 'teacher_original'
         and q.usable_for_demo)
     )
    group by selected.demo, selected.grade_band, selected.skill_id, q.concept_key
    having count(q.id) <> 5
  ) concept_pool;
  if v_bad <> 0 then
    raise exception 'future REVIEW five-round assertion failed: % concepts do not have five originals', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select c.skill_id, count(card.id) as card_count,
      count(card.id) filter (
        where length(btrim(card.title)) > 0
          and length(btrim(card.core)) > 0
          and length(btrim(card.detail)) > 0
          and length(btrim(card.micro_example)) > 0
          and jsonb_typeof(card.structured_content) = 'object'
          and card.structured_content <> '{}'::jsonb
      ) as complete_count
    from (
      select distinct selected_skill as skill_id
      from _future_final_assignment
    ) c
    left join public.chem_knowledge_cards card
      on card.skill_id = c.skill_id
     and card.review_status = 'approved'
    group by c.skill_id
  ) cards
  where cards.card_count <> 1 or cards.complete_count <> 1;
  if v_bad <> 0 then
    raise exception 'future REVIEW knowledge-card assertion failed: % skills', v_bad;
  end if;

  -- All currently evidenced students start the future window with their most
  -- strongly evidenced unresolved skill.  Daily-REDOX students remain the one
  -- explicit teacher-directed exception.
  select count(*) into v_bad
  from _future_review_students t
  join _future_answer_priority evidence
    on evidence.student_id = t.student_id and evidence.priority_rank = 1
  join _future_final_assignment f
    on f.student_id = t.student_id and f.plan_date = date '2026-08-22'
  where not t.redox_every_day and f.selected_skill <> evidence.skill_id;
  if v_bad <> 0 then
    raise exception 'future REVIEW evidence-priority assertion failed: % students', v_bad;
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join _future_review_students t on t.student_id = p.student_id
  where t.grade_band = '高三'
    and p.mode = 'REVIEW'
    and p.plan_date between date '2026-08-22' and date '2026-08-26'
    and p.title not like '8·27质检前｜%';
  if v_bad <> 0 then
    raise exception 'High-3 pre-inspection timeline assertion failed: % rows', v_bad;
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join _future_review_students t on t.student_id = p.student_id
  where t.grade_band = '高三'
    and p.mode = 'REVIEW'
    and p.plan_date = date '2026-08-27'
    and p.title not like '8·27质检当天｜%轻回看';
  if v_bad <> 0 then
    raise exception 'High-3 inspection-day timeline assertion failed: % rows', v_bad;
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join _future_review_students t on t.student_id = p.student_id
  where t.grade_band = '高三'
    and p.mode = 'REVIEW'
    and p.plan_date between date '2026-08-28' and date '2026-09-25'
    and p.title not like '质检后%';
  if v_bad <> 0 then
    raise exception 'High-3 post-inspection timeline assertion failed: % rows', v_bad;
  end if;
end $$;

-- Assert the migration did not alter any row outside its authorized window,
-- and did not alter, add or remove attempts/answers.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from _today_plan_snapshot snapshot
  left join public.chem_learning_plans p on p.id = snapshot.id
  where p.id is null
    or (to_jsonb(p) - 'title' - 'knowledge_summaries')
      is distinct from (snapshot.row_data - 'title' - 'knowledge_summaries');
  if v_bad <> 0 then
    raise exception 'today REVIEW narrow-update assertion failed: % plans changed outside title/summary', v_bad;
  end if;

  select count(*) into v_bad
  from _today_formal_start_contract before
  left join public.chem_learning_plans p on p.id = before.id
  where p.id is null
    or p.student_id is distinct from before.student_id
    or p.mode is distinct from before.mode
    or p.skill_ids is distinct from before.skill_ids
    or p.question_count is distinct from before.question_count
    or p.round_limit is distinct from before.round_limit
    or p.max_question_level is distinct from before.max_question_level
    or p.is_scheduled is distinct from before.is_scheduled;
  if v_bad <> 0
    or (select count(*) from _today_formal_start_contract) <> (
      select count(*)
      from public.chem_learning_plans p
      join _future_review_students t on t.student_id = p.student_id
      where not t.demo and p.mode = 'REVIEW' and p.plan_date = date '2026-08-21'
    )
  then
    raise exception 'today REVIEW start contract changed for a formal student';
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans p
  join _future_review_students t on t.student_id = p.student_id
  join _future_skill_catalog c
    on c.grade_band = t.grade_band and c.skill_id = p.skill_ids[1]
  join _future_skill_summaries summaries
    on summaries.grade_band = t.grade_band and summaries.skill_id = p.skill_ids[1]
  where p.mode = 'REVIEW'
    and p.plan_date = date '2026-08-21'
    and (
      p.title <> '今日复习｜' || c.display_name
      or p.knowledge_summaries is distinct from summaries.summaries
    );
  if v_bad <> 0 then
    raise exception 'today REVIEW honest-title assertion failed: % plans', v_bad;
  end if;

  select count(*) into v_bad
  from _preserved_plan_snapshot snapshot
  left join public.chem_learning_plans p on p.id = snapshot.id
  where p.id is null or to_jsonb(p) is distinct from snapshot.row_data;
  if v_bad <> 0 then
    raise exception 'future REVIEW preservation assertion failed: % past or out-of-scope plans changed', v_bad;
  end if;

  if (select count(*) from public.chem_learning_attempts) <> (select count(*) from _attempt_snapshot)
    or exists (
      select 1
      from _attempt_snapshot snapshot
      left join public.chem_learning_attempts a on a.id = snapshot.id
      where a.id is null or to_jsonb(a) is distinct from snapshot.row_data
    )
  then
    raise exception 'future REVIEW preservation assertion failed: an attempt row changed';
  end if;

  if (select count(*) from public.chem_attempt_answers) <> (select count(*) from _answer_snapshot)
    or exists (
      select 1
      from _answer_snapshot snapshot
      left join public.chem_attempt_answers a on a.id = snapshot.id
      where a.id is null or to_jsonb(a) is distinct from snapshot.row_data
    )
  then
    raise exception 'future REVIEW preservation assertion failed: an answer row changed';
  end if;

  -- Every student for whom the database has evidence receives at least one
  -- evidence-specific anchor.  A student with neither submitted evidence nor
  -- a profile signal is intentionally allowed to stay on the honest standard
  -- diagnostic sequence; no fake personalization is invented.
  select count(*) into v_bad
  from _future_review_students t
  where not t.redox_every_day
    and (
      exists (
        select 1 from _future_answer_priority evidence
        where evidence.student_id = t.student_id
      )
      or exists (
        select 1 from _future_profile_priority profile
        where profile.student_id = t.student_id
      )
    )
    and not exists (
      select 1
      from _future_final_assignment f
      where f.student_id = t.student_id
        and (
          f.assignment_reason = 'answer_evidence'
          or f.assignment_reason = 'profile_evidence'
        )
    );
  if v_bad <> 0 then
    raise exception 'future REVIEW personalization assertion failed: % evidenced students have no priority anchor', v_bad;
  end if;
end $$;

commit;
