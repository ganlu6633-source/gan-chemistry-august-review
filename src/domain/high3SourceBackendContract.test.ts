import { describe, expect, it } from 'vitest'
import accessFunction from '../../supabase/functions/chemistry-access/index.ts?raw'
import sourceAssetsMigration from '../../supabase/migrations/20260815060000_add_source_backed_question_assets.sql?raw'

describe('high-school source-backed REVIEW backend contract', () => {
  it('serves exact source assets only through an authenticated question-bound request', () => {
    expect(accessFunction).toContain('body.action === "question_asset"')
    expect(accessFunction).toContain('body.data?.questionId')
    expect(accessFunction).toContain('body.data?.assetId')
    expect(accessFunction).toContain('["question", "analysis"].includes(phase)')
    expect(accessFunction).toContain('matchingRawAssetRef(question.asset_refs, assetId, asset)')
    expect(accessFunction).toContain('body.data?.planId')
    expect(accessFunction).toContain('body.data?.attemptSequence')
    expect(accessFunction).toContain('isExpectedCurrentQuestion')
    expect(accessFunction).toContain('这张原题图不属于当前账号正在作答的本轮题组')
    expect(accessFunction).toContain('chem_has_current_question_answer_lock')
    expect(accessFunction).toContain('hasCompletedAnswer')
    expect(accessFunction).toContain('snapshot.assetRefs || snapshot.asset_refs')
    expect(accessFunction).toContain('currentAssetEligible')
    expect(accessFunction).toContain('!["高一", "高二", "高三"].includes(String(question.grade_band))')
    expect(accessFunction).toContain('question.scope_status === "IN"')
    expect(accessFunction).toContain('question.source_kind !== "licensed_local"')
    expect(accessFunction).toContain('dataUrl: `data:${mimeType};base64,${payloadBase64}`')
    expect(accessFunction).not.toContain('asset_path: String(asset.asset_path)')
  })

  it('never ships a licensed High-3 solution in start_plan and locks first-answer feedback on the server', () => {
    expect(accessFunction).toContain('issuedSolutionFields(row, hideSolution)')
    expect(accessFunction).toContain('issuedAssetRefs(questionAssetRefs(row.asset_refs, true), hideSolution)')
    expect(accessFunction).toContain('body.action === "question_feedback"')
    expect(accessFunction).toContain('chem_lock_question_answer')
    expect(accessFunction).toContain('这道题已经按第一次提交的选项锁定')
    expect(accessFunction).toContain('chem_get_question_answer_locks')
    expect(accessFunction).toContain('本轮答案必须与服务器锁定的第一次选择一致')
    expect(accessFunction).toContain('lockedFeedback')
  })

  it('keeps public high-school demos on a separate teacher-authored pool with no licensed asset or feedback access', () => {
    expect(accessFunction).toContain('const demoHighSchoolReview = demoProfile && plan.mode === "REVIEW"')
    expect(accessFunction).toContain('if (demoHighSchoolReview)')
    expect(accessFunction).toContain('.eq("source_kind", "teacher_original")')
    expect(accessFunction).toContain('.eq("usable_for_demo", true)')
    expect(accessFunction).toContain('eligibleQuestions = eligibleQuestions.eq(questionUsageColumn, true)')
    expect(accessFunction).toContain('demoProfile && historical.sourceKind === "licensed_local"')
    expect(accessFunction).toContain('演示账号不提供本地授权原题或解析图片')
    expect(accessFunction).toContain('演示账号使用独立安全题库，不提供本地授权原题反馈')
  })

  it('binds every submission to the immutable source revision and stores separate snapshot identities', () => {
    expect(accessFunction).toContain('submitted.revisionToken')
    expect(accessFunction).toContain('submittedRevisionToken !== expectedRevisionToken')
    expect(accessFunction).toContain('version: 3')
    expect(accessFunction).toContain('sourceKind: question.source_kind')
    expect(accessFunction).toContain('sourceInfo: questionSourceInfo(question.source_info)')
    expect(accessFunction).toContain('assetRefs: Array.isArray(question.asset_refs) ? question.asset_refs : []')
    expect(accessFunction).toContain('revisionToken: expectedRevisionToken')
    expect(accessFunction).toContain('contentFingerprint: question.content_fingerprint')
    expect(accessFunction).toContain('question.question_revision_token')
    expect(accessFunction).not.toContain('expectedRevisionToken = question.content_fingerprint')
    expect(accessFunction).not.toContain('row.content_fingerprint ? String(row.content_fingerprint)')
    expect(accessFunction).toContain('imageUrl: null')
    expect(accessFunction).toContain('supabase.rpc("chem_finalize_learning_attempt"')
    expect(accessFunction).not.toContain('from("chem_learning_attempts").insert')
    expect(accessFunction).not.toContain('from("chem_attempt_answers").insert')
  })

  it('prevents a source item or content fingerprint from repeating on the same plan day', () => {
    expect(accessFunction).toContain('sourceDistinctQuestionPool(questionPool, selectionHistory)')
    expect(accessFunction).toContain('usedSourceItemKeys')
    expect(accessFunction).toContain('usedContentFingerprints')
    expect(accessFunction).toContain('new Set(submittedSourceItems).size !== submittedSourceItems.length')
    expect(accessFunction).toContain('new Set(submittedFingerprints).size !== submittedFingerprints.length')
    expect(accessFunction).toContain('同一来源原题')
  })

  it('keeps full source evidence available in the completed learning record', () => {
    expect(accessFunction).toContain('sourceKind: historical.sourceKind')
    expect(accessFunction).toContain('assetRefs: historical.assetRefs')
    expect(accessFunction).toContain('renderMode: historical.renderMode')
    expect(accessFunction).toContain('mode: String(attemptById.get(String(answer.attempt_id))?.mode || "REVIEW")')
  })
})

