-- Applied formal REVIEW daily-cap and next-day personalization contract.
-- The chemistry-access Edge Function and this migration passed the production audit together.
--
-- Formal high-school REVIEW semantics after this candidate:
--   * one daily package, 1..8 original questions, never five same-day rounds;
--   * every wrong or uncertain fine concept from today's completed package is
--     placed first in tomorrow's package when a fresh original exists;
--   * if today has no unresolved concept, the learner's latest unresolved
--     history or an individually rotated progression concept is used;
--   * the rest of tomorrow's package follows its existing classroom sequence;
--   * question, mother, source-item and content-fingerprint identities never
--     repeat for the same student across completed REVIEW history;
--   * only an unstarted next-day REVIEW plan may be updated;
--   * attempts, answers, access data and independent quiz_sessions are never
--     inserted, updated or deleted here.

begin;

set transaction isolation level serializable;
set local lock_timeout = '5s';

-- A question answer lock means that the learner has already seen and answered
-- part of the package even if finalization has not inserted an attempt yet.
-- SHARE prevents a concurrent answer-lock insert while this migration decides
-- which future plans are still safe to rewrite.
lock table app_private.chem_question_answer_locks in share mode;

create temporary table _protected_started_review_plan on commit drop as
select
  plan.id,
  plan.student_id,
  plan.plan_date,
  plan.mode,
  plan.title,
  plan.question_count,
  plan.round_limit,
  plan.skill_ids,
  plan.target_concept_keys,
  plan.knowledge_summaries,
  plan.estimated_minutes,
  plan.source
from public.chem_learning_plans plan
where exists (
  select 1
  from public.chem_learning_attempts attempt
  where attempt.plan_day_id = plan.id
)
or exists (
  select 1
  from app_private.chem_question_answer_locks answer_lock
  where answer_lock.plan_day_id = plan.id
);

-- Student-facing concept names are curriculum data, not source-ingest data.
-- In particular, the active H3 release deliberately stores raw concept keys
-- in source_info and a subset of the H2 source rows contains stale/misaligned
-- labels.  Keep the reviewed 130-name catalog in the private schema and make
-- every planner join this table by the exact (grade, skill, concept) identity.
create table if not exists app_private.chem_review_concept_catalog (
  grade_band text not null check (grade_band in ('高一','高二','高三')),
  skill_id text not null references public.chem_skills(id) on delete restrict,
  concept_key text primary key,
  concept_order smallint not null check (concept_order between 1 and 5),
  concept_label text not null check (
    pg_catalog.length(pg_catalog.btrim(concept_label)) between 2 and 80
    and concept_label <> concept_key
  ),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (grade_band, skill_id, concept_order),
  check (concept_key = skill_id || '__C0' || concept_order::text)
);

alter table app_private.chem_review_concept_catalog enable row level security;
revoke all on table app_private.chem_review_concept_catalog
  from public, anon, authenticated;
grant usage on schema app_private to service_role;
grant select on table app_private.chem_review_concept_catalog to service_role;

