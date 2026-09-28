-- Run against a database with the quality-gate migration applied. All fixture
-- changes roll back; this verifies the actual teacher and student read paths.
begin;

do $$
declare
  v_table regclass := to_regclass('app_private.chem_question_item_visual_reviews');
  v_review regprocedure := to_regprocedure('public.chem_record_question_item_visual_review(text,text,text,text,text,jsonb)');
  v_queue regprocedure := to_regprocedure('public.chem_queue_question_item_visual_recheck(text,text,text)');
  v_question text;
  v_revision text;
  v_locator text;
  v_old_question text;
  v_repaired_question text;
  v_unreviewed_release uuid := gen_random_uuid();
  v_expected_gate_error boolean := false;
begin
  if v_table is null or not coalesce((select relrowsecurity from pg_class where oid=v_table),false) then
    raise exception 'private per-question visual reviews must exist with RLS';
  end if;
  if v_review is null or v_queue is null
    or has_function_privilege('anon',v_review,'execute')
    or has_function_privilege('authenticated',v_review,'execute')
    or has_function_privilege('anon',v_queue,'execute')
    or has_function_privilege('authenticated',v_queue,'execute')
    or not has_function_privilege('service_role',v_review,'execute')
    or not has_function_privilege('service_role',v_queue,'execute')
  then raise exception 'item review RPC privileges are unsafe'; end if;
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid='public.chem_questions'::regclass
      and t.tgname='chem_queue_question_item_visual_review' and t.tgenabled='O'
  ) or not exists (
    select 1 from pg_trigger t
    where t.tgrelid='app_private.chem_question_source_releases'::regclass
      and t.tgname='chem_require_item_visual_reviews_before_activation' and t.tgenabled='O'
  ) then raise exception 'future imports or activations lack the per-item gate'; end if;

  select q.id,q.question_revision_token,q.source_info->>'locator'
    into v_question,v_revision,v_locator
  from app_private.chem_teaching_ready_questions q
  where q.grade_band in ('高一','高二','高三')
  order by q.id limit 1;
  if v_question is null then
    raise exception 'test needs one high-school teaching-ready fixture';
  end if;

  perform public.chem_queue_question_item_visual_recheck(
    v_question,'回归测试：模拟发现原题公式字符缺失待核对','quality-gate-test'
  );
  if not exists (
    select 1 from public.chem_question_delivery_holds() h
    where h.question_id=v_question
  ) or exists (
    select 1 from app_private.chem_teaching_ready_questions q
    where q.id=v_question
  ) then raise exception 'pending individual review must block both delivery and teacher assignment'; end if;

  -- This is rolled back: it exercises the evidence checks and transition,
  -- and does not claim that the fixture has actually passed visual inspection.
  perform public.chem_record_question_item_visual_review(
    v_question,v_revision,v_locator,'quality-gate-test',
    '回归测试：只验证事务内的逐题审核状态转换，不作为真实人工审核记录',
    '{"stem_options_and_formula":true,"answer_and_explanation":true,"source_image_complete":true,"source_locator_matches":true}'::jsonb
  );
  if not app_private.chem_question_item_visual_reviewed(v_question)
    or exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=v_question)
    or not exists(select 1 from app_private.chem_teaching_ready_questions q where q.id=v_question)
  then raise exception 'verified current revision must resume delivery and teacher assignment'; end if;

  update app_private.chem_question_item_visual_reviews
  set revision_token=case when v_revision=repeat('0',64) then repeat('1',64) else repeat('0',64) end
  where question_id=v_question;
  if app_private.chem_question_item_visual_reviewed(v_question)
    or not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=v_question)
    or exists(select 1 from app_private.chem_teaching_ready_questions q where q.id=v_question)
  then raise exception 'stale approved revision must fail closed'; end if;

  select a.id,b.id into v_old_question,v_repaired_question
  from public.chem_questions a
  join app_private.chem_teaching_ready_questions b
    on b.source_item_key=a.source_item_key
   and b.id<>a.id
   and b.content_fingerprint is distinct from a.content_fingerprint
  where a.source_release_id is not null
    and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=b.id)
  order by a.id,b.id limit 1;
  if v_old_question is null then
    raise exception 'test needs an old and repaired source item with different content fingerprints';
  end if;
  insert into app_private.chem_question_delivery_holds(anchor_question_id,reason)
  values(v_old_question,'回归测试：旧版原题文字缺式')
  on conflict(anchor_question_id) do update
    set reason=excluded.reason,resolved_at=null;
  if not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=v_old_question)
    or exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=v_repaired_question)
  then raise exception 'old-revision hold must not spread through source_item_key to repaired text'; end if;

  insert into app_private.chem_question_source_releases(
    id,manifest_sha256,grade_band,status,expected_question_count,release_kind
  ) values (
    v_unreviewed_release,
    md5(v_unreviewed_release::text) || md5(v_unreviewed_release::text || 'visual'),
    '高三','staged',1,'teaching_material'
  );
  begin
    update app_private.chem_question_source_releases
    set status='active' where id=v_unreviewed_release;
  exception when others then
    v_expected_gate_error := position('逐题原图核验或严格历史继承未满足' in sqlerrm)>0;
    if not v_expected_gate_error then raise; end if;
  end;
  if not v_expected_gate_error then
    raise exception 'future release activation must reject unreviewed questions';
  end if;
end;
$$;

rollback;
