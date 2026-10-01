-- Connect the seven visually checked original 7.3 questions to their textbook section.
do $verified_section$
declare
  v_release constant uuid := '6b7b37e8-f10c-508a-ac26-ee2e7dc6b41a';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.status='active'
      and r.expected_question_count=395
      and r.manifest_sha256='2c4640787a611cd3d6e284340b688eb19d03c065856f2ca7e513ea8b11fa24be'
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception '7.3 source-paired junior release is not active and fully verified';
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
     'c79eb25428aca3edf625f4c9dbcb58e45f7c250a76ffca7483ccc2604241b46c',
     'fb707d6ad06e9aefe221f1b20d4c3c6ebf0007e6a4a8cfb97aa80b2463942ae7'
   )
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_SOLUTION_CONCENTRATION'
    and q.usable_for_review;
  if v_count<>7 then
    raise exception 'expected seven visually checked 7.3 originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.J.KY.U07.S03',
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
    on t.id='CHEM.J.KY.U07.S03' and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_SOLUTION_CONCENTRATION'
    and q.usable_for_review
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_SOLUTION_CONCENTRATION'
    and link.topic_id='CHEM.J.KY.U07.S03';
  if v_count<>7 then
    raise exception '7.3 section links incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics set updated_at=now()
  where id='CHEM.J.KY.U07.S03';
end;
$verified_section$;