insert into app_private.chem_review_concept_catalog (
  grade_band, skill_id, concept_key, concept_order, concept_label
) values
  ('高一','H1_CLASSIFY','H1_CLASSIFY__C01',1,'分类标准与分类树'),
  ('高一','H1_CLASSIFY','H1_CLASSIFY__C02',2,'纯净物与混合物'),
  ('高一','H1_CLASSIFY','H1_CLASSIFY__C03',3,'分散系与胶体'),
  ('高一','H1_CLASSIFY','H1_CLASSIFY__C04',4,'酸性与碱性氧化物'),
  ('高一','H1_CLASSIFY','H1_CLASSIFY__C05',5,'物质类别的交叉判断'),
  ('高一','H1_GAS_MOLAR_VOLUME','H1_GAS_MOLAR_VOLUME__C01',1,'决定气体体积的因素'),
  ('高一','H1_GAS_MOLAR_VOLUME','H1_GAS_MOLAR_VOLUME__C02',2,'气体摩尔体积的条件'),
  ('高一','H1_GAS_MOLAR_VOLUME','H1_GAS_MOLAR_VOLUME__C03',3,'气体体积与物质的量'),
  ('高一','H1_GAS_MOLAR_VOLUME','H1_GAS_MOLAR_VOLUME__C04',4,'阿伏加德罗定律'),
  ('高一','H1_GAS_MOLAR_VOLUME','H1_GAS_MOLAR_VOLUME__C05',5,'气体密度与摩尔质量'),
  ('高一','H1_MOLE_INTRO','H1_MOLE_INTRO__C01',1,'物质的量与摩尔'),
  ('高一','H1_MOLE_INTRO','H1_MOLE_INTRO__C02',2,'阿伏加德罗常数'),
  ('高一','H1_MOLE_INTRO','H1_MOLE_INTRO__C03',3,'微粒对象与粒子数'),
  ('高一','H1_MOLE_INTRO','H1_MOLE_INTRO__C04',4,'摩尔质量及单位'),
  ('高一','H1_MOLE_INTRO','H1_MOLE_INTRO__C05',5,'质量与物质的量换算'),
  ('高一','H1_PERIODIC','H1_PERIODIC__C01',1,'原子结构与位置'),
  ('高一','H1_PERIODIC','H1_PERIODIC__C02',2,'同周期递变'),
  ('高一','H1_PERIODIC','H1_PERIODIC__C03',3,'同主族递变'),
  ('高一','H1_PERIODIC','H1_PERIODIC__C04',4,'结构位置性质'),
  ('高一','H1_PERIODIC','H1_PERIODIC__C05',5,'性质事实验证规律'),
  ('高一','H1_REDOX','H1_REDOX__C01',1,'化合价升降'),
  ('高一','H1_REDOX','H1_REDOX__C02',2,'氧化剂与还原剂'),
  ('高一','H1_REDOX','H1_REDOX__C03',3,'氧化产物与还原产物'),
  ('高一','H1_REDOX','H1_REDOX__C04',4,'电子守恒'),
  ('高一','H1_REDOX','H1_REDOX__C05',5,'陌生反应迁移'),
  ('高一','H1_REACTION_CLASSIFICATION','H1_REACTION_CLASSIFICATION__C01',1,'常见物质转化关系与知识网络'),
  ('高一','H1_REACTION_CLASSIFICATION','H1_REACTION_CLASSIFICATION__C02',2,'一步转化的可行性与反应条件'),
  ('高一','H1_REACTION_CLASSIFICATION','H1_REACTION_CLASSIFICATION__C03',3,'化合、分解、置换、复分解反应'),
  ('高一','H1_REACTION_CLASSIFICATION','H1_REACTION_CLASSIFICATION__C04',4,'四种基本反应类型的边界与反例'),
  ('高一','H1_REACTION_CLASSIFICATION','H1_REACTION_CLASSIFICATION__C05',5,'转化流程与反应分类综合'),
  ('高一','H1_SOLUTION_CONCENTRATION','H1_SOLUTION_CONCENTRATION__C01',1,'物质的量浓度概念、溶液体积与离子浓度'),
  ('高一','H1_SOLUTION_CONCENTRATION','H1_SOLUTION_CONCENTRATION__C02',2,'物质的量浓度与质量分数、密度的换算'),
  ('高一','H1_SOLUTION_CONCENTRATION','H1_SOLUTION_CONCENTRATION__C03',3,'稀释、混合与体积边界'),
  ('高一','H1_SOLUTION_CONCENTRATION','H1_SOLUTION_CONCENTRATION__C04',4,'一定物质的量浓度溶液的配制'),
  ('高一','H1_SOLUTION_CONCENTRATION','H1_SOLUTION_CONCENTRATION__C05',5,'配制操作的误差分析'),
  ('高二','H2_THERMO','H2_THERMO__C01',1,'焓变正负'),
  ('高二','H2_THERMO','H2_THERMO__C02',2,'热化学方程式'),
  ('高二','H2_THERMO','H2_THERMO__C03',3,'盖斯定律'),
  ('高二','H2_THERMO','H2_THERMO__C04',4,'键能与反应热'),
  ('高二','H2_THERMO','H2_THERMO__C05',5,'能量守恒与测量'),
  ('高二','H2_RATE','H2_RATE__C01',1,'速率表示'),
  ('高二','H2_RATE','H2_RATE__C02',2,'计量数与速率比'),
  ('高二','H2_RATE','H2_RATE__C03',3,'浓度和压强影响'),
  ('高二','H2_RATE','H2_RATE__C04',4,'温度与有效碰撞'),
  ('高二','H2_RATE','H2_RATE__C05',5,'催化剂与活化能'),
  ('高二','H2_EQUIL','H2_EQUIL__C01',1,'平衡状态'),
  ('高二','H2_EQUIL','H2_EQUIL__C02',2,'正逆速率'),
  ('高二','H2_EQUIL','H2_EQUIL__C03',3,'平衡移动'),
  ('高二','H2_EQUIL','H2_EQUIL__C04',4,'勒夏特列原理'),
  ('高二','H2_EQUIL','H2_EQUIL__C05',5,'条件改变的瞬间判断'),
  ('高二','H2_K','H2_K__C01',1,'平衡常数表达式'),
  ('高二','H2_K','H2_K__C02',2,'三段式计算'),
  ('高二','H2_K','H2_K__C03',3,'反应商与平衡方向'),
  ('高二','H2_K','H2_K__C04',4,'转化率'),
  ('高二','H2_K','H2_K__C05',5,'温度与平衡常数'),
  ('高二','H2_WEAK','H2_WEAK__C01',1,'弱电解质部分电离'),
  ('高二','H2_WEAK','H2_WEAK__C02',2,'电离平衡'),
  ('高二','H2_WEAK','H2_WEAK__C03',3,'稀释效应'),
  ('高二','H2_WEAK','H2_WEAK__C04',4,'同离子效应'),
  ('高二','H2_WEAK','H2_WEAK__C05',5,'Ka与酸碱强弱'),
  ('高二','H2_PH_HYDRO','H2_PH_HYDRO__C01',1,'水的电离'),
  ('高二','H2_PH_HYDRO','H2_PH_HYDRO__C02',2,'pH与离子浓度'),
  ('高二','H2_PH_HYDRO','H2_PH_HYDRO__C03',3,'盐类水解'),
  ('高二','H2_PH_HYDRO','H2_PH_HYDRO__C04',4,'三大守恒'),
  ('高二','H2_PH_HYDRO','H2_PH_HYDRO__C05',5,'酸碱中和与滴定'),
  ('高二','H2_KSP','H2_KSP__C01',1,'溶解平衡'),
  ('高二','H2_KSP','H2_KSP__C02',2,'Ksp表达式'),
  ('高二','H2_KSP','H2_KSP__C03',3,'Qsp与沉淀'),
  ('高二','H2_KSP','H2_KSP__C04',4,'同离子效应'),
  ('高二','H2_KSP','H2_KSP__C05',5,'沉淀转化'),
  ('高二','H2_ELECTRO','H2_ELECTRO__C01',1,'原电池与电解池'),
  ('高二','H2_ELECTRO','H2_ELECTRO__C02',2,'正负极与阴阳极'),
  ('高二','H2_ELECTRO','H2_ELECTRO__C03',3,'电极反应'),
  ('高二','H2_ELECTRO','H2_ELECTRO__C04',4,'电子和离子方向'),
  ('高二','H2_ELECTRO','H2_ELECTRO__C05',5,'金属腐蚀与防护'),
  ('高三','H3_STOICH','H3_STOICH__C01',1,'阿伏加德罗常数与微粒数、电子数'),
  ('高三','H3_STOICH','H3_STOICH__C02',2,'溶液浓度、质量分数与混合定量'),
  ('高三','H3_STOICH','H3_STOICH__C03',3,'溶液配制、稀释与误差分析'),
  ('高三','H3_STOICH','H3_STOICH__C04',4,'差量法与气体体积定量'),
  ('高三','H3_STOICH','H3_STOICH__C05',5,'守恒法、关系式与纯度定量'),
  ('高三','H3_ION_REDOX','H3_ION_REDOX__C01',1,'离子大量共存'),
  ('高三','H3_ION_REDOX','H3_ION_REDOX__C02',2,'离子方程式的基本书写规则'),
  ('高三','H3_ION_REDOX','H3_ION_REDOX__C03',3,'情境型离子方程式与过量问题'),
  ('高三','H3_ION_REDOX','H3_ION_REDOX__C04',4,'氧化还原基本概念与性质判断'),
  ('高三','H3_ION_REDOX','H3_ION_REDOX__C05',5,'氧化还原配平、电子守恒与应用'),
  ('高三','H3_INORGANIC','H3_INORGANIC__C01',1,'物质性质与用途'),
  ('高三','H3_INORGANIC','H3_INORGANIC__C02',2,'价态—类别二维图与物质类别'),
  ('高三','H3_INORGANIC','H3_INORGANIC__C03',3,'无机物转化网络与元素推断'),
  ('高三','H3_INORGANIC','H3_INORGANIC__C04',4,'物质制备、分离与反应条件'),
  ('高三','H3_INORGANIC','H3_INORGANIC__C05',5,'工业制备与资源综合利用'),
  ('高三','H3_THERMO_RATE','H3_THERMO_RATE__C01',1,'焓变、反应热与能量图'),
  ('高三','H3_THERMO_RATE','H3_THERMO_RATE__C02',2,'活化能、能垒与决速步骤'),
  ('高三','H3_THERMO_RATE','H3_THERMO_RATE__C03',3,'催化剂与反应路径'),
  ('高三','H3_THERMO_RATE','H3_THERMO_RATE__C04',4,'基元反应、中间体与过渡态'),
  ('高三','H3_THERMO_RATE','H3_THERMO_RATE__C05',5,'反应机理与速率、选择性'),
  ('高三','H3_EQUILIBRIUM','H3_EQUILIBRIUM__C01',1,'反应速率、速率曲线与影响因素'),
  ('高三','H3_EQUILIBRIUM','H3_EQUILIBRIUM__C02',2,'化学平衡状态与平衡移动'),
  ('高三','H3_EQUILIBRIUM','H3_EQUILIBRIUM__C03',3,'平衡常数、速率常数与定量关系'),
  ('高三','H3_EQUILIBRIUM','H3_EQUILIBRIUM__C04',4,'温度、压强与平衡图像'),
  ('高三','H3_EQUILIBRIUM','H3_EQUILIBRIUM__C05',5,'多反应转化率、选择性与条件优化'),
  ('高三','H3_AQ','H3_AQ__C01',1,'弱酸电离与微粒分布'),
  ('高三','H3_AQ','H3_AQ__C02',2,'酸碱滴定与pH定量'),
  ('高三','H3_AQ','H3_AQ__C03',3,'盐类水解与离子浓度守恒'),
  ('高三','H3_AQ','H3_AQ__C04',4,'沉淀溶解平衡与沉淀转化'),
  ('高三','H3_AQ','H3_AQ__C05',5,'多重平衡图像与配合物平衡'),
  ('高三','H3_ELECTRO','H3_ELECTRO__C01',1,'原电池与燃料电池放电原理'),
  ('高三','H3_ELECTRO','H3_ELECTRO__C02',2,'二次电池充放电'),
  ('高三','H3_ELECTRO','H3_ELECTRO__C03',3,'电解池与电极反应'),
  ('高三','H3_ELECTRO','H3_ELECTRO__C04',4,'离子交换膜与离子迁移'),
  ('高三','H3_ELECTRO','H3_ELECTRO__C05',5,'电化学定量与联用装置'),
  ('高三','H3_EXPERIMENT','H3_EXPERIMENT__C01',1,'基本操作与实验安全'),
  ('高三','H3_EXPERIMENT','H3_EXPERIMENT__C02',2,'分离、提纯与物质检验'),
  ('高三','H3_EXPERIMENT','H3_EXPERIMENT__C03',3,'气体制备、装置连接与尾气处理'),
  ('高三','H3_EXPERIMENT','H3_EXPERIMENT__C04',4,'实验现象、证据与性质探究'),
  ('高三','H3_EXPERIMENT','H3_EXPERIMENT__C05',5,'实验方案设计与评价'),
  ('高三','H3_PROCESS','H3_PROCESS__C01',1,'综合流程图读取与物质转化'),
  ('高三','H3_PROCESS','H3_PROCESS__C02',2,'工业与实验制备的步骤和条件控制'),
  ('高三','H3_PROCESS','H3_PROCESS__C03',3,'分离、提纯与流程操作评价'),
  ('高三','H3_PROCESS','H3_PROCESS__C04',4,'电化学制备与资源循环'),
  ('高三','H3_PROCESS','H3_PROCESS__C05',5,'污染治理、绿色利用与定量评价'),
  ('高三','H3_STRUCTURE','H3_STRUCTURE__C01',1,'原子结构、电子排布与周期性'),
  ('高三','H3_STRUCTURE','H3_STRUCTURE__C02',2,'化学键、杂化与分子构型'),
  ('高三','H3_STRUCTURE','H3_STRUCTURE__C03',3,'分子间作用力、晶体类型与性质'),
  ('高三','H3_STRUCTURE','H3_STRUCTURE__C04',4,'晶胞组成、配位数与分数坐标'),
  ('高三','H3_STRUCTURE','H3_STRUCTURE__C05',5,'晶胞参数、密度与晶体缺陷'),
  ('高三','H3_ORGANIC','H3_ORGANIC__C01',1,'官能团、有机物类别与结构性质'),
  ('高三','H3_ORGANIC','H3_ORGANIC__C02',2,'有机反应类型与转化路线'),
  ('高三','H3_ORGANIC','H3_ORGANIC__C03',3,'同分异构、立体结构与结构计数'),
  ('高三','H3_ORGANIC','H3_ORGANIC__C04',4,'高分子结构与聚合反应'),
  ('高三','H3_ORGANIC','H3_ORGANIC__C05',5,'生物有机物与医药分子')
on conflict (concept_key) do update set
  grade_band = excluded.grade_band,
  skill_id = excluded.skill_id,
  concept_order = excluded.concept_order,
  concept_label = excluded.concept_label,
  updated_at = pg_catalog.now();

comment on table app_private.chem_review_concept_catalog is
  'Private, teacher-reviewed REVIEW concept names. Source-ingest metadata must never overwrite student-facing labels.';

