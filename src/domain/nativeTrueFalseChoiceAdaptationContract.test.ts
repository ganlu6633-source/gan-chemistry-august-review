import { describe, expect, it } from 'vitest'
import nativeJudgementPatch from '../../supabase/migrations/20261003014600_native_true_false_choice_adaptation.sql?raw'
import fillInPatch from '../../supabase/migrations/20261003005300_explicit_native_fill_in_choice_adaptation.sql?raw'
import sameDocumentPatch from '../../supabase/migrations/20261003011800_native_same_document_choice_adaptation.sql?raw'
import activationBeforeItemReview from '../../supabase/migrations/20260929041000_require_unresolved_hold_for_revision.sql?raw'
import itemReviewPatch from '../../supabase/migrations/20260929045000_require_item_review_before_release_activation.sql?raw'
import originalTeachingContract from '../../supabase/migrations/20260912021040_add_private_teaching_material_releases.sql?raw'

const normalize = (value: string) => value.replace(/\r\n/g, '\n')
const readLiteral = (sql: string, name: string, tag: string) => {
  const match = normalize(sql).match(new RegExp(`${name} text:=\\$${tag}\\$([\\s\\S]*?)\\$${tag}\\$;`))
  if (!match) throw new Error(`Missing exact adaptation patch clause: ${name}`)
  return match[1]
}
const fill = normalize(fillInPatch)
let baseline = normalize(activationBeforeItemReview)
const itemReviewInserted = normalize(itemReviewPatch).match(/inserted constant text := \$code\$([\s\S]*?)\$code\$;/)?.[1]
if (!itemReviewInserted) throw new Error('Missing existing item review insertion')
baseline = baseline.replace("perform pg_catalog.set_config('app.chem_release_activation', 'on', true);", () => itemReviewInserted)
const oldPolicy = readLiteral(fill, 'old_policy', 'old')
const newPolicy = readLiteral(fill, 'new_policy', 'new')
const anchor = readLiteral(fill, 'original_anchor', 'anchor')
const guard = readLiteral(fill, 'adapted_guard', 'guard')
baseline = baseline.replace(oldPolicy, () => newPolicy).replace(anchor, () => anchor + guard)
for (const [oldName, oldTag, newName, newTag] of [
  ['old_pair', 'oldpair', 'new_pair', 'newpair'],
  ['old_proof', 'oldproof', 'new_proof', 'newproof'],
]) {
  baseline = baseline.replace(readLiteral(sameDocumentPatch, oldName, oldTag), () => readLiteral(sameDocumentPatch, newName, newTag))
}
const migration = normalize(nativeJudgementPatch)
const clauses = [
  ['old_title', 'oldtitle', 'new_title', 'newtitle'],
  ['old_policy', 'oldpolicy', 'new_policy', 'newpolicy'],
  ['old_kind', 'oldkind', 'new_kind', 'newkind'],
].map(([oldName, oldTag, newName, newTag]) => ({
  old: readLiteral(migration, oldName, oldTag),
  next: readLiteral(migration, newName, newTag),
}))
const patched = clauses.reduce((text, clause) => text.replace(clause.old, () => clause.next), baseline)
const newTitle = clauses[0].next
const newOptionPolicy = clauses[1].next
const newKind = clauses[2].next

