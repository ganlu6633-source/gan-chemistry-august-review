begin;

-- A review day is a five-round closed loop. The first and later rounds each
-- contain five questions; later rounds are re-ranked from that day's evidence.
alter table public.chem_learning_plans
  add column if not exists question_count smallint not null default 5
    check (question_count between 1 and 10),
  add column if not exists round_limit smallint not null default 5
    check (round_limit between 1 and 8),
  add column if not exists max_question_level smallint
    check (max_question_level between 1 and 8);

comment on column public.chem_learning_plans.question_count is
  'Number of questions served in each adaptive round.';
comment on column public.chem_learning_plans.round_limit is
  'Maximum rounds for this plan day. Review plans use five same-day rounds.';
comment on column public.chem_learning_plans.max_question_level is
  'Optional ceiling used to keep a cohort inside its taught depth.';

-- Gas molar volume must be independent from the broad H1_MOLE card, because
-- the latter also contains concentration, solution preparation and reaction
-- stoichiometry that the five current high-one students have not learned yet.
insert into public.chem_skills(
  id,title,module_id,grade_band,max_level,exam_importance,exam_depth,
  prerequisites,level_criteria,active,updated_at
) values (
  'H1_GAS_MOLAR_VOLUME',
  '气体摩尔体积基础',
  'H1-F05B',
  '高一',
  4,
  5,
  3,
  array['H1_MOLE_INTRO']::text[],
  '[
    {"level":1,"studentFacingGoal":"知道气体摩尔体积的对象和标准状况条件","requiredAbility":"能先检查气体与标准状况两个条件"},
    {"level":2,"studentFacingGoal":"能用V=nVₘ完成一步换算","requiredAbility":"能在V、n和Vₘ之间正确换算并带单位"},
    {"level":3,"studentFacingGoal":"能把气体体积与微粒数、质量接起来","requiredAbility":"能沿V→n→N或V→n→m完成两步换算"},
    {"level":4,"studentFacingGoal":"能在同温同压比较气体体积","requiredAbility":"能用同温同压下体积比等于物质的量比解释比较"}
  ]'::jsonb,
  true,
  now()
)
on conflict (id) do update set
  title=excluded.title,
  module_id=excluded.module_id,
  grade_band=excluded.grade_band,
  max_level=excluded.max_level,
  exam_importance=excluded.exam_importance,
  exam_depth=excluded.exam_depth,
  prerequisites=excluded.prerequisites,
  level_criteria=excluded.level_criteria,
  active=true,
  updated_at=now();

