-- Run after the migration as database owner. No fixture is published or kept.
begin;
do $test$
declare
  rid uuid:=gen_random_uuid(); q public.chem_questions%rowtype;
  routes text[]; item jsonb; item2 jsonb; bad jsonb; failed boolean; coverage record;
begin
  select array_agg(x.knowledge_id order by x.knowledge_id) into routes from (
    select distinct knowledge_id from public.chem_questions
    where grade_band='初三' and source_kind='user_provided_local' and usable_for_review
    order by knowledge_id limit 3) x;
  if cardinality(routes)<>3 then raise exception 'fixture requires three existing junior routes'; end if;
  select * into q from public.chem_questions
    where grade_band='初三' and source_kind='user_provided_local' and knowledge_id=routes[1]
    order by id limit 1;
  perform public.chem_prepare_junior_source_release(rid,repeat('a',64),'科粤版',routes,21);
  item:=jsonb_build_object('question_id','TEST-SUB-'||rid::text||'-1','mother_id','TEST-M-'||rid::text,
    'knowledge_id',q.knowledge_id,'concept_key',q.concept_key,'level',1,
    'stem',q.stem||'（回滚验证甲）','options',q.options,'correct_option',q.correct_option,
    'explanation',q.explanation,'scaffold',null,'same_type_key',q.same_type_key,
    'source_item_key',md5(rid::text||'item1'),'parent_source_item_key',md5(rid::text||'parent'),
    'canonical_source_id','TEST.'||rid::text||'.P1','source_title','事务验证原题',
    'source_exam','事务验证','source_question_no','1(1)','source_locator_label','事务验证第1页第1题第1小问');
  perform public.chem_stage_junior_source_release_item(rid,item);
  item2:=item||jsonb_build_object('question_id','TEST-SUB-'||rid::text||'-2',
    'source_item_key',md5(rid::text||'item2'),'stem',q.stem||'（回滚验证乙）','source_question_no','1(2)');
  perform public.chem_stage_junior_source_release_item(rid,item2);
  perform app_private.chem_assert_junior_subquestion_identities(rid);
  if (select count(*) from public.chem_questions where source_release_id=rid)<>2
    or (select count(distinct parent_source_item_key) from public.chem_questions where source_release_id=rid)<>1 then
    raise exception 'two subquestions must retain exactly one original parent';
  end if;
  select * into coverage from public.chem_junior_source_reserve_coverage(rid);
  if coverage.item_count<>2 or coverage.independent_parent_count<>1
    or coverage.potential_other_parent_count<>0 or not coverage.needs_more_independent_parents then
    raise exception 'inventory report counted subquestions as independent recovery originals';
  end if;
  bad:=item||jsonb_build_object('question_id','TEST-SUB-'||rid::text||'-3',
    'source_item_key',md5(rid::text||'item3'),'stem',q.stem||'（回滚验证丙）');
  failed:=false;
  begin
    perform public.chem_stage_junior_source_release_item(rid,bad||jsonb_build_object('parent_source_item_key',md5(rid::text||'other-parent')));
  exception when raise_exception then
    if sqlerrm<>'junior subquestion parent/mother mapping is inconsistent' then raise; end if;
    failed:=true;
  end;
  if not failed then raise exception 'one mother was assigned contradictory parent identities'; end if;
  failed:=false;
  begin
    perform public.chem_stage_junior_source_release_item(rid,bad||jsonb_build_object('mother_id','TEST-OTHER-M-'||rid::text));
  exception when raise_exception then
    if sqlerrm<>'junior subquestion parent/mother mapping is inconsistent' then raise; end if;
    failed:=true;
  end;
  if not failed then raise exception 'one parent was artificially split into new mother identities'; end if;
  failed:=false;
  begin
    perform public.chem_stage_junior_source_release_item(rid,bad||jsonb_build_object(
      'mother_id','TEST-OTHER-M-'||rid::text,'parent_source_item_key',md5(rid::text||'other-parent')));
  exception when raise_exception then
    if sqlerrm<>'a junior canonical source may be shared only by subquestions of the same parent' then raise; end if;
    failed:=true;
  end;
  if not failed then raise exception 'canonical source alias was reused across unrelated parents'; end if;
  failed:=false;
  begin
    perform public.chem_stage_junior_source_release_item(rid,bad||jsonb_build_object('source_item_key',item->>'source_item_key'));
  exception when unique_violation then failed:=true; end;
  if not failed then raise exception 'source item identity uniqueness was lost'; end if;
  failed:=false;
  begin
    perform public.chem_stage_junior_source_release_item(rid,bad||jsonb_build_object('stem',item->>'stem'));
  exception when unique_violation then failed:=true; end;
  if not failed then raise exception 'duplicate content fingerprint was accepted'; end if;
  if has_function_privilege('anon','public.chem_junior_source_reserve_coverage(uuid)','execute')
    or has_function_privilege('authenticated','public.chem_junior_source_reserve_coverage(uuid)','execute') then
    raise exception 'private source inventory is exposed publicly';
  end if;
end;
$test$;
rollback;
