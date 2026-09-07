begin;

-- Source content/snapshots remain immutable. This separate private queue records
-- only the first wrong option and its explicitly reviewed, versioned reserves.
create table app_private.chem_junior_option_branches (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete restrict,
  anchor_step_id uuid not null unique references public.chem_junior_session_steps(id) on delete restrict,
  anchor_session_id uuid not null references public.chem_junior_daily_sessions(id) on delete restrict,
  anchor_question_id text not null references public.chem_questions(id) on delete restrict,
  anchor_revision_token text not null,
  selected_option smallint not null check(selected_option between 0 and 3),
  knowledge_id text not null,
  knowledge_point text not null default '',
  binding_snapshot jsonb,
  candidates jsonb not null default '[]' check(jsonb_typeof(candidates)='array' and jsonb_array_length(candidates)<=5),
  status text not null default 'reserve_gap' check(status in ('practicing','pending','consolidated','needs_practice','reserve_gap')),
  reason text not null default '',
  target_count smallint not null default 3 check(target_count between 3 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index chem_junior_option_branches_student_queue on app_private.chem_junior_option_branches(student_id,created_at,id);
create table app_private.chem_junior_option_steps (
  step_id uuid primary key references public.chem_junior_session_steps(id) on delete restrict,
  branch_id uuid not null references app_private.chem_junior_option_branches(id) on delete restrict,
  position smallint not null check(position between 1 and 5),
  unique(branch_id,position)
);
alter table app_private.chem_junior_option_branches enable row level security;
alter table app_private.chem_junior_option_steps enable row level security;
revoke all on table app_private.chem_junior_option_branches,app_private.chem_junior_option_steps from public,anon,authenticated,service_role;

create function app_private.chem_junior_option_identity_guard() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then raise exception 'junior option evidence cannot be deleted'; end if;
  if to_jsonb(new)-array['knowledge_point','binding_snapshot','candidates','status','reason','target_count','updated_at']
     is distinct from to_jsonb(old)-array['knowledge_point','binding_snapshot','candidates','status','reason','target_count','updated_at']
    or (jsonb_array_length(old.candidates)>0 and (new.candidates is distinct from old.candidates or new.binding_snapshot is distinct from old.binding_snapshot or new.knowledge_point is distinct from old.knowledge_point))
  then raise exception 'junior first-option identity and reserved versions are immutable'; end if;
  return new;
end; $$;
create trigger chem_junior_option_identity_guard before update or delete on app_private.chem_junior_option_branches for each row execute function app_private.chem_junior_option_identity_guard();
revoke all on function app_private.chem_junior_option_identity_guard() from public,anon,authenticated,service_role;

-- Definer is restricted to service_role, because the custom-session Edge route
-- has already authenticated the student and the queue is not Data API visible.
create function public.chem_junior_option_state(p_student_id uuid,p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  sess public.chem_junior_daily_sessions%rowtype;
  anchor record; branch app_private.chem_junior_option_branches%rowtype;
  binding app_private.chem_option_practice_bindings%rowtype;
  candidate jsonb; q public.chem_questions%rowtype;
  chosen jsonb; n integer; good integer; has_error boolean; last_three_good boolean;
  target integer; issued_count integer; next_id text; next_revision text;
  result jsonb := '[]'; branch_status text; branch_reason text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
  -- A student row serializes queue allocation across days/tabs before sessions.
  perform s.id from public.chem_students_v2 s where s.id=p_student_id and s.grade_band='初三'
    and s.record_status='active' and coalesce((s.metadata->>'demo')::boolean,false)=false for update;
  if not found then raise exception 'junior option student is not eligible'; end if;
  select * into sess from public.chem_junior_daily_sessions s where s.id=p_session_id and s.student_id=p_student_id for update;
  if not found then raise exception 'junior option session ownership mismatch'; end if;
  select count(*) into issued_count from public.chem_junior_session_steps s where s.session_id=p_session_id;

  -- Only ordinary issued steps create branches. A reserve can never recurse.
  for anchor in select st.* from public.chem_junior_session_steps st
    join public.chem_junior_daily_sessions ds on ds.id=st.session_id
    where ds.student_id=p_student_id and ds.textbook_version=sess.textbook_version
      and st.answered_at is not null and st.correct=false
      and not exists(select 1 from app_private.chem_junior_option_steps os where os.step_id=st.id)
      and not exists(select 1 from app_private.chem_junior_option_branches b where b.anchor_step_id=st.id)
    order by st.answered_at,st.id
  loop
    insert into app_private.chem_junior_option_branches(student_id,anchor_step_id,anchor_session_id,anchor_question_id,anchor_revision_token,selected_option,knowledge_id)
    values(p_student_id,anchor.id,anchor.session_id,anchor.question_id,coalesce(anchor.question_snapshot->>'revisionToken',''),anchor.selected_option,anchor.knowledge_id);
  end loop;

  for branch in select * from app_private.chem_junior_option_branches b where b.student_id=p_student_id order by b.created_at,b.id for update
  loop
    -- An empty gap may acquire a newly reviewed pool, but a nonempty pool is
    -- frozen for the lifetime of this first-option branch, including next day.
    if jsonb_array_length(branch.candidates)=0 then
      select * into binding from app_private.chem_option_practice_bindings b
        where b.anchor_question_id=branch.anchor_question_id and b.option_index=branch.selected_option
          and b.anchor_revision_token=branch.anchor_revision_token and b.review_status='verified';
      chosen := '[]';
      if found then
        for candidate in select value from jsonb_array_elements(binding.candidates)
        loop
          select question.* into q from public.chem_questions question
            join app_private.chem_question_source_releases r on r.id=question.source_release_id and r.status='active'
              and r.verification_status='full_visual_verified' and r.revision_contract='v3_junior_native_text'
            join app_private.chem_junior_knowledge_provenance p on p.knowledge_id=question.knowledge_id
              and p.textbook_version=sess.textbook_version and p.source_release_id=r.id and p.verification_status='verified'
            where question.id=candidate->>'questionId' and question.question_revision_token=candidate->>'revisionToken'
              and question.grade_band='初三' and question.textbook_version=sess.textbook_version
              and question.source_kind='user_provided_local' and question.review_status='approved'
              and question.scope_status='IN' and question.usable_for_review and question.render_mode='native'
              and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=question.id);
          if not found then continue; end if;
          if exists(select 1 from public.chem_junior_session_steps st join public.chem_junior_daily_sessions ds on ds.id=st.session_id
              where ds.student_id=p_student_id and (st.question_id=q.id or st.mother_id=q.mother_id or st.source_item_key=q.source_item_key or st.parent_source_item_key=q.parent_source_item_key or st.content_fingerprint=q.content_fingerprint))
            or exists(select 1 from jsonb_array_elements(chosen) c join public.chem_questions prior on prior.id=c->>'questionId'
              where prior.id=q.id or prior.mother_id=q.mother_id or prior.source_item_key=q.source_item_key or prior.parent_source_item_key=q.parent_source_item_key or prior.content_fingerprint=q.content_fingerprint)
            or exists(select 1 from app_private.chem_junior_option_branches other cross join lateral jsonb_array_elements(other.candidates) c
              join public.chem_questions reserved on reserved.id=c->>'questionId'
              where other.student_id=p_student_id and other.id<>branch.id and other.status in ('practicing','pending','reserve_gap')
                and (reserved.id=q.id or reserved.mother_id=q.mother_id or reserved.source_item_key=q.source_item_key or reserved.parent_source_item_key=q.parent_source_item_key or reserved.content_fingerprint=q.content_fingerprint))
          then continue; end if;
          chosen := chosen || jsonb_build_array(candidate);
        end loop;
        if jsonb_array_length(chosen)>=3 then
          update app_private.chem_junior_option_branches set candidates=chosen,binding_snapshot=to_jsonb(binding),knowledge_point=binding.knowledge_point,updated_at=now() where id=branch.id returning * into branch;
        end if;
      end if;
    end if;

    select count(*) filter(where st.answered_at is not null),count(*) filter(where st.correct=true),coalesce(bool_or(st.correct=false and os.position<=3),false)
      into n,good,has_error from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where os.branch_id=branch.id;
    select count(*)=3 and bool_and(t.correct) into last_three_good from (
      select st.correct from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id
      where os.branch_id=branch.id and st.answered_at is not null order by os.position desc limit 3
    ) t;
    target := case when has_error then greatest(3,least(5,jsonb_array_length(branch.candidates))) else 3 end;
    next_id := null; next_revision := null;
    branch_status := 'practicing'; branch_reason := '';
    if jsonb_array_length(branch.candidates)<3 then branch_status:='reserve_gap'; branch_reason:='fewer_than_three_verified_fresh_originals';
    elsif n>=target then
      if last_three_good then branch_status:='consolidated';
      else branch_status:='needs_practice'; branch_reason:='reviewed_reserves_exhausted_without_three_consecutive_correct'; end if;
    else
      next_id:=branch.candidates->n->>'questionId'; next_revision:=branch.candidates->n->>'revisionToken';
      select * into q from public.chem_questions question where question.id=next_id;
      if not found or q.question_revision_token is distinct from next_revision or not q.usable_for_review
        or exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=next_id)
      then branch_status:='reserve_gap'; branch_reason:='reserved_original_unavailable';
      elsif not (q.knowledge_id=any(sess.knowledge_skill_ids)) then branch_status:='pending'; branch_reason:='waiting_for_compatible_curriculum';
      elsif sess.status<>'active' or issued_count>=sess.hard_question_cap then branch_status:='pending'; branch_reason:='daily_limit_carry_forward';
      end if;
    end if;
    update app_private.chem_junior_option_branches set status=branch_status,reason=branch_reason,target_count=target,updated_at=now() where id=branch.id;
    result:=result||jsonb_build_array(jsonb_build_object('branchId',branch.id,'anchorStepId',branch.anchor_step_id,'anchorSessionId',branch.anchor_session_id,
      'knowledgeId',branch.knowledge_id,'knowledgePoint',branch.knowledge_point,'optionIndex',branch.selected_option,
      'status',branch_status,'reason',branch_reason,'answered',n,'correct',good,'total',target,
      'candidates',branch.candidates,'nextQuestionId',next_id,'nextRevisionToken',next_revision));
  end loop;
  return jsonb_build_object('branches',result,'stepContexts',coalesce((select jsonb_agg(jsonb_build_object('stepId',os.step_id,'branchId',os.branch_id,'position',os.position)) from app_private.chem_junior_option_steps os join public.chem_junior_session_steps st on st.id=os.step_id where st.session_id=p_session_id),'[]'::jsonb));
end; $$;
revoke all on function public.chem_junior_option_state(uuid,uuid) from public,anon,authenticated;
grant execute on function public.chem_junior_option_state(uuid,uuid) to service_role;

-- The existing source/rights/provenance/hold/snapshot gate still owns issuance.
-- Queue validation + original issue RPC + association commit atomically.
create function public.chem_junior_issue_option_step(p_student_id uuid,p_session_id uuid,p_branch_id uuid,p_question_id text,p_sequence smallint,p_route_kind text,p_route_reason text,p_question_snapshot jsonb)
returns table(step_id uuid,question_id text,sequence smallint)
language plpgsql security definer set search_path='' as $$
declare state jsonb; branch jsonb; issued record; position integer;
begin
  state:=public.chem_junior_option_state(p_student_id,p_session_id);
  -- Array order is the persistent oldest-first queue order, not a caller choice.
  select b into branch from jsonb_array_elements(state->'branches') with ordinality t(b,n) where b->>'status'='practicing' order by n limit 1;
  if p_branch_id is null then
    if branch is not null then raise exception 'junior option queue advanced' using errcode='40001'; end if;
    if p_route_kind not in ('new_learning','stability_validation')
      or exists(select 1 from jsonb_array_elements(state->'branches') b cross join lateral jsonb_array_elements(b->'candidates') c
        join public.chem_questions reserved on reserved.id=c->>'questionId'
        join public.chem_questions requested on requested.id=p_question_id
        where b->>'status' in ('practicing','pending','reserve_gap') and (reserved.id=requested.id or reserved.mother_id=requested.mother_id
          or reserved.source_item_key=requested.source_item_key or reserved.parent_source_item_key=requested.parent_source_item_key or reserved.content_fingerprint=requested.content_fingerprint))
      or exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=p_question_id)
    then raise exception 'ordinary junior practice cannot substitute or consume a strict reserve'; end if;
    return query select * from public.chem_junior_issue_step(p_session_id,p_student_id,p_question_id,p_sequence,p_route_kind,p_route_reason,p_question_snapshot);
    return;
  end if;
  if branch is null or branch->>'branchId' is distinct from p_branch_id::text or branch->>'nextQuestionId' is distinct from p_question_id
    or branch->>'nextRevisionToken' is distinct from p_question_snapshot->>'revisionToken'
    or p_route_kind<>'foundation_repair' or p_route_reason is distinct from ('针对该选项考点的已审核原题补练：'||(branch->>'knowledgePoint'))
  then raise exception 'junior option issue is not the next frozen reserve'; end if;
  position:=(branch->>'answered')::integer+1;
  select * into issued from public.chem_junior_issue_step(p_session_id,p_student_id,p_question_id,p_sequence,p_route_kind,p_route_reason,p_question_snapshot);
  insert into app_private.chem_junior_option_steps(step_id,branch_id,position) values(issued.step_id,p_branch_id,position);
  return query select issued.step_id,issued.question_id,issued.sequence;
