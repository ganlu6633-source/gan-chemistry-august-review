import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const teacherSource = readFileSync('supabase/functions/chemistry-teacher/index.ts', 'utf8')
const teacherAppSource = readFileSync('src/components/TeacherApp.tsx', 'utf8')

describe('teacher source-pool readiness contract', () => {
  it('covers the full forty-day operating window instead of only the next two weeks', () => {
    expect(teacherSource).toContain('readinessEndDate: dateKey(38)')
    expect(teacherSource).toContain('未来40天计划会用到')
    expect(teacherSource).not.toContain('未来14天计划会用到')
  })

  it('counts only approved in-scope licensed review originals by fine concept', () => {
    expect(teacherSource).toContain('.eq("review_status", "approved")')
    expect(teacherSource).toContain('.eq("scope_status", "IN")')
    expect(teacherSource).toContain('.eq("usable_for_review", true)')
    expect(teacherSource).toContain('.eq("source_kind", "licensed_local")')
    expect(teacherSource).toContain('.eq("render_mode", "image_primary")')
    expect(teacherSource).toContain('.not("source_release_id", "is", null)')
    expect(teacherSource).toContain('.select("skill_id,concept_key,source_item_key,content_fingerprint,mother_id,level,source_info")')
    expect(teacherSource).toContain('pool.sources.add(sourceKey)')
    expect(teacherSource).toContain('pool.fingerprints.add(fingerprint)')
    expect(teacherSource).toContain('pool.mothers.add(motherId)')
    expect(teacherSource).toContain('Math.min(pool.sources.size, pool.fingerprints.size, pool.mothers.size)')
  })

  it('blocks a future plan below five concepts or five originals per concept', () => {
    expect(teacherSource).toContain('conceptCount !== stat.expectedConceptCount')
    expect(teacherSource).toContain('minimumQuestionsPerConcept < requiredForFiveRounds')
    expect(teacherSource).toContain('系统必须停止下发')
  })

  it('separately reports the stricter cross-date no-repeat capacity', () => {
    expect(teacherSource).toContain('maximumPreviouslyUsedPerConcept')
    expect(teacherSource).toContain('chem_review_source_usage_counts')
    expect(teacherSource).toContain('previouslyUsed + stat.roundLimit * visits')
    expect(teacherSource).toContain('已做原题也计入占用')
    expect(teacherSource).toContain('跨日完全不重复口径')
    expect(teacherSource).toContain('id: `${gradeBand}:${skillId}:capacity`')
    expect(teacherSource).toContain('id: `${gradeBand}:${skillId}:progression`')
    expect(teacherSource).toContain('conceptTitle: pool.title')
    expect(teacherSource).toContain('missingQuestions: Math.max(0, requiredQuestions - availableQuestions)')
  })

  it('reports concepts whose originals cannot support a real difficulty upgrade', () => {
    expect(teacherSource).toContain('minimumDifficultyLevelsPerConcept < 3')
    expect(teacherSource).toContain('基础、提高、综合三个难度层级')
    expect(teacherAppSource).toContain('detail.difficultyLevels < 3')
    expect(teacherAppSource).not.toContain('detail.difficultyLevels < 2')
  })
})
