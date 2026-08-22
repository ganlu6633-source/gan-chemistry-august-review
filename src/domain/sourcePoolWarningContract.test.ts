import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const teacherSource = readFileSync('supabase/functions/chemistry-teacher/index.ts', 'utf8')
const teacherAppSource = readFileSync('src/components/TeacherApp.tsx', 'utf8')

describe('teacher source-pool readiness contract', () => {
  it('covers the funded window through September 29 without drifting later', () => {
    expect(teacherSource).toContain('readinessEndDate: date < "2026-09-29" ? "2026-09-29" : dateKey(0)')
    expect(teacherSource).toContain('截至9月29日的计划会用到')
    expect(teacherSource).not.toContain('未来14天计划会用到')
  })

  it('counts only approved in-scope licensed review originals by fine concept', () => {
    expect(teacherSource).toContain('.eq("review_status", "approved")')
    expect(teacherSource).toContain('.eq("scope_status", "IN")')
    expect(teacherSource).toContain('.eq("usable_for_review", true)')
    expect(teacherSource).toContain('.eq("source_kind", "licensed_local")')
    expect(teacherSource).toContain('.eq("render_mode", "image_primary")')
    expect(teacherSource).toContain('admin.rpc("chem_active_verified_source_releases")')
    expect(teacherSource).toContain('.in("source_release_id", activeVerifiedReleaseIds)')
    expect(teacherSource).toContain('.select("skill_id,concept_key,source_item_key,content_fingerprint,mother_id,level,grade_band,source_release_id,asset_refs")')
    expect(teacherSource).toContain('String(question.source_release_id || "") !== expectedReleaseId')
    expect(teacherSource).toContain('!hasRequiredReviewSourceAssets(question.asset_refs)')
    expect(teacherSource).toContain('validReviewSourceAssetRef(ref, "question_image")')
    expect(teacherSource).toContain('validReviewSourceAssetRef(ref, "analysis_image")')
    expect(teacherSource).toContain('admin.rpc("chem_review_concept_catalog_rows")')
    expect(teacherSource).toContain('title: catalogEntry?.title || conceptKey')
    expect(teacherSource).not.toContain('sourceInfo.conceptLabel')
    expect(teacherSource).toContain('pool.sources.add(sourceKey)')
    expect(teacherSource).toContain('pool.fingerprints.add(fingerprint)')
    expect(teacherSource).toContain('pool.mothers.add(motherId)')
    expect(teacherSource).toContain('Math.min(pool.sources.size, pool.fingerprints.size, pool.mothers.size)')
  })

  it('blocks an invalid daily package or a target without a source original', () => {
    expect(teacherSource).toContain('stat.invalidDailyPackageCount > 0')
    expect(teacherSource).toContain('requiredForDailyPackage = 1')
    expect(teacherSource).toContain('1—8道、知识点与题目一一对应')
    expect(teacherSource).toContain('系统必须停止下发')
  })

  it('separately reports the stricter cross-date no-repeat capacity', () => {
    expect(teacherSource).toContain('maximumPreviouslyUsedPerConcept')
    expect(teacherSource).toContain('chem_review_active_source_usage_counts')
    expect(teacherSource).toContain('previouslyUsed + visits')
    expect(teacherSource).toContain('已做原题也计入占用')
    expect(teacherSource).toContain('跨日完全不重复口径')
    expect(teacherSource).toContain('id: `${gradeBand}:${skillId}:capacity`')
    expect(teacherSource).toContain('id: `${gradeBand}:${skillId}:progression`')
    expect(teacherSource).toContain('conceptTitle: pool.title')
    expect(teacherSource).toContain('missingQuestions: Math.max(0, requiredQuestions - availableQuestions)')
  })

  it('reports concepts whose originals cannot support a real difficulty upgrade', () => {
    expect(teacherSource).toContain('levels.size || 0) < 2')
    expect(teacherSource).toContain('只有一个难度层级')
    expect(teacherAppSource).toContain('detail.difficultyLevels < 2')
    expect(teacherAppSource).not.toContain('detail.difficultyLevels < 3')
  })
})
