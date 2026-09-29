-- Expose the seven source-checked original 9.3 questions in the textbook
-- section only after their complete additive release is active.
do $verified_section$
declare
  v_release constant uuid := '73abd596-d2c1-5c9b-80dc-0339e5712a25';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.status='active'
      and r.expected_question_count=331
      and r.manifest_sha256='55d6690a2cf9151b195867daba88f33b962c0284de87556841a444c40916ac67'
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception '9.3 source-paired junior release is not active and fully verified';
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
     '7fc37d2975f94e1a158fd34c871c494613192b882bafb29d5f2efd5a52a10fe5',
     '88e8f4a07c3975940547d0f96be06a80829694ddef221b3e66dd5728cd243b24',
     '8d633fd592479294450384f4890a6d2d0fa90ef0e19ffb10f7f725ce10555fe9'
   )
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_CHEMICAL_ENERGY'
    and q.usable_for_review;
  if v_count<>7 then
    raise exception 'expected seven visually checked 9.3 originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.J.KY.U09.S03',
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
    on t.id='CHEM.J.KY.U09.S03' and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_CHEMICAL_ENERGY'
    and q.usable_for_review
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_CHEMICAL_ENERGY'
    and link.topic_id='CHEM.J.KY.U09.S03';
  if v_count<>7 then
    raise exception '9.3 section links incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics set updated_at=now()
  where id='CHEM.J.KY.U09.S03';
end;
$verified_section$;