create or replace function public.chem_review_concept_catalog_rows()
returns table(
  grade_band text,
  skill_id text,
  concept_key text,
  concept_title text,
  sequence_no integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    catalog.grade_band,
    catalog.skill_id,
    catalog.concept_key,
    catalog.concept_label as concept_title,
    catalog.concept_order::integer as sequence_no
  from app_private.chem_review_concept_catalog catalog
  order by catalog.grade_band, catalog.skill_id, catalog.concept_order;
$$;

revoke all on function public.chem_review_concept_catalog_rows()
  from public, anon, authenticated;
grant execute on function public.chem_review_concept_catalog_rows()
  to service_role;

comment on function public.chem_review_concept_catalog_rows() is
  'Server-only authoritative REVIEW concept labels for teacher readiness and source-capacity views.';

create or replace function public.chem_review_active_source_usage_counts(
  p_student_ids uuid[]
)
returns table(
  student_id uuid,
  concept_key text,
  used_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_student_ids is null or pg_catalog.cardinality(p_student_ids) = 0 then
    return;
  end if;
  if pg_catalog.cardinality(p_student_ids) > 500 then
    raise exception 'at most 500 students may be audited at once';
  end if;

  return query
  with requested_student as (
    select distinct student.id as student_id, student.grade_band
    from public.chem_students_v2 student
    where student.id = any(p_student_ids)
      and student.record_status = 'active'
      and student.grade_band in ('高一','高二','高三')
      and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
  ), active_pool as (
    select
      question.id as question_id,
      question.grade_band,
      question.concept_key,
      question.mother_id,
      question.source_item_key,
      question.content_fingerprint
    from public.chem_questions question
    join app_private.chem_question_source_releases release
      on release.id = question.source_release_id
     and release.grade_band = question.grade_band
     and release.status = 'active'
     and release.verification_status = 'full_visual_verified'
    where question.grade_band in ('高一','高二','高三')
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.source_kind = 'licensed_local'
      and question.render_mode = 'image_primary'
      and question.concept_key is not null
      and question.mother_id is not null
      and question.source_item_key is not null
      and question.content_fingerprint is not null
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'question_image'
      )
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'analysis_image'
      )
  ), used_identity as (
    select
      attempt.student_id,
      answer.question_id,
      answer.mother_id,
      coalesce(
        nullif(answer.question_snapshot->>'sourceItemKey', ''),
        nullif(answered_question.source_item_key, '')
      ) as source_item_key,
      coalesce(
        nullif(answer.question_snapshot->>'contentFingerprint', ''),
        nullif(answered_question.content_fingerprint, '')
      ) as content_fingerprint
    from public.chem_learning_attempts attempt
    join requested_student requested on requested.student_id = attempt.student_id
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    left join public.chem_questions answered_question
      on answered_question.id = answer.question_id
    where attempt.mode = 'REVIEW'

    union all

    select
      answer_lock.student_id,
      answer_lock.question_id,
      locked_question.mother_id,
      locked_question.source_item_key,
      locked_question.content_fingerprint
    from app_private.chem_question_answer_locks answer_lock
    join requested_student requested on requested.student_id = answer_lock.student_id
    join public.chem_questions locked_question
      on locked_question.id = answer_lock.question_id
  )
  select
    requested.student_id,
    pool.concept_key,
    count(distinct pool.question_id)::integer as used_count
  from requested_student requested
  join active_pool pool on pool.grade_band = requested.grade_band
  join used_identity used on used.student_id = requested.student_id
    and (
      used.question_id = pool.question_id
      or used.mother_id = pool.mother_id
      or used.source_item_key = pool.source_item_key
      or used.content_fingerprint = pool.content_fingerprint
    )
  group by requested.student_id, pool.concept_key
  order by requested.student_id, pool.concept_key;
end;
$$;

revoke all on function public.chem_review_active_source_usage_counts(uuid[])
  from public, anon, authenticated;
grant execute on function public.chem_review_active_source_usage_counts(uuid[])
  to service_role;

comment on function public.chem_review_active_source_usage_counts(uuid[]) is
  'Server-only teacher capacity audit: counts active verified source originals excluded by each learner''s four historical identities; retired-release-only identities do not consume current capacity.';

create or replace function public.chem_active_verified_source_releases()
returns table (grade_band text, source_release_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select release.grade_band, release.id
  from app_private.chem_question_source_releases release
  where release.grade_band in ('高一','高二','高三')
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
  order by release.grade_band;
$$;

revoke all on function public.chem_active_verified_source_releases()
  from public, anon, authenticated;
grant execute on function public.chem_active_verified_source_releases()
  to service_role;

comment on function public.chem_active_verified_source_releases() is
  'Server-only release allowlist for REVIEW delivery; returns identifiers only and no question or answer content.';

-- Serialize first-answer locks with that student's suffix re-budget. This
-- replaces a harmful runtime table-wide SHARE lock while preserving the
-- immutable-first-answer contract. It also refuses retired or incomplete
-- source releases before a lock can be created.
create or replace function public.chem_lock_question_answer(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_id text,
  p_selected_option integer,
  p_uncertain boolean,
  p_duration_sec integer,
  p_revision_token text
)
returns table (
  selected_option integer,
  uncertain boolean,
  duration_sec integer,
  revision_token text,
  created_at timestamptz,
  is_new boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer := 0;
begin
  if p_student_id is null
    or p_plan_day_id is null
    or p_attempt_sequence is null
    or p_attempt_sequence not between 0 and 7
    or length(coalesce(p_question_id, '')) not between 1 and 160
    or p_selected_option is null
    or p_selected_option not between 0 and 9
    or p_duration_sec is null
    or p_duration_sec not between 0 and 3600
  then
    raise exception 'invalid answer lock request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-review-suffix:' || p_student_id::text, 0)
  );

  if not exists (
    select 1 from public.chem_learning_plans plan
    where plan.id = p_plan_day_id and plan.student_id = p_student_id
  ) then
    raise exception 'plan does not belong to student';
  end if;

  if not exists (
    select 1
    from public.chem_questions question
    join app_private.chem_question_source_releases release
      on release.id = question.source_release_id
     and release.grade_band = question.grade_band
     and release.status = 'active'
     and release.verification_status = 'full_visual_verified'
    where question.id = p_question_id
      and question.grade_band in ('高一','高二','高三')
      and question.source_kind = 'licensed_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'image_primary'
      and question.question_revision_token is not distinct from nullif(p_revision_token, '')
      and exists (
        select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'question_image'
      )
      and exists (
        select 1 from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'analysis_image'
      )
  ) then
    raise exception 'question revision is stale or not eligible for an answer lock';
  end if;

  insert into app_private.chem_question_answer_locks (
    student_id, plan_day_id, attempt_sequence, question_id,
    selected_option, uncertain, duration_sec, revision_token
  ) values (
    p_student_id, p_plan_day_id, p_attempt_sequence, p_question_id,
    p_selected_option, coalesce(p_uncertain, false), p_duration_sec,
    nullif(p_revision_token, '')
  )
  on conflict (student_id, plan_day_id, attempt_sequence, question_id) do nothing;
  get diagnostics v_inserted = row_count;

  return query
  select lock.selected_option::integer, lock.uncertain, lock.duration_sec,
    lock.revision_token, lock.created_at, v_inserted = 1
  from app_private.chem_question_answer_locks lock
  where lock.student_id = p_student_id
    and lock.plan_day_id = p_plan_day_id
    and lock.attempt_sequence = p_attempt_sequence
    and lock.question_id = p_question_id;
end;
$$;

revoke all on function public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)
  from public, anon, authenticated;
grant execute on function public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text)
  to service_role;

do $$
begin
  if (select count(*) from app_private.chem_review_concept_catalog) <> 130
     or (select count(*) from app_private.chem_review_concept_catalog where grade_band='高一') <> 35
     or (select count(*) from app_private.chem_review_concept_catalog where grade_band='高二') <> 40
     or (select count(*) from app_private.chem_review_concept_catalog where grade_band='高三') <> 55
     or exists (
       select 1
       from app_private.chem_review_concept_catalog catalog
       join public.chem_skills skill on skill.id = catalog.skill_id
       where skill.grade_band <> catalog.grade_band
          or catalog.concept_label = catalog.concept_key
          or catalog.concept_label ~ '^H[123]_[A-Z0-9_]+__C[0-9]+$'
     )
     or (
       select count(distinct question.concept_key)
       from public.chem_questions question
       join app_private.chem_question_source_releases release
         on release.id = question.source_release_id
        and release.status = 'active'
        and release.verification_status = 'full_visual_verified'
       where question.grade_band in ('高一','高二','高三')
         and question.review_status = 'approved'
         and question.scope_status = 'IN'
         and question.usable_for_review
         and question.source_kind = 'licensed_local'
         and question.render_mode = 'image_primary'
     ) <> 130
     or exists (
       select 1
       from public.chem_questions question
       join app_private.chem_question_source_releases release
         on release.id = question.source_release_id
        and release.status = 'active'
        and release.verification_status = 'full_visual_verified'
       left join app_private.chem_review_concept_catalog catalog
         on catalog.grade_band = question.grade_band
        and catalog.skill_id = question.skill_id
        and catalog.concept_key = question.concept_key
       where question.grade_band in ('高一','高二','高三')
         and question.review_status = 'approved'
         and question.scope_status = 'IN'
         and question.usable_for_review
         and question.source_kind = 'licensed_local'
         and question.render_mode = 'image_primary'
         and catalog.concept_key is null
     )
  then
    raise exception 'authoritative 130-concept REVIEW catalog failed closed';
  end if;
end $$;

-- The companion capacity migration persists round_limit=1 together with the
-- funded concept arrays. This statement is deliberately compile-only here.
update public.chem_learning_plans plan
set round_limit = 1
from public.chem_students_v2 student
where student.id = plan.student_id
  -- The companion capacity-funded calendar migration is the sole writer of
  -- future plans. Keeping this catalog/RPC migration write-free avoids a
  -- partially mapped interval between the two reviewed migrations.
  and false
  and student.record_status = 'active'
  and student.grade_band in ('高一','高二','高三')
  and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
  and plan.mode = 'REVIEW'
  and plan.plan_date >= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  and plan.question_count between 1 and 8
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = plan.id
  )
  and not exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    where answer_lock.plan_day_id = plan.id
  );

-- Backfill every unstarted formal future plan with exact, human-readable
-- targets. Existing exact targets remain first; the student's unresolved
-- concepts rotate across later dates; then that date's taught skill sequence
-- fills the package. Each candidate must still have a fresh active-release
-- original after the student's complete REVIEW history.
create temporary table _formal_future_review_plan on commit drop as
select
  plan.id as plan_id,
  plan.student_id,
  plan.plan_date,
  plan.question_count,
  plan.max_question_level,
  plan.skill_ids,
  plan.target_concept_keys,
  student.grade_band,
  student.metadata
