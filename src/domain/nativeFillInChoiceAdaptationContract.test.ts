import { describe, expect, it } from 'vitest'
import adaptation from '../../supabase/migrations/20261003005300_explicit_native_fill_in_choice_adaptation.sql?raw'
import sameDocumentAdaptation from '../../supabase/migrations/20261003011800_native_same_document_choice_adaptation.sql?raw'
import activationBeforeItemReview from '../../supabase/migrations/20260929041000_require_unresolved_hold_for_revision.sql?raw'
import itemReviewPatch from '../../supabase/migrations/20260929045000_require_item_review_before_release_activation.sql?raw'
import originalTeachingContract from '../../supabase/migrations/20260912021040_add_private_teaching_material_releases.sql?raw'
import sourceSecurity from '../../supabase/functions/chemistry-access/source-security.ts?raw'
import { shouldHideLicensedHighSchoolSolution } from '../../supabase/functions/chemistry-access/source-security'

const normalize = (value: string) => value.replace(/\r\n/g, '\n')
const migration = normalize(adaptation)
const baseline = normalize(activationBeforeItemReview)
const literal = (name: string, delimiter: string) => {
  const match = migration.match(new RegExp(`${name} text:=\\$${delimiter}\\$([\\s\\S]*?)\\$${delimiter}\\$;`))
  if (!match) throw new Error(`Missing audited patch literal: ${name}`)
  return match[1]
}
const oldPolicy = literal('old_policy', 'old')
const newPolicy = literal('new_policy', 'new')
const anchor = literal('original_anchor', 'anchor')
const guard = literal('adapted_guard', 'guard')
const patched = baseline.replace(oldPolicy, newPolicy).replace(anchor, anchor + guard)
const sameDocumentMigration = normalize(sameDocumentAdaptation)
const sameDocumentLiteral = (name: string, delimiter: string) => {
  const match = sameDocumentMigration.match(new RegExp(`${name} text:=\\$${delimiter}\\$([\\s\\S]*?)\\$${delimiter}\\$;`))
  if (!match) throw new Error(`Missing audited same-document patch literal: ${name}`)
  return match[1]
}
const oldPair = sameDocumentLiteral('old_pair', 'oldpair')
const newPair = sameDocumentLiteral('new_pair', 'newpair')
const oldProof = sameDocumentLiteral('old_proof', 'oldproof')
const newProof = sameDocumentLiteral('new_proof', 'newproof')
// SQL regex end anchors can contain JavaScript's special replacement token $'.
// Function replacements preserve these audited SQL literals byte for byte.
const sameDocumentPatched = patched.replace(oldPair, () => newPair).replace(oldProof, () => newProof)

