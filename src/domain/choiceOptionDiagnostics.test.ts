import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const readMigration = (name: string) => readFileSync(resolve('supabase', 'migrations', name), 'utf8').replace(/\r\n/g, '\n')
const migration = readMigration('20261002155802_option_knowledge_diagnostics.sql')
const previous = readMigration('20260929155202_choice_preview_live_source_parity.sql')
const focusPatch = readMigration('20260930162310_choice_runtime_exact_concept_focus.sql')
const projectionStart = 'CREATE OR REPLACE FUNCTION app_private.chem_choice_projection'
const projection = migration.slice(migration.indexOf(projectionStart))
const schema = migration.slice(0, migration.indexOf(projectionStart))
const body = (sql: string) => sql.match(/AS \$function\$([\s\S]*?)\$function\$/)?.[1]
const focusVariable = (name: string, delimiter: string) => {
  const value = focusPatch.match(new RegExp(`${name} text:=\\$${delimiter}\\$([\\s\\S]*?)\\$${delimiter}\\$;`))?.[1]
  if (!value) throw new Error(`Missing exact-focus baseline variable ${name}`)
  return value
}
const previousCurrentBody = body(previous)
  ?.replace(focusVariable('old_order', 'old'), focusVariable('new_order', 'new'))
  .replace(focusVariable('old_guard', 'old'), focusVariable('new_guard', 'new'))

describe('exact option diagnosis when original practice stock is insufficient', () => {
  it('changes only the empty reserve-gap knowledge point and preserves the training engine', () => {
    const before = "'knowledgePoint',coalesce(binding->>'knowledge_point',''),'skillId'"
    const after = "'knowledgePoint',coalesce(nullif(binding->>'knowledge_point',''),app_private.chem_option_diagnostic_point(current_anchor,anchor->>'question_revision_token',(a->>'selected_option')::integer),''),'skillId'"
    expect(projection.split(after)).toHaveLength(2)
    expect(body(projection)?.replace(after, before)).toEqual(previousCurrentBody)
    expect(projection).toContain("if jsonb_array_length(frozen)<3 or jsonb_array_length(frozen)>5 or coalesce(binding->>'knowledge_point','')='' then")
    expect(projection).toContain("'questionIds','[]'::jsonb,'status','reserve_gap','gap','exact_reserve_unavailable'")
  })

  it('keeps verified practice-binding diagnosis first and never invents a reserve pool', () => {
    expect(projection).toContain("coalesce(nullif(binding->>'knowledge_point',''),app_private.chem_option_diagnostic_point(")
    const table = schema.slice(schema.indexOf('create table '), schema.indexOf('alter table '))
    expect(table).not.toContain('candidates')
    expect(table).not.toContain('mastery')
    expect(table).not.toContain('consolidated')
    expect(schema).not.toMatch(/\binsert\s+into\b/i)
  })

  it('keeps new diagnosis data private and leaves the existing public RPC and authorization intact', () => {
    expect(schema).toContain('alter table app_private.chem_option_knowledge_diagnostics enable row level security;')
    expect(schema).toContain('revoke all on table app_private.chem_option_knowledge_diagnostics from public,anon,authenticated,service_role;')
    expect(schema).toContain('revoke all on function app_private.chem_option_diagnostic_point(text,text,integer) from public,anon,authenticated,service_role;')
    expect(schema).toContain("returns text language sql stable security invoker set search_path=''")
    expect(schema).not.toMatch(/\bgrant\b/i)
    expect(migration).not.toContain('CREATE OR REPLACE FUNCTION public.')
    expect(projection).toContain('STABLE SECURITY DEFINER')
    expect(projection).toContain("SET search_path TO ''")
    expect(projection).toContain('c:=app_private.chem_choice_assert_plan(p_student_id,p_plan_id);')
  })

  it('rejects a changed projection baseline rather than replacing unrelated changes', () => {
    expect(schema).toContain("md5(pg_get_functiondef('app_private.chem_choice_projection(uuid,uuid,jsonb)'::regprocedure))")
    expect(schema).toContain('Choice projection changed since exact diagnostic baseline')
    expect(schema).toContain('Option diagnostic table already exists; inspect rather than silently replacing')
  })

  it('checks the current question revision and the exact original option before a diagnosis is returned', () => {
    expect(schema).toContain('q.question_revision_token=d.anchor_revision_token')
    expect(schema).toContain('d.anchor_revision_token=p_revision_token')
    expect(schema).toContain('d.option_index=p_option_index')
    expect(schema).toContain('q.options->>p_option_index=d.source_option_text')
    expect(schema).toContain("d.review_status='verified'")
    expect(schema).toContain("q.review_status='approved' and q.usable_for_review")
  })

  it('resolves only the authored terminal leaf, keeping bicarbonate and hydrogen sulfate distinct', () => {
    expect(schema).toContain("k.structured_content #> array['sections',d.section_index::text,'items',d.item_index::text]")
    expect(schema).toContain("k.review_status='approved'")
    expect(schema).toContain("n.node->>'label'=d.knowledge_point")
    expect(schema).toContain("coalesce(n.node->>'reviewPointIndex','0')=d.review_point_index::text")
    expect(schema).toContain("jsonb_array_length(case when jsonb_typeof(n.node->'children')='array' then n.node->'children' else '[]'::jsonb end)=0")
    expect(schema).toContain("check(knowledge_point_id=knowledge_card_id||':s'||section_index::text||':i'||item_index::text||':p'||review_point_index::text)")
    expect(schema).toContain('primary key(anchor_question_id,option_index)')
  })
})
