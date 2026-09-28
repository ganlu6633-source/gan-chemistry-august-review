-- A release can no longer become active with merely a verified manifest.
-- Each of its questions must already have an individual review of the exact
-- current revision. This catches missing formulas at publication time, before
-- the teacher attempts to schedule the question.
begin;

do $patch$
declare
  signature text;
  definition text;
  needle constant text :=
    'perform pg_catalog.set_config(''app.chem_release_activation'', ''on'', true);';
  inserted constant text := $code$
  if exists (
    select 1 from public.chem_questions question
    where question.source_release_id = p_release_id
      and not app_private.chem_question_item_delivery_review_ready(question.id)
  ) then
    raise exception 'release contains a question without current item-level source review';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);$code$;
  occurrences integer;
begin
  foreach signature in array array[
    'public.chem_activate_teaching_material_release(uuid,text)',
    'public.chem_activate_source_original_release(uuid,text)'
  ] loop
    definition := replace(pg_get_functiondef(signature::regprocedure), chr(13), '');
    occurrences := (length(definition) - length(replace(definition, needle, '')))
      / length(needle);
    if occurrences <> 1 then
      raise exception 'Expected one activation anchor in %, found %', signature, occurrences;
    end if;
    execute replace(definition, needle, inserted);
  end loop;
end
$patch$;

commit;
