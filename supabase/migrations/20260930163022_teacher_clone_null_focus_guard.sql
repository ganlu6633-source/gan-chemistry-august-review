-- SQL UNKNOWN is not proof that a preferred question matches the target.
-- Keep the existing helper privileges and all source/ownership gates unchanged.
do $migration$
declare
 definition text:=replace(pg_get_functiondef('app_private.chem_clone_choice_policy(uuid,uuid)'::regprocedure),E'\r\n',E'\n');
 old_match text:=$old$   focus_found:=focus_found or (q->>'skill_id'=any(reference.focus_skill_ids)
    and (cardinality(coalesce(target_plan.target_concept_keys,'{}'))=0
      or q->>'concept_key'=any(target_plan.target_concept_keys)));$old$;
 new_match text:=$new$   focus_found:=coalesce(focus_found,false) or coalesce((q->>'skill_id'=any(reference.focus_skill_ids)
    and (cardinality(coalesce(target_plan.target_concept_keys,'{}'))=0
      or q->>'concept_key'=any(target_plan.target_concept_keys))),false);$new$;
begin
 if (length(definition)-length(replace(definition,old_match,'')))/length(old_match)<>1
  or strpos(definition,'if not focus_found then')=0
  or strpos(definition,'if cardinality(preferred)<>8 or not focus_found then')=0 then
  raise exception 'teacher clone focus implementation changed; review NULL guard before applying';
 end if;
 definition:=replace(definition,old_match,new_match);
 definition:=replace(definition,'if not focus_found then','if focus_found is not true then');
 definition:=replace(definition,'if cardinality(preferred)<>8 or not focus_found then','if cardinality(preferred)<>8 or focus_found is not true then');
 execute definition;
end $migration$;