insert into public.chem_knowledge_cards(
  id,skill_id,title,core,detail,steps,common_mistakes,micro_example,
  asset,review_status,structured_content,updated_at
) values (
  'KC_H1_GAS_MOLAR_VOLUME_ZERO',
  'H1_GAS_MOLAR_VOLUME',
  '气体摩尔体积：先查条件，再走V—n这座桥',
  '气体摩尔体积表示一定温度和压强下，1 mol气体所占的体积；标准状况下约为22.4 L·mol⁻¹。',
  '先确认研究对象在题给条件下是气体，再确认温度和压强。只有标准状况下，才可直接使用Vₘ≈22.4 L·mol⁻¹；其他条件优先使用题目给出的Vₘ。',
  '["圈出温度、压强和物态","确认是否为标准状况下的气体","用n=V/Vₘ或V=nVₘ","需要时再由n连接N或m","最后检查L与mol的单位"]'::jsonb,
  '["把1 mol任何物质都说成22.4 L","在25 ℃下机械套22.4 L·mol⁻¹","忘记标准状况下水是液体","把气体分子数和原子数混为一谈"]'::jsonb,
  '标准状况下11.2 L O₂的物质的量为11.2÷22.4=0.5 mol，因此含0.5N_A个O₂分子、1.0N_A个O原子。',
  '{"type":"diagram","alt":"气体体积、物质的量、微粒数和质量换算网络"}'::jsonb,
  'approved',
  $gas_card${
    "skillId":"H1_GAS_MOLAR_VOLUME",
    "version":1,
    "intro":"把气体体积题看成一条有闸门的路：先过‘气体’和‘条件’两道门，再从V走到n，最后才连接微粒数或质量。",
    "overview":[
      "Vₘ是1 mol气体在一定温度和压强下所占的体积，不是永远等于22.4。",
      "标准状况指0 ℃、101 kPa；此时气体的Vₘ约为22.4 L·mol⁻¹。",
      "所有换算先回到n：V÷Vₘ得到n，再由n连接N或m。",
      "本卡不使用物质的量浓度、溶液配制、理想气体方程或反应计量。"
    ],
    "visualSummary":{
      "kind":"network",
      "title":"气体体积换算总图",
      "center":"物质的量 n",
      "groups":[
        {"label":"先过条件门","items":["题给物质是气体","标准状况0 ℃、101 kPa"]},
        {"label":"体积通道","items":["V÷Vₘ→n","n×Vₘ→V","标况Vₘ≈22.4 L·mol⁻¹"]},
        {"label":"已学连接","items":["n×N_A→微粒数N","n×M→质量m"]}
      ]
    },
    "sections":[
      {
        "title":"第一道门：研究对象必须是气体",
        "summary":"先看物态，再看数值。",
        "items":[
          {"label":"只对气体使用","rule":"气体摩尔体积描述的是气体；同一物质在不同条件下物态可能不同。","examples":["【示范：标准状况下的水】标准状况下H₂O是液体，不能用22.4 L·mol⁻¹求1 mol水的体积。"],"visualSteps":["看物质","看题给条件","判断物态","气体才进入Vₘ通道"]},
          {"label":"1 mol任何微粒不等于22.4 L","rule":"1 mol只规定微粒数；只有气体在确定温度和压强下才谈相应体积。","examples":["【示范：1 mol NaCl与1 mol O₂】两者微粒数都与N_A相关，但固体NaCl不能套气体摩尔体积，标准状况下O₂可以。"],"visualSteps":["先认1 mol","区分微粒数","区分物态","决定能否用Vₘ"]},
          {"label":"混合气体仍先数总n","rule":"若题目只问同温同压下的总体积，可先求各气体物质的量之和；本阶段不做复杂混合气体组成计算。","examples":["【示范：1 mol N₂与1 mol O₂】标准状况下总物质的量2 mol，总体积约44.8 L。"],"visualSteps":["分别求n","相加得总n","同一条件","乘Vₘ得总体积"]}
        ]
      },
      {
        "title":"第二道门：22.4必须带着标准状况",
        "summary":"数值和条件要成套出现。",
        "items":[
          {"label":"标准状况","rule":"高中常用标准状况为0 ℃、101 kPa；此时气体摩尔体积约为22.4 L·mol⁻¹。","examples":["【示范：标况2 mol N₂】V=2 mol×22.4 L·mol⁻¹=44.8 L。"],"visualSteps":["0 ℃","101 kPa","确认气体","使用22.4"]},
          {"label":"非标准状况不硬套","rule":"温度或压强不满足标准状况时，不能机械使用22.4；若题目给出该条件下Vₘ，就用题给值。","examples":["【示范：25 ℃的气体】题目没有给25 ℃下Vₘ时，不能自行用22.4替代。"],"visualSteps":["圈温度压强","发现非标况","寻找题给Vₘ","没有数据就不硬算"]},
          {"label":"近似值要保留约号意识","rule":"22.4 L·mol⁻¹是中学常用近似值，答案精度按题目给定数据处理。","examples":["【示范：标况0.5 mol O₂】体积约为11.2 L，不把近似模型写成在所有条件下绝对精确。"],"visualSteps":["识别近似","按题给精度","完成计算","检查单位"]}
        ]
      },
      {
        "title":"V—n—N—m换算网络",
        "summary":"任何两步题都先在n这个中心站换乘。",
        "items":[
          {"label":"V与n互换","rule":"n=V/Vₘ，V=nVₘ；V常用L，Vₘ常用L·mol⁻¹，单位要配套。","examples":["【示范：标况11.2 L O₂】n=11.2÷22.4=0.5 mol。"],"visualSteps":["读V","除Vₘ","得到n","标mol"]},
          {"label":"V连接微粒数","rule":"先由V求n，再用N=nN_A；若问原子数，还要乘化学式下标。","examples":["【示范：标况11.2 L O₂含多少O原子】0.5 mol O₂含1.0 mol O原子，所以O原子数为N_A。"],"visualSteps":["V÷Vₘ","得O₂的n","乘下标2","乘N_A"]},
          {"label":"V连接质量","rule":"先由V求n，再用m=nM；不能把体积数值直接与摩尔质量相乘。","examples":["【示范：标况22.4 L CO₂的质量】n=1 mol，m=1×44=44 g。"],"visualSteps":["V÷Vₘ","得n","写摩尔质量M","m=nM"]}
        ]
      }
    ],
    "workedExamples":[
      {"substance":"标准状况下11.2 L O₂","path":"先确认O₂在标准状况下是气体；n=11.2/22.4=0.5 mol；O₂分子数为0.5N_A，O原子数还要乘2，等于N_A。","labels":["查气体","查标况","V→n","分子→原子"]},
      {"substance":"标准状况下22.4 L CO₂","path":"体积对应1 mol CO₂；分子数为N_A，质量为1 mol×44 g·mol⁻¹=44 g。整个过程都在n这个中心站换乘。","labels":["V→n","n→N","n→m","单位检查"]}
    ],
    "checkpoints":[
      "我会先检查气体和标准状况两个条件。",
      "我能用n=V/Vₘ和V=nVₘ做一步换算。",
      "我能从气体体积继续求分子数、原子数或质量。",
      "我不会把22.4 L·mol⁻¹用于液体、固体或任意温压。"
    ],
    "scopeNote":"只覆盖已讲的气体摩尔体积基础及与n、N、m的连接；不进入物质的量浓度、配液误差、理想气体方程、混合气体综合或反应计量。",
    "sourceBasis":"依据福建高中化学范围与苏教版必修第一册物质的量基础，按当前课堂进度收窄。"
  }$gas_card$::jsonb,
  now()
)
on conflict (id) do update set
  skill_id=excluded.skill_id,
  title=excluded.title,
  core=excluded.core,
  detail=excluded.detail,
  steps=excluded.steps,
  common_mistakes=excluded.common_mistakes,
  micro_example=excluded.micro_example,
  asset=excluded.asset,
  review_status='approved',
  structured_content=excluded.structured_content,
  updated_at=now();

