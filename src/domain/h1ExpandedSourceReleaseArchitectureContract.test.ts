import { describe, expect, it } from 'vitest'

import candidate from '../../supabase/candidates/20260823021500_h1_expanded_source_release_contract.sql?raw'
import deployed from '../../supabase/migrations/20260824152000_h1_expanded_source_release_contract.sql?raw'

describe('High-1 expanded source-release architecture', () => {
  it('deploys the exact audited contract and accepts only the three audited rendering policies', () => {
    expect(deployed.slice(deployed.indexOf('begin;'))).toBe(candidate.slice(candidate.indexOf('begin;')))
    expect(candidate).toContain("'source_image_authoritative'")
    expect(candidate).toContain("'teacher_verified_exact_reflow_of_registered_source'")
    expect(candidate).toContain("'source_crop_sanitized'")
  })

  it('admits only legacy High-1 totals or a replacement with at least 36 additions', () => {
    expect(candidate).toContain('expected_question_count in (125,175)')
    expect(candidate).toContain('expected_question_count between 211 and 275')
    expect(candidate).toContain('added_question_count integer not null check (added_question_count between 36 and 100)')
    expect(candidate).toContain('p_release_id,p_base_release_id,175,p_expected_question_count-175')
    expect(candidate).toContain('target.expected_question_count\n        =extension_row.retained_question_count+extension_row.added_question_count')
  })

  it('requires the exact active verified 175-question baseline before staging', () => {
    expect(candidate).toContain("base.grade_band='高一'")
    expect(candidate).toContain("base.status='active'")
    expect(candidate).toContain('base.expected_question_count=175')
    expect(candidate).toContain("base.verification_status='full_visual_verified'")
    expect(candidate).toContain('base.verification_manifest_sha256=base.manifest_sha256')
    expect(candidate).toContain("base.revision_contract='v2_explanation_assets'")
    expect(candidate).toContain('where q.source_release_id=base.id\n      )=350')
    expect(candidate).toContain('where item.release_id=base.id\n      )=175')
  })

  it('records one-to-one private lineage for all 175 retained originals', () => {
    expect(candidate).toContain('app_private.chem_question_source_release_lineage')
    expect(candidate).toContain('primary key (release_id, question_id)')
    expect(candidate).toContain('unique (release_id, previous_question_id)')
    expect(candidate).toContain('new_q.id<>old_q.id')
    expect(candidate).toContain('new_q.mother_id=old_q.mother_id')
    expect(candidate).toContain('new_q.source_item_key=old_q.source_item_key')
    expect(candidate).toContain('new_q.content_fingerprint=old_q.content_fingerprint')
    expect(candidate).toContain('new_item.canonical_source_id=old_item.canonical_source_id')
    expect(candidate).toContain('new_item.question_asset_sha256=old_item.question_asset_sha256')
    expect(candidate).toContain('new_item.analysis_asset_sha256=old_item.analysis_asset_sha256')
    expect(candidate).toContain("select jsonb_agg(ref-'path' order by ref->>'kind')")
    expect(candidate).toContain('new_q.image_url is not distinct from old_q.image_url')
    expect(candidate).toContain("raise exception 'expanded release preserves % of 175 baseline questions'")
  })

  it('makes supplemental questions fresh across all four historical identities', () => {
    expect(candidate).toContain('added.id=old_q.id')
    expect(candidate).toContain('added.mother_id=old_q.mother_id')
    expect(candidate).toContain('added.source_item_key=old_q.source_item_key')
    expect(candidate).toContain('added.content_fingerprint=old_q.content_fingerprint')
    expect(candidate).toContain("old_q.source_release_id is distinct from p_release_id")
    expect(candidate).toContain("raise exception 'an added High-1 question collides with a prior four-part source identity'")
  })

  it('keeps extension and lineage metadata private and immutable after staging', () => {
    expect(candidate).toContain('alter table app_private.chem_question_source_release_extensions enable row level security')
    expect(candidate).toContain('alter table app_private.chem_question_source_release_lineage enable row level security')
    expect(candidate).toContain('from public, anon, authenticated, service_role')
    expect(candidate).toContain("release.status='staged'")
    expect(candidate).toContain("raise exception 'expanded source-release lineage may change only while staged'")
    expect(candidate).toContain("raise exception 'question lineage may change only while the target release is staged'")
  })

  it('exposes staging only to service_role with hardened functions', () => {
    expect(candidate).toContain("security definer\nset search_path = ''")
    expect(candidate).toContain(
      'revoke all on function public.chem_prepare_h1_expanded_source_release(uuid,text,integer,uuid)\n  from public, anon, authenticated;',
    )
    expect(candidate).toContain(
      'grant execute on function public.chem_prepare_h1_expanded_source_release(uuid,text,integer,uuid)\n  to service_role;',
    )
    expect(candidate).toContain(
      'grant execute on function public.chem_stage_h1_expanded_release_lineage(uuid)\n  to service_role;',
    )
    expect(candidate).toContain(
      'revoke all on function app_private.chem_assert_h1_expanded_release(uuid)\n  from public, anon, authenticated, service_role;',
    )
  })

  it('blocks activation while a retained original has an unfinished answer lock', () => {
    expect(candidate).toContain('from app_private.chem_question_answer_locks answer_lock')
    expect(candidate).toContain('old_q.source_release_id=v_base_release_id')
    expect(candidate).toContain(
      "raise exception 'High-1 activation is blocked while a baseline question has an unfinished answer lock'",
    )
    expect(candidate).toContain('perform app_private.chem_assert_h1_expanded_release(p_release_id)')
  })

  it('retains all source, image, hash, manifest, and atomic-switch gates', () => {
    const markers = [
      "q.source_kind <> 'licensed_local'",
      "q.review_status <> 'approved'",
      "q.scope_status <> 'IN'",
      'jsonb_array_length(q.options) <> 4',
      'q.correct_option not between 0 and 3',
      'app_private.chem_h3_content_fingerprint(q.stem, q.options)',
      "raise exception 'every release question must have exactly one question image and one analysis image'",
      "raise exception 'private asset payload does not match its SHA-256 digest'",
      "raise exception 'release revision token or ledger digest does not match the staged question and assets'",
      "raise exception 'release manifest does not match the staged source items'",
      'set usable_for_review = false',
      'set usable_for_review = true',
      "set status = 'retired'",
      "set status = 'active'",
      "raise exception 'postcondition failed: the grade must have exactly one active source release'",
    ]
    for (const marker of markers) expect(candidate).toContain(marker)
  })

  it('contains no question payload and never mutates learning or quiz history', () => {
    expect(candidate).not.toMatch(/insert\s+into\s+public\.chem_questions/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_learning_attempts/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.chem_attempt_answers/i)
    expect(candidate).not.toMatch(/(?:insert\s+into|update|delete\s+from)\s+public\.quiz_sessions/i)
  })
})