describe('Explicit native fill-in to four-choice teaching adaptation', () => {
  it('changes only the one policy allowance and an additional rejecting guard', () => {
    expect(baseline.split(oldPolicy)).toHaveLength(2)
    expect(baseline.split(anchor)).toHaveLength(2)
    expect(patched.replace(newPolicy, oldPolicy).replace(anchor + guard, anchor)).toBe(baseline)
    expect(migration).toContain("md5(before_definition)<>'e4fc7e7134a4ed7a1ccaf8aa1050b580'")
    expect(migration).toContain('replace(replace(before_definition,old_policy,new_policy),original_anchor,original_anchor||adapted_guard)')
    expect(migration).toContain('pg_get_functiondef(\'public.chem_activate_teaching_material_release(uuid,text)\'::regprocedure)<>after_definition')
    expect(migration).toContain('Expected unique source contract insertion points missing')
  })

  it('retains the release, exact-source, four-choice, item-review and whole-visual gates', () => {
    for (const marker of [
      "v_release_status <> 'staged'",
      "v_verification_status <> 'full_visual_verified'",
      'v_verification_manifest is distinct from p_manifest_sha256',
      "q.source_kind <> 'licensed_local'",
      "q.review_status <> 'approved'",
      "q.scope_status <> 'IN'",
      'jsonb_array_length(q.options) <> 4',
      'q.correct_option not between 0 and 3',
      'release contains duplicated answer options',
      'app_private.chem_h3_content_fingerprint(q.stem, q.options)',
      'release ledger is missing a staged question',
      'source item identities are not unique inside release',
      'release manifest does not match the staged source items',
    ]) expect(patched).toContain(marker)
    expect(itemReviewPatch).toContain('not app_private.chem_question_item_delivery_review_ready(question.id)')
    expect(itemReviewPatch).toContain('release contains a question without current item-level source review')
    expect(migration).not.toContain('chem_question_item_delivery_review_ready')
  })

  it('preserves image identity, payload hash, current revision and unresolved predecessor hold checks', () => {
    for (const marker of [
      'every release question must have exactly one question image and one analysis image',
      'release contains a missing or metadata-mismatched private asset',
      'private asset payload does not match its SHA-256 digest',
      'private asset store must contain exactly the two declared images per question',
      'release assets must use the audited lossless WebP transport',
      'release revision token or ledger digest does not match the staged question and assets',
      'every source-backed question must have both question and analysis images',
      'same-fingerprint predecessor must be explicitly held before a revision replaces it',
      'h.anchor_question_id = old_q.id',
      'h.resolved_at is null',
    ]) expect(patched).toContain(marker)
  })

  it('rejects adapted questions outside High-1, an explicit title or a genuine native pair', () => {
    expect(guard).toContain("q.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'")
    expect(guard).toContain("q.grade_band<>'高一' or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'")
    expect(guard).toContain("position('原填空改四选' in coalesce(q.source_info->>'title',''))=0")
    expect(guard).toContain("q.source_info->>'sourcePairingStatus'<>'SOURCE_NATIVE_PAIR'")
    expect(guard).not.toContain("q.grade_band in ('高一','高二','高三')")
    expect(guard).not.toContain("sourcePairingStatus'='EXACT'")
    expect(guard).toContain('A/B/C/D distractors explicitly generated; original conditions and correct answer preserved')
  })

  it('rejects NULL, missing, false or string-true evidence rather than letting SQL UNKNOWN bypass proof', () => {
    for (const flag of ['generatedOptions', 'originalConditionsUnchanged', 'correctChoiceMatchesOriginal', 'nativeStudentTeacherProofRetained']) {
      expect(guard).toContain(`::jsonb->'${flag}' is distinct from 'true'::jsonb`)
      expect(guard).not.toContain(`::jsonb->'${flag}'<>`)
    }
    expect(guard).toContain("::jsonb->>'kind' is distinct from 'native_fill_in_to_four_choices'")
    for (const field of ['originalPrompt', 'originalCorrectAnswer']) {
      expect(guard).toContain(`coalesce(btrim((q.source_info->>'transcriptionAuditMethod')::jsonb->>'${field}'),'')=''`)
    }
    expect(patched).toContain("coalesce(btrim(q.source_info->>'transcriptionAuditMethod'), '') = ''")
    expect(patched).toContain("coalesce(btrim(q.source_info->>'optionTranscriptionPolicy'), '') = ''")
    expect(patched).toContain("coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')")
  })

  it('leaves original EXACT and SOURCE_NATIVE_PAIR questions under their original source policies', () => {
    for (const policy of ['source_image_authoritative', 'teacher_verified_exact_reflow_of_registered_source', 'source_crop_sanitized']) {
      expect(newPolicy.includes(policy) || patched.includes(`'${policy}'`)).toBe(true)
    }
    expect(guard).toMatch(/where q\.source_release_id=p_release_id\s+and q\.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'\s+and \(/)
    expect(patched).toContain("not in ('EXACT','SOURCE_NATIVE_PAIR')")
    expect(patched).toContain('(select count(*) from jsonb_object_keys(q.source_info)) <> 12')
    expect(guard).not.toContain('jsonb_object_keys')
  })

  it('keeps the existing server-only activation privileges and hardened function boundary', () => {
    expect(originalTeachingContract).toContain('revoke all on function public.chem_activate_teaching_material_release(uuid,text) from public,anon,authenticated;')
    expect(originalTeachingContract).toContain('grant execute on function public.chem_activate_teaching_material_release(uuid,text) to service_role;')
    expect(patched).toMatch(/SECURITY DEFINER\s+SET search_path TO ''/)
    expect(migration).not.toMatch(/\b(?:grant|revoke|create policy|alter table|drop function)\b/i)
    expect(migration).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+(?:public|app_private)\./i)
  })

  it('does not introduce a frontend/source-security policy whitelist or expose an adapted solution early', () => {
    expect(sourceSecurity).not.toContain('transcriptionPolicy')
    for (const grade of ['高一', '高二', '高三']) {
      expect(shouldHideLicensedHighSchoolSolution({
        grade_band: grade,
        source_kind: 'licensed_local',
        source_info: { transcriptionPolicy: 'teacher_verified_multiple_choice_adaptation' },
      }, true)).toBe(true)
    }
  })
})

