-- Expose only the seven source-paired 5.1 hydrogen questions in the textbook section.
do $verified_section$
declare
  v_release constant uuid := 'aabf2365-aabd-58d2-a5c3-544399ea2b6f';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.status='active'
      and r.expected_question_count=345
      and r.manifest_sha256='176d0d92ca90b13d73e35cf05b3d42ae0a3ae4ae0f74bba27991342681734d1f'
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception '5.1 source-paired junior release is not active and fully verified';
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
     '2b7cd0573d9f5c472e71d655c8a9241f475df51734ab49cf7ba6b00adddc68d7',
     '8d633fd592479294450384f4890a6d2d0fa90ef0e19ffb10f7f725ce10555fe9'
   )
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_HYDROGEN_FUEL'
    and q.usable_for_review;
  if v_count<>7 then
    raise exception 'expected seven visually checked 5.1 originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id,'CHEM.J.KY.U05.S01',
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
    on t.id='CHEM.J.KY.U05.S01' and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_HYDROGEN_FUEL'
    and q.usable_for_review
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics link
  join public.chem_questions q on q.id=link.question_id
  where q.source_release_id=v_release
    and q.knowledge_id='J_KY_HYDROGEN_FUEL'
    and link.topic_id='CHEM.J.KY.U05.S01';
  if v_count<>7 then
    raise exception '5.1 section links incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics set updated_at=now()
  where id='CHEM.J.KY.U05.S01';
end;
$verified_section$;