-- Keep the classification card inside the three students' taught boundary.
-- The reaction-form/redox crossover is taught from H1_REDOX, not here.
update public.chem_knowledge_cards k
set structured_content = jsonb_set(
      jsonb_set(
        jsonb_set(
          k.structured_content,
          '{overview}',
          '[
            "先按样品含几种物质分成纯净物和混合物；这是整棵树的第一刀。",
            "纯净物再按元素种类分成单质和化合物；混合物不能直接进入这条分支。",
            "无机化合物继续分为氧化物、酸、碱、盐；每一类都有独立判断标准。",
            "酸和碱的元数、强弱、含氧与否或溶解性是可以交叉的独立分类轴。",
            "电解质与非电解质是只针对化合物的横向分类线，不能用能否导电直接替代。"
          ]'::jsonb,
          true
        ),
        '{sections}',
        coalesce((
          select jsonb_agg(section_value order by section_order)
          from jsonb_array_elements(k.structured_content->'sections') with ordinality as section(section_value,section_order)
          where section_value->>'title' <> '四类基本反应与横向分类'
        ), '[]'::jsonb),
        true
      ),
      '{workedExamples}',
      coalesce((
        select jsonb_agg(example_value order by example_order)
        from jsonb_array_elements(coalesce(k.structured_content->'workedExamples','[]'::jsonb)) with ordinality as example(example_value,example_order)
        where example_value->>'substance' <> '反应分类双通道'
      ), '[]'::jsonb),
      true
    ),
    updated_at = now()
