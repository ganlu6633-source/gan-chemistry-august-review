-- Preserve all existing release and visual verification guards; support explicitly labeled source fill-ins only.
do $patch$
declare
 before_definition text:=pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure);
 after_definition text;
 old_policy text:=$old$          'teacher_verified_exact_reflow_of_registered_source',
          'source_crop_sanitized'$old$;
 new_policy text:=$new$          'teacher_verified_exact_reflow_of_registered_source',
          'teacher_verified_multiple_choice_adaptation',
          'source_crop_sanitized'$new$;
 original_anchor text:=$anchor$    raise exception 'release contains an incomplete or non-canonical public source record';
  end if;
$anchor$;
 adapted_guard text:=$guard$
  -- A genuine source fill-in may be presented as four choices only with explicit provenance.
  if exists (
    select 1 from public.chem_questions q
    where q.source_release_id=p_release_id
      and q.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'
      and (
        q.grade_band<>'高一' or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'
        or position('原填空改四选' in coalesce(q.source_info->>'title',''))=0
        or q.source_info->>'sourcePairingStatus'<>'SOURCE_NATIVE_PAIR'
        or q.source_info->>'optionTranscriptionPolicy'<>'native_fill_in_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original conditions and correct answer preserved'
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind' is distinct from 'native_fill_in_to_four_choices'
        or coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalPrompt'),'')=''
        or coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalCorrectAnswer'),'')=''
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'generatedOptions' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'originalConditionsUnchanged' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'correctChoiceMatchesOriginal' is distinct from 'true'::jsonb
        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb
      )
  ) then
    raise exception 'Source fill-in choice adaptation lacks explicit original prompt, key, generated choices or native provenance';
  end if;
$guard$;
begin
 if md5(before_definition)<>'e4fc7e7134a4ed7a1ccaf8aa1050b580' then
   raise exception 'Teaching release activation changed before explicit adaptation patch'; end if;
 if (length(before_definition)-length(replace(before_definition,old_policy,'')))/length(old_policy)<>1
  or (length(before_definition)-length(replace(before_definition,original_anchor,'')))/length(original_anchor)<>1 then
   raise exception 'Expected unique source contract insertion points missing'; end if;
 after_definition:=replace(replace(before_definition,old_policy,new_policy),original_anchor,original_anchor||adapted_guard);
 execute after_definition;
 if pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure)<>after_definition then
   raise exception 'Unexpected activation definition after exact guarded patch'; end if;
end $patch$;
