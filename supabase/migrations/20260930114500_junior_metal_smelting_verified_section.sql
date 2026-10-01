-- Connect seven visually checked original 6.3 questions to their textbook section.
do $verified_section$
declare
  v_release constant uuid := '960ef405-823c-52b1-a378-7e00fab24bba';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.status='active'
      and r.expected_question_count=402
      and r.manifest_sha256='687de5f3eb560d1b4951cb334d579e480e079a19a6770915110c3830ab5cf0f2'
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception '6.3 source-paired junior release is not active and fully verified';
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
     'a7c8a22498606f9a41f1efc127a6cee7434b5e3b9ed5ec41633258e70352fd1f',
     '7fc37d2975f94e1a158fd34c871c494613192b882bafb29d5f2efd5a52a10fe5',
     '88e8f4a07c3975940547d0f96be06a80829694ddef221b3e66dd5728cd243b24',
     'ff6a3f69761951739cba02fddba16585bfb5107a45e42f1cf200e084d9132a88'
   )
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_METAL_SMELTING'
    and q.usable_for_review;
  if v_count<>7 then
    raise exception 'expected seven visually checked 6.3 originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.J.KY.U06.S03',
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
    on t.id='CHEM.J.KY.U06.S03' and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_METAL_SMELTING'
    and q.usable_for_review
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_METAL_SMELTING'
    and link.topic_id='CHEM.J.KY.U06.S03';
  if v_count<>7 then
    raise exception '6.3 section links incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics set updated_at=now()
  where id='CHEM.J.KY.U06.S03';
end;
$verified_section$;