where k.skill_id='H1_CLASSIFY'
  and k.review_status='approved';

update public.chem_knowledge_cards k
set structured_content = jsonb_set(
      k.structured_content,
      '{checkpoints}',
      coalesce((
        select jsonb_agg(checkpoint_value order by checkpoint_order)
        from jsonb_array_elements(coalesce(k.structured_content->'checkpoints','[]'::jsonb)) with ordinality as checkpoint(checkpoint_value,checkpoint_order)
        where checkpoint_value #>> '{}' not like '%氧化还原%'
      ), '[]'::jsonb),
      true
    ),
    updated_at = now()
where k.skill_id='H1_CLASSIFY'
  and k.review_status='approved';

update public.chem_knowledge_cards
set detail='本卡先稳住n、N、m、M四个量；已经学过的气体摩尔体积由下一张独立知识卡连接，溶液浓度和反应计量仍不提前。',
    structured_content=jsonb_set(
      structured_content,
      '{intro}',
      to_jsonb('物质的量是一座桥：先用n连接质量m和微粒数N；气体体积V会在独立卡中通过Vₘ接到同一个中心站。当前不进入溶液浓度或反应计量。'::text),
      true
    ),
    updated_at=now()
where skill_id='H1_MOLE_INTRO' and review_status='approved';

