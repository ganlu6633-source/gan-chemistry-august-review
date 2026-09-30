-- Attach seven source-paired 9.1 original questions to their textbook section.
do $verified_section$
declare
  v_release constant uuid := 'e45975f5-1ace-5e94-a86d-2bc12b621788';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.status='active'
      and r.expected_question_count=338
      and r.manifest_sha256='3f7e7a178fec3d57436bf97617558744a353b968c1d59dd616d42f98119d2315'
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception '9.1 source-paired junior release is not active and fully verified';
  end if;

  select count(*) into v_count
  from public.chem_questions q
  join app_private.chem_question_item_visual_reviews v
    on v.question_id=q.id and v.source_release_id=v_release
   and v.review_state='verified' and v.revision_token=q.question_revision_token
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
   and d.source_document_sha256 in (
     '161a5bc7723ad31ece04bc28281df2185d96806f7b95768bc5a4a6c1ad534898',
     '8d633fd592479294450384f4890a6d2d0fa90ef0e19ffb10f7f725ce10555fe9',
     '88e8f4a07c3975940547d0f96be06a80829694ddef221b3e66dd5728cd243b24'
   )
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_ORGANIC_BASICS'
    and q.usable_for_review;
  if v_count<>7 then
    raise exception 'expected seven visually checked 9.1 originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.J.KY.U09.S01',
    jsonb_build_object(
      'kind','visually_verified_textbook_section',
      'textbookVersion','科粤版',
      'knowledgeId',q.knowledge_id,
      'questionRevisionToken',q.question_revision_token,
      'sourceLocator',d.source_locator,
      'sourceDocumentSha256',d.source_document_sha256,
      'sourceReleaseId',v_release
    )
  from public.chem_questions q
  join app_private.chem_teaching_topics t
    on t.id='CHEM.J.KY.U09.S01' and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_ORGANIC_BASICS'
    and q.usable_for_review
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_ORGANIC_BASICS'
    and link.topic_id='CHEM.J.KY.U09.S01';
  if v_count<>7 then
    raise exception '9.1 section links incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics set updated_at=now()
  where id='CHEM.J.KY.U09.S01';
end;
$verified_section$;
