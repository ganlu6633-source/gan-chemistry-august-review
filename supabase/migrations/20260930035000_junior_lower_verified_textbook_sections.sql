-- Expose the 21 page-checked lower-volume originals in their actual 科粤版
-- textbook sections. This maps source-backed originals only; it does not
-- invent option-level backup questions from a broad chapter label.
do $verified_sections$
declare
  v_release constant uuid := '3d73e998-e8b4-521b-a201-7ffd9444cd0d';
  v_count integer;
begin
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id=v_release and r.grade_band='初三'
      and r.textbook_version='科粤版' and r.expected_question_count=310
      and r.verification_status='full_visual_verified'
      and r.verification_manifest_sha256=r.manifest_sha256
  ) then
    raise exception 'page-reviewed junior lower release is unavailable';
  end if;

  select count(*) into v_count
  from public.chem_questions q
  join app_private.chem_question_item_visual_reviews v
    on v.question_id=q.id and v.source_release_id=v_release
   and v.review_state='verified'
   and v.revision_token=q.question_revision_token
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
   and d.source_document_sha256 =
     '161a5bc7723ad31ece04bc28281df2185d96806f7b95768bc5a4a6c1ad534898'
  where q.source_release_id=v_release
    and q.knowledge_id in ('J_KY_METALS','J_KY_SOLUTIONS','J_KY_ACID_ALKALI');
  if v_count<>21 then
    raise exception 'expected 21 distinct visually checked lower-volume originals, got %',v_count;
  end if;

  insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
  select q.id, m.topic_id,
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
  join (values
    ('J_KY_METALS','CHEM.J.KY.U06.S01'),
    ('J_KY_SOLUTIONS','CHEM.J.KY.U07.S01'),
    ('J_KY_ACID_ALKALI','CHEM.J.KY.U08.S01')
  ) as m(knowledge_id,topic_id) on m.knowledge_id=q.knowledge_id
  join app_private.chem_teaching_topics t
    on t.id=m.topic_id and '初三'=any(t.grade_bands)
  join app_private.chem_junior_question_source_documents d
    on d.question_id=q.id and d.source_release_id=v_release
   and d.revision_token=q.question_revision_token
  where q.source_release_id=v_release
  on conflict (question_id,topic_id) do nothing;

  select count(*) into v_count
  from app_private.chem_teaching_question_topics t
  join public.chem_questions q on q.id=t.question_id
  where q.source_release_id=v_release
    and ((q.knowledge_id='J_KY_METALS' and t.topic_id='CHEM.J.KY.U06.S01')
      or (q.knowledge_id='J_KY_SOLUTIONS' and t.topic_id='CHEM.J.KY.U07.S01')
      or (q.knowledge_id='J_KY_ACID_ALKALI' and t.topic_id='CHEM.J.KY.U08.S01'));
  if v_count<>21 then
    raise exception 'junior lower textbook section mapping incomplete: %',v_count;
  end if;

  update app_private.chem_teaching_topics t set updated_at=now()
  where t.id in ('CHEM.J.KY.U06.S01','CHEM.J.KY.U07.S01','CHEM.J.KY.U08.S01');
end;
$verified_sections$;