insert into public.chem_questions(
  id,mother_id,skill_id,level,grade_band,stem,options,correct_option,
  explanation,scaffold,review_status,scope_status,source_kind,image_url,
  usable_for_class_quiz,usable_for_review,usable_for_exam_sprint,updated_at
) values
('QGAS_ZERO_01','MGAS_ZERO_01','H1_GAS_MOLAR_VOLUME',1,'高一','标准状况下，气体摩尔体积约为','["22.4 L·mol⁻¹","22.4 mol·L⁻¹","6.02×10²³ L·mol⁻¹","1 L·mol⁻¹"]'::jsonb,0,'标准状况下，1 mol气体所占体积约为22.4 L，所以Vₘ≈22.4 L·mol⁻¹。','先同时确认“气体”和“标准状况”。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_ZERO_02','MGAS_ZERO_02','H1_GAS_MOLAR_VOLUME',1,'高一','标准状况下11.2 L O₂的物质的量约为','["0.25 mol","0.5 mol","1 mol","2 mol"]'::jsonb,1,'n=V/Vₘ=11.2÷22.4=0.5 mol。','先写n=V/Vₘ。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_01','MGAS_TF_01','H1_GAS_MOLAR_VOLUME',1,'高一','判断：标准状况下，1 mol任何物质的体积都约为22.4 L。','["正确","错误"]'::jsonb,1,'错误。22.4 L·mol⁻¹只适用于标准状况下的气体，不能用于固体或液体。','先问：题目对象一定是气体吗？','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_02','MGAS_TF_02','H1_GAS_MOLAR_VOLUME',1,'高一','判断：标准状况下，1 mol O₂的体积约为22.4 L。','["正确","错误"]'::jsonb,0,'正确。O₂在标准状况下是气体，可以使用V=nVₘ。',null,'approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_ZERO_03','MGAS_ZERO_03','H1_GAS_MOLAR_VOLUME',2,'高一','标准状况下44.8 L N₂所含N₂分子数约为','["0.5N_A","N_A","2N_A","4N_A"]'::jsonb,2,'44.8 L对应2 mol N₂，所以含2N_A个N₂分子。','先由V求n，再由n求N。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_ZERO_04','MGAS_ZERO_04','H1_GAS_MOLAR_VOLUME',2,'高一','标准状况下8 g CH₄的体积约为（M(CH₄)=16 g·mol⁻¹）','["5.6 L","11.2 L","22.4 L","44.8 L"]'::jsonb,1,'n=m/M=8÷16=0.5 mol，再用V=nVₘ=0.5×22.4=11.2 L。','按m→n→V两步走。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_03','MGAS_TF_03','H1_GAS_MOLAR_VOLUME',2,'高一','判断：25 ℃、101 kPa时，1 mol任何气体都必须按22.4 L计算。','["正确","错误"]'::jsonb,1,'错误。25 ℃不是标准状况，不能机械套用标准状况下的22.4 L·mol⁻¹。','检查温度是否为0 ℃。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_04','MGAS_TF_04','H1_GAS_MOLAR_VOLUME',2,'高一','判断：非标准状况下，若题目给出该条件的气体摩尔体积，应使用题给值。','["正确","错误"]'::jsonb,0,'正确。Vₘ随温度和压强改变，非标准状况优先使用题目给出的Vₘ。',null,'approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_05','MGAS_TF_05','H1_GAS_MOLAR_VOLUME',2,'高一','判断：同温同压下，等物质的量的两种气体体积相等。','["正确","错误"]'::jsonb,0,'正确。同温同压下两种气体的Vₘ相同，因此物质的量相等时体积相等。',null,'approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_ZERO_05','MGAS_ZERO_05','H1_GAS_MOLAR_VOLUME',3,'高一','标准状况下2.24 L CO₂中氧原子数约为','["0.05N_A","0.1N_A","0.2N_A","2N_A"]'::jsonb,2,'2.24 L CO₂为0.1 mol CO₂；每个CO₂含2个O原子，所以氧原子为0.2 mol，即0.2N_A个。','V→CO₂的n→O原子的n→N。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_ZERO_06','MGAS_ZERO_06','H1_GAS_MOLAR_VOLUME',3,'高一','标准状况下含3.01×10²³个H₂分子的气体体积约为','["5.6 L","11.2 L","22.4 L","44.8 L"]'::jsonb,1,'3.01×10²³个H₂分子约为0.5 mol，体积约0.5×22.4=11.2 L。','N→n→V。','approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_06','MGAS_TF_06','H1_GAS_MOLAR_VOLUME',3,'高一','判断：标准状况下22.4 L H₂和22.4 L O₂所含分子数相同。','["正确","错误"]'::jsonb,0,'正确。两者都为1 mol气体，所以都含N_A个分子；分子种类不同不影响分子个数。',null,'approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_07','MGAS_TF_07','H1_GAS_MOLAR_VOLUME',3,'高一','判断：标准状况下22.4 L CO₂的质量为44 g。','["正确","错误"]'::jsonb,0,'正确。22.4 L CO₂约为1 mol，CO₂的摩尔质量为44 g·mol⁻¹，所以质量为44 g。',null,'approved','IN','teacher_original',null,false,true,true,now()),
('QGAS_TF_08','MGAS_TF_08','H1_GAS_MOLAR_VOLUME',3,'高一','判断：标准状况下11.2 L O₂含0.5N_A个氧原子。','["正确","错误"]'::jsonb,1,'错误。11.2 L O₂是0.5 mol O₂分子，但每个O₂含2个O原子，因此氧原子数为N_A。','别忘记O₂的下标2。','approved','IN','teacher_original',null,false,true,true,now())
on conflict (id) do update set
  mother_id=excluded.mother_id,
  skill_id=excluded.skill_id,
  level=excluded.level,
  grade_band=excluded.grade_band,
  stem=excluded.stem,
  options=excluded.options,
  correct_option=excluded.correct_option,
  explanation=excluded.explanation,
  scaffold=excluded.scaffold,
  review_status='approved',
  scope_status='IN',
  source_kind=excluded.source_kind,
  image_url=excluded.image_url,
  usable_for_class_quiz=false,
  usable_for_review=true,
  usable_for_exam_sprint=true,
  updated_at=now();

create temporary table target_current_high1_students(
  id uuid primary key,
  redox_every_day boolean not null
) on commit drop;

