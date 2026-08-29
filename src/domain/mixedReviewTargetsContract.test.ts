import { describe, expect, it } from 'vitest'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'
import teacherSource from '../../supabase/functions/chemistry-teacher/index.ts?raw'
import migration from '../../supabase/migrations/20260821224500_add_review_target_concepts.sql?raw'

describe('mixed REVIEW fine-concept targets', () => {
  it('adds an optional five-target plan column without changing existing plans', () => {
    expect(migration).toContain('add column if not exists target_concept_keys text[] not null')
    expect(migration).toContain("cardinality(target_concept_keys) = 0")
    expect(migration).toContain('cardinality(target_concept_keys) = question_count')
    expect(migration).toContain('app_private.chem_text_array_is_unique_nonblank(target_concept_keys)')
    expect(migration).toContain('count(distinct pg_catalog.btrim(value))')
    expect(migration).toContain('target concept migration changed existing plans unexpectedly')
    expect(migration).not.toMatch(/update\s+public\.chem_learning_plans/i)
    expect(migration).not.toMatch(/quiz_sessions|chem_quiz/i)
    expect(migration).toContain('chem_review_source_usage_counts')
    expect(migration).toContain('chem_review_answer_history')
    expect(migration).toContain('security definer')
    expect(migration).toContain('grant execute on function public.chem_review_source_usage_counts(uuid[]) to service_role')
    expect(migration).toContain('grant execute on function public.chem_review_answer_history(uuid) to service_role')
  })

  it('fails closed on duplicate, unowned or incomplete target concepts', () => {
    expect(accessSource).toContain('new Set(targetConceptKeys).size !== targetConceptKeys.length')
    expect(accessSource).toContain('conceptKey.startsWith(`${skillId}__`)')
    expect(accessSource).toContain('expectedConceptKeys.some((conceptKey) => !conceptCounts.has(conceptKey))')
    expect(accessSource).toContain('some((count) => count < roundLimit)')
    expect(accessSource).not.toContain('some((levels) => levels.size < 3)')
    expect(accessSource).not.toContain('some((count) => count !== roundLimit)')
    expect(accessSource).toContain('.in("concept_key", targetConceptKeys)')
    expect(accessSource).toContain('当天必须配置 ${questionCount} 个互不重复的细知识点')
  })

  it('uses the same exact target filter when issuing and submitting', () => {
    expect(accessSource.match(/\.in\("concept_key", targetConceptKeys\)/g)).toHaveLength(2)
    expect(accessSource).toContain('.select("id,student_id,plan_date,mode,skill_ids,target_concept_keys,question_count,round_limit,max_question_level,delivery_mode")')
  })

  it('computes teacher capacity by repeated fine concept instead of whole mixed skill days', () => {
    expect(teacherSource).toContain('id,student_id,plan_date,skill_ids,target_concept_keys,knowledge_summaries,question_count,round_limit')
    expect(teacherSource).toContain('visitsByStudentConcept')
    expect(teacherSource).toContain('targetConcepts')
    expect(teacherSource).toContain('conceptKey.startsWith(`${skillId}__`)')
  })

  it('loads complete REVIEW history so an original cannot repeat on a later date', () => {
    expect(accessSource).toContain('supabase.rpc("chem_review_answer_history", { p_student_id: studentId })')
    expect(accessSource).toContain('Number(answer.history_order)')
    expect(accessSource).toContain('Source originals never repeat for the same student')
    expect(migration).toContain("attempt.mode = 'REVIEW'")
    expect(accessSource).not.toContain('allReviewAttempts')
  })
})