from public.chem_learning_plans plan
join public.chem_students_v2 student on student.id = plan.student_id
where student.record_status = 'active'
  -- See above: compile the legacy backfill query for auditability, but leave
  -- the authoritative plan assignment to the capacity-funded migration.
  and false
  and student.grade_band in ('高一','高二','高三')
  and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
  and plan.mode = 'REVIEW'
  and plan.plan_date >= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  and plan.question_count between 1 and 8
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = plan.id
  )
  and not exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    where answer_lock.plan_day_id = plan.id
  );

create temporary table _latest_review_concept_state on commit drop as
with history as (
  select
    attempt.student_id,
    coalesce(nullif(answer.skill_id, ''), question.skill_id) as skill_id,
    coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      question.concept_key
    ) as concept_key,
    answer.correct,
    answer.uncertain,
    coalesce(
      nullif(answer.question_snapshot->>'level', '')::integer,
      question.level::integer
    ) as question_level,
    attempt.completed_at,
    attempt.sequence,
    answer.id,
    row_number() over (
      partition by attempt.student_id, coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        question.concept_key
      )
      order by attempt.completed_at desc, attempt.sequence desc, answer.id desc
    ) as latest_rank
  from public.chem_learning_attempts attempt
  join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
  left join public.chem_questions question on question.id = answer.question_id
  where attempt.mode = 'REVIEW'
    and attempt.completed_at is not null
)
select *
from history
where latest_rank = 1 and concept_key is not null;

do $$
begin
  if exists (
    select 1
    from _formal_future_review_plan plan
    cross join lateral pg_catalog.unnest(plan.skill_ids) listed(skill_id)
    where plan.grade_band = '高一'
      and plan.plan_date < date '2026-09-01'
      and not (
        case
          when pg_catalog.jsonb_typeof(plan.metadata->'confirmedLearnedSkillIds') = 'array'
            then plan.metadata->'confirmedLearnedSkillIds'
          else '[]'::jsonb
        end ? listed.skill_id
      )
  ) then
    raise exception 'a pre-opening High-1 REVIEW plan leaves confirmedLearnedSkillIds';
  end if;
end $$;

create temporary table _future_available_concept on commit drop as
select
  plan.plan_id,
  plan.student_id,
  plan.plan_date,
  plan.question_count,
  plan.grade_band,
  catalog.skill_id,
  catalog.concept_key,
  catalog.concept_order,
  catalog.concept_label
from _formal_future_review_plan plan
join app_private.chem_review_concept_catalog catalog
  on catalog.grade_band = plan.grade_band
where exists (
  select 1
  from public.chem_questions question
  join app_private.chem_question_source_releases release
    on release.id = question.source_release_id
   and release.grade_band = question.grade_band
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
  where question.grade_band = plan.grade_band
    and question.skill_id = catalog.skill_id
    and question.concept_key = catalog.concept_key
    and question.review_status = 'approved'
    and question.scope_status = 'IN'
    and question.usable_for_review
    and question.source_kind = 'licensed_local'
    and question.render_mode = 'image_primary'
    and question.mother_id is not null
    and question.source_item_key is not null
    and question.content_fingerprint is not null
    and (plan.max_question_level is null or question.level <= plan.max_question_level)
    and (
      not exists (
        select 1
        from _latest_review_concept_state evidence
        where evidence.student_id = plan.student_id
          and evidence.concept_key = catalog.concept_key
      )
      or exists (
        select 1
        from _latest_review_concept_state evidence
        where evidence.student_id = plan.student_id
          and evidence.concept_key = catalog.concept_key
          and evidence.question_level is not null
          and (
            (
              evidence.correct
              and not evidence.uncertain
              and question.level > evidence.question_level
            )
            or (
              (not evidence.correct or evidence.uncertain)
              and question.level <= evidence.question_level
            )
          )
      )
    )
    and exists (
      select 1
      from pg_catalog.jsonb_array_elements(question.asset_refs) asset
      where asset->>'kind' = 'question_image'
    )
    and exists (
      select 1
      from pg_catalog.jsonb_array_elements(question.asset_refs) asset
      where asset->>'kind' = 'analysis_image'
    )
    and not exists (
      select 1
      from public.chem_learning_attempts used_attempt
      join public.chem_attempt_answers used_answer
        on used_answer.attempt_id = used_attempt.id
      left join public.chem_questions used_question
        on used_question.id = used_answer.question_id
      where used_attempt.student_id = plan.student_id
        and used_attempt.mode = 'REVIEW'
        and used_attempt.completed_at is not null
        and (
          used_answer.question_id = question.id
          or used_answer.mother_id = question.mother_id
          or coalesce(
            nullif(used_answer.question_snapshot->>'sourceItemKey', ''),
            nullif(used_question.source_item_key, '')
          ) = question.source_item_key
          or coalesce(
            nullif(used_answer.question_snapshot->>'contentFingerprint', ''),
            nullif(used_question.content_fingerprint, '')
          ) = question.content_fingerprint
        )
    )
    and not exists (
      select 1
      from app_private.chem_question_answer_locks used_lock
      join public.chem_questions locked_question
        on locked_question.id = used_lock.question_id
      where used_lock.student_id = plan.student_id
        and (
          used_lock.question_id = question.id
          or locked_question.mother_id = question.mother_id
          or locked_question.source_item_key = question.source_item_key
          or locked_question.content_fingerprint = question.content_fingerprint
        )
    )
)
and exists (
  select 1
  from public.chem_knowledge_cards card
  where card.skill_id = catalog.skill_id
    and card.review_status = 'approved'
);

create temporary table _future_review_target on commit drop as
with unresolved_evidence as (
  select
    state.*,
    row_number() over (
      partition by state.student_id
      order by state.completed_at desc, state.sequence desc, state.id desc,
        state.concept_key
    )::integer as evidence_rank,
    count(*) over (partition by state.student_id)::integer as evidence_count
  from _latest_review_concept_state state
  where not state.correct or state.uncertain
), unresolved as (
  select
    plan.plan_id,
    available.skill_id,
    available.concept_key,
    available.concept_label,
    1 as priority,
    row_number() over (
      partition by plan.plan_id
      order by
        pg_catalog.mod(
          state.evidence_rank
          + (plan.plan_date - (pg_catalog.now() at time zone 'Asia/Shanghai')::date),
          greatest(state.evidence_count, 1)
        ),
        state.concept_key
    )::integer as evidence_order
  from _formal_future_review_plan plan
  join unresolved_evidence state
    on state.student_id = plan.student_id
   and (
     plan.grade_band = '高三'
     or state.skill_id = any(plan.skill_ids)
   )
  join _future_available_concept available
    on available.plan_id = plan.plan_id
   and available.skill_id = state.skill_id
   and available.concept_key = state.concept_key
), existing_target as (
  select
    plan.plan_id,
    available.skill_id,
    available.concept_key,
    available.concept_label,
    2 as priority,
    target.position::integer as evidence_order
  from _formal_future_review_plan plan
  cross join lateral pg_catalog.unnest(plan.target_concept_keys)
    with ordinality as target(concept_key, position)
  join _future_available_concept available
    on available.plan_id = plan.plan_id
   and available.concept_key = target.concept_key
  where plan.grade_band = '高三'
     or available.skill_id = any(plan.skill_ids)
), scheduled_progress as (
  select
    plan.plan_id,
    available.skill_id,
    available.concept_key,
    available.concept_label,
    3 as priority,
    row_number() over (
      partition by plan.plan_id
      order by
        pg_catalog.hashtextextended(
          plan.student_id::text || ':' || plan.plan_date::text || ':scheduled:' || available.concept_key,
          0
        ),
        available.concept_key
    )::integer as evidence_order
  from _formal_future_review_plan plan
  join _future_available_concept available on available.plan_id = plan.plan_id
  where available.skill_id = any(plan.skill_ids)
), learned_progress as (
  select
    plan.plan_id,
    available.skill_id,
    available.concept_key,
    available.concept_label,
    4 as priority,
    row_number() over (
      partition by plan.plan_id
      order by
        pg_catalog.hashtextextended(
          plan.student_id::text || ':' || plan.plan_date::text || ':learned:' || available.concept_key,
          0
        ),
        available.concept_key
    )::integer as evidence_order
  from _formal_future_review_plan plan
  join _future_available_concept available on available.plan_id = plan.plan_id
  where exists (
    select 1
    from _latest_review_concept_state state
    where state.student_id = plan.student_id
      and state.skill_id = available.skill_id
  )
    and (
      plan.grade_band in ('高二','高三')
      or (
        plan.grade_band = '高一'
        and (
          case
            when pg_catalog.jsonb_typeof(plan.metadata->'confirmedLearnedSkillIds') = 'array'
              then plan.metadata->'confirmedLearnedSkillIds'
            else '[]'::jsonb
          end ? available.skill_id
        )
      )
    )
), candidates as (
  select * from unresolved
  union all select * from existing_target
  union all select * from scheduled_progress
  union all select * from learned_progress
), deduplicated as (
  select
    candidates.*,
    row_number() over (
      partition by candidates.plan_id, candidates.concept_key
      order by candidates.priority, candidates.evidence_order, candidates.skill_id
    ) as concept_rank
  from candidates
), ordered as (
  select
    deduplicated.*,
    row_number() over (
      partition by deduplicated.plan_id
      order by deduplicated.priority, deduplicated.evidence_order,
        deduplicated.concept_key
    )::integer as target_order
  from deduplicated
  where deduplicated.concept_rank = 1
)
select ordered.*
from ordered
join _formal_future_review_plan plan on plan.plan_id = ordered.plan_id
where ordered.target_order <= plan.question_count;

