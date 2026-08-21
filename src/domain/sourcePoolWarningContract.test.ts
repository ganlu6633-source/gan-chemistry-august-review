import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const teacherSource = readFileSync('supabase/functions/chemistry-teacher/index.ts', 'utf8')

describe('teacher source-pool readiness contract', () => {
  it('counts only approved in-scope licensed review originals by fine concept', () => {
    expect(teacherSource).toContain('.eq("review_status", "approved")')
    expect(teacherSource).toContain('.eq("scope_status", "IN")')
    expect(teacherSource).toContain('.eq("usable_for_review", true)')
    expect(teacherSource).toContain('.eq("source_kind", "licensed_local")')
    expect(teacherSource).toContain('.eq("render_mode", "image_primary")')
    expect(teacherSource).toContain('.select("skill_id,concept_key,source_item_key,mother_id,level")')
    expect(teacherSource).toContain('pool.sources.add(sourceKey)')
    expect(teacherSource).toContain('pool.sources.size')
  })

  it('blocks a future plan below five concepts or five originals per concept', () => {
    expect(teacherSource).toContain('conceptCount !== stat.expectedConceptCount')
    expect(teacherSource).toContain('minimumQuestionsPerConcept < requiredForFiveRounds')
    expect(teacherSource).toContain('系统必须停止下发')
  })

  it('separately reports the stricter cross-date no-repeat capacity', () => {
    expect(teacherSource).toContain('requiredForCrossDateNoRepeat = stat.roundLimit * maxVisitsPerStudent')
    expect(teacherSource).toContain('若跨日也完全不重复')
  })

  it('reports concepts whose originals cannot support a real difficulty upgrade', () => {
    expect(teacherSource).toContain('minimumDifficultyLevelsPerConcept < 2')
    expect(teacherSource).toContain('答对后无法真正升级')
  })
})
