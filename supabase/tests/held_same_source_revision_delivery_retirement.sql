-- Insert before activation inside the exact eight-question staged rollback fixture.

do $qa$ declare blocked boolean; begin
  if not app_private.chem_replacement_has_exact_source_ancestor('ba6fad4a-0c3b-5b27-bf06-6003bd8748e9','QH2SCI06_40560927FBF069AA','QH2R2_20260908_02AB0B75EAE68016906856E935583EA4') then raise exception 'known exact ancestor missing'; end if;
  if app_private.chem_replacement_has_exact_source_ancestor('ba6fad4a-0c3b-5b27-bf06-6003bd8748e9','QH2SCI06_40560927FBF069AA','QH2PR30_4DB3946C519BE55F230578075097F7DF') then raise exception 'unrelated original accepted'; end if;

  blocked:=false;
  begin
    update public.chem_questions set usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4';
  exception when others then
    if position('activate a complete new release' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'direct retirement was incorrectly allowed'; end if;
  perform set_config('app.chem_release_activation','on',true);
  perform set_config('app.chem_held_revision_retirement','ba6fad4a-0c3b-5b27-bf06-6003bd8748e9',true);

  blocked:=false;
  begin
    update public.chem_questions set stem=stem||' qa illegal change',usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4';
  exception when others then
    if position('immutable' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'content change while retiring was incorrectly allowed'; end if;

  blocked:=false;
  begin
    update app_private.chem_question_delivery_holds set resolved_at=now() where anchor_question_id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4'; update public.chem_questions set usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4';
  exception when others then
    if position('immutable' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'retirement without unresolved hold was incorrectly allowed'; end if;

  blocked:=false;
  begin
    update app_private.chem_question_source_release_items set canonical_source_id='qa-unrelated-original' where release_id='ba6fad4a-0c3b-5b27-bf06-6003bd8748e9' and question_id='QH2SCI06_40560927FBF069AA'; update public.chem_questions set usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4';
  exception when others then
    if position('immutable' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'different canonical retirement was incorrectly allowed'; end if;

  blocked:=false;
  begin
    delete from app_private.chem_question_source_release_lineage where release_id='ba6fad4a-0c3b-5b27-bf06-6003bd8748e9' and question_id='QH2SCI06_40560927FBF069AA'; update public.chem_questions set usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4';
  exception when others then
    if position('immutable' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'missing exact lineage was incorrectly allowed'; end if;

  blocked:=false;
  begin
    update app_private.chem_question_item_visual_reviews set review_state='pending' where question_id='QH2SCI06_40560927FBF069AA'; update public.chem_questions set usable_for_review=false,usable_for_class_quiz=false,usable_for_exam_sprint=false,usable_for_demo=false where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4';
  exception when others then
    if position('immutable' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'unreviewed replacement was incorrectly allowed'; end if;
  perform set_config('app.chem_release_activation','off',true);
  perform set_config('app.chem_held_revision_retirement','',true);

  blocked:=false;
  begin
    update app_private.chem_question_delivery_holds set resolved_at=now() where anchor_question_id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4'; perform public.chem_activate_teaching_material_release('ba6fad4a-0c3b-5b27-bf06-6003bd8748e9',(select manifest_sha256 from app_private.chem_question_source_releases where id='ba6fad4a-0c3b-5b27-bf06-6003bd8748e9'));
  exception when others then
    if position('retirement requires' in SQLERRM)=0 then raise; end if; blocked:=true;
  end;
  if not blocked then raise exception 'release without ancestor hold was incorrectly allowed'; end if;
  if exists(select 1 from (values ('anon'),('authenticated'),('service_role')) role(r)
    where has_function_privilege(role.r,'app_private.chem_retire_held_same_original_revisions(uuid)','EXECUTE')
      or has_function_privilege(role.r,'app_private.chem_replacement_has_exact_source_ancestor(uuid,text,text)','EXECUTE')) then raise exception 'retirement helper privileges leaked'; end if;
  if not exists(select 1 from pg_index where indexrelid='public.chem_questions_review_original_fingerprint_uidx'::regclass and indisunique) then raise exception 'duplicate guard removed'; end if;
end; $qa$;

-- Insert after successful activation in the same rollback fixture.

do $qa$ begin
  if exists(select 1 from qa_original_content_before b join public.chem_questions q on q.id=b.id
    where b.content is distinct from to_jsonb(q)-array['usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','updated_at']) then raise exception 'historical original content changed'; end if;
  if exists(select 1 from qa_answer_history_before b full join public.chem_attempt_answers a on a.id=b.id
    where b.content is distinct from to_jsonb(a)) then raise exception 'historical answers changed'; end if;
  if (select usable_for_review from public.chem_questions where id='QH2R2_20260908_02AB0B75EAE68016906856E935583EA4') then raise exception 'held exact ancestor not retired'; end if;
  if current_setting('app.chem_held_revision_retirement',true)<>'' or current_setting('app.chem_release_activation',true)<>'off' then raise exception 'activation bypass left enabled'; end if;
end; $qa$;
select jsonb_build_object('result','pass','reviewed_replacements',8,'negative_guard_checks',9,'historical_content_preserved',true,'student_answer_history_preserved',true,'duplicate_index_preserved',true) as result;

