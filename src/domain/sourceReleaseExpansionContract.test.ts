import { describe, expect, it } from 'vitest'
import baselineMigration from '../../supabase/migrations/20260822090000_expand_h1_source_release_contract.sql?raw'
import expansionMigration from '../../supabase/migrations/20260822200019_expand_h2_h3_source_release_contract.sql?raw'

const normalizeNewlines = (value: string) => value.replace(/\r\n/g, '\n')

describe('High-2 and High-3 source-release expansion contract', () => {
  it('changes only the authorized High-2/High-3 count and distribution gates', () => {
    const expected = normalizeNewlines(baselineMigration)
      .replace(
        '-- Allow a rollback-safe High-1 release to grow from five to seven exact skills.',
        '-- Allow rollback-safe High-2 and High-3 releases to grow without weakening source, asset, hash, ledger, or atomic-switch checks.',
      )
      .replace(
        "    or (grade_band='高二' and expected_question_count=200)\n    or (grade_band='高三' and expected_question_count=275)",
        "    or (grade_band='高二' and expected_question_count between 200 and 2000)\n    or (grade_band='高三' and expected_question_count between 275 and 2000)",
      )
      .replace(
        "    or (v_grade_band = '高二' and v_release_expected <> 200)\n    or (v_grade_band = '高三' and v_release_expected <> 275)",
        "    or (v_grade_band = '高二' and v_release_expected not between 200 and 2000)\n    or (v_grade_band = '高三' and v_release_expected not between 275 and 2000)",
      )
      .replace(
        "    having count(*) <> 25 or count(distinct q.concept_key) <> 5\n  ) then\n    raise exception 'every release skill must contain 25 questions across exactly five concepts';",
        "    having count(distinct q.concept_key) <> 5\n      or (v_grade_band = '高一' and count(*) <> 25)\n      or (v_grade_band in ('高二','高三') and count(*) < 25)\n  ) then\n    raise exception 'every release skill must use exactly five concepts; High-1 requires exactly 25 questions per skill, while High-2 and High-3 require at least 25';",
      )
      .replace(
        "      having count(*) = 5\n    ) concept_groups\n  ) <> v_expected_concept_count then\n    raise exception 'every fine concept must contain exactly five questions';",
        "      having (v_grade_band = '高一' and count(*) = 5)\n        or (v_grade_band in ('高二','高三') and count(*) >= 5)\n    ) concept_groups\n  ) <> v_expected_concept_count then\n    raise exception 'High-1 requires exactly five questions per fine concept; High-2 and High-3 require at least five';",
      )

    expect(normalizeNewlines(expansionMigration)).toBe(expected)
  })

  it('keeps High-1 exact while admitting only the bounded High-2/High-3 totals', () => {
    expect(expansionMigration).toContain("(grade_band='高一' and expected_question_count in (125,175))")
    expect(expansionMigration).toContain("(grade_band='高二' and expected_question_count between 200 and 2000)")
    expect(expansionMigration).toContain("(grade_band='高三' and expected_question_count between 275 and 2000)")
    expect(expansionMigration).toContain("(v_grade_band = '高一' and v_release_expected not in (125,175))")
    expect(expansionMigration).toContain("(v_grade_band = '高二' and v_release_expected not between 200 and 2000)")
    expect(expansionMigration).toContain("(v_grade_band = '高三' and v_release_expected not between 275 and 2000)")
  })

  it('requires the exact grade skill sets and the intended per-skill/per-concept minima', () => {
    expect(expansionMigration).toContain(
      "array['H2_ELECTRO','H2_EQUIL','H2_K','H2_KSP','H2_PH_HYDRO','H2_RATE','H2_THERMO','H2_WEAK']::text[]",
    )
    expect(expansionMigration).toContain(
      "array['H3_AQ','H3_ELECTRO','H3_EQUILIBRIUM','H3_EXPERIMENT','H3_INORGANIC','H3_ION_REDOX','H3_ORGANIC','H3_PROCESS','H3_STOICH','H3_STRUCTURE','H3_THERMO_RATE']::text[]",
    )
    expect(expansionMigration).toContain("(v_grade_band = '高一' and count(*) <> 25)")
    expect(expansionMigration).toContain("(v_grade_band in ('高二','高三') and count(*) < 25)")
    expect(expansionMigration).toContain("having (v_grade_band = '高一' and count(*) = 5)")
    expect(expansionMigration).toContain("or (v_grade_band in ('高二','高三') and count(*) >= 5)")
    expect(expansionMigration).toContain('v_expected_concept_count := pg_catalog.array_length(v_expected_skill_ids, 1) * 5')
  })

  it('preserves the four-option single-choice, provenance, asset, ledger, hash, and atomic-switch gates', () => {
    const requiredMarkers = [
      'jsonb_array_length(q.options) <> 4',
      'q.correct_option not between 0 and 3',
      "q.source_kind <> 'licensed_local'",
      "q.review_status <> 'approved'",
      "q.scope_status <> 'IN'",
      'app_private.chem_h3_content_fingerprint(q.stem, q.options)',
      "raise exception 'release ledger must contain exactly % items, found %'",
      "raise exception 'release revision token or ledger digest does not match the staged question and assets'",
      "raise exception 'release manifest does not match the staged source items'",
      "raise exception 'every source-backed question must have both question and analysis images'",
      'set usable_for_review = false',
      'set usable_for_review = true',
      "raise exception 'postcondition failed: the grade must have exactly one active source release'",
    ]

    for (const marker of requiredMarkers) expect(expansionMigration).toContain(marker)
  })

  it('keeps the activation function server-only with a hardened search path', () => {
    expect(expansionMigration).toContain('security definer\nset search_path = \'\'')
    expect(expansionMigration).toContain(
      'revoke all on function public.chem_activate_source_original_release(uuid,text) from public, anon, authenticated;',
    )
    expect(expansionMigration).toContain(
      'grant execute on function public.chem_activate_source_original_release(uuid,text) to service_role;',
    )
  })
})