create temporary table _future_review_assignment on commit drop as
select
  target.plan_id,
  array_agg(target.concept_key order by target.target_order) as target_concept_keys,
  array_agg(target.concept_label order by target.target_order) as knowledge_summaries,
  array(
    select first_skill.skill_id
    from (
      select nested.skill_id, min(nested.target_order) as first_order
      from _future_review_target nested
      where nested.plan_id = target.plan_id
      group by nested.skill_id
    ) first_skill
    order by first_skill.first_order, first_skill.skill_id
  ) as skill_ids
from _future_review_target target
group by target.plan_id;

do $$
begin
  if exists (
    select 1
    from _formal_future_review_plan plan
    left join _future_review_assignment assignment on assignment.plan_id = plan.plan_id
    where assignment.plan_id is null
       or cardinality(assignment.target_concept_keys) <> plan.question_count
       or cardinality(assignment.knowledge_summaries) <> plan.question_count
       or cardinality(assignment.skill_ids) = 0
  ) then
    raise exception 'an unstarted formal future REVIEW plan cannot be mapped to exact fresh concepts';
  end if;
end $$;

update public.chem_learning_plans plan
set
  skill_ids = assignment.skill_ids,
  target_concept_keys = assignment.target_concept_keys,
  knowledge_summaries = assignment.knowledge_summaries,
  round_limit = 1
from _future_review_assignment assignment
where plan.id = assignment.plan_id
  and not exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = plan.id
  );

do $$
begin
  if exists (
    select 1
    from public.chem_learning_plans plan
    where plan.mode = 'REVIEW'
    group by plan.student_id, plan.plan_date
    having count(*) > 1
  ) then
    raise exception 'duplicate REVIEW plans must be resolved before enforcing one daily package';
  end if;
end $$;

create unique index if not exists chem_learning_plans_one_review_per_student_day_uidx
  on public.chem_learning_plans (student_id, plan_date)
  where mode = 'REVIEW';

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'chem_learning_plans_review_daily_question_cap_check'
      and conrelid = 'public.chem_learning_plans'::regclass
  ) then
    alter table public.chem_learning_plans
      add constraint chem_learning_plans_review_daily_question_cap_check
      check (mode <> 'REVIEW' or question_count between 1 and 8);
  end if;
end $$;

