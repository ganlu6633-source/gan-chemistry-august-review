-- Run after the schema migration while the existing 43-item base is active
-- and the cumulative replacement is staged. No student data is touched.
begin;
do $test$
declare
  base_release app_private.chem_question_source_releases%rowtype;
  source_id text; other_source_id text; target_id text; novel_id text; target_release uuid;
  verdict jsonb; novel_review jsonb; other_grades_before text; rejected boolean; before_events integer; after_events integer;
begin
  select md5(coalesce(string_agg(id,',' order by id),'')) into other_grades_before
    from app_private.chem_teaching_ready_questions where grade_band<>'初三';
  if not exists(select 1 from app_private.chem_junior_visual_legacy_base) then
    select * into base_release from app_private.chem_question_source_releases
      where grade_band='初三' and textbook_version='科粤版' and status='active' and expected_question_count=43;
    if not found then raise exception 'test requires the original accepted 43-item active base'; end if;
    if public.chem_capture_junior_visual_legacy_base(base_release.id,base_release.manifest_sha256,
      'transaction-test','Temporary capture of the existing legacy acceptance; source images are not claimed rechecked.')<>43 then
      raise exception 'legacy registration count differs';
    end if;
  else
    select r.* into base_release from app_private.chem_question_source_releases r
      join app_private.chem_junior_visual_legacy_base b on b.release_id=r.id;
  end if;
  if (select count(*) from app_private.chem_junior_visual_legacy_origins)<>43 then
    raise exception 'legacy allowlist must contain exactly43 originals';
  end if;
  if exists(select 1 from app_private.chem_junior_visual_legacy_origins origin
    join public.chem_questions q on q.id=origin.question_id where q.knowledge_id like 'J_KY_OXY_%') then
    raise exception 'new oxygen questions entered the frozen original43 allowlist';
  end if;
  rejected:=false;
  begin
    perform public.chem_capture_junior_visual_legacy_base(base_release.id,base_release.manifest_sha256,'transaction-test','A second base must not be registered.');
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'a second legacy base was accepted'; end if;

  select origin.question_id,q.id,q.source_release_id into source_id,target_id,target_release
    from app_private.chem_junior_visual_legacy_origins origin
    join public.chem_questions q on app_private.chem_junior_visual_lineage_payload(q.id)=app_private.chem_junior_visual_lineage_payload(origin.question_id)
    join app_private.chem_question_source_releases r on r.id=q.source_release_id and r.status='staged'
    join app_private.chem_question_item_visual_reviews v on v.question_id=q.id and v.review_state='pending'
      and v.review_actor is null and v.review_note is null and v.review_checks='{}'::jsonb
    where not exists(select 1 from app_private.chem_question_item_legacy_carries c where c.question_id=q.id)
    order by r.created_at desc,q.id limit 1;
  if target_id is null then raise exception 'test requires an unchanged staged copy with automatic pending review'; end if;
  select question_id into other_source_id from app_private.chem_junior_visual_legacy_origins where question_id<>source_id order by question_id limit 1;
  select id into novel_id from public.chem_questions where source_release_id=target_release and knowledge_id='J_KY_OXY_H2O2' order by id limit 1;
  if novel_id is null then raise exception 'test requires a genuinely new oxygen item'; end if;
  select to_jsonb(v) into novel_review from app_private.chem_question_item_visual_reviews v where v.question_id=novel_id;

  rejected:=false;
  begin perform public.chem_carry_question_item_legacy_review(novel_id,source_id,'transaction-test','New oxygen content must not inherit an unrelated legacy review.');
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'new oxygen content bypassed real visual review'; end if;
  rejected:=false;
  begin perform public.chem_carry_question_item_legacy_review(target_id,novel_id,'transaction-test','A new staged question must not become a legacy source.');
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'uncaptured source was accepted'; end if;
  rejected:=false;
  begin perform public.chem_carry_question_item_legacy_review(target_id,other_source_id,'transaction-test','A different legacy question cannot authenticate this exact payload.');
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'mismatching legacy source fields were accepted'; end if;

  -- An explicit pending recheck is materially different from initial import.
  begin
    perform public.chem_queue_question_item_visual_recheck(target_id,'This target requires a real source image recheck before further use.','transaction-test');
    rejected:=false;
    begin perform public.chem_carry_question_item_legacy_review(target_id,source_id,'transaction-test','Explicit rechecks must not be overwritten by a carry.');
    exception when raise_exception then rejected:=true; end;
    if not rejected then raise exception 'explicit pending recheck was overwritten'; end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;

  verdict:=public.chem_carry_question_item_legacy_review(target_id,source_id,'transaction-test',
    'Exact17 field match against the captured prior active release; no new source-image verification is asserted.');
  if verdict->>'reviewState'<>'legacy_carried'
    or app_private.chem_question_item_visual_reviewed(target_id)
    or not app_private.chem_question_item_legacy_carried(target_id)
    or not app_private.chem_question_item_delivery_review_ready(target_id) then
    raise exception 'legacy acceptance was misrepresented as a new verified review';
  end if;
  if not exists(select 1 from app_private.chem_question_item_visual_reviews where question_id=target_id
      and review_checks->'source_image_complete'='false'::jsonb and reviewed_at is null
      and source_document_sha256 is null and question_image_sha256 is null and analysis_image_sha256 is null)
    then raise exception 'legacy carry claimed unavailable image evidence'; end if;
  select count(*) into before_events from app_private.chem_question_item_visual_review_events where question_id=target_id;
  perform public.chem_carry_question_item_legacy_review(target_id,source_id,'transaction-test','Idempotent carry should preserve the immutable original audit.');
  select count(*) into after_events from app_private.chem_question_item_visual_review_events where question_id=target_id;
  if before_events<>after_events then raise exception 'idempotent carry rewrote review history'; end if;

  rejected:=false;
  begin update app_private.chem_question_item_visual_reviews
    set review_checks=jsonb_set(review_checks,'{source_image_complete}','true'::jsonb) where question_id=target_id;
  exception when check_violation then rejected:=true; end;
  if not rejected then raise exception 'legacy review may not claim complete original images'; end if;
  rejected:=false;
  begin update app_private.chem_question_item_legacy_carries set source_question_id=other_source_id where question_id=target_id;
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'immutable legacy lineage was rewritten'; end if;
  rejected:=false;
  begin delete from app_private.chem_junior_visual_legacy_origins where question_id=other_source_id;
  exception when raise_exception then rejected:=true; end;
  if not rejected then raise exception 'captured legacy allowlist was deleted'; end if;

  -- Stale target identity closes access even if somebody tampers with the
  -- review row; no source question content is edited in this test.
  begin
    update app_private.chem_question_item_visual_reviews set revision_token=repeat('0',64) where question_id=target_id;
    if app_private.chem_question_item_delivery_review_ready(target_id) then raise exception 'stale legacy revision remained ready'; end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;
  -- Old source content already has an immutable activated-source contract.
  -- The new lineage helper adds a separate frozen release-manifest assertion.
  rejected:=false;
  begin
    perform set_config('app.chem_junior_release_lifecycle','on',true);
    update public.chem_questions set explanation=explanation||' changed' where id=source_id;
  exception when raise_exception then rejected:=true; end;
  perform set_config('app.chem_junior_release_lifecycle','off',true);
  if not rejected then raise exception 'activated source content unexpectedly became mutable'; end if;
  begin
    perform set_config('app.chem_junior_release_lifecycle','on',true);
    update app_private.chem_question_source_releases set manifest_sha256=repeat('9',64) where id=base_release.id;
    if app_private.chem_junior_visual_legacy_origin_valid(source_id)
      or app_private.chem_question_item_delivery_review_ready(target_id) then
      raise exception 'changed legacy release manifest remained accepted';
    end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;
  begin
    perform set_config('app.chem_junior_release_lifecycle','on',true);
    update app_private.chem_question_source_releases set status='retired' where id=base_release.id;
    if not app_private.chem_question_item_delivery_review_ready(target_id) then
      raise exception 'legitimate old-base retirement invalidated unchanged carried evidence';
    end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;
  begin
    perform public.chem_queue_question_item_visual_recheck(source_id,'The original legacy source now needs a targeted source recheck.','transaction-test');
    if app_private.chem_junior_visual_legacy_origin_valid(source_id)
      or app_private.chem_question_item_delivery_review_ready(target_id) then
      raise exception 'an explicit source recheck did not invalidate inherited delivery';
    end if;
    update app_private.chem_question_item_visual_reviews set review_state='rejected' where question_id=source_id;
    if app_private.chem_question_item_delivery_review_ready(target_id) then raise exception 'a rejected original remained inheritable'; end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;
  begin
    insert into app_private.chem_question_delivery_holds(anchor_question_id,reason)
      values(source_id,'Transaction test: hold on the captured original must propagate to copied items.')
      on conflict(anchor_question_id) do update set reason=excluded.reason,resolved_at=null;
    if app_private.chem_junior_visual_legacy_origin_valid(source_id)
      or app_private.chem_question_item_delivery_review_ready(target_id) then
      raise exception 'explicit source delivery hold did not invalidate inherited access';
    end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;
  begin
    insert into app_private.chem_question_delivery_holds(anchor_question_id,reason)
      values(target_id,'Transaction test: hold on the copied item must invalidate its carried delivery.')
      on conflict(anchor_question_id) do update set reason=excluded.reason,resolved_at=null;
    if app_private.chem_question_item_delivery_review_ready(target_id) then
      raise exception 'explicit target delivery hold did not invalidate inherited access';
    end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;
  begin
    perform public.chem_queue_question_item_visual_recheck(target_id,'The copied legacy item now needs an original-image recheck.','transaction-test');
    if app_private.chem_question_item_delivery_review_ready(target_id) then raise exception 'target recheck did not close legacy readiness'; end if;
    rejected:=false;
    begin perform public.chem_carry_question_item_legacy_review(target_id,source_id,'transaction-test','A recheck after inheritance must require real verification.');
    exception when raise_exception then rejected:=true; end;
    if not rejected then raise exception 'a previously carried recheck was erased'; end if;
    raise exception using errcode='PZ001',message='rollback this test case';
  exception when sqlstate 'PZ001' then null; end;

  if exists(select 1 from app_private.chem_question_item_legacy_carries where question_id=novel_id)
    or novel_review is distinct from (select to_jsonb(v) from app_private.chem_question_item_visual_reviews v where v.question_id=novel_id) then
    raise exception 'new oxygen verification was replaced or changed by unrelated legacy inheritance';
  end if;
  if other_grades_before is distinct from (select md5(coalesce(string_agg(id,',' order by id),''))
      from app_private.chem_teaching_ready_questions where grade_band<>'初三') then
    raise exception 'junior legacy inheritance changed another grades visible question IDs';
  end if;
  if has_function_privilege('anon','public.chem_carry_question_item_legacy_review(text,text,text,text)','execute')
    or has_function_privilege('authenticated','public.chem_capture_junior_visual_legacy_base(uuid,text,text,text)','execute')
    or has_table_privilege('service_role','app_private.chem_junior_visual_legacy_origins','insert') then
    raise exception 'legacy registration or immutable ledger is exposed to a public/direct-write role';
  end if;
end;
$test$;
rollback;
select 'legacy carry integration passed; all test audit writes rolled back' as result;
