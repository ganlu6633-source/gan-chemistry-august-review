-- Repairs the server-only REVIEW personalizer without broadening access.
--
-- The prior suffix planner tried to consume nearly every compatible original
-- in the remaining calendar.  Because one daily package cannot contain the
-- same fine concept twice, that aggregate-only budget could strand several
-- originals in too few concepts near the end of the window.  Keep deliberate
-- headroom and cap each concept by the number of remaining dates.

begin;

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('review-personalization-runtime-contract', 0)
);

do $migration$
declare
  v_definition text;
  v_old text := $old$
    v_remaining_question_budget := least(
      v_fresh_questions - v_anchor_question_count,
      v_remaining_plan_count * 8
    );
$old$;
  v_new text := $new$
    -- A concept can appear at most once per daily package.  Aggregate source
    -- capacity therefore has to be capped by remaining dates per concept.
    -- Retaining twenty percent headroom prevents a late suffix from being
    -- forced into an impossible all-capacity matching.  The anchor itself may
    -- still contain all 1..8 unresolved concepts from today's evidence.
    select coalesce(sum(least(
        per_concept.fresh_questions
          - case
              when per_concept.concept_key = any(p_anchor_concept_keys) then 1
              else 0
            end,
        v_remaining_plan_count
      )), 0)::integer
    into v_remaining_question_budget
    from (
      select fresh.concept_key, count(*)::integer as fresh_questions
      from _suffix_fresh_original fresh
      group by fresh.concept_key
    ) per_concept;

    v_remaining_question_budget := least(
      v_remaining_question_budget,
      greatest(
        v_remaining_plan_count,
        v_first_pass_concepts,
        least(
          floor(v_remaining_question_budget * 0.80)::integer,
          v_remaining_plan_count * 7
        )
      )
    );
$new$;
  v_occurrences integer;
begin
  select pg_catalog.pg_get_functiondef(
    'app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])'::regprocedure
  ) into v_definition;

  if pg_catalog.strpos(v_definition, v_new) = 0 then
    v_occurrences := (
      pg_catalog.length(v_definition)
      - pg_catalog.length(pg_catalog.replace(v_definition, v_old, ''))
    ) / pg_catalog.length(v_old);

    if v_occurrences <> 1 then
      raise exception
        'review suffix planner source drifted; expected one budget block, found %',
        v_occurrences;
    end if;

    v_definition := pg_catalog.replace(v_definition, v_old, v_new);
    execute v_definition;
  end if;

  select pg_catalog.pg_get_functiondef(
    'app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])'::regprocedure
  ) into v_definition;

  if pg_catalog.strpos(v_definition, v_new) = 0
     or pg_catalog.strpos(v_definition, v_old) <> 0 then
    raise exception 'review suffix planner headroom patch did not persist';
  end if;
end
$migration$;

-- The public personalizer is SECURITY INVOKER and is executable only by the
-- server role.  It needs read-only access to issued-answer identities so it
-- can refuse duplicate originals and never reshuffle an opened plan.
revoke all on table app_private.chem_question_answer_locks
  from public, anon, authenticated;
grant usage on schema app_private to service_role;
grant select on table app_private.chem_question_answer_locks to service_role;

revoke all on function app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])
  from public, anon, authenticated;
grant execute on function app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[])
  to service_role;

do $$
begin
  if not pg_catalog.has_table_privilege(
      'service_role',
      'app_private.chem_question_answer_locks',
      'SELECT'
    )
     or pg_catalog.has_table_privilege(
       'anon',
       'app_private.chem_question_answer_locks',
       'SELECT'
     )
     or pg_catalog.has_table_privilege(
       'authenticated',
       'app_private.chem_question_answer_locks',
       'SELECT'
     )
  then
    raise exception 'answer-lock least-privilege contract failed';
  end if;
end $$;

comment on function app_private.chem_rebudget_unstarted_review_suffix(uuid,uuid,text[]) is
  'Server-only atomic REVIEW suffix planner: preserves a 1..8 unresolved-concept anchor, re-funds later unstarted dates with per-concept date caps and source headroom, and fails closed without changing opened plans.';

commit;
