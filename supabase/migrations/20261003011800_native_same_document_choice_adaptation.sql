-- Same-document source questions and keys retain honest EXACT provenance.
-- All existing source, item-review, visual, asset, revision and role gates remain intact.
do $source_variant$
declare
 before_definition text:=pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure);
 after_definition text;
 old_pair text:=$oldpair$        or q.source_info->>'sourcePairingStatus'<>'SOURCE_NATIVE_PAIR'$oldpair$;
 new_pair text:=$newpair$        or q.source_info->>'sourcePairingStatus' not in ('EXACT','SOURCE_NATIVE_PAIR')$newpair$;
 old_proof text:=$oldproof$        or (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb$oldproof$;
 new_proof text:=$newproof$        or (q.source_info->>'sourcePairingStatus'='SOURCE_NATIVE_PAIR'
          and (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb)
        or (q.source_info->>'sourcePairingStatus'='EXACT'
          and (
            (q.source_info->>'transcriptionAuditMethod')::jsonb->>'originalSourceMode' is distinct from 'same_native_question_and_key'
            or (q.source_info->>'transcriptionAuditMethod')::jsonb->'nativeSameDocumentQuestionAndKeyProofRetained' is distinct from 'true'::jsonb
            or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'nativeOriginalDocumentSha256','') !~ '^[0-9a-f]{64}$'
          ))$newproof$;
begin
 if md5(before_definition)<>'caa3466f6ce637691c681e39d51b9b5d' then
   raise exception 'Explicit adaptation activation changed before same-document proof patch'; end if;
 if (length(before_definition)-length(replace(before_definition,old_pair,'')))/length(old_pair)<>1
  or (length(before_definition)-length(replace(before_definition,old_proof,'')))/length(old_proof)<>1 then
   raise exception 'Expected unique native proof clauses missing'; end if;
 after_definition:=replace(replace(before_definition,old_pair,new_pair),old_proof,new_proof);
 execute after_definition;
 if pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure)<>after_definition then
   raise exception 'Unexpected activation definition after same-document proof patch'; end if;
end $source_variant$;