end; $$;
revoke all on function public.chem_junior_issue_option_step(uuid,uuid,uuid,text,smallint,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.chem_junior_issue_option_step(uuid,uuid,uuid,text,smallint,text,text,jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.chem_junior_finalize_session(p_session_id uuid, p_student_id uuid)
 RETURNS TABLE(completed boolean, total_questions integer, correct_questions integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_plan_mode text;
  v_profile_id uuid;
  v_total integer;
  v_answered integer;
  v_correct integer;
  v_attempt_id uuid;
  v_answer_ledger_count integer;
  v_completed_at timestamptz;
  v_required_skill_count integer;
  v_required_card_count integer;
  v_verified_provenance_count integer;
  v_current_contract_count integer;
begin
  if p_session_id is null or p_student_id is null then
    raise exception 'invalid junior session finalization';
  end if;

  -- Use the same global lifecycle locks as activation, issue, validation and
  -- answer recording before taking the per-session serialization lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  -- Reconcile the private first-option queue before deriving mastery. The
  -- original 12/15, source-rights and exact-snapshot checks below are unchanged.
  perform public.chem_junior_option_state(p_student_id,p_session_id);

  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status in ('active', 'completed')
    and session.study_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable';
  end if;

  -- Re-lock the complete authorization snapshot before touching steps or an
  -- existing attempt.  Even an idempotent retry must prove that the current
  -- plan/profile/curriculum/card contract still authorizes this student.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1
  for share;

  if not found then
    raise exception 'junior session plan contract changed before finalization';
  end if;
  v_plan_mode := v_plan.mode;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The locked session makes the union stable before step locks are taken.
  -- It includes the current three skills plus every actual recovery skill.
  perform card.id
  from public.chem_knowledge_cards as card
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = card.skill_id
  where card.review_status = 'approved'
  order by card.skill_id, card.id
  for share of card;

  select count(*)::integer
  into v_required_skill_count
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required_knowledge;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct required.skill_id
      from (
        select requested.skill_id
        from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
        union all
        select existing.knowledge_id
        from public.chem_junior_session_steps as existing
        where existing.session_id = p_session_id
      ) as required
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
     and app_private.chem_junior_knowledge_card_is_ready(
       v_session.textbook_version,
       required.skill_id
     )
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_skill_count then
    raise exception 'junior knowledge-card approval contract changed before finalization';
  end if;

  -- Lock all issued steps, then their question, provenance and release rows in
  -- that order.  The following validation reads only rows held by these locks.
  perform step.id
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id
  order by step.sequence
  for update;

  select
    count(*)::integer,
    (count(*) filter (where step.answered_at is not null))::integer,
    (count(*) filter (where step.correct))::integer
  into v_total, v_answered, v_correct
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_total not between v_session.initial_question_target and v_session.hard_question_cap
    or v_answered <> v_total then
    raise exception 'junior session is not ready to finalize';
  end if;

  perform question.id
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by question.id
  for share of question;

  perform provenance.knowledge_id
  from app_private.chem_junior_knowledge_provenance as provenance
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = provenance.knowledge_id
  where provenance.textbook_version = v_session.textbook_version
  order by provenance.knowledge_id
  for share of provenance;

  perform release.id
  from app_private.chem_question_source_releases as release
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where release.id in (
    select provenance.source_release_id
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id in (
        select required.skill_id
        from (
          select requested.skill_id
          from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
          union
          select existing.knowledge_id
          from public.chem_junior_session_steps as existing
          where existing.session_id = p_session_id
        ) as required
      )
    union
    select question.source_release_id
    from public.chem_junior_session_steps as step
    join public.chem_questions as question
      on question.id = step.question_id
    where step.session_id = p_session_id
  )
  order by release.id
  for share of release, rights;

  -- Every current or recovery knowledge route must still resolve to one
  -- verified provenance row on an active, fully verified native release.
  perform provenance.knowledge_id
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = required.skill_id
   and provenance.verification_status = 'verified'
   and provenance.reviewed_at is not null
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0;
  get diagnostics v_verified_provenance_count = row_count;
  if v_verified_provenance_count <> v_required_skill_count then
    raise exception 'junior verified provenance is no longer active';
  end if;

  -- Revalidate every original and its exact issue snapshot while all source
  -- rows remain locked.  The CASE wrappers keep malformed JSON fail-closed
  -- without invoking array functions on a non-array value.
  select count(*)::integer
  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = step.knowledge_id
   and provenance.source_release_id = question.source_release_id
   and provenance.verification_status = 'verified'
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  join app_private.chem_junior_source_release_rights as rights
    on rights.release_id = release.id
   and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
   and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
   and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  where step.session_id = p_session_id
    and step.answered_at is not null
    and question.grade_band = '初三'
    and question.textbook_version = v_session.textbook_version
    and question.source_kind = 'user_provided_local'
    and question.review_status = 'approved'
    and question.scope_status = 'IN'
    and question.usable_for_review
    and question.render_mode = 'native'
    and question.image_url is null
    and question.asset_refs = '[]'::jsonb
    and question.skill_id = step.skill_id
    and question.knowledge_id = step.knowledge_id
    and question.skill_id = question.knowledge_id
    and question.mother_id = step.mother_id
    and question.same_type_key = step.same_type_key
    and question.source_item_key = step.source_item_key
    and question.parent_source_item_key = step.parent_source_item_key
    and question.content_fingerprint = step.content_fingerprint
    and question.level = step.level
    and question.source_release_id is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.stem, ''))) > 0
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.explanation, ''))) > 0
    and pg_catalog.jsonb_typeof(question.options) = 'array'
    and case
      when pg_catalog.jsonb_typeof(question.options) = 'array'
        then pg_catalog.jsonb_array_length(question.options)
      else -1
    end = 4
    and question.correct_option between 0 and 3
    and not exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
      where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
        or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
    )
    and (
      select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
    ) = 4
    and question.content_fingerprint =
      app_private.chem_h3_content_fingerprint(question.stem, question.options)
    and question.question_revision_token =
      app_private.chem_junior_native_revision_sha256(question)
    and step.question_snapshot = pg_catalog.jsonb_build_object(
      'questionId', question.id,
      'motherId', question.mother_id,
      'skillId', question.skill_id,
      'knowledgeId', question.knowledge_id,
      'conceptKey', question.concept_key,
      'level', question.level,
      'gradeBand', question.grade_band,
      'textbookVersion', question.textbook_version,
      'stem', question.stem,
      'options', question.options,
      'correctOption', question.correct_option,
      'explanation', question.explanation,
      'scaffold', question.scaffold,
      'reviewStatus', question.review_status,
      'scopeStatus', question.scope_status,
      'sourceKind', question.source_kind,
      'renderMode', question.render_mode,
      'imageUrl', question.image_url,
      'assetRefs', question.asset_refs,
      'sourceReleaseId', question.source_release_id,
      'sourceItemKey', question.source_item_key,
      'parentSourceItemKey', question.parent_source_item_key,
      'sameTypeKey', question.same_type_key,
      'contentFingerprint', question.content_fingerprint,
      'revisionToken', question.question_revision_token,
      'routeKind', step.route_kind,
      'routeReason', step.route_reason
    )
    and coalesce(step.question_snapshot ->> 'revisionToken', '') =
      coalesce(question.question_revision_token, '');

  if v_current_contract_count <> v_total then
    raise exception 'junior source evidence contract changed before finalization';
  end if;

  -- Only now may a completed retry return.  The existing attempt lookup is
  -- intentionally after all present-tense authorization and source locks so
  -- completion never bypasses a revoked plan/profile/curriculum/card/release.
  select attempt.id
  into v_attempt_id
  from public.chem_learning_attempts as attempt
  where attempt.junior_session_id = p_session_id
    and attempt.student_id = p_student_id
    and attempt.plan_day_id = v_session.plan_day_id
  for share;

  if v_attempt_id is not null then
    if v_session.status <> 'completed' then
      raise exception 'junior attempt exists for a session that is not completed';
    end if;
    select count(*)::integer
    into v_answer_ledger_count
    from public.chem_attempt_answers as answer
    where answer.attempt_id = v_attempt_id;
    if v_answer_ledger_count <> v_total then
      raise exception 'junior immutable answer ledger is incomplete';
    end if;
    return query select true, v_total, v_correct;
    return;
  end if;

  if v_session.status = 'completed' then
    raise exception 'completed junior session has no immutable attempt ledger';
  end if;

  v_completed_at := coalesce(v_session.completed_at, now());
  v_attempt_id := gen_random_uuid();

  insert into public.chem_learning_attempts (
    id,
    student_id,
    plan_day_id,
    attempt_kind,
    sequence,
    mode,
    started_at,
    completed_at,
    first_score,
    junior_session_id
  ) values (
    v_attempt_id,
    p_student_id,
    v_session.plan_day_id,
    'scheduled',
    0,
    v_plan_mode,
    v_session.started_at,
    v_completed_at,
    v_correct,
    p_session_id
  );

  insert into public.chem_attempt_answers (
    attempt_id,
    question_id,
    mother_id,
    skill_id,
    concept_key,
    level,
    correct,
    uncertain,
    duration_sec,
    selected_option,
    question_snapshot,
    created_at
  )
  select
    v_attempt_id,
    step.question_id,
    step.mother_id,
    step.skill_id,
    coalesce(nullif(step.question_snapshot ->> 'conceptKey', ''), question.concept_key),
    step.level,
    step.correct,
    step.uncertain,
    step.duration_sec,
    step.selected_option,
    coalesce(step.question_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'version', 2,
        'source', 'junior_adaptive_session',
        'capturedAt', step.created_at,
        'answeredAt', step.answered_at,
        'questionId', step.question_id,
        'motherId', step.mother_id,
        'skillId', step.skill_id,
        'knowledgeId', step.knowledge_id,
        'level', step.level,
        'gradeBand', coalesce(nullif(step.question_snapshot ->> 'gradeBand', ''), question.grade_band),
        'textbookVersion', v_session.textbook_version,
        'stem', coalesce(nullif(step.question_snapshot ->> 'stem', ''), question.stem),
        'options', case
          when jsonb_typeof(step.question_snapshot -> 'options') = 'array'
            then step.question_snapshot -> 'options'
          else question.options
        end,
        'correctOption', case
          when jsonb_typeof(step.question_snapshot -> 'correctOption') = 'number'
            then (step.question_snapshot ->> 'correctOption')::smallint
          else question.correct_option
        end,
        'explanation', coalesce(nullif(step.question_snapshot ->> 'explanation', ''), question.explanation),
        'scaffold', coalesce(step.question_snapshot ->> 'scaffold', question.scaffold),
        'sourceKind', 'user_provided_local',
        'sourceReleaseId', coalesce(
          nullif(step.question_snapshot ->> 'sourceReleaseId', ''),
          question.source_release_id::text
        ),
        'sameTypeKey', step.same_type_key,
        'sourceItemKey', step.source_item_key,
        'parentSourceItemKey', step.parent_source_item_key,
        'contentFingerprint', step.content_fingerprint,
        'revisionToken', coalesce(
          nullif(step.question_snapshot ->> 'revisionToken', ''),
          question.question_revision_token
        ),
        'renderMode', coalesce(nullif(step.question_snapshot ->> 'renderMode', ''), question.render_mode),
        'routeKind', step.route_kind,
        'routeReason', step.route_reason,
        'sequence', step.sequence
      ),
    step.answered_at
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by step.sequence;

  select count(*)::integer
  into v_answer_ledger_count
  from public.chem_attempt_answers as answer
  where answer.attempt_id = v_attempt_id;

  if v_answer_ledger_count <> v_total then
    raise exception 'junior immutable answer ledger is incomplete';
  end if;

  with requested_skills as (
    select distinct unnest(v_session.knowledge_skill_ids) as skill_id
  ),
  verified_provenance as (
    select requested.skill_id, provenance.source_release_id
    from requested_skills as requested
    join app_private.chem_junior_knowledge_provenance as provenance
      on provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id = requested.skill_id
      and provenance.verification_status = 'verified'
    join app_private.chem_question_source_releases as release
      on release.id = provenance.source_release_id
      and release.grade_band = '初三'
      and release.textbook_version = v_session.textbook_version
      and release.status = 'active'
      and release.verification_status = 'full_visual_verified'
      and release.verification_manifest_sha256 = release.manifest_sha256
      and release.revision_contract = 'v3_junior_native_text'
      and release.verified_at is not null
      and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
      and release.activated_at is not null
    join app_private.chem_junior_source_release_rights as rights
      on rights.release_id = release.id
      and rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'
      and rights.redistribution_allowed = false
  and rights.attested_manifest_sha256 = release.manifest_sha256
   and rights.attested_card_manifest_sha256 =
     app_private.chem_junior_knowledge_card_manifest_sha256(release.id)
  and rights.attested_at is not null
      and pg_catalog.length(pg_catalog.btrim(rights.attestation_actor)) > 0
  ),
  foundation_levels as (
    select provenance.skill_id, min(question.level)::smallint as foundation_level
    from verified_provenance as provenance
    join public.chem_questions as question
      on question.source_release_id = provenance.source_release_id
      and question.skill_id = provenance.skill_id
      and question.knowledge_id = provenance.skill_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.source_kind = 'user_provided_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'native'
      and coalesce(btrim(question.image_url), '') = ''
      and question.asset_refs = '[]'::jsonb
    group by provenance.skill_id
  ),
  original_evidence as (
    select step.*
    from public.chem_junior_session_steps as step
    join verified_provenance as provenance
      on provenance.skill_id = step.skill_id
    join public.chem_questions as question
      on question.id = step.question_id
      and question.source_release_id = provenance.source_release_id
      and question.skill_id = step.skill_id
      and question.knowledge_id = step.knowledge_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.source_kind = 'user_provided_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'native'
      and coalesce(btrim(question.image_url), '') = ''
      and question.asset_refs = '[]'::jsonb
      and question.mother_id = step.mother_id
      and question.source_item_key = step.source_item_key
      and question.parent_source_item_key = step.parent_source_item_key
      and question.content_fingerprint = step.content_fingerprint
      and question.question_revision_token is not distinct from nullif(step.question_snapshot ->> 'revisionToken', '')
    where step.session_id = p_session_id
  ),
  evidence as (
    select
      requested.skill_id,
      foundation.foundation_level,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_question_count,
      count(distinct original.mother_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_mother_count,
      count(distinct original.source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_source_count,
      count(distinct original.parent_source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_parent_count,
      count(distinct original.content_fingerprint) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_fingerprint_count,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      ) as higher_question_count,
      max(original.level) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      )::smallint as achieved_level,
      (
        select count(*)::integer
        from public.chem_junior_session_steps as all_step
        where all_step.session_id = p_session_id
          and all_step.skill_id = requested.skill_id
          and (not all_step.correct or all_step.uncertain)
      ) as error_or_uncertain_count
    from requested_skills as requested
    left join foundation_levels as foundation
      on foundation.skill_id = requested.skill_id
    left join original_evidence as original
      on original.skill_id = requested.skill_id
    group by requested.skill_id, foundation.foundation_level
  ),
  mastery as (
    select
      evidence.*,
      evidence.foundation_level is not null
        and evidence.foundation_question_count >= 2
        and evidence.foundation_mother_count >= 2
        and evidence.foundation_source_count >= 2
        and evidence.foundation_parent_count >= 2
        and evidence.foundation_fingerprint_count >= 2
        and evidence.higher_question_count >= 1
        and evidence.achieved_level > evidence.foundation_level
        and not exists (
          select 1 from app_private.chem_junior_option_branches b
          where b.student_id=p_student_id and b.knowledge_id=evidence.skill_id
            and b.status <> 'consolidated'
        )
        as mastered
    from evidence
  )
  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    verified_level,
    candidate_level,
    stability,
    consecutive_errors,
    next_review_at,
    review_interval_index,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  )
  select
    p_student_id,
    mastery.skill_id,
    case when mastery.mastered then mastery.achieved_level else 0 end,
    case when mastery.mastered then mastery.achieved_level else null end,
    case when mastery.mastered then 'verified' else 'learning' end,
    mastery.error_or_uncertain_count,
    now() + case when mastery.mastered then interval '3 days' else interval '1 day' end,
    case when mastery.mastered then 1 else 0 end,
    now(),
    not mastery.mastered and mastery.error_or_uncertain_count >= 3,
    now()
  from mastery
  on conflict (student_id, skill_id) do update set
    verified_level = case
      when excluded.stability = 'verified'
        then greatest(public.chem_student_skill_state.verified_level, excluded.verified_level)
      else public.chem_student_skill_state.verified_level
    end,
    candidate_level = case
      when excluded.stability = 'verified' then excluded.candidate_level
      else null
    end,
    stability = case
      when excluded.stability = 'verified' then 'verified'
      when public.chem_student_skill_state.verified_level > 0
        and excluded.consecutive_errors > 0 then 'forgotten'
      else 'learning'
    end,
    consecutive_errors = case
      when excluded.stability = 'verified' then 0
      else greatest(
        public.chem_student_skill_state.consecutive_errors,
        excluded.consecutive_errors
      )
    end,
    next_review_at = excluded.next_review_at,
    review_interval_index = case
      when excluded.stability = 'verified'
        then least(4, public.chem_student_skill_state.review_interval_index + 1)
      else 0
    end,
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or excluded.teacher_intervention,
    updated_at = now();

  update public.chem_junior_daily_sessions
  set status = 'completed',
      completed_at = v_completed_at,
      blocked_reason_code = null,
      blocked_reason_detail = null,
      blocked_at = null,
      updated_at = now()
  where id = p_session_id;

  return query select true, v_total, v_correct;
end;
$function$;


commit;