create table if not exists app_private.review_plan_personalization_jobs (
  completed_plan_id uuid primary key
    references public.chem_learning_plans(id) on delete cascade,
  student_id uuid not null
    references public.chem_students_v2(id) on delete cascade,
  evidence_completed_at timestamptz,
  next_plan_date date,
  status text not null default 'pending'
    check (status in ('pending','blocked','succeeded','not_needed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text check (last_error is null or length(last_error) <= 500),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

alter table app_private.review_plan_personalization_jobs enable row level security;
revoke all on table app_private.review_plan_personalization_jobs
  from public, anon, authenticated;
grant select, insert, update on table app_private.review_plan_personalization_jobs
  to service_role;

create index if not exists review_plan_personalization_jobs_pending_idx
  on app_private.review_plan_personalization_jobs (updated_at, completed_plan_id)
  where status = 'pending';

comment on table app_private.review_plan_personalization_jobs is
  'Server-only compensation queue. A pending row means next-day REVIEW personalization needs a safe retry or teacher attention; it contains no answer text, access data or quiz-session data.';

create or replace function public.chem_personalize_next_review_plan(
  p_student_id uuid,
  p_completed_plan_id uuid,
  p_completed_at timestamptz
)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_grade_band text;
  v_student_metadata jsonb;
  v_next_date date;
  v_completed_plan_date date;
  v_evidence_completed_at timestamptz;
  v_completed_skill_ids text[];
  v_allowed_skills text[];
  v_next_plan public.chem_learning_plans%rowtype;
  v_question_count integer;
  v_target_concepts text[];
  v_target_skills text[];
  v_target_labels text[];
  v_skill_ids text[];
  v_raw_unresolved_count integer;
  v_fresh_unresolved_count integer;
  v_unmapped_unresolved_count integer;
  v_rebudget_result jsonb;
begin
  begin
  if p_student_id is null or p_completed_plan_id is null then
    raise exception 'personalization input is incomplete';
  end if;

  select student.grade_band, student.metadata
  into v_grade_band, v_student_metadata
  from public.chem_students_v2 student
  where student.id = p_student_id
    and student.record_status = 'active'
    and student.grade_band in ('高一','高二','高三')
    and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb;

  if v_grade_band is null then
    return false;
  end if;

  -- Match the suffix helper and answer-lock RPC lock order: the learner-level
  -- advisory must be acquired before any plan row is locked.  This prevents
  -- older retry jobs and a newly completed adjacent day from deadlocking.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-review-suffix:' || p_student_id::text, 0)
  );

  select plan.plan_date, plan.skill_ids, evidence.completed_at
  into v_completed_plan_date, v_completed_skill_ids, v_evidence_completed_at
  from public.chem_learning_plans plan
  join lateral (
    select attempt.completed_at
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ) evidence on true
  where plan.id = p_completed_plan_id
    and plan.student_id = p_student_id
    and plan.mode = 'REVIEW';

  if v_completed_plan_date is null or v_evidence_completed_at is null then
    raise exception 'completed REVIEW evidence is missing';
  end if;

  -- "Next day" is the day immediately after the completed plan date. A
  -- learner finishing after midnight must not cause us to skip an already
  -- scheduled plan and mutate a later date instead.
  v_next_date := v_completed_plan_date + 1;

  -- The capacity-funded calendar ends on 2026-09-29. Completion of its last
  -- plan is terminal, not a missing-plan failure requiring teacher action.
  if v_next_date > date '2026-09-29' then
    insert into app_private.review_plan_personalization_jobs (
      completed_plan_id, student_id, evidence_completed_at, next_plan_date,
      status, attempt_count, last_error, updated_at
    ) values (
      p_completed_plan_id, p_student_id, v_evidence_completed_at, v_next_date,
      'not_needed', 0, null, pg_catalog.now()
    )
    on conflict (completed_plan_id) do update set
      student_id = excluded.student_id,
      evidence_completed_at = excluded.evidence_completed_at,
      next_plan_date = excluded.next_plan_date,
      status = 'not_needed',
      last_error = null,
      updated_at = pg_catalog.now();
    return false;
  end if;

  insert into app_private.review_plan_personalization_jobs (
    completed_plan_id, student_id, evidence_completed_at, next_plan_date,
    status, attempt_count, last_error, updated_at
  ) values (
    p_completed_plan_id, p_student_id, v_evidence_completed_at, v_next_date,
    'pending', 1, null, pg_catalog.now()
  )
  on conflict (completed_plan_id) do update set
    student_id = excluded.student_id,
    evidence_completed_at = excluded.evidence_completed_at,
    next_plan_date = excluded.next_plan_date,
    status = 'pending',
    attempt_count = app_private.review_plan_personalization_jobs.attempt_count + 1,
    last_error = null,
    updated_at = pg_catalog.now();

  select plan.*
  into v_next_plan
  from public.chem_learning_plans plan
  where plan.student_id = p_student_id
    and plan.mode = 'REVIEW'
    and plan.plan_date = v_next_date
  order by plan.id
  limit 1
  for update;

  if not found then
    update app_private.review_plan_personalization_jobs
    set last_error = 'next REVIEW plan is missing', updated_at = pg_catalog.now()
    where completed_plan_id = p_completed_plan_id;
    return false;
  end if;

  if exists (
    select 1
    from public.chem_learning_attempts attempt
    where attempt.plan_day_id = v_next_plan.id
  ) or exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    where answer_lock.student_id = p_student_id
      and answer_lock.plan_day_id = v_next_plan.id
  ) then
    update app_private.review_plan_personalization_jobs
    set status = 'not_needed', last_error = null, updated_at = pg_catalog.now()
    where completed_plan_id = p_completed_plan_id;
    return false;
  end if;

  if (
    select count(*)
    from public.chem_learning_plans plan
    where plan.student_id = p_student_id
      and plan.mode = 'REVIEW'
      and plan.plan_date = v_next_date
  ) <> 1 then
    raise exception 'next date contains more than one REVIEW plan';
  end if;

  v_question_count := v_next_plan.question_count;
  if v_question_count is null or v_question_count < 1 or v_question_count > 8 then
    raise exception 'next REVIEW question_count must be between 1 and 8';
  end if;

  if v_grade_band = '高三' then
    select array_agg(distinct catalog.skill_id order by catalog.skill_id)
    into v_allowed_skills
    from app_private.chem_review_concept_catalog catalog
    where catalog.grade_band = '高三';
  elsif v_grade_band = '高二' then
    select array_agg(distinct allowed.skill_id order by allowed.skill_id)
    into v_allowed_skills
    from (
      select pg_catalog.unnest(v_next_plan.skill_ids) as skill_id
      union
      select pg_catalog.unnest(v_completed_skill_ids) as skill_id
    ) allowed
    join app_private.chem_review_concept_catalog catalog
      on catalog.grade_band = '高二' and catalog.skill_id = allowed.skill_id;
  else
    select array_agg(distinct allowed.skill_id order by allowed.skill_id)
    into v_allowed_skills
    from (
      select pg_catalog.unnest(v_next_plan.skill_ids) as skill_id
      union
      select pg_catalog.unnest(v_completed_skill_ids) as skill_id
      union
      select learned.skill_id
      from pg_catalog.jsonb_array_elements_text(
        case
          when pg_catalog.jsonb_typeof(v_student_metadata->'confirmedLearnedSkillIds') = 'array'
            then v_student_metadata->'confirmedLearnedSkillIds'
          else '[]'::jsonb
        end
      ) learned(skill_id)
    ) allowed
    join app_private.chem_review_concept_catalog catalog
      on catalog.grade_band = '高一' and catalog.skill_id = allowed.skill_id
    where v_next_date >= date '2026-09-01'
       or coalesce(v_student_metadata->'confirmedLearnedSkillIds', '[]'::jsonb) ? allowed.skill_id;
  end if;

  if cardinality(coalesce(v_allowed_skills, array[]::text[])) = 0
     or exists (
       select 1
       from pg_catalog.unnest(v_next_plan.skill_ids) listed(skill_id)
       where not (listed.skill_id = any(v_allowed_skills))
     )
  then
    raise exception 'next REVIEW plan leaves the learner confirmed curriculum scope';
  end if;

  with latest_current_attempt as (
    select attempt.id
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ), unresolved as (
    select distinct coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      answered_question.concept_key
    ) as concept_key
    from latest_current_attempt latest
    join public.chem_attempt_answers answer on answer.attempt_id = latest.id
    left join public.chem_questions answered_question on answered_question.id = answer.question_id
    where not answer.correct or answer.uncertain
  )
  select
    count(*) filter (where concept_key is not null)::integer,
    count(*) filter (where concept_key is null)::integer
  into v_raw_unresolved_count, v_unmapped_unresolved_count
  from unresolved;

  if v_unmapped_unresolved_count <> 0 then
    raise exception 'a wrong or uncertain answer lacks an exact concept mapping';
  end if;
  if v_raw_unresolved_count > 8 then
    raise exception 'a completed daily REVIEW package contains more than eight unresolved concepts';
  end if;

  -- Never truncate the sixth through eighth wrong/uncertain concept merely
  -- because tomorrow was prebuilt as a five-question plan.
  v_question_count := greatest(v_question_count, v_raw_unresolved_count);

  with latest_current_attempt as (
    select attempt.id
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ), used_history as (
    select
      answer.question_id,
      answer.mother_id,
      coalesce(
        nullif(answer.question_snapshot->>'sourceItemKey', ''),
        nullif(used_question.source_item_key, '')
      ) as source_item_key,
      coalesce(
        nullif(answer.question_snapshot->>'contentFingerprint', ''),
        nullif(used_question.content_fingerprint, '')
      ) as content_fingerprint
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    left join public.chem_questions used_question on used_question.id = answer.question_id
    where attempt.student_id = p_student_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null

    union all

    select
      answer_lock.question_id,
      locked_question.mother_id,
      locked_question.source_item_key,
      locked_question.content_fingerprint
    from app_private.chem_question_answer_locks answer_lock
    join public.chem_questions locked_question
      on locked_question.id = answer_lock.question_id
    where answer_lock.student_id = p_student_id
  ), latest_concept_evidence as (
    select *
    from (
      select
        coalesce(
          nullif(answer.concept_key, ''),
          nullif(answer.question_snapshot->>'conceptKey', ''),
          answered_question.concept_key
        ) as concept_key,
        answer.correct,
        answer.uncertain,
        coalesce(
          nullif(answer.question_snapshot->>'level', '')::integer,
          answered_question.level::integer
        ) as question_level,
        row_number() over (
          partition by coalesce(
            nullif(answer.concept_key, ''),
            nullif(answer.question_snapshot->>'conceptKey', ''),
            answered_question.concept_key
          )
          order by attempt.completed_at desc, attempt.sequence desc, answer.id desc
        ) as latest_rank
      from public.chem_learning_attempts attempt
      join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
      left join public.chem_questions answered_question
        on answered_question.id = answer.question_id
      where attempt.student_id = p_student_id
        and attempt.mode = 'REVIEW'
        and attempt.completed_at is not null
    ) ranked
    where ranked.latest_rank = 1
      and ranked.concept_key is not null
  ), fresh_question as (
    select question.*
    from public.chem_questions question
    join app_private.chem_question_source_releases release
      on release.id = question.source_release_id
     and release.grade_band = question.grade_band
     and release.status = 'active'
     and release.verification_status = 'full_visual_verified'
    where question.grade_band = v_grade_band
      and question.skill_id = any(v_allowed_skills)
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.source_kind = 'licensed_local'
      and question.render_mode = 'image_primary'
      and question.source_release_id is not null
      and question.mother_id is not null
      and question.concept_key is not null
      and question.source_item_key is not null
      and question.content_fingerprint is not null
      and (v_next_plan.max_question_level is null or question.level <= v_next_plan.max_question_level)
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'question_image'
      )
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(question.asset_refs) asset
        where asset->>'kind' = 'analysis_image'
      )
      and (
        not exists (
          select 1
          from latest_concept_evidence evidence
          where evidence.concept_key = question.concept_key
        )
        or exists (
          select 1
          from latest_concept_evidence evidence
          where evidence.concept_key = question.concept_key
            and evidence.question_level is not null
            and (
              (
                evidence.correct
                and not evidence.uncertain
                and question.level > evidence.question_level
              )
              or (
                (not evidence.correct or evidence.uncertain)
                and question.level <= evidence.question_level
              )
            )
        )
      )
      and not exists (
        select 1
        from used_history used
        where used.question_id = question.id
           or used.mother_id = question.mother_id
           or used.source_item_key = question.source_item_key
           or used.content_fingerprint = question.content_fingerprint
      )
  ), concept_pool as (
    select
      question.skill_id,
      question.concept_key,
      catalog.concept_label,
      count(distinct question.id) as fresh_questions,
      count(distinct question.mother_id) as fresh_mothers,
      count(distinct question.source_item_key) as fresh_sources,
      count(distinct question.content_fingerprint) as fresh_fingerprints
    from fresh_question question
    join public.chem_skills skill on skill.id = question.skill_id and skill.active
    join app_private.chem_review_concept_catalog catalog
      on catalog.grade_band = question.grade_band
     and catalog.skill_id = question.skill_id
     and catalog.concept_key = question.concept_key
    where exists (
      select 1
      from public.chem_knowledge_cards card
      where card.skill_id = question.skill_id
        and card.review_status = 'approved'
    )
    group by question.skill_id, question.concept_key, catalog.concept_label
    having count(distinct question.id) > 0
      and count(distinct question.id) = count(distinct question.mother_id)
      and count(distinct question.id) = count(distinct question.source_item_key)
      and count(distinct question.id) = count(distinct question.content_fingerprint)
  ), raw_current_unresolved as (
    select distinct on (coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      answered_question.concept_key
    ))
      coalesce(nullif(answer.skill_id, ''), answered_question.skill_id) as skill_id,
      coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        answered_question.concept_key
      ) as concept_key,
      answer.correct,
      answer.uncertain,
      answer.id
    from latest_current_attempt latest
    join public.chem_attempt_answers answer on answer.attempt_id = latest.id
    left join public.chem_questions answered_question on answered_question.id = answer.question_id
    where not answer.correct or answer.uncertain
    order by coalesce(
      nullif(answer.concept_key, ''),
      nullif(answer.question_snapshot->>'conceptKey', ''),
      answered_question.concept_key
    ), answer.id desc
  ), current_unresolved as (
    select
      1 as priority,
      row_number() over (order by raw.id)::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from raw_current_unresolved raw
    join concept_pool pool
      on pool.skill_id = raw.skill_id
     and pool.concept_key = raw.concept_key
  ), answer_history as (
    select
      coalesce(nullif(answer.skill_id, ''), answered_question.skill_id) as skill_id,
      coalesce(
        nullif(answer.concept_key, ''),
        nullif(answer.question_snapshot->>'conceptKey', ''),
        answered_question.concept_key
      ) as concept_key,
      answer.correct,
      answer.uncertain,
      attempt.completed_at,
      attempt.sequence,
      answer.id,
      row_number() over (
        partition by coalesce(
          nullif(answer.concept_key, ''),
          nullif(answer.question_snapshot->>'conceptKey', ''),
          answered_question.concept_key
        )
        order by attempt.completed_at desc, attempt.sequence desc, answer.id desc
      ) as latest_rank
    from public.chem_learning_attempts attempt
    join public.chem_attempt_answers answer on answer.attempt_id = attempt.id
    left join public.chem_questions answered_question on answered_question.id = answer.question_id
    where attempt.student_id = p_student_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
  ), prior_unresolved as (
    select
      2 as priority,
      row_number() over (
        order by history.completed_at desc, history.sequence desc, history.id desc
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from answer_history history
    join concept_pool pool
      on pool.skill_id = history.skill_id
     and pool.concept_key = history.concept_key
    where history.latest_rank = 1
      and (not history.correct or history.uncertain)
    order by history.completed_at desc, history.sequence desc, history.id desc
  ), weak_skill as (
    select
      3 as priority,
      row_number() over (
        order by
          state.teacher_intervention desc,
          state.consecutive_errors desc,
          state.verified_level asc,
          state.last_reviewed_at asc nulls first,
          pg_catalog.hashtextextended(
            p_student_id::text || ':' || v_next_date::text || ':weak:' || pool.concept_key,
            0
          )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from public.chem_student_skill_state state
    join concept_pool pool on pool.skill_id = state.skill_id
    where state.student_id = p_student_id
      and (
        state.teacher_intervention
        or state.consecutive_errors > 0
        or state.stability in ('unknown','learning','forgotten')
        or state.next_review_at <= v_evidence_completed_at
      )
  ), personal_progress as (
    select
      4 as priority,
      row_number() over (
        order by history.completed_at desc, history.sequence desc, history.id desc,
          pg_catalog.hashtextextended(
            p_student_id::text || ':' || v_next_date::text || ':progress:' || pool.concept_key,
            0
          )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from answer_history history
    join concept_pool pool
      on pool.skill_id = history.skill_id
     and pool.concept_key = history.concept_key
    where history.latest_rank = 1
      and history.correct
      and not history.uncertain
  ), existing_target as (
    select
      5 as priority,
      target.position::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from pg_catalog.unnest(v_next_plan.target_concept_keys)
      with ordinality as target(concept_key, position)
    join concept_pool pool on pool.concept_key = target.concept_key
  ), same_skill_alternative as (
    select
      6 as priority,
      row_number() over (
        order by pg_catalog.hashtextextended(
          p_student_id::text || ':' || v_next_date::text || ':' || pool.concept_key,
          0
        )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from concept_pool pool
    where pool.skill_id = any(v_next_plan.skill_ids)
  ), learned_alternative as (
    select
      7 as priority,
      row_number() over (
        order by pg_catalog.hashtextextended(
          p_student_id::text || ':' || v_next_date::text || ':learned:' || pool.concept_key,
          0
        )
      )::integer as evidence_order,
      pool.skill_id,
      pool.concept_key,
      pool.concept_label
    from concept_pool pool
    where exists (
      select 1
      from answer_history history
      where history.skill_id = pool.skill_id
    )
  ), candidates as (
    select * from current_unresolved
    union all select * from prior_unresolved
    union all select * from weak_skill
    union all select * from personal_progress
    union all select * from existing_target
    union all select * from same_skill_alternative
    union all select * from learned_alternative
  ), deduplicated as (
    select
      candidates.*,
      row_number() over (
        partition by candidates.concept_key
        order by candidates.priority, candidates.evidence_order, candidates.skill_id
      ) as concept_rank
    from candidates
  ), ordered as (
    select
      deduplicated.*,
      row_number() over (
        order by deduplicated.priority, deduplicated.evidence_order,
          deduplicated.concept_key
      ) as target_order
    from deduplicated
    where deduplicated.concept_rank = 1
  ), chosen as (
    select *
    from ordered
    where target_order <= v_question_count
  )
  select
    array_agg(chosen.concept_key order by chosen.target_order),
    array_agg(chosen.skill_id order by chosen.target_order),
    array_agg(chosen.concept_label order by chosen.target_order),
    (select count(*) from raw_current_unresolved),
    (select count(*) from current_unresolved)
  into
    v_target_concepts,
    v_target_skills,
    v_target_labels,
    v_raw_unresolved_count,
    v_fresh_unresolved_count
  from chosen;

  if v_raw_unresolved_count <> v_fresh_unresolved_count then
    raise exception 'a wrong or uncertain concept has no fresh source original';
  end if;

  if pg_catalog.cardinality(v_target_concepts) <> v_question_count
     or pg_catalog.cardinality(v_target_skills) <> v_question_count
     or pg_catalog.cardinality(v_target_labels) <> v_question_count then
    raise exception 'personalized next-day source capacity is insufficient';
  end if;

  select array_agg(skill.skill_id order by skill.first_position)
  into v_skill_ids
  from (
    select target.skill_id, min(target.position)::integer as first_position
    from pg_catalog.unnest(v_target_skills)
      with ordinality as target(skill_id, position)
    group by target.skill_id
  ) skill;

  if exists (
    select 1
    from pg_catalog.unnest(v_target_concepts)
      with ordinality as target(concept_key, position)
    where not target.concept_key like v_target_skills[target.position] || '__%'
  ) then
    raise exception 'personalized concept-to-skill mapping is invalid';
  end if;

  -- The capacity calendar owns the suffix budget. Do not update tomorrow in
  -- isolation: atomically anchor tomorrow and re-budget every still-unstarted
  -- plan through 2026-09-29 so each occurrence remains funded by a different
  -- original. Dynamic SQL lets this catalog migration land before the
  -- companion capacity migration creates the private helper.
  if pg_catalog.to_regprocedure(
    'app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])'
  ) is null then
    raise exception 'capacity suffix rebudget helper is not installed';
  end if;

  execute
    'select app_private.chem_rebudget_unstarted_review_suffix($1,$2,$3)'
    into strict v_rebudget_result
    using p_student_id, v_next_plan.id, v_target_concepts;

  if not coalesce((v_rebudget_result->>'ok')::boolean, false) then
    if coalesce(v_rebudget_result->>'reasonCode', '') in (
      'suffix_contains_started_plan',
      'suffix_contains_answer_lock'
    ) then
      if nullif(v_rebudget_result->>'conflictPlanDate', '')::date = v_next_date then
        -- Tomorrow itself has already started, so its issued questions are
        -- immutable and no further personalization is required for this job.
        update app_private.review_plan_personalization_jobs
        set status = 'not_needed', last_error = null, updated_at = pg_catalog.now()
        where completed_plan_id = p_completed_plan_id;
      else
        -- A later suffix date was opened unexpectedly.  Do not silently call
        -- tomorrow personalized: retain a non-retryable teacher-visible block.
        update app_private.review_plan_personalization_jobs
        set status = 'blocked',
            last_error = pg_catalog.left(
              coalesce(v_rebudget_result->>'reasonCode', 'SUFFIX_REBUDGET_BLOCKED')
              || ': conflictPlanDate='
              || coalesce(v_rebudget_result->>'conflictPlanDate', 'unknown'),
              500
            ),
            updated_at = pg_catalog.now()
        where completed_plan_id = p_completed_plan_id;
      end if;
      return false;
    end if;

    update app_private.review_plan_personalization_jobs
    set last_error = pg_catalog.left(
          coalesce(v_rebudget_result->>'reasonCode', 'SUFFIX_REBUDGET_REJECTED')
          || case
               when nullif(v_rebudget_result->>'detail', '') is null then ''
               else ': ' || (v_rebudget_result->>'detail')
             end,
          500
        ),
        updated_at = pg_catalog.now()
    where completed_plan_id = p_completed_plan_id;
    return false;
  end if;

  select plan.*
  into v_next_plan
  from public.chem_learning_plans plan
  where plan.id = v_next_plan.id;

  if v_next_plan.question_count <> v_question_count
     or v_next_plan.round_limit <> 1
     or v_next_plan.target_concept_keys is distinct from v_target_concepts
     or v_next_plan.knowledge_summaries is distinct from v_target_labels
     or v_next_plan.skill_ids is distinct from v_skill_ids
  then
    raise exception 'capacity suffix rebudget persisted a mismatched next-day plan';
  end if;

  update app_private.review_plan_personalization_jobs
  set status = 'succeeded', last_error = null, updated_at = pg_catalog.now()
  where completed_plan_id = p_completed_plan_id;

  return true;
  exception when others then
    if p_completed_plan_id is not null
       and p_student_id is not null
       and exists (
         select 1
         from public.chem_learning_plans plan
         where plan.id = p_completed_plan_id
           and plan.student_id = p_student_id
           and plan.mode = 'REVIEW'
       )
    then
      insert into app_private.review_plan_personalization_jobs (
        completed_plan_id, student_id, evidence_completed_at, next_plan_date,
        status, attempt_count, last_error, updated_at
      ) values (
        p_completed_plan_id, p_student_id, v_evidence_completed_at,
        v_completed_plan_date + 1, 'pending', 1,
        pg_catalog.left(sqlerrm, 500), pg_catalog.now()
      )
      on conflict (completed_plan_id) do update set
        status = 'pending',
        attempt_count = app_private.review_plan_personalization_jobs.attempt_count + 1,
        last_error = excluded.last_error,
        evidence_completed_at = coalesce(
          excluded.evidence_completed_at,
          app_private.review_plan_personalization_jobs.evidence_completed_at
        ),
        next_plan_date = coalesce(
          excluded.next_plan_date,
          app_private.review_plan_personalization_jobs.next_plan_date
        ),
        updated_at = pg_catalog.now();
    end if;
    return false;
  end;
end;
$$;

revoke all on function public.chem_personalize_next_review_plan(uuid,uuid,timestamptz)
  from public, anon, authenticated;
grant execute on function public.chem_personalize_next_review_plan(uuid,uuid,timestamptz)
  to service_role;

comment on function public.chem_personalize_next_review_plan(uuid,uuid,timestamptz) is
  'Server-only: after a formal REVIEW completion, uses the persisted attempt time (never caller time), prioritizes wrong/uncertain fine concepts in the unstarted next-day plan, preserves a single <=8-question package and records retryable failures.';

create or replace function public.chem_enqueue_review_personalization(
  p_student_id uuid,
  p_completed_plan_id uuid
)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_plan_date date;
  v_completed_at timestamptz;
begin
  select plan.plan_date, evidence.completed_at
  into v_plan_date, v_completed_at
  from public.chem_learning_plans plan
  join public.chem_students_v2 student
    on student.id = plan.student_id
   and student.record_status = 'active'
   and student.grade_band in ('高一','高二','高三')
   and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
  join lateral (
    select attempt.completed_at
    from public.chem_learning_attempts attempt
    where attempt.student_id = p_student_id
      and attempt.plan_day_id = p_completed_plan_id
      and attempt.mode = 'REVIEW'
      and attempt.completed_at is not null
    order by attempt.completed_at desc, attempt.sequence desc, attempt.id desc
    limit 1
  ) evidence on true
  where plan.id = p_completed_plan_id
    and plan.student_id = p_student_id
    and plan.mode = 'REVIEW';

  if v_plan_date is null or v_completed_at is null then
    return false;
  end if;

  insert into app_private.review_plan_personalization_jobs (
    completed_plan_id, student_id, evidence_completed_at, next_plan_date,
    status, attempt_count, last_error, updated_at
  ) values (
    p_completed_plan_id, p_student_id, v_completed_at, v_plan_date + 1,
    case
      when v_plan_date + 1 > date '2026-09-29' then 'not_needed'
      else 'pending'
    end,
    0, null, pg_catalog.now()
  )
  on conflict (completed_plan_id) do update set
    student_id = excluded.student_id,
    evidence_completed_at = excluded.evidence_completed_at,
    next_plan_date = excluded.next_plan_date,
    status = case
      when excluded.status = 'not_needed' then 'not_needed'
      when app_private.review_plan_personalization_jobs.status = 'succeeded'
        then 'succeeded'
      else 'pending'
    end,
    last_error = case
      when excluded.status = 'not_needed' then null
      when app_private.review_plan_personalization_jobs.status = 'succeeded'
        then null
      else app_private.review_plan_personalization_jobs.last_error
    end,
    updated_at = pg_catalog.now();

  return true;
end;
$$;

revoke all on function public.chem_enqueue_review_personalization(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.chem_enqueue_review_personalization(uuid,uuid)
  to service_role;

create or replace function public.chem_reconcile_missing_review_personalization_jobs()
returns integer
language sql
volatile
security invoker
set search_path = ''
as $$
  with eligible as (
    select
      completed_plan.id as completed_plan_id,
      completed_plan.student_id,
      max(attempt.completed_at) as evidence_completed_at,
      completed_plan.plan_date + 1 as next_plan_date
    from public.chem_learning_plans completed_plan
    join public.chem_students_v2 student
      on student.id = completed_plan.student_id
     and student.record_status = 'active'
     and student.grade_band in ('高一','高二','高三')
     and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
    join public.chem_learning_attempts attempt
      on attempt.plan_day_id = completed_plan.id
     and attempt.student_id = completed_plan.student_id
     and attempt.mode = 'REVIEW'
     and attempt.completed_at is not null
    where completed_plan.mode = 'REVIEW'
      -- Reconcile only the new single-package calendar. Importing historical
      -- five-round completions would create a large, unactionable queue.
      and completed_plan.plan_date >= date '2026-08-23'
      and completed_plan.plan_date < date '2026-09-29'
      and exists (
        select 1
        from public.chem_learning_plans next_plan
        where next_plan.student_id = completed_plan.student_id
          and next_plan.mode = 'REVIEW'
          and next_plan.plan_date = completed_plan.plan_date + 1
          and not exists (
            select 1
            from public.chem_learning_attempts next_attempt
            where next_attempt.plan_day_id = next_plan.id
          )
          and not exists (
            select 1
            from app_private.chem_question_answer_locks next_lock
            where next_lock.student_id = completed_plan.student_id
              and next_lock.plan_day_id = next_plan.id
          )
      )
      and not exists (
        select 1
        from app_private.review_plan_personalization_jobs existing_job
        where existing_job.completed_plan_id = completed_plan.id
      )
    group by
      completed_plan.id,
      completed_plan.student_id,
      completed_plan.plan_date,
      completed_plan.round_limit
    having count(distinct attempt.sequence) >= completed_plan.round_limit
  ), inserted as (
    insert into app_private.review_plan_personalization_jobs (
      completed_plan_id, student_id, evidence_completed_at, next_plan_date,
      status, attempt_count, last_error, updated_at
    )
    select
      eligible.completed_plan_id,
      eligible.student_id,
      eligible.evidence_completed_at,
      eligible.next_plan_date,
      'pending',
      0,
      null,
      pg_catalog.now()
    from eligible
    on conflict (completed_plan_id) do nothing
    returning 1
  )
  select count(*)::integer from inserted;
$$;

revoke all on function public.chem_reconcile_missing_review_personalization_jobs()
  from public, anon, authenticated;
grant execute on function public.chem_reconcile_missing_review_personalization_jobs()
  to service_role;

create or replace function public.chem_retry_pending_review_personalization(
  p_limit integer default 25
)
returns table(
  completed_plan_id uuid,
  student_id uuid,
  succeeded boolean,
  status text,
  last_error text
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_job record;
  v_success boolean;
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'retry limit must be between 1 and 100';
  end if;

  for v_job in
    select job.completed_plan_id, job.student_id, job.evidence_completed_at
    from app_private.review_plan_personalization_jobs job
    where job.status = 'pending'
      and job.updated_at <= pg_catalog.now() - interval '5 minutes'
      and job.attempt_count < 5
    order by job.updated_at, job.completed_plan_id
    limit p_limit
    for update skip locked
  loop
    v_success := public.chem_personalize_next_review_plan(
      v_job.student_id,
      v_job.completed_plan_id,
      v_job.evidence_completed_at
    );

    return query
    select
      job.completed_plan_id,
      job.student_id,
      v_success,
      job.status,
      job.last_error
    from app_private.review_plan_personalization_jobs job
    where job.completed_plan_id = v_job.completed_plan_id;
  end loop;
end;
$$;

revoke all on function public.chem_retry_pending_review_personalization(integer)
  from public, anon, authenticated;
grant execute on function public.chem_retry_pending_review_personalization(integer)
  to service_role;

create or replace function public.chem_review_personalization_job_rows()
returns table(
  completed_plan_id uuid,
  student_id uuid,
  evidence_completed_at timestamptz,
  next_plan_date date,
  status text,
  attempt_count integer,
  last_error text,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    job.completed_plan_id,
    job.student_id,
    job.evidence_completed_at,
    job.next_plan_date,
    job.status,
    job.attempt_count,
    job.last_error,
    job.updated_at
  from app_private.review_plan_personalization_jobs job
  order by
    case job.status when 'blocked' then 0 when 'pending' then 1 when 'not_needed' then 2 else 3 end,
    job.updated_at desc;
$$;

revoke all on function public.chem_review_personalization_job_rows()
  from public, anon, authenticated;
grant execute on function public.chem_review_personalization_job_rows()
  to service_role;

do $$
declare
  v_bad integer;
begin
  -- Final plan assertions run after the companion capacity migration. This
  -- migration owns the catalog, constraints and server-only RPCs only.
  return;
  select count(*) into v_bad
  from public.chem_learning_plans plan
  join public.chem_students_v2 student on student.id = plan.student_id
  where student.record_status = 'active'
    and student.grade_band in ('高一','高二','高三')
    and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
    and plan.mode = 'REVIEW'
    and plan.plan_date >= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and (
      plan.question_count not between 1 and 8
      or (
        not exists (
          select 1 from public.chem_learning_attempts attempt
          where attempt.plan_day_id = plan.id
        )
        and not exists (
          select 1 from app_private.chem_question_answer_locks answer_lock
          where answer_lock.plan_day_id = plan.id
        )
        and plan.round_limit <> 1
      )
    );
  if v_bad <> 0 then
    raise exception 'formal future REVIEW daily-package contract failed for % plans', v_bad;
  end if;

  select count(*) into v_bad
  from (
    select plan.student_id, plan.plan_date
    from public.chem_learning_plans plan
    join public.chem_students_v2 student on student.id = plan.student_id
    where student.record_status = 'active'
      and student.grade_band in ('高一','高二','高三')
      and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
      and plan.mode = 'REVIEW'
      and plan.plan_date >= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    group by plan.student_id, plan.plan_date
    having count(*) <> 1
  ) duplicate_day;
  if v_bad <> 0 then
    raise exception 'formal REVIEW must contain exactly one plan per student/date';
  end if;

  select count(*) into v_bad
  from public.chem_learning_plans plan
  join public.chem_students_v2 student on student.id = plan.student_id
  where student.record_status = 'active'
    and student.grade_band in ('高一','高二','高三')
    and coalesce(student.metadata->'demo', 'false'::jsonb) <> 'true'::jsonb
    and plan.mode = 'REVIEW'
    and plan.plan_date >= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and not exists (
      select 1 from public.chem_learning_attempts attempt
      where attempt.plan_day_id = plan.id
    )
    and not exists (
      select 1 from app_private.chem_question_answer_locks answer_lock
      where answer_lock.plan_day_id = plan.id
    )
    and (
      cardinality(plan.target_concept_keys) <> plan.question_count
      or cardinality(plan.knowledge_summaries) <> plan.question_count
      or cardinality(plan.skill_ids) not between 1 and plan.question_count
      or (
        select count(distinct listed.skill_id)
        from pg_catalog.unnest(plan.skill_ids) listed(skill_id)
      ) <> cardinality(plan.skill_ids)
      or exists (
        select 1
        from pg_catalog.unnest(plan.target_concept_keys)
          with ordinality as target(concept_key, position)
        left join app_private.chem_review_concept_catalog catalog
          on catalog.grade_band = student.grade_band
         and catalog.concept_key = target.concept_key
        where catalog.concept_key is null
           or catalog.concept_label <> plan.knowledge_summaries[target.position]
           or not (catalog.skill_id = any(plan.skill_ids))
      )
      or exists (
        select 1
        from pg_catalog.unnest(plan.skill_ids) listed(skill_id)
        where not exists (
          select 1
          from pg_catalog.unnest(plan.target_concept_keys) target(concept_key)
          join app_private.chem_review_concept_catalog catalog
            on catalog.concept_key = target.concept_key
          where catalog.skill_id = listed.skill_id
        )
      )
    );
  if v_bad <> 0 then
    raise exception 'formal future REVIEW target/label/skill alignment failed for % plans', v_bad;
  end if;

  select count(*) into v_bad
  from _protected_started_review_plan before
  left join public.chem_learning_plans plan on plan.id = before.id
  where plan.id is null
    or plan.student_id is distinct from before.student_id
    or plan.plan_date is distinct from before.plan_date
    or plan.mode is distinct from before.mode
    or plan.title is distinct from before.title
    or plan.question_count is distinct from before.question_count
    or plan.round_limit is distinct from before.round_limit
    or plan.skill_ids is distinct from before.skill_ids
    or plan.target_concept_keys is distinct from before.target_concept_keys
    or plan.knowledge_summaries is distinct from before.knowledge_summaries
    or plan.estimated_minutes is distinct from before.estimated_minutes
    or plan.source is distinct from before.source;
  if v_bad <> 0 then
    raise exception 'a started learning plan changed unexpectedly';
  end if;
end $$;

commit;
