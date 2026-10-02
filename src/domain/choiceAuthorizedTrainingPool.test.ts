import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const readMigration = (name: string) => readFileSync(resolve('supabase', 'migrations', name), 'utf8').replace(/\r\n/g, '\n')
const migration = readMigration('20261002173904_choice_authorized_training_pool.sql')
const priorMigration = readMigration('20261002155802_option_knowledge_diagnostics.sql')
const projectionStart = 'CREATE OR REPLACE FUNCTION app_private.chem_choice_projection'
const currentProjection = priorMigration.slice(priorMigration.indexOf(projectionStart)).trimEnd() + '\n'
const sha256 = (text: string) => createHash('sha256').update(text).digest('hex')
const filterValue = (name: string, delimiter: string) => {
  const text = migration.match(new RegExp(`${name} text:=\\$${delimiter}\\$([\\s\\S]*?)\\$${delimiter}\\$;`))?.[1]
  if (!text) throw new Error(`Missing exact ${name} patch`)
  return text
}
const oldFilter = filterValue('old_filter', 'old')
const newFilter = filterValue('new_filter', 'new')
const nextProjection = currentProjection.replace(oldFilter, newFilter)

describe('plan-scoped original-question training whitelist', () => {
  it('patches exactly one pool-discovery condition and no other engine byte', () => {
    expect(currentProjection.split(oldFilter)).toHaveLength(2)
    expect(nextProjection.replace(newFilter, oldFilter)).toEqual(currentProjection)
    expect(sha256(currentProjection)).toBe('3ca6dc778e43f94f98fb066640a7e0c068319b1ca77e4ac4816520f04851814b')
    expect(sha256(nextProjection)).toBe('6989e213614cb48dab260b4e7bbaa37064b18f6c4adb890d14fef96438c74000')
    expect(migration).toContain(sha256(currentProjection))
    expect(migration).toContain(sha256(nextProjection))
    expect(migration).toContain('Expected one precise pool discovery filter')
  })

  it('uses NULL to preserve every legacy plan rather than emptying its pool', () => {
    expect(migration).toContain('add column authorized_training_pool_ids text[];')
    expect(migration).not.toMatch(/authorized_training_pool_ids\s+text\[\]\s+(not null|default)/i)
    expect(newFilter).toBe(`     and (c.authorized_training_pool_ids is null or pool_q.id=any(c.authorized_training_pool_ids))\n${oldFilter}`)
    expect(newFilter).not.toContain('coalesce')
  })

  it('only narrows the existing release, grade, skill, source and readiness authority', () => {
    for (const guard of [
      'pool_q.source_release_id=any(c.source_release_ids)',
      'pool_q.grade_band=c.grade_band',
      'pool_q.skill_id=any(c.authorized_skill_ids)',
      "pool_q.source_kind='licensed_local'",
      "pool_q.render_mode='image_primary'",
      "pool_q.review_status='approved' and pool_q.scope_status='IN' and pool_q.usable_for_review",
      'app_private.chem_choice_parent_identity(to_jsonb(pool_q)) is not null',
      'public.chem_teaching_ready_question_ids(c.grade_band,ready_ids)',
    ]) expect(nextProjection).toContain(guard)
    const poolStart = nextProjection.indexOf('select coalesce(array_agg(pool_q.id)')
    const whitelist = nextProjection.indexOf('c.authorized_training_pool_ids is null')
    const poolEnd = nextProjection.indexOf('if cardinality(ready_ids)>1000')
    expect(whitelist).toBeGreaterThan(poolStart)
    expect(whitelist).toBeLessThan(poolEnd)
  })

  it('rejects empty, oversized, null-element and malformed non-NULL arrays', () => {
    expect(migration).toContain('authorized_training_pool_ids is null or (')
    expect(migration).toContain('array_ndims(authorized_training_pool_ids)=1')
    expect(migration).toContain('cardinality(authorized_training_pool_ids) between 8 and 1000')
    expect(migration).toContain('array_position(authorized_training_pool_ids,null) is null')
    expect(migration).toContain("array_position(authorized_training_pool_ids,'') is null")
  })

  it('leaves permissions, public RPCs, authentication and saving unchanged', () => {
    expect(migration).not.toMatch(/\b(grant|revoke|create policy|alter policy|disable row level security)\b/i)
    expect(migration).not.toContain('CREATE OR REPLACE FUNCTION public.')
    expect(nextProjection).toContain('STABLE SECURITY DEFINER')
    expect(nextProjection).toContain("SET search_path TO ''")
    expect(nextProjection).toContain('c:=app_private.chem_choice_assert_plan(p_student_id,p_plan_id);')
    expect(migration).not.toMatch(/\b(insert into|update|delete from)\b/i)
  })

  it('keeps revision, actual eight, frozen branches, used parents and history spacing guards', () => {
    for (const guard of [
      "q->>'question_revision_token' is distinct from candidate->>'revisionToken'",
      'app_private.chem_choice_identities(q) && (used_ids||branch_ids)',
      'app_private.chem_choice_repetition_state(q,history,today)',
      "if repetition->>'eligible'<>'true' then continue; end if;",
      "if jsonb_array_length(frozen)<3 or jsonb_array_length(frozen)>5",
      'binding:=prior_branch',
      'base_ids:=sess.base_question_ids',
      "raise exception 'choice_first_answer_immutable'",
      "raise exception 'choice_frozen_issuance_changed'",
      'if daily_used+8>30',
    ]) expect(nextProjection).toContain(guard)
  })

  it('does not populate plan lists or rewrite an existing student session in a schema migration', () => {
    expect(migration).toContain('Populating a whitelist is a separately guarded publication action')
    expect(migration).toContain('Training whitelist column already exists; inspect rather than replace')
    expect(migration).toContain('Choice projection full body changed since exact scoped-pool baseline')
    expect(migration).toContain('Scoped-pool exact projection postcondition failed')
    expect(migration).not.toMatch(/(?:truncate|drop)\s+table/i)
  })
})
