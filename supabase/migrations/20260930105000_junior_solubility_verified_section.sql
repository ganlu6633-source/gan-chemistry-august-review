-- Connect the seven visually checked original 7.2 questions to their textbook section.
do $verified_section$
declare
  v_release constant uuid := '4cd29840-3dd6-5a89-a7e2-af999c718ba4';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.status='active'
      and r.expected_question_count=388
      and r.manifest_sha256='b80b4eea44107427032e07fc9c6bc24afe6646899e12f0af3f21e7d9964e81f6'
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception '7.2 source-paired junior release is not active and fully verified';
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
     'e9be58ce019cf6cbfe5869fae95f79f8bc459fe70dd6ac7cf718729702f70def',
     '468546ecceff65b3e31ed0e9d5b20596b4e428508f31e7cad90c76beb0edff2a'
   )
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_SOLUBILITY'
    and q.usable_for_review;
  if v_count<>7 then
    raise exception 'expected seven visually checked 7.2 originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.J.KY.U07.S02',
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
    on t.id='CHEM.J.KY.U07.S02' and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_SOLUBILITY'
    and q.usable_for_review
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_SOLUBILITY'
    and link.topic_id='CHEM.J.KY.U07.S02';
  if v_count<>7 then
    raise exception '7.2 section links incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics set updated_at=now()
  where id='CHEM.J.KY.U07.S02';
end;
$verified_section$;