describe('honest native judgement to four-choice adaptation', () => {
  it('changes only three exact adapted-source clauses, and can restore every prior function byte', () => {
    for (const clause of clauses) expect(baseline.split(clause.old)).toHaveLength(2)
    expect(clauses.reduce((text, clause) => text.replace(clause.next, () => clause.old), patched)).toBe(baseline)
    expect(migration).toContain("md5(before_definition)<>'bd6a2b059365f22dfed6af575d0cd2d4'")
    expect(migration).toContain('replace(replace(replace(before_definition,old_title,new_title),old_policy,new_policy),old_kind,new_kind)')
    expect(migration).toContain("pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure)<>after_definition")
    expect(migration).toContain('Expected unique adaptation title, policy and kind clauses missing')
  })

  it('uses the actual source kind to require its own honest title and option provenance', () => {
    expect(newTitle).toContain("when 'native_fill_in_to_four_choices' then position('原填空改四选'")
    expect(newTitle).toMatch(/when 'native_true_false_to_four_choices' then\s+position\('原判断改四选'/)
    expect(newOptionPolicy).toMatch(/when 'native_fill_in_to_four_choices' then\s+q\.source_info->>'optionTranscriptionPolicy' is distinct from 'native_fill_in_to_four_choices:/)
    expect(newOptionPolicy).toMatch(/when 'native_true_false_to_four_choices' then\s+q\.source_info->>'optionTranscriptionPolicy' is distinct from 'native_true_false_to_four_choices:/)
    expect(newOptionPolicy).toContain('original judgement, conditions and correct answer preserved')
    expect(newTitle).toContain('else true end')
    expect(newOptionPolicy).toContain('else true end')
  })

  it('accepts either real boolean judgement key and rejects NULL, absent, string or numeric keys', () => {
    expect(newTitle).toContain("jsonb_typeof((q.source_info->>'transcriptionAuditMethod')::jsonb->'originalTrueFalseKey') is distinct from 'boolean'")
    expect(newTitle).not.toContain("->'originalTrueFalseKey' is distinct from 'true'::jsonb")
    expect(newTitle).not.toContain("->>'originalTrueFalseKey'::boolean")
    expect(newTitle).not.toMatch(/originalTrueFalseKey'\s*(?:<>|=)/)
    expect(newTitle).toContain("->'correctChoiceStatesOriginalJudgement' is distinct from 'true'::jsonb")
    expect(newTitle).not.toContain("->'correctChoiceStatesOriginalJudgement'<>")
  })

  it('fails closed for a missing or unexpected adaptation kind and mismatched option provenance', () => {
    expect(newKind).toBe("        or coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'kind','') not in ('native_fill_in_to_four_choices','native_true_false_to_four_choices')")
    expect(newOptionPolicy.match(/is distinct from/g)).toHaveLength(2)
    expect(newTitle.match(/when 'native_/g)).toHaveLength(2)
    expect(newOptionPolicy.match(/when 'native_/g)).toHaveLength(2)
  })

  it('retains the old fill-in title, all original condition/key flags and both native proof paths', () => {
    expect(newOptionPolicy).toContain("native_fill_in_to_four_choices: all choices adapted; A/B/C/D distractors explicitly generated; original conditions and correct answer preserved")
    for (const flag of ['generatedOptions', 'originalConditionsUnchanged', 'correctChoiceMatchesOriginal']) {
      expect(patched).toContain(`::jsonb->'${flag}' is distinct from 'true'::jsonb`)
    }
    for (const field of ['originalPrompt', 'originalCorrectAnswer']) {
      expect(patched).toContain(`coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'${field}'),'')=''`)
    }
    expect(patched).toContain("sourcePairingStatus'='SOURCE_NATIVE_PAIR'")
    expect(patched).toContain("->'nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb")
    expect(patched).toContain("sourcePairingStatus'='EXACT'")
    expect(patched).toContain("->>'originalSourceMode' is distinct from 'same_native_question_and_key'")
    expect(patched).toContain("->'nativeSameDocumentQuestionAndKeyProofRetained' is distinct from 'true'::jsonb")
    expect(patched).toContain("->>'nativeOriginalDocumentSha256','') !~ '^[0-9a-f]{64}$'")
    expect(migration).not.toContain('nativeStudentTeacherProofRetained')
    expect(migration).not.toContain('nativeSameDocumentQuestionAndKeyProofRetained')
  })

  it('allows this adapter only for High-1 licensed image questions, leaving original source policies untouched', () => {
    expect(patched).toContain("q.grade_band<>'高一' or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'")
    expect(patched).toContain("and q.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'")
    expect(patched).toContain("coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')")
    for (const policy of ['source_image_authoritative', 'teacher_verified_exact_reflow_of_registered_source', 'source_crop_sanitized']) {
      expect(patched).toContain(`'${policy}'`)
      expect(migration).not.toContain(policy)
    }
    expect(patched).toContain('(select count(*) from jsonb_object_keys(q.source_info)) <> 12')
    expect(migration).not.toContain('jsonb_object_keys')
  })

  it('keeps every release, source, four-choice, visual, asset, revision and official-hold gate', () => {
    for (const marker of [
      "v_release_status <> 'staged'",
      "v_verification_status <> 'full_visual_verified'",
      'v_verification_manifest is distinct from p_manifest_sha256',
      "q.review_status <> 'approved'",
      "q.scope_status <> 'IN'",
      'jsonb_array_length(q.options) <> 4',
      'q.correct_option not between 0 and 3',
      'release contains duplicated answer options',
      'content fingerprint must equal the normalized stem and four options',
      'release ledger is missing a staged question',
      'private asset payload does not match its SHA-256 digest',
      'private asset store must contain exactly the two declared images per question',
      'release assets must use the audited lossless WebP transport',
      'release revision token or ledger digest does not match the staged question and assets',
      'release manifest does not match the staged source items',
      'same-fingerprint predecessor must be explicitly held before a revision replaces it',
      'h.resolved_at is null',
      'not app_private.chem_question_item_delivery_review_ready(question.id)',
    ]) expect(patched).toContain(marker)
  })

  it('retains the server-only function boundary and cannot change user records, grants or schema', () => {
    expect(patched).toMatch(/SECURITY DEFINER\s+SET search_path TO ''/)
    expect(originalTeachingContract).toContain('revoke all on function public.chem_activate_teaching_material_release(uuid,text) from public,anon,authenticated;')
    expect(originalTeachingContract).toContain('grant execute on function public.chem_activate_teaching_material_release(uuid,text) to service_role;')
    expect(migration).not.toMatch(/\b(?:grant|revoke|create policy|alter table|drop function)\b/i)
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+(?:public|app_private)\./i)
  })
})
