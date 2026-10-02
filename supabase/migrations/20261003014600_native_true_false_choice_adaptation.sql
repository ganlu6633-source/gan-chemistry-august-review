-- A genuine native judgement can become four choices only with explicit provenance.
-- Fill-in adaptation retains its own title and policy. All source/asset/release/ACL
-- gates are preserved by an exact full-function baseline and three local clauses.
do $native_judgement$
declare
 before_definition text:=pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure);
 after_definition text;
 old_title text:=$oldtitle$        or position('原填空改四选' in coalesce(q.source_info->>'title',''))=0$oldtitle$;
 new_title text:=$newtitle$        or case (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind'
          when 'native_fill_in_to_four_choices' then position('原填空改四选' in coalesce(q.source_info->>'title',''))=0
          when 'native_true_false_to_four_choices' then
            position('原判断改四选' in coalesce(q.source_info->>'title',''))=0
            or jsonb_typeof((q.source_info->>'transcriptionAuditMethod')::jsonb->'originalTrueFalseKey') is distinct from 'boolean'
            or (q.source_info->>'transcriptionAuditMethod')::jsonb->'correctChoiceStatesOriginalJudgement' is distinct from 'true'::jsonb
          else true end$newtitle$;
 old_policy text:=$oldpolicy$        or q.source_info->>'optionTranscriptionPolicy'<>'native_fill_in_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original conditions and correct answer preserved'$oldpolicy$;
 new_policy text:=$newpolicy$        or case (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind'
          when 'native_fill_in_to_four_choices' then
            q.source_info->>'optionTranscriptionPolicy' is distinct from 'native_fill_in_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original conditions and correct answer preserved'
          when 'native_true_false_to_four_choices' then
            q.source_info->>'optionTranscriptionPolicy' is distinct from 'native_true_false_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original judgement, conditions and correct answer preserved'
          else true end$newpolicy$;
 old_kind text:=$oldkind$        or (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind' is distinct from 'native_fill_in_to_four_choices'$oldkind$;
 new_kind text:=$newkind$        or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind','') not in ('native_fill_in_to_four_choices','native_true_false_to_four_choices')$newkind$;
begin
 if md5(before_definition)<>'bd6a2b059365f22dfed6af575d0cd2d4' then
   raise exception 'Activation changed before native true-false adaptation patch'; end if;
 if (length(before_definition)-length(replace(before_definition,old_title,'')))/length(old_title)<>1
  or (length(before_definition)-length(replace(before_definition,old_policy,'')))/length(old_policy)<>1
  or (length(before_definition)-length(replace(before_definition,old_kind,'')))/length(old_kind)<>1 then
   raise exception 'Expected unique adaptation title, policy and kind clauses missing'; end if;
 after_definition:=replace(replace(replace(before_definition,old_title,new_title),old_policy,new_policy),old_kind,new_kind);
 execute after_definition;
 if pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure)<>after_definition then
   raise exception 'Unexpected activation definition after native true-false adaptation patch'; end if;
end $native_judgement$;
