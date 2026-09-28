-- Run on a database with one activated same-fingerprint teaching revision.
-- All deliberately changed review evidence rolls back.
begin;
do $test$
declare
  v_old text;
  v_new text;
  v_expected bigint;
  v_actual bigint;
  v_hold_def text;
  v_activation_def text;
begin
  select old_q.id,new_q.id into v_old,v_new
  from public.chem_questions old_q
  join public.chem_questions new_q
    on new_q.parent_source_item_key=old_q.source_item_key
   and new_q.grade_band=old_q.grade_band
   and new_q.content_fingerprint=old_q.content_fingerprint
   and new_q.id<>old_q.id
  join app_private.chem_question_source_releases release
    on release.id=new_q.source_release_id
   and release.status='active'
   and release.verification_status='full_visual_verified'
  join app_private.chem_question_source_release_items child_item
    on child_item.release_id=new_q.source_release_id and child_item.question_id=new_q.id
  join app_private.chem_question_source_release_items parent_item
    on parent_item.release_id=old_q.source_release_id and parent_item.question_id=old_q.id
   and parent_item.canonical_source_id=child_item.canonical_source_id
  where exists(select 1 from app_private.chem_question_delivery_holds h
               where h.anchor_question_id=old_q.id and h.resolved_at is null)
  order by new_q.id limit 1;
  if v_old is null then raise exception 'requires one exact-lineage held predecessor fixture'; end if;

  if exists(select 1 from app_private.chem_teaching_ready_questions where id=v_old)
     or not exists(select 1 from public.chem_question_delivery_holds() where question_id=v_old)
     or not exists(select 1 from app_private.chem_teaching_ready_questions where id=v_new)
     or exists(select 1 from public.chem_question_delivery_holds() where question_id=v_new)
     or not app_private.chem_question_item_visual_reviewed(v_new)
  then raise exception 'held old and verified new revision delivery are inconsistent'; end if;

  select pg_get_functiondef('public.chem_question_delivery_holds()'::regprocedure)
    into v_hold_def;
  select pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure)
    into v_activation_def;
  if position('q.parent_source_item_key=anchor.source_item_key' in v_hold_def)=0
    or position('parent_item.canonical_source_id=child_item.canonical_source_id' in v_hold_def)=0
    or position('app_private.chem_question_item_visual_reviewed(q.id)' in v_hold_def)=0
    or position('h.resolved_at is null' in v_activation_def)=0
    or position('old_q.content_fingerprint = new_q.content_fingerprint' in v_activation_def)=0
  then raise exception 'hold exemption or activation retired-source rules weakened'; end if;

  select count(*) into v_expected
  from public.chem_learning_plans p
  join public.chem_students_v2 s on s.id=p.student_id
  cross join lateral jsonb_array_elements_text(coalesce(
    s.metadata#>array['reviewProgram','questionAssignments',p.plan_date::text],
    '[]'::jsonb)) assigned
  where p.is_scheduled and p.plan_date>=(now() at time zone 'Asia/Shanghai')::date;
  select count(*) into v_actual from app_private.chem_future_plan_source_qa_audit;
  if v_expected<>v_actual then
    raise exception 'future source QA view dropped fixed assignments: % <> %',v_actual,v_expected;
  end if;

  -- A later visual-review withdrawal must once again inherit the old source
  -- hold and leave the delivery pool, even though the release stays active.
  update app_private.chem_question_item_visual_reviews
  set review_state='pending' where question_id=v_new;
  if not exists(select 1 from public.chem_question_delivery_holds() where question_id=v_new)
    or exists(select 1 from app_private.chem_teaching_ready_questions where id=v_new)
  then raise exception 'unreviewed child failed to inherit the predecessor hold'; end if;
end;
$test$;
rollback;