describe('private source release migration contract', () => {
  it('keeps binaries and release manifests server-only', () => {
    expect(sourceAssetsMigration).toContain('create table if not exists app_private.chem_question_assets')
    expect(sourceAssetsMigration).toContain("'analysis_image'")
    expect(sourceAssetsMigration).toContain('revoke all on table app_private.chem_question_assets from public, anon, authenticated, service_role')
    expect(sourceAssetsMigration).toContain('grant execute on function public.chem_get_question_assets(text[]) to service_role')
    expect(sourceAssetsMigration).toContain('create table if not exists app_private.chem_question_answer_locks')
    expect(sourceAssetsMigration).toContain('revoke all on table app_private.chem_question_answer_locks from public, anon, authenticated, service_role')
    expect(sourceAssetsMigration).toContain('grant execute on function public.chem_lock_question_answer')
    expect(sourceAssetsMigration).toContain('create or replace function public.chem_finalize_learning_attempt')
    expect(sourceAssetsMigration).toContain('grant execute on function public.chem_finalize_learning_attempt')
  })

  it('atomically activates only a complete 275-question, 11-skill release', () => {
    expect(sourceAssetsMigration).toContain('chem_activate_h3_original_release')
    expect(sourceAssetsMigration).toContain('chem_preflight_h3_original_release')
    expect(sourceAssetsMigration).toContain('v_question_count <> 275')
    expect(sourceAssetsMigration).toContain('v_skill_ids is distinct from v_expected_skill_ids')
    expect(sourceAssetsMigration).toContain('count(*) <> 25 or count(distinct q.concept_key) <> 5')
    expect(sourceAssetsMigration).toContain("raise exception 'every High-3 fine concept must contain exactly five questions'")
    expect(sourceAssetsMigration).toContain("raise exception 'every source-backed question must have both question and analysis images'")
    expect(sourceAssetsMigration).toContain('set usable_for_review = false')
    expect(sourceAssetsMigration).toContain("q.review_status <> 'approved'")
    expect(sourceAssetsMigration).toContain('set usable_for_review = true')
  })

  it('separates semantic deduplication from crop-bound revision checks', () => {
    expect(sourceAssetsMigration).toContain('add column if not exists question_revision_token text')
    expect(sourceAssetsMigration).toContain('chem_h3_content_fingerprint')
    expect(sourceAssetsMigration).toContain('chem_h3_question_revision_sha256')
    expect(sourceAssetsMigration).toContain('q.content_fingerprint is distinct from')
    expect(sourceAssetsMigration).toContain('q.question_revision_token is distinct from')
    expect(sourceAssetsMigration).toContain('app_private.chem_release_manifest_field(p_question.question_revision_token)')
  })
})
