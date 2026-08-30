import { describe, expect, it } from 'vitest'

import migration from '../../supabase/migrations/20260829213000_correct_keyue_user_provided_junior_contract.sql?raw'

function sqlFunction(qualifiedName: string) {
  const marker = `create or replace function ${qualifiedName.toLowerCase()}(`
  const normalized = migration.toLowerCase()
  const start = normalized.lastIndexOf(marker)
  if (start < 0) return ''
  const end = migration.indexOf('\n$$;', start)
  return migration.slice(start, end < 0 ? undefined : end + 4)
}

describe('科粤版初三 user-provided source corrective migration', () => {
  it('is an append-only static migration with no runtime function-definition patching', () => {
    expect(migration.trimStart().startsWith('begin;')).toBe(true)
    expect(migration.trimEnd().endsWith('commit;')).toBe(true)
    expect(migration).not.toMatch(/pg_get_functiondef|execute\s+format/i)
    expect((migration.match(/create or replace function/gi) || [])).toHaveLength(23)
  })

  it('adds the exact 科粤版 and truthful user-provided database vocabulary', () => {
    expect(migration).toMatch(
      /chem_questions_source_kind_check[\s\S]{0,260}'licensed_local'[\s\S]{0,120}'user_provided_local'/i,
    )
    expect(migration).toMatch(
      /chem_question_source_releases_textbook_scope_check[\s\S]{0,220}grade_band\s*=\s*'初三'[\s\S]{0,100}textbook_version\s*=\s*'科粤版'/i,
    )
    for (const constraint of [
      'chem_junior_source_release_specs_textbook_version_check',
      'chem_junior_source_release_provenance_textbook_version_check',
      'chem_junior_curriculum_days_keyue_textbook_check',
      'chem_junior_daily_sessions_keyue_textbook_check',
      'chem_junior_knowledge_provenance_keyue_textbook_check',
    ]) {
      expect(migration).toMatch(new RegExp(`${constraint}[\\s\\S]{0,160}textbook_version\\s*=\\s*'科粤版'`, 'i'))
    }
    expect(migration).toMatch(
      /chem_questions_junior_no_new_legacy_licensed[\s\S]{0,180}grade_band\s*<>\s*'初三'[\s\S]{0,100}source_kind\s*<>\s*'licensed_local'[\s\S]{0,40}not valid/i,
    )
    expect(migration).toMatch(
      /chem_questions_junior_source_contract[\s\S]{0,400}source_kind\s*<>\s*'user_provided_local'[\s\S]{0,180}textbook_version\s*=\s*'科粤版'/i,
    )
  })

  it('rebuilds the junior pool and all five release-identity indexes for the new source kind', () => {
    const indexes = [
      'chem_questions_junior_adaptive_pool_idx',
      'chem_questions_junior_release_mother_uidx',
      'chem_questions_junior_release_source_item_uidx',
      'chem_questions_junior_release_parent_source_item_uidx',
      'chem_questions_junior_release_fingerprint_uidx',
      'chem_questions_junior_release_revision_uidx',
    ]
    for (const index of indexes) {
      expect(migration).toContain(`drop index if exists public.${index};`)
      const create = migration.indexOf(`index ${index}`)
      expect(create).toBeGreaterThan(-1)
      expect(migration.slice(create, migration.indexOf(';', create) + 1)).toContain("source_kind = 'user_provided_local'")
    }
  })

  it('stores a private, no-redistribution rights truth and gates activation on it', () => {
    const rightsStatus = 'user_provided_private_use_unverified_for_redistribution'
    expect(migration).toContain('create table if not exists app_private.chem_junior_source_release_rights')
    expect(migration).toContain(`check (rights_status = '${rightsStatus}')`)
    expect(migration).toContain('check (redistribution_allowed = false)')
    expect(migration).toContain('attested_manifest_sha256 text not null')
    expect(migration).toContain('attested_card_manifest_sha256 text not null')
    expect(migration).toMatch(/chem_junior_source_release_rights enable row level security/i)
    expect(migration).toMatch(
      /revoke all on table app_private\.chem_junior_source_release_rights[\s\S]{0,100}service_role/i,
    )

    const attest = sqlFunction('public.chem_attest_junior_source_release_private_use')
    expect(attest).toContain("release_row.grade_band = '初三'")
    expect(attest).toContain("release_row.textbook_version = '科粤版'")
    expect(attest).toContain("release_row.status = 'staged'")
    expect(attest).toContain(`'${rightsStatus}'`)
    expect(attest).toContain('false')
    expect(migration).toMatch(
      /revoke all on function public\.chem_attest_junior_source_release_private_use\(uuid,text\)[\s\S]{0,180}grant execute[\s\S]{0,120}to service_role/i,
    )

    const trigger = sqlFunction('app_private.chem_require_junior_rights_before_activation')
    expect(trigger).toContain("new.grade_band = '初三'")
    expect(trigger).toContain("new.status = 'active'")
    expect(trigger).toContain("new.textbook_version is distinct from '科粤版'")
    expect(trigger).toContain(`rights.rights_status = '${rightsStatus}'`)
    expect(trigger).toContain('rights.redistribution_allowed = false')
    expect(trigger).toContain('rights.attested_manifest_sha256 = new.manifest_sha256')
    expect(trigger).toContain('rights.attested_card_manifest_sha256')
    expect(trigger).toContain('chem_junior_knowledge_card_binding_matches')
    expect(migration).toMatch(
      /create trigger chem_require_junior_rights_before_activation[\s\S]{0,180}before insert or update on app_private\.chem_question_source_releases/i,
    )
  })

  it('binds each knowledge card to its exact runtime payload and verified source before rights attestation', () => {
    expect(migration).toContain('create table if not exists app_private.chem_junior_knowledge_card_bindings')
    expect(migration).toContain("fingerprint_contract = 'sha256_utf8_length_framed_student_card_payload_v1'")
    expect(migration).toMatch(/chem_junior_knowledge_card_bindings enable row level security/i)
    expect(migration).toMatch(/revoke all on table app_private\.chem_junior_knowledge_card_bindings[\s\S]{0,100}service_role/i)

    const field = sqlFunction('app_private.chem_junior_card_manifest_field')
    expect(field).toContain('pg_catalog.octet_length')
    expect(field).toContain("pg_catalog.convert_to(coalesce(p_value, ''), 'UTF8')")
    const digest = sqlFunction('app_private.chem_junior_knowledge_card_sha256')
    for (const fieldName of ['p_card.id', 'p_card.skill_id', 'p_card.title', 'p_card.core', 'p_card.detail', 'p_card.steps', 'p_card.common_mistakes', 'p_card.micro_example', 'p_card.structured_content', 'p_card.review_status']) {
      expect(digest, `card digest omits ${fieldName}`).toContain(fieldName)
    }
    expect(digest).toContain('chem_junior_card_manifest_field')

    const bind = sqlFunction('public.chem_bind_junior_knowledge_card')
    expect(bind).toContain("p_verification_actor is distinct from 'codex-knowledge-card-source-qa'")
    expect(bind).toContain('v_card_sha256 is distinct from p_expected_card_sha256')
    expect(bind).toContain('app_private.chem_junior_source_release_provenance')
    expect(bind).toContain('provenance.source_id = btrim(p_canonical_source_id)')
    expect(bind).toContain('provenance.source_sha256 = p_canonical_source_sha256')
    expect(bind).toContain("provenance.verification_actor = 'codex-source-provenance-qa'")

    const matches = sqlFunction('app_private.chem_junior_knowledge_card_binding_matches')
    expect(matches).toContain('binding.card_sha256 = app_private.chem_junior_knowledge_card_sha256(card)')
    expect(matches).toContain('app_private.chem_junior_source_release_provenance')
    expect(matches).toContain('source_provenance.source_id = binding.canonical_source_id')
    expect(matches).toContain('source_provenance.source_sha256 = binding.canonical_source_sha256')

    const cardStatementLock = sqlFunction('app_private.chem_lock_junior_knowledge_card_statement')
    expect(cardStatementLock).toMatch(/pg_advisory_xact_lock[\s\S]*chem-source-original-release[\s\S]*pg_advisory_xact_lock[\s\S]*chem-h3-original-release/i)
    expect(migration).toMatch(/create trigger chem_lock_junior_knowledge_card_statement[\s\S]{0,160}before insert or update on public\.chem_knowledge_cards[\s\S]{0,100}for each statement/i)

    const cardGuard = sqlFunction('app_private.chem_guard_bound_junior_knowledge_card')
    expect(cardGuard).not.toContain('pg_advisory_xact_lock')
    expect(cardGuard).toContain('binding.card_id = old.id')
    expect(migration).toMatch(/create trigger chem_guard_bound_junior_knowledge_card[\s\S]{0,140}before update or delete on public\.chem_knowledge_cards[\s\S]{0,100}for each row/i)
  })

  it('freezes attested card/source bindings and rechecks the card manifest in every formal runtime gate', () => {
    for (const [guardName, triggerName] of [
      ['app_private.chem_guard_attested_junior_source_provenance', 'chem_guard_attested_junior_source_provenance'],
      ['app_private.chem_guard_attested_junior_card_binding', 'chem_guard_attested_junior_card_binding'],
    ] as const) {
      const guard = sqlFunction(guardName)
      expect(guard).toContain("current_setting('app.chem_junior_release_lifecycle', true) = 'on'")
      expect(guard).toContain('app_private.chem_junior_source_release_rights')
      expect(guard).toMatch(/pg_advisory_xact_lock[\s\S]*chem-source-original-release[\s\S]*pg_advisory_xact_lock[\s\S]*chem-h3-original-release/i)
      expect(migration).toContain(`create trigger ${triggerName}`)
    }

    const assertion = sqlFunction('app_private.chem_assert_junior_source_release')
    expect(assertion).toContain('app_private.chem_junior_knowledge_card_bindings')
    expect(assertion).toContain('for update of card')
    expect(assertion).toContain('chem_junior_knowledge_card_binding_matches')
    expect(assertion).toContain('rights.attested_card_manifest_sha256')

    for (const name of [
      'public.chem_junior_record_step',
      'public.chem_junior_finalize_session',
      'public.chem_junior_issue_step',
      'public.chem_junior_validate_issued_step',
    ]) {
      expect(sqlFunction(name), `${name} omits runtime card readiness`).toContain('chem_junior_knowledge_card_is_ready')
    }
  })

  it('rechecks rights and the user-provided source kind in runtime provenance readiness', () => {
    const readiness = sqlFunction('public.chem_junior_verified_provenance_rows')
    expect(readiness).toContain("release.textbook_version = '科粤版'")
    expect(readiness).toContain("release.status = 'active'")
    expect(readiness).toContain("release.verification_status = 'full_visual_verified'")
    expect(readiness).toContain('release.verification_manifest_sha256 = release.manifest_sha256')
    expect(readiness).toContain('app_private.chem_junior_source_release_rights')
    expect(readiness).toContain("rights.rights_status = 'user_provided_private_use_unverified_for_redistribution'")
    expect(readiness).toContain('rights.redistribution_allowed = false')
    expect(readiness).toContain("question.source_kind = 'user_provided_local'")
    expect(readiness).toContain('question.knowledge_id = provenance.knowledge_id')
    expect(readiness).not.toContain("question.source_kind = 'licensed_local'")
    expect(migration).toMatch(
      /revoke all on function public\.chem_junior_verified_provenance_rows\(text,text\[\]\)[\s\S]{0,180}grant execute[\s\S]{0,100}to service_role/i,
    )
  })

  it('seals the authoritative manifest only after a complete unverified staged ledger', () => {
    const seal = sqlFunction('public.chem_seal_junior_source_release_manifest')
    expect(seal).not.toBe('')
    expect(seal).toMatch(/pg_advisory_xact_lock[\s\S]*chem-source-original-release[\s\S]*pg_advisory_xact_lock[\s\S]*chem-h3-original-release/i)
    expect(seal).toContain("release_row.grade_band = '初三'")
    expect(seal).toContain("release_row.textbook_version = '科粤版'")
    expect(seal).toContain("release_row.status = 'staged'")
    expect(seal).toContain("v_release.verification_status <> 'pending'")
    expect(seal).toContain('v_release.verification_manifest_sha256 is not null')
    expect(seal).toContain('v_question_count <> v_release.expected_question_count')
    expect(seal).toContain('v_item_count <> v_release.expected_question_count')
    expect(seal).toContain('app_private.chem_junior_native_release_item_sha256')
    expect(seal).toMatch(/string_agg\(item\.item_sha256,\s*E'\\n'\s+order by item\.question_id\)/i)
    expect(seal).toContain('other_release.manifest_sha256 = v_manifest')
    expect(seal).toContain("set_config('app.chem_junior_release_lifecycle', 'on', true)")
    expect(seal).toMatch(/set manifest_sha256\s*=\s*v_manifest[\s\S]*verification_status\s*=\s*'pending'[\s\S]*verification_manifest_sha256\s*=\s*null[\s\S]*verification_actor\s*=\s*null[\s\S]*verified_at\s*=\s*null/i)
    expect(seal).toContain('return v_manifest;')
    expect(migration).toMatch(
      /revoke all on function public\.chem_seal_junior_source_release_manifest\(uuid\)[\s\S]{0,180}grant execute[\s\S]{0,100}to service_role/i,
    )

    const stage = sqlFunction('public.chem_stage_junior_source_release_item')
    expect(stage).toContain('release_row.manifest_sha256')
    expect(stage).toMatch(/string_agg\(item\.item_sha256,\s*E'\\n'\s+order by item\.question_id\)/i)
    expect(stage).toContain('v_staged_item_count = v_expected')
    expect(stage).toContain('v_staged_manifest is not distinct from v_manifest_sha256')
    expect(stage).toContain('a sealed junior source release cannot be changed')
  })

  it('statically replaces all nine affected function definitions without weakening high school licensed routing', () => {
    const names = [
      'app_private.chem_guard_source_question_content_mutation',
      'public.chem_prepare_junior_source_release',
      'public.chem_stage_junior_source_release_item',
      'app_private.chem_assert_junior_source_release',
      'public.chem_activate_junior_source_release',
      'public.chem_junior_record_step',
      'public.chem_junior_finalize_session',
      'public.chem_junior_issue_step',
      'public.chem_junior_validate_issued_step',
    ]
    for (const name of names) expect(sqlFunction(name), `missing ${name}`).not.toBe('')

    const guard = sqlFunction('app_private.chem_guard_source_question_content_mutation')
    expect(guard).toMatch(/language plpgsql\s+security definer\s+set search_path = ''/i)
    expect(guard).toContain("new.source_kind in ('licensed_local', 'user_provided_local')")
    expect(guard).toContain("old.source_kind in ('licensed_local', 'user_provided_local')")
    expect(guard).toContain("new.source_kind not in ('licensed_local', 'user_provided_local')")

    const prepare = sqlFunction('public.chem_prepare_junior_source_release')
    expect(prepare).toContain("p_textbook_version is distinct from '科粤版'")
    expect(prepare).not.toContain("not in ('苏教版', '人教版', '通用')")

    const stage = sqlFunction('public.chem_stage_junior_source_release_item')
    expect(stage).toContain("'user_provided_local'")
    expect(stage).not.toContain("'licensed_local'")

    const assertion = sqlFunction('app_private.chem_assert_junior_source_release')
    expect(assertion).toContain("question.source_kind <> 'user_provided_local'")
    expect(assertion).toContain('app_private.chem_junior_source_release_rights')
    expect(assertion).toContain('redistribution_allowed = false')

    for (const name of [
      'public.chem_activate_junior_source_release',
      'public.chem_junior_record_step',
      'public.chem_junior_finalize_session',
      'public.chem_junior_issue_step',
      'public.chem_junior_validate_issued_step',
    ]) {
      const body = sqlFunction(name)
      expect(body, `${name} must route junior questions through the truthful source kind`).toContain('user_provided_local')
      expect(body, `${name} retained a legacy junior route`).not.toContain("source_kind = 'licensed_local'")
      expect(body, `${name} retained a legacy junior gate`).not.toContain("source_kind <> 'licensed_local'")
      expect(body).toContain("'初三'")
    }

    expect(migration).toContain("'licensed_local',\n    'user_provided_local'")
    expect(migration).not.toMatch(/create or replace function public\.chem_(?:activate_)?source_release\(/i)
    expect(migration).not.toMatch(/create or replace function public\.chem_record_source_answer_lock\(/i)
  })
})