-- Select the whole teacher-approved current-high-one cohort. The two profiles
-- with extra redox instruction are matched by a one-way hash so no student
-- name or internal profile UUID is published in this public source file.
insert into target_current_high1_students(id,redox_every_day)
select
  s.id,
  encode(extensions.digest(s.id::text,'sha256'),'hex') in (
    '3d891e2a95488c044a5210163872d9bb24419bfff6e10db6a1721050f6904ae6',
    'e77669d1f17b1f06a54a7e12161a24fc0dbc8af5eb10b2afee50cc30787a1400'
  )
from public.chem_students_v2 s
where s.grade_band='高一'
  and s.record_status='active'
  and s.metadata->>'curriculumCohort'='high1_current';

do $$
begin
  if (select count(*) from target_current_high1_students)<>5
     or (select count(*) from target_current_high1_students where redox_every_day)<>2 then
    raise exception 'The five current high-one profiles no longer match the teacher-approved roster';
  end if;
end $$;

create temporary table high_school_review_order on commit drop as
select
  p.id as plan_id,
  p.student_id,
  s.grade_band,
  coalesce(s.metadata->>'curriculumCohort','') as cohort,
  (row_number() over(partition by p.student_id order by p.plan_date,p.id)-1)::integer as day_index
from public.chem_learning_plans p
join public.chem_students_v2 s on s.id=p.student_id
where p.mode='REVIEW'
  and s.record_status='active'
  and s.grade_band in ('高一','高二','高三');

do $$
begin
  if exists (
    select 1
    from (
      select student_id,count(*) plans,min(day_index) first_index,max(day_index) last_index
      from high_school_review_order
      group by student_id
    ) x
    where x.plans<>40 or x.first_index<>0 or x.last_index<>39
  ) then
    raise exception 'Every active high-school profile must have exactly 40 ordered REVIEW days before rescheduling';
  end if;
  if exists (
    select 1
    from public.chem_learning_attempts a
    join high_school_review_order o on o.plan_id=a.plan_day_id
    join public.chem_students_v2 s on s.id=o.student_id
    where coalesce((s.metadata->>'demo')::boolean,false) is not true
  ) then
    raise exception 'A non-demo high-school REVIEW plan already has attempts; preserve history before rescheduling';
  end if;
end $$;

-- Move all active high-school review calendars to one shared day one. A fixed
-- staging window prevents transient unique-key collisions during the move.
update public.chem_learning_plans p
set plan_date=date '2027-08-17'+o.day_index
from high_school_review_order o
where p.id=o.plan_id;

update public.chem_learning_plans p
set plan_date=date '2026-08-17'+o.day_index,
    question_count=5,
    round_limit=5,
    estimated_minutes=35,
    max_question_level=case
      when o.grade_band='高一' and o.cohort='high1_current' then 3
      when o.grade_band='高一' then 4
      else null
    end
from high_school_review_order o
where p.id=o.plan_id;

update public.chem_students_v2 s
set metadata=jsonb_set(coalesce(s.metadata,'{}'::jsonb),'{reviewStartDate}','"2026-08-17"'::jsonb,true),
    updated_at=now()
where s.record_status='active'
  and s.grade_band in ('高一','高二','高三');

-- The completed high-one cohort remains inside the teacher-confirmed four
-- modules. Do not infer electrolyte, gas volume or later chapters for them.
update public.chem_students_v2 s
set metadata=jsonb_set(
      s.metadata,
      '{confirmedLearnedSkillIds}',
      '["H1_CLASSIFY","H1_PERIODIC","H1_MOLE_INTRO","H1_REDOX"]'::jsonb,
      true
    ),
    updated_at=now()
where s.grade_band='高一'
  and s.metadata->>'curriculumCohort'='high1_completed';

