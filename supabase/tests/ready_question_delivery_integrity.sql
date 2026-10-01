-- Run against a populated teaching database after source releases are loaded.
-- This catches broken delivery wiring, not chemistry errors in the source.
begin;
do $audit$
declare
  v_ready integer;
  v_bad integer;
begin
  select count(*) into v_ready from app_private.chem_teaching_ready_questions;
  if v_ready = 0 then raise exception 'No teaching-ready questions to audit'; end if;

  select count(*) into v_bad
  from app_private.chem_teaching_ready_questions ready
  join public.chem_questions q on q.id=ready.id
  where not exists (
    select 1 from app_private.chem_teaching_question_topics route
    join app_private.chem_teaching_topics topic on topic.id=route.topic_id
    where route.question_id=q.id and q.grade_band=any(topic.grade_bands)
  );
  if v_bad<>0 then raise exception '% ready questions have no grade-matched knowledge-point route',v_bad; end if;

  select count(*) into v_bad
  from app_private.chem_teaching_ready_questions ready
  join public.chem_questions q on q.id=ready.id
  where jsonb_typeof(q.options)<>'array' or jsonb_array_length(q.options)<>4
    or q.correct_option not between 0 and 3
    or length(btrim(q.stem))=0 or length(btrim(q.explanation))=0
    or (select count(distinct btrim(option_text)) from jsonb_array_elements_text(q.options) option_text)<>4
    or q.stem like '%[图片:%' or q.options::text like '%[图片:%' or q.explanation like '%[图片:%'
    or q.stem like '%【待补%' or q.options::text like '%【待补%' or q.explanation like '%【待补%';
  if v_bad<>0 then raise exception '% ready questions have incomplete four-choice content',v_bad; end if;

  select count(*) into v_bad
  from app_private.chem_teaching_ready_questions ready
  join public.chem_questions q on q.id=ready.id
  where q.render_mode='image_primary' and (
    (select count(*) from app_private.chem_question_assets a where a.question_id=q.id)<>2
    or (select count(*) from app_private.chem_question_assets a where a.question_id=q.id and a.asset_kind='question_image')<>1
    or (select count(*) from app_private.chem_question_assets a where a.question_id=q.id and a.asset_kind='analysis_image')<>1
  );
  if v_bad<>0 then raise exception '% ready image questions have missing or extra images',v_bad; end if;

  select count(*) into v_bad
  from app_private.chem_question_assets a
  join app_private.chem_teaching_ready_questions ready on ready.id=a.question_id
  where encode(extensions.digest(decode(a.payload_base64,'base64'),'sha256'),'hex')<>a.sha256;
  if v_bad<>0 then raise exception '% ready-question images do not match their stored checksum',v_bad; end if;
end $audit$;
rollback;