describe('Honest same-document native fill-in adaptation', () => {
  it('changes exactly the pairing allowance and branches the proof without changing existing source gates', () => {
    expect(patched.split(oldPair)).toHaveLength(2)
    expect(patched.split(oldProof)).toHaveLength(2)
    expect(sameDocumentPatched.replace(newPair, () => oldPair).replace(newProof, () => oldProof)).toBe(patched)
    expect(sameDocumentMigration).toContain("md5(before_definition)<>'caa3466f6ce637691c681e39d51b9b5d'")
    expect(sameDocumentMigration).toContain('replace(replace(before_definition,old_pair,new_pair),old_proof,new_proof)')
    expect(sameDocumentMigration).toContain("pg_get_functiondef('public.chem_activate_teaching_material_release(uuid,text)'::regprocedure)<>after_definition")
    for (const marker of [
      'v_verification_manifest is distinct from p_manifest_sha256',
      'jsonb_array_length(q.options) <> 4',
      'private asset payload does not match its SHA-256 digest',
      'release revision token or ledger digest does not match the staged question and assets',
      'same-fingerprint predecessor must be explicitly held before a revision replaces it',
      '(select count(*) from jsonb_object_keys(q.source_info)) <> 12',
    ]) expect(sameDocumentPatched).toContain(marker)
    expect(sameDocumentMigration).not.toMatch(/\b(?:grant|revoke|create policy|alter table|drop function)\b/i)
  })

  it('retains genuine paired student/teacher proof and does not require same-document proof for that old positive path', () => {
    expect(newPair).toContain("not in ('EXACT','SOURCE_NATIVE_PAIR')")
    expect(newProof).toMatch(/sourcePairingStatus'='SOURCE_NATIVE_PAIR'\s+and .*nativeStudentTeacherProofRetained' is distinct from 'true'::jsonb/)
    const exactBranch = newProof.slice(newProof.indexOf("or (q.source_info->>'sourcePairingStatus'='EXACT'"))
    expect(exactBranch).toContain('nativeSameDocumentQuestionAndKeyProofRetained')
    expect(exactBranch).not.toContain('nativeStudentTeacherProofRetained')
    expect(newProof).not.toContain("sourcePairingStatus'='SOURCE_NATIVE_PAIR' or")
  })

  it('fails closed for missing, NULL, false, string-true, wrong-mode or malformed original document identity evidence', () => {
    expect(newProof).toContain("->>'originalSourceMode' is distinct from 'same_native_question_and_key'")
    expect(newProof).toContain("->'nativeSameDocumentQuestionAndKeyProofRetained' is distinct from 'true'::jsonb")
    expect(newProof).toContain("coalesce((q.source_info->>'transcriptionAuditMethod')::jsonb->>'nativeOriginalDocumentSha256','') !~ '^[0-9a-f]{64}$'")
    expect(newProof).not.toContain("->'nativeSameDocumentQuestionAndKeyProofRetained'<>")
    expect(sameDocumentPatched).toContain("coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')")
    for (const flag of ['generatedOptions', 'originalConditionsUnchanged', 'correctChoiceMatchesOriginal']) {
      expect(sameDocumentPatched).toContain(`::jsonb->'${flag}' is distinct from 'true'::jsonb`)
    }
  })

  it('keeps High-1 only and the adapted-policy-only guard while leaving original source questions unaffected', () => {
    expect(sameDocumentPatched).toContain("q.grade_band<>'高一' or q.source_kind<>'licensed_local' or q.render_mode<>'image_primary'")
    expect(sameDocumentPatched).toContain("position('原填空改四选' in coalesce(q.source_info->>'title',''))=0")
    expect(sameDocumentPatched).toContain("and q.source_info->>'transcriptionPolicy'='teacher_verified_multiple_choice_adaptation'")
    expect(sameDocumentMigration).not.toContain('teacher_verified_exact_reflow_of_registered_source')
    expect(sameDocumentMigration).not.toContain('chem_question_item_delivery_review_ready')
    expect(sameDocumentMigration).not.toContain('originalConditionsUnchanged')
    expect(sameDocumentMigration).not.toContain('correctChoiceMatchesOriginal')
  })
})