update public.chem_students_v2 s
set metadata=jsonb_set(
      s.metadata,
      '{confirmedLearnedSkillIds}',
      case when t.redox_every_day
        then '["H1_CLASSIFY","H1_PERIODIC","H1_MOLE_INTRO","H1_GAS_MOLAR_VOLUME","H1_REDOX"]'::jsonb
        else '["H1_CLASSIFY","H1_PERIODIC","H1_MOLE_INTRO","H1_GAS_MOLAR_VOLUME"]'::jsonb
      end,
      true
    ),
    updated_at=now()
from target_current_high1_students t
where s.id=t.id;

-- Rebuild only the five current high-one plan descriptions. For the two
-- redox-approved profiles H1_REDOX is present every day; the other three
-- students never receive it.
update public.chem_learning_plans p
set title = case mod(o.day_index,7)
      when 0 then case when t.redox_every_day then '氧化还原每日回收＋物质分类' else '物质分类：从总树开始' end
      when 1 then case when t.redox_every_day then '氧化还原每日回收＋元素周期律' else '元素周期律：位置—结构—性质' end
      when 2 then case when t.redox_every_day then '氧化还原每日回收＋物质的量' else '物质的量与阿伏加德罗常数' end
      when 3 then case when t.redox_every_day then '氧化还原每日回收＋气体摩尔体积' else '气体摩尔体积：条件与换算' end
      when 4 then case when t.redox_every_day then '氧化还原每日回收＋分类与周期律' else '分类与周期律连接' end
      when 5 then case when t.redox_every_day then '氧化还原每日回收＋n—N—m—V' else 'n—N—m—V换算网络' end
      else case when t.redox_every_day then '本周五条主线综合回收' else '本周四条已学主线综合回收' end
    end,
    skill_ids = case mod(o.day_index,7)
      when 0 then case when t.redox_every_day then array['H1_REDOX','H1_CLASSIFY'] else array['H1_CLASSIFY'] end
      when 1 then case when t.redox_every_day then array['H1_REDOX','H1_PERIODIC'] else array['H1_PERIODIC'] end
      when 2 then case when t.redox_every_day then array['H1_REDOX','H1_MOLE_INTRO'] else array['H1_MOLE_INTRO'] end
      when 3 then case when t.redox_every_day then array['H1_REDOX','H1_GAS_MOLAR_VOLUME'] else array['H1_GAS_MOLAR_VOLUME'] end
      when 4 then case when t.redox_every_day then array['H1_REDOX','H1_CLASSIFY','H1_PERIODIC'] else array['H1_CLASSIFY','H1_PERIODIC'] end
      when 5 then case when t.redox_every_day then array['H1_REDOX','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME'] else array['H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME'] end
      else case when t.redox_every_day
        then array['H1_REDOX','H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME']
        else array['H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME']
      end
    end,
    knowledge_summaries = case mod(o.day_index,7)
      when 0 then case when t.redox_every_day
        then array['化合价升降与电子得失','纯净物—混合物—单质—化合物分类树','酸、碱、盐、氧化物边界']
        else array['纯净物—混合物—单质—化合物分类树','酸、碱、盐、氧化物边界','分散系与交叉分类'] end
      when 1 then case when t.redox_every_day
        then array['标价—升降—电子守恒','位置—结构—性质','最高价水化物酸碱性与气态氢化物稳定性']
        else array['位置—结构—性质','同周期与同主族递变','最高价水化物酸碱性与气态氢化物稳定性'] end
      when 2 then case when t.redox_every_day
        then array['氧化剂与还原剂身份','微粒对象与1 mol','N=nN_A与m=nM']
        else array['微粒对象与1 mol','阿伏加德罗常数','N=nN_A与m=nM'] end
      when 3 then case when t.redox_every_day
        then array['化合价升降与电子得失','气体与标准状况两道条件门','V=nVₘ']
        else array['气体与标准状况两道条件门','Vₘ≈22.4 L·mol⁻¹的适用边界','V=nVₘ'] end
      when 4 then case when t.redox_every_day
        then array['氧化还原概念链','分类树与横向标签','周期递变的证据链']
        else array['分类树与横向标签','周期递变的因果链','最高价水化物与氢化物规律'] end
      when 5 then case when t.redox_every_day
        then array['电子守恒基础','n连接N、m和V','单位与条件检查']
        else array['n连接N、m和V','标准状况与气体条件','单位和微粒对象检查'] end
      else case when t.redox_every_day
        then array['分类','周期律','物质的量与气体摩尔体积','氧化还原','当天错因回收']
        else array['分类','周期律','物质的量与气体摩尔体积','当天错因回收'] end
    end,
    estimated_minutes=35,
    source='course',
    question_count=5,
    round_limit=5,
    max_question_level=3
