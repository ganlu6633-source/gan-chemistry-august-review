import { describe, expect, it } from 'vitest'
import accessFunction from '../../supabase/functions/chemistry-access/index.ts?raw'
import reviewMigration from '../../supabase/migrations/20260814125818_high_school_review_five_rounds.sql?raw'

describe('current high-one teaching-scope contract', () => {
  it('uses the teacher-confirmed learned-skill list before any cohort fallback', () => {
    expect(accessFunction).toContain('confirmedLearnedSkillIds')
    expect(accessFunction).toContain('if (confirmed.length) return confirmed;')
    expect(accessFunction).toContain('["H1_CLASSIFY", "H1_PERIODIC", "H1_MOLE_INTRO", "H1_GAS_MOLAR_VOLUME"]')
  })

  it('keeps the three-student group free of redox and the two-student group on daily redox', () => {
    expect(reviewMigration).toContain("array['H1_CLASSIFY','H1_PERIODIC','H1_MOLE_INTRO','H1_GAS_MOLAR_VOLUME']")
    expect(reviewMigration).toContain("array['H1_REDOX','H1_GAS_MOLAR_VOLUME']")
    expect(reviewMigration).toContain("t.redox_every_day and not ('H1_REDOX'=any(p.skill_ids))")
    expect(reviewMigration).toContain("not t.redox_every_day and 'H1_REDOX'=any(p.skill_ids)")
  })

  it('allows only approved IN questions within the current difficulty ceiling', () => {
    expect(reviewMigration).toContain("q.scope_status='IN'")
    expect(reviewMigration).toContain('q.level<=p.max_question_level')
    expect(reviewMigration).toContain('max_question_level=3')
  })
})
