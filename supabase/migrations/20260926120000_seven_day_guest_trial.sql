-- Anonymous visitors receive a separate seven-day identity. No access code,
-- phone account, teacher roster membership, or formal source-bank permission
-- is created. Only the service-role Edge Function may call these RPCs.
create table app_private.chem_guest_trials (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null unique references public.chem_students_v2(id) on delete cascade,
  trial_key_hash text not null unique check (trial_key_hash ~ '^[0-9a-f]{64}$'),
  fingerprint_hash text not null check (fingerprint_hash ~ '^[0-9a-f]{64}$'),
  network_hash text not null check (network_hash ~ '^[0-9a-f]{64}$'),
  grade_band text not null check (grade_band in ('初三','高一','高二','高三')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  check (expires_at > created_at and expires_at <= created_at + interval '7 days')
);
create index chem_guest_trials_fingerprint_date on app_private.chem_guest_trials(fingerprint_hash,created_at desc);
create index chem_guest_trials_network_date on app_private.chem_guest_trials(network_hash,created_at desc);

create table app_private.chem_guest_sessions (
  id uuid primary key default gen_random_uuid(),
  trial_id uuid not null references app_private.chem_guest_trials(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_seen_at timestamptz not null default now(),
  check (expires_at > created_at and expires_at <= created_at + interval '12 hours')
);
create index chem_guest_sessions_trial_date on app_private.chem_guest_sessions(trial_id,created_at desc);

-- These are intentionally original, introductory examples, separate from
-- chem_questions and its licensed/student-only source releases.
create table app_private.chem_guest_questions (
  id text primary key,
  grade_band text not null check (grade_band in ('初三','高一','高二','高三')),
  sort_order smallint not null check (sort_order between 1 and 50),
  stem text not null,
  options jsonb not null check (jsonb_typeof(options)='array' and jsonb_array_length(options)=4),
  correct_option smallint not null check (correct_option between 0 and 3),
  explanation text not null,
  unique(grade_band,sort_order)
);

create table app_private.chem_guest_answers (
  trial_id uuid not null references app_private.chem_guest_trials(id) on delete cascade,
  question_id text not null references app_private.chem_guest_questions(id),
  selected_option smallint not null check (selected_option between 0 and 3),
  answered_at timestamptz not null default now(),
  primary key(trial_id,question_id)
);

alter table app_private.chem_guest_trials enable row level security;
alter table app_private.chem_guest_sessions enable row level security;
alter table app_private.chem_guest_questions enable row level security;
alter table app_private.chem_guest_answers enable row level security;
revoke all on app_private.chem_guest_trials,app_private.chem_guest_sessions,
  app_private.chem_guest_questions,app_private.chem_guest_answers from public,anon,authenticated;
grant select,insert,update on app_private.chem_guest_trials,app_private.chem_guest_sessions,
  app_private.chem_guest_questions,app_private.chem_guest_answers to service_role;

insert into app_private.chem_guest_questions(id,grade_band,sort_order,stem,options,correct_option,explanation) values
('guest-j3-01','初三',1,'下列变化中，属于化学变化的是哪一项？','["冰块融化","铁钉生锈","玻璃破碎","水蒸发"]',1,'铁钉生锈时生成了新的物质；其余变化没有生成新物质。'),
('guest-j3-02','初三',2,'空气中体积分数最大的气体是？','["氧气","二氧化碳","氮气","水蒸气"]',2,'空气中氮气约占体积的五分之四。'),
('guest-j3-03','初三',3,'一杯澄清的食盐水属于哪一类物质？','["单质","化合物","混合物","元素"]',2,'食盐水由水和氯化钠共同组成，属于混合物。'),
('guest-j3-04','初三',4,'用天平测得密闭容器内反应前总质量为 20 g。反应后容器内物质的总质量应为多少？','["10 g","18 g","20 g","无法判断"]',2,'密闭容器中的化学反应遵守质量守恒定律，总质量仍为 20 g。'),
('guest-j3-05','初三',5,'pH 为 3 的溶液通常呈什么性？','["酸性","中性","碱性","无法判断"]',0,'常温下，pH 小于 7 的水溶液呈酸性。'),
('guest-j3-06','初三',6,'下列粒子中，保持水化学性质的最小粒子是？','["氢原子","氧原子","水分子","电子"]',2,'水由水分子构成，水分子能保持水的化学性质。'),
('guest-h1-01','高一',1,'钠原子的质子数为 11。一个电中性的钠原子有几个电子？','["10","11","12","23"]',1,'电中性原子的电子数等于质子数。'),
('guest-h1-02','高一',2,'在同温同压下，2 L 氢气与足量氧气完全反应，按化学方程式计算需要多少升氧气？','["1 L","2 L","3 L","4 L"]',0,'反应式为 2H₂ + O₂ → 2H₂O，同温同压下气体体积比为 2:1。'),
('guest-h1-03','高一',3,'下列物质中，通常含有离子键的是？','["H₂","Cl₂","NaCl","CO₂"]',2,'氯化钠由钠离子与氯离子构成，含离子键。'),
('guest-h1-04','高一',4,'氧气 O₂ 中氧元素的化合价是？','["-2","-1","0","+2"]',2,'单质中元素的化合价为 0。'),
('guest-h1-05','高一',5,'1 mol 任何微粒约含有多少个该微粒？','["6.02×10²³","6.02×10²²","1.00×10²³","1.00×10²⁴"]',0,'1 mol 的微粒数约为阿伏加德罗常数 6.02×10²³。'),
('guest-h1-06','高一',6,'下列做法中，通常能加快固体与液体反应速率的是？','["降低温度","把固体研成粉末","减少接触面积","停止搅拌"]',1,'粉碎固体可增大与液体的接触面积，通常使反应更快。'),
('guest-h2-01','高二',1,'对多数化学反应，升高温度通常会怎样影响反应速率？','["加快","减慢","保持不变","使反应停止"]',0,'升温通常增加能有效发生反应的粒子碰撞，反应速率加快。'),
('guest-h2-02','高二',2,'加入催化剂对已建立的化学平衡通常有什么影响？','["一定向正反应方向移动","一定向逆反应方向移动","不改变平衡位置","使平衡常数加倍"]',2,'催化剂同时影响正、逆反应速率，通常不改变平衡位置和平衡常数。'),
('guest-h2-03','高二',3,'25 ℃ 时，某强酸溶液的氢离子浓度为 1×10⁻³ mol/L，其 pH 约为？','["1","3","7","11"]',1,'pH = -lg[H⁺]，因此 pH 为 3。'),
('guest-h2-04','高二',4,'放热反应的焓变 ΔH 一般满足哪项？','["ΔH＞0","ΔH＝0","ΔH＜0","与热量无关"]',2,'反应向外放出热量，体系焓降低，ΔH 为负值。'),
('guest-h2-05','高二',5,'电解池的阴极发生哪一类反应？','["氧化反应","还原反应","中和反应","沉淀反应"]',1,'阴极获得电子，发生还原反应。'),
('guest-h2-06','高二',6,'稀释 10 倍的强酸溶液时，其氢离子浓度通常会怎样变化？','["变为原来的约 1/10","变为原来的约 10 倍","完全不变","必然变成碱性"]',0,'稀释使单位体积内的氢离子数减少；在常见强酸浓度范围内约为原来的 1/10。'),
('guest-h3-01','高三',1,'乙醇分子中的特征官能团是？','["羧基","羟基","醛基","碳碳双键"]',1,'乙醇含有 -OH 羟基。'),
('guest-h3-02','高三',2,'乙酸与乙醇在适当条件下反应，主要生成哪类有机物？','["酯","醛","烯烃","酮"]',0,'羧酸与醇发生酯化反应，可以生成酯和水。'),
('guest-h3-03','高三',3,'原电池的负极通常发生什么反应？','["氧化反应","还原反应","中和反应","水解反应"]',0,'负极失去电子，发生氧化反应。'),
('guest-h3-04','高三',4,'聚乙烯由哪种单体发生加聚反应得到？','["甲烷","乙烯","乙炔","乙醇"]',1,'乙烯分子中的双键打开后可发生加聚，形成聚乙烯。'),
('guest-h3-05','高三',5,'蛋白质分子中氨基酸残基之间主要通过哪种键连接？','["离子键","氢键","肽键","金属键"]',2,'氨基酸经脱水缩合形成肽键，把残基连接起来。'),
('guest-h3-06','高三',6,'向平衡体系加入催化剂，平衡常数通常怎样变化？','["增大","减小","不变","先增大后减小"]',2,'平衡常数由温度决定；单独加入催化剂通常不改变它。');

create function public.chem_start_guest_trial(
  p_grade_band text,p_trial_key_hash text,p_fingerprint_hash text,p_network_hash text,p_session_hash text,p_resume boolean
)
returns table(student_id uuid,trial_id uuid,trial_expires_at timestamptz,session_expires_at timestamptz,result_code text)
language plpgsql security definer set search_path='' as $$
declare v_trial app_private.chem_guest_trials%rowtype; v_student_id uuid;
  v_created timestamptz; v_session_expires timestamptz;
begin
  if p_session_hash is null or p_session_hash !~ '^[0-9a-f]{64}$'
    or p_fingerprint_hash is null or p_fingerprint_hash !~ '^[0-9a-f]{64}$'
    or p_network_hash is null or p_network_hash !~ '^[0-9a-f]{64}$'
    or p_trial_key_hash is null or p_trial_key_hash !~ '^[0-9a-f]{64}$' or p_resume is null then
    return query select null::uuid,null::uuid,null::timestamptz,null::timestamptz,'invalid'::text;
    return;
  end if;
  if not p_resume then
    if p_grade_band is null or p_grade_band not in ('初三','高一','高二','高三') then
      return query select null::uuid,null::uuid,null::timestamptz,null::timestamptz,'invalid'::text;
      return;
    end if;
    perform pg_advisory_xact_lock(hashtext(p_network_hash));
    -- Several classmates can share one school IP and an identical browser UA.
    -- Limit unusually large network bursts without capping an ordinary class.
    if (select count(*) from app_private.chem_guest_trials t
        where t.network_hash=p_network_hash and t.created_at>now()-interval '30 days')>=500 then
      return query select null::uuid,null::uuid,null::timestamptz,null::timestamptz,'rate_limited'::text;
      return;
    end if;
    v_created:=now();
    insert into public.chem_students_v2(
      display_name,grade_band,record_status,enrollment_start_date,textbook_version,
      needs_initial_diagnostic,metadata
    ) values('访客体验',p_grade_band,'pending',current_date,'通用',false,
      '{"demo":true,"guestTrial":true}'::jsonb)
    returning id into v_student_id;
    insert into app_private.chem_guest_trials(
      student_id,trial_key_hash,fingerprint_hash,network_hash,grade_band,created_at,expires_at
    ) values(v_student_id,p_trial_key_hash,p_fingerprint_hash,p_network_hash,p_grade_band,
      v_created,v_created+interval '7 days') returning * into v_trial;
  else
    select * into v_trial from app_private.chem_guest_trials t
    where t.trial_key_hash=p_trial_key_hash for update;
    if not found then
      return query select null::uuid,null::uuid,null::timestamptz,null::timestamptz,'invalid'::text;
      return;
    end if;
    if v_trial.revoked_at is not null or v_trial.expires_at<=now() then
      return query select null::uuid,null::uuid,v_trial.expires_at,null::timestamptz,'expired'::text;
      return;
    end if;
    if (select count(*) from app_private.chem_guest_sessions gs
        where gs.trial_id=v_trial.id and gs.created_at>now()-interval '1 hour')>=20
      or (select count(*) from app_private.chem_guest_sessions gs
        where gs.trial_id=v_trial.id)>=200 then
      return query select null::uuid,null::uuid,v_trial.expires_at,null::timestamptz,'rate_limited'::text;
      return;
    end if;
  end if;
  v_session_expires:=least(now()+interval '12 hours',v_trial.expires_at);
  insert into app_private.chem_guest_sessions(trial_id,token_hash,expires_at)
  values(v_trial.id,p_session_hash,v_session_expires);
  return query select v_trial.student_id,v_trial.id,v_trial.expires_at,v_session_expires,'ok'::text;
end $$;

create function public.chem_resolve_guest_session(p_token_hash text)
returns table(trial_id uuid,student_id uuid,grade_band text,session_expires_at timestamptz,trial_expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return; end if;
  return query
    update app_private.chem_guest_sessions gs set last_seen_at=now()
    from app_private.chem_guest_trials t,public.chem_students_v2 s
    where gs.token_hash=p_token_hash and gs.trial_id=t.id and t.student_id=s.id
      and gs.revoked_at is null and gs.expires_at>now()
      and t.revoked_at is null and t.expires_at>now()
      and s.record_status='pending' and s.metadata @> '{"guestTrial":true,"demo":true}'::jsonb
    returning t.id,t.student_id,t.grade_band,gs.expires_at,t.expires_at;
end $$;

create function public.chem_submit_guest_answer(p_token_hash text,p_question_id text,p_selected_option integer)
returns table(question_id text,selected_option integer,correct boolean,correct_option integer,explanation text)
language plpgsql security definer set search_path='' as $$
declare v_trial app_private.chem_guest_trials%rowtype;
  v_question app_private.chem_guest_questions%rowtype;
  v_existing app_private.chem_guest_answers%rowtype;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
    or p_question_id is null or p_selected_option is null or p_selected_option not between 0 and 3 then return; end if;
  select t.* into v_trial from app_private.chem_guest_trials t
  join app_private.chem_guest_sessions gs on gs.trial_id=t.id
  join public.chem_students_v2 s on s.id=t.student_id
  where gs.token_hash=p_token_hash and gs.revoked_at is null and gs.expires_at>now()
    and t.revoked_at is null and t.expires_at>now()
    and s.record_status='pending' and s.metadata @> '{"guestTrial":true,"demo":true}'::jsonb
  for update of t;
  if not found then return; end if;
  select a.* into v_existing from app_private.chem_guest_answers a
  join app_private.chem_guest_questions q on q.id=a.question_id
  where a.trial_id=v_trial.id and a.question_id=p_question_id and q.grade_band=v_trial.grade_band;
  if found then
    return query select q.id,v_existing.selected_option::integer,
      (v_existing.selected_option=q.correct_option),q.correct_option::integer,q.explanation
    from app_private.chem_guest_questions q where q.id=p_question_id;
    return;
  end if;
  select q.* into v_question from app_private.chem_guest_questions q
  where q.grade_band=v_trial.grade_band and not exists(
    select 1 from app_private.chem_guest_answers a where a.trial_id=v_trial.id and a.question_id=q.id
  ) order by q.sort_order,q.id limit 1;
  if not found or v_question.id<>p_question_id then return; end if;
  insert into app_private.chem_guest_answers(trial_id,question_id,selected_option)
  values(v_trial.id,v_question.id,p_selected_option);
  return query select v_question.id,p_selected_option,(p_selected_option=v_question.correct_option),
    v_question.correct_option::integer,v_question.explanation;
end $$;

create function public.chem_guest_practice(p_token_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_trial app_private.chem_guest_trials%rowtype;
  v_total integer; v_answered integer; v_correct integer;
  v_current jsonb; v_history jsonb;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return null; end if;
  select t.* into v_trial from app_private.chem_guest_trials t
  join app_private.chem_guest_sessions gs on gs.trial_id=t.id
  join public.chem_students_v2 s on s.id=t.student_id
  where gs.token_hash=p_token_hash and gs.revoked_at is null and gs.expires_at>now()
    and t.revoked_at is null and t.expires_at>now()
    and s.record_status='pending' and s.metadata @> '{"guestTrial":true,"demo":true}'::jsonb;
  if not found then return null; end if;
  select count(*)::integer,count(a.question_id)::integer,
    count(*) filter (where a.selected_option=q.correct_option)::integer
  into v_total,v_answered,v_correct
  from app_private.chem_guest_questions q
  left join app_private.chem_guest_answers a on a.question_id=q.id and a.trial_id=v_trial.id
  where q.grade_band=v_trial.grade_band;
  select jsonb_build_object('id',q.id,'stem',q.stem,'options',q.options)
    into v_current from app_private.chem_guest_questions q
  where q.grade_band=v_trial.grade_band and not exists(
    select 1 from app_private.chem_guest_answers a
    where a.trial_id=v_trial.id and a.question_id=q.id
  ) order by q.sort_order,q.id limit 1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'questionId',q.id,'selectedOption',a.selected_option,
    'correct',a.selected_option=q.correct_option
  ) order by q.sort_order,q.id),'[]'::jsonb) into v_history
  from app_private.chem_guest_answers a
  join app_private.chem_guest_questions q on q.id=a.question_id
  where a.trial_id=v_trial.id and q.grade_band=v_trial.grade_band;
  return jsonb_build_object('gradeBand',v_trial.grade_band,'total',v_total,
    'answeredCount',v_answered,'correctCount',v_correct,
    'currentQuestion',v_current,'history',v_history);
end $$;

revoke all on function public.chem_start_guest_trial(text,text,text,text,text,boolean),
  public.chem_resolve_guest_session(text),public.chem_submit_guest_answer(text,text,integer),
  public.chem_guest_practice(text)
  from public,anon,authenticated;
grant execute on function public.chem_start_guest_trial(text,text,text,text,text,boolean),
  public.chem_resolve_guest_session(text),public.chem_submit_guest_answer(text,text,integer),
  public.chem_guest_practice(text)
  to service_role;