from high_school_review_order o
join target_current_high1_students t on t.id=o.student_id
where p.id=o.plan_id;

do $$
begin
  if exists (
    select 1
    from high_school_review_order o
    join public.chem_learning_plans p on p.id=o.plan_id
    where p.plan_date<>date '2026-08-17'+o.day_index
       or p.question_count<>5
       or p.round_limit<>5
  ) then
    raise exception 'High-school review start date or five-round configuration verification failed';
  end if;

  if exists (
    select 1
    from target_current_high1_students t
    join public.chem_learning_plans p on p.student_id=t.id and p.mode='REVIEW'
    where p.skill_ids && array['H1_ELECTROLYTE_INTRO','H1_ELECTROLYTE','H1_MOLE','H1_NACL']::text[]
       or (not t.redox_every_day and 'H1_REDOX'=any(p.skill_ids))
       or (t.redox_every_day and not ('H1_REDOX'=any(p.skill_ids)))
  ) then
    raise exception 'Current high-one taught-scope isolation failed';
  end if;

  if exists (
    select 1
    from target_current_high1_students t
    left join lateral (
      select count(*) days,
             count(*) filter(where 'H1_GAS_MOLAR_VOLUME'=any(p.skill_ids)) gas_days,
             min(p.plan_date) first_day,
             max(p.plan_date) last_day
      from public.chem_learning_plans p
      where p.student_id=t.id and p.mode='REVIEW'
    ) x on true
    where x.days<>40 or x.gas_days<5
       or x.first_day<>date '2026-08-17' or x.last_day<>date '2026-09-25'
  ) then
    raise exception 'Current high-one 40-day daily coverage verification failed';
  end if;

  if (select count(*) from public.chem_questions
      where skill_id='H1_GAS_MOLAR_VOLUME' and review_status='approved'
        and scope_status='IN' and usable_for_review and not usable_for_class_quiz) < 14 then
    raise exception 'Gas molar volume review pool is incomplete';
  end if;

  if exists (
    select 1
    from target_current_high1_students t
    join public.chem_learning_plans p on p.student_id=t.id and p.mode='REVIEW'
    where (
      select count(*)
      from public.chem_questions q
      where q.grade_band='高一'
        and q.skill_id=any(p.skill_ids)
        and q.level<=p.max_question_level
        and q.review_status='approved'
        and q.scope_status='IN'
        and q.usable_for_review
    ) < p.question_count
  ) then
    raise exception 'At least one current high-one day cannot supply five in-scope questions';
  end if;

  if exists (
    select 1
    from high_school_review_order o
    join public.chem_learning_plans p on p.id=o.plan_id
    where (
      select count(*)
      from public.chem_questions q
      where q.grade_band=o.grade_band
        and q.skill_id=any(p.skill_ids)
        and (p.max_question_level is null or q.level<=p.max_question_level)
        and q.review_status='approved'
        and q.scope_status='IN'
        and q.usable_for_review
    ) < p.question_count
  ) then
    raise exception 'At least one active high-school review day cannot supply five approved IN-scope questions';
  end if;

  if exists (
    select 1 from public.chem_knowledge_cards
    where skill_id='H1_CLASSIFY' and review_status='approved'
      and structured_content::text like '%氧化还原%'
  ) then
    raise exception 'The classification card still leaks redox content into the three-student scope';
  end if;
end $$;

commit;
