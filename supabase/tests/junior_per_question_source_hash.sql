-- Every assertion runs in a rollback-only transaction.
begin;
do $$
declare
  v_first text;
  v_second text;
  v_local text;
  v_revision text;
  v_rejected boolean := false;
begin
  if (select count(*) from app_private.chem_teaching_ready_questions
      where grade_band='初三') <> 289
    or (select count(*) from app_private.chem_junior_question_source_documents) <> 289
    or (select count(distinct source_document_sha256)
        from app_private.chem_junior_question_source_documents) <> 25
    or exists (
      select 1 from app_private.chem_junior_question_source_documents doc
      join app_private.chem_question_item_visual_reviews review
        on review.question_id=doc.question_id
      where review.source_document_sha256 is distinct from doc.source_document_sha256
    )
  then raise exception 'junior source hashes are not complete and consistent'; end if;

  if has_function_privilege(
      'anon','public.chem_bind_junior_question_source_document(text,text,text,text,text,text)','execute'
    ) or has_function_privilege(
      'authenticated','public.chem_bind_junior_question_source_document(text,text,text,text,text,text)','execute'
    ) or not has_function_privilege(
      'service_role','public.chem_bind_junior_question_source_document(text,text,text,text,text,text)','execute'
    )
  then raise exception 'document binding RPC has unsafe privileges'; end if;

  -- Two questions in one knowledge group really do come from two files.
  select a.id,b.id into v_first,v_second
  from app_private.chem_teaching_ready_questions a
  join app_private.chem_teaching_ready_questions b
    on b.grade_band='初三' and b.knowledge_id=a.knowledge_id and b.id>a.id
  join app_private.chem_junior_question_source_documents a_doc
    on a_doc.question_id=a.id
  join app_private.chem_junior_question_source_documents b_doc
    on b_doc.question_id=b.id
  where a.grade_band='初三'
    and a_doc.source_document_sha256<>b_doc.source_document_sha256
  limit 1;
  if v_first is null then raise exception 'test needs two sources in one knowledge group'; end if;
  update app_private.chem_junior_question_source_documents
  set source_document_sha256=repeat('0',64) where question_id=v_first;
  if app_private.chem_question_item_visual_reviewed(v_first)
    or exists(select 1 from app_private.chem_teaching_ready_questions where id=v_first)
    or not app_private.chem_question_item_visual_reviewed(v_second)
    or not exists(select 1 from app_private.chem_teaching_ready_questions where id=v_second)
  then raise exception 'wrong source hash must hold only the exact question'; end if;

  select q.id,q.question_revision_token into v_local,v_revision
  from app_private.chem_teaching_ready_questions q
  join app_private.chem_question_source_release_items item
    on item.release_id=q.source_release_id and item.question_id=q.id
  where q.grade_band='初三'
    and item.canonical_source_id ~ '^LOCAL-(DOCX|PDF)-[0-9a-f]{64}'
  limit 1;
  if v_local is null then raise exception 'test needs a LOCAL original'; end if;
  begin
    perform public.chem_bind_junior_question_source_document(
      v_local,v_revision,repeat('0',64),'deliberately wrong source',
      'source-hash-test','回归测试：故意把另一份原件绑定到这道题上'
    );
  exception when others then
    v_rejected := position('原文件摘要与该题已登记的原件身份不一致' in sqlerrm)>0;
    if not v_rejected then raise; end if;
  end;
  if not v_rejected then raise exception 'wrong LOCAL source must be rejected'; end if;
end;
$$;
rollback;
