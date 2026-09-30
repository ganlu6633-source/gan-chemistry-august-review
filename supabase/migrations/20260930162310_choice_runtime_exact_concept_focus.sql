-- New sessions must actually train their selected small knowledge point.
-- Frozen sessions and saved answers retain their original source snapshots.
do $migration$
declare
 definition text:=replace(pg_get_functiondef('app_private.chem_choice_projection(uuid,uuid,jsonb)'::regprocedure),E'\r\n',E'\n');
 old_order text:=$old$       order by coalesce(array_position(c.preferred_base_ids,e.key),1001),
         case when e.value->>'skill_id'=any(c.focus_skill_ids) then 0 else 1 end,
         (e.value->>'level')::integer,e.key loop$old$;
 new_order text:=$new$       order by case when e.value->>'skill_id'=any(c.focus_skill_ids)
           and (cardinality(coalesce(p.target_concept_keys,'{}'))=0
             or e.value->>'concept_key'=any(p.target_concept_keys)) then 0 else 1 end,
         coalesce(array_position(c.preferred_base_ids,e.key),1001),
         case when e.value->>'skill_id'=any(c.focus_skill_ids) then 0 else 1 end,
         (e.value->>'level')::integer,e.key loop$new$;
 old_guard text:=$old$     if cardinality(base_ids)<>8 then pending_reason:='base_source_gap'; questions:='[]'; base_ids:='{}'; end if;$old$;
 new_guard text:=$new$     if cardinality(base_ids)<>8 or not exists(
       select 1 from jsonb_array_elements(questions) selected_question
       where selected_question->>'skill_id'=any(c.focus_skill_ids)
        and (cardinality(coalesce(p.target_concept_keys,'{}'))=0
          or selected_question->>'concept_key'=any(p.target_concept_keys))
     ) then pending_reason:='base_source_gap'; questions:='[]'; base_ids:='{}'; end if;$new$;
begin
 if (length(definition)-length(replace(definition,old_order,'')))/length(old_order)<>1
  or (length(definition)-length(replace(definition,old_guard,'')))/length(old_guard)<>1 then
  raise exception 'choice initial source selection changed; review exact-focus migration before applying';
 end if;
 execute replace(replace(definition,old_order,new_order),old_guard,new_guard);
end $migration$;
