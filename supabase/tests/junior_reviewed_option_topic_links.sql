begin;
do $$
declare
  v_topics integer;
  v_pairs integer;
  v_invalid integer;
begin
  select count(distinct m.topic_id),count(*)
  into v_topics,v_pairs
  from app_private.chem_teaching_question_topics m
  join app_private.chem_teaching_topics t on t.id=m.topic_id
  join app_private.chem_teaching_ready_questions q on q.id=m.question_id
  where q.grade_band='初三'
    and '初三'=any(t.grade_bands)
    and m.evidence->>'kind'='reviewed_option_binding_current_revision';
  if v_topics < 10 or v_pairs < 49 then
    raise exception 'Junior reviewed option links missing: % topics, % pairs',v_topics,v_pairs;
  end if;

  select count(*) into v_invalid
  from app_private.chem_teaching_question_topics m
  join app_private.chem_teaching_topics t on t.id=m.topic_id
  join app_private.chem_teaching_ready_questions q on q.id=m.question_id
  where m.evidence->>'kind'='reviewed_option_binding_current_revision'
    and (
      q.grade_band<>'初三'
      or not '初三'=any(t.grade_bands)
      or not exists (
        select 1
        from app_private.chem_option_practice_bindings b
        where b.same_type_key=m.evidence->>'sameTypeKey'
          and b.review_status='verified'
          and (
            (b.anchor_question_id=q.id and b.anchor_revision_token=q.question_revision_token)
            or exists (
              select 1
              from jsonb_array_elements(coalesce(b.candidates,'[]'::jsonb)) c(value)
              where c.value->>'questionId'=q.id
                and c.value->>'revisionToken'=q.question_revision_token
            )
          )
      )
    );
  if v_invalid<>0 then
    raise exception 'Junior micro-topic link mismatches: %',v_invalid;
  end if;
end;
$$;
rollback;
