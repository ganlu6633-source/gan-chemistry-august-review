import { describe, expect, it } from 'vitest'
import { juniorImageProofMap, juniorReviewedImageQuestionIsSafe, juniorParentSourceIdentity } from '../../supabase/functions/chemistry-access/junior-image-delivery'
import imageDateMigration from '../../supabase/migrations/20261005012000_complete_reviewed_junior_image_date_delivery.sql?raw'

const release = 'ce79f0db-34c1-50b3-98aa-388eed653c0f'
const cardRelease = '00000000-0000-4000-8000-000000000001'
const token = '1'.repeat(64)

it('keeps the date image proof pool bounded when the complete library exceeds 800 questions', () => {
  const pool = imageDateMigration.slice(imageDateMigration.indexOf('CREATE OR REPLACE FUNCTION public.chem_junior_practice_pool('),
    imageDateMigration.indexOf('CREATE OR REPLACE FUNCTION public.chem_junior_issue_step('))
  expect(pool).toContain('((row_number() over(order by image.id)-1)/800)::bigint as batch_number')
  expect(pool).toContain('array_agg(candidate.id order by candidate.id) as question_ids')
  expect(pool).toContain('cross join lateral public.chem_junior_image_question_context(batch.question_ids) proof')
  expect(pool).toContain('join image_proofs proof')
  expect(pool).not.toContain('chem_junior_image_question_context(array(select')
})
const row = {
  id: 'JLOCAL-REAL-ORIGINAL', mother_id: 'REAL-ORIGINAL', grade_band: '初三', textbook_version: '科粤版',
  skill_id: 'J_KY_ELEMENTS', knowledge_id: 'J_KY_ELEMENTS', source_kind: 'licensed_local', render_mode: 'image_primary',
  image_url: null, review_status: 'approved', scope_status: 'IN', usable_for_review: true,
  usable_for_class_quiz: false, usable_for_exam_sprint: false, usable_for_demo: false,
  stem: '氧化铝中的铝元素化合价为', options: ['+1', '+2', '+3', '+4'], correct_option: 2,
  explanation: 'A、B、D 不符合化合物中化合价代数和为零。C：Al₂O₃ 中铝为 +3 价。',
  source_release_id: release, question_revision_token: token, source_item_key: 'SOURCE-REAL-ORIGINAL-001', parent_source_item_key: null,
  asset_refs: [
    { kind: 'question_image', path: 'real-source/question_001', sha256: '2'.repeat(64), alt: '原题', width: 1000, height: 500 },
    { kind: 'analysis_image', path: 'real-source/analysis_001', sha256: '3'.repeat(64), alt: '解析', width: 1000, height: 700 },
  ],
}
const proof = { question_id: row.id, revision_token: token, source_release_id: release,
  knowledge_id: row.knowledge_id, textbook_version: '科粤版', card_source_release_id: cardRelease, card_id: 'KC_REAL' }
const cards = new Map([[row.knowledge_id, cardRelease]])

describe('reviewed original images in junior date practice', () => {
  it('requires a real source proof independently of the textbook card release', () => {
    expect(juniorReviewedImageQuestionIsSafe(row, juniorImageProofMap([proof]), cards)).toBe(true)
    expect(juniorReviewedImageQuestionIsSafe(row, new Map(), cards)).toBe(false)
    expect(juniorReviewedImageQuestionIsSafe(row, juniorImageProofMap([proof]), new Map())).toBe(false)
    expect(juniorReviewedImageQuestionIsSafe(row, juniorImageProofMap([{ ...proof, card_source_release_id: release }]), cards)).toBe(false)
  })
  it.each(['revision_token', 'source_release_id', 'knowledge_id'] as const)('rejects a mismatched proof %s', (field) => {
    const wrong = { ...proof, [field]: field === 'revision_token' ? '4'.repeat(64) : field === 'source_release_id' ? cardRelease : 'WRONG_SKILL' }
    expect(juniorReviewedImageQuestionIsSafe(row, juniorImageProofMap([wrong]), cards)).toBe(false)
  })
  it('rejects ambiguous source/card evidence instead of picking one', () => {
    expect(() => juniorImageProofMap([proof, proof])).toThrow(/ambiguous/)
    expect(() => juniorImageProofMap([{ ...proof, card_id: '' }])).toThrow()
    expect(() => juniorImageProofMap(null)).toThrow()
  })
  it.each([
    { asset_refs: [row.asset_refs[0]] }, { asset_refs: [row.asset_refs[0], row.asset_refs[0]] },
    { options: ['A', 'A', 'C', 'D'] }, { correct_option: 4 }, { usable_for_demo: true },
    { usable_for_class_quiz: true }, { usable_for_exam_sprint: true }, { render_mode: 'native' },
  ])('does not let an approved flag bypass an incomplete format: %o', (changed) => {
    expect(juniorReviewedImageQuestionIsSafe({ ...row, ...changed }, juniorImageProofMap([proof]), cards)).toBe(false)
  })
  it('uses an intact whole original as its own parent and preserves explicit revision lineage', () => {
    expect(juniorParentSourceIdentity(row)).toBe(row.source_item_key)
    expect(juniorParentSourceIdentity({ ...row, parent_source_item_key: 'EXPLICIT-PARENT' })).toBe('EXPLICIT-PARENT')
    expect(juniorParentSourceIdentity({ ...row, source_kind: 'user_provided_local' })).toBe('')
    expect(row.parent_source_item_key).toBeNull()
  })
})
