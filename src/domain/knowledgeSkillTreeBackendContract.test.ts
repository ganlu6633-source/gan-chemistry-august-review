import { describe, expect, it } from 'vitest'
import accessSource from '../../supabase/functions/chemistry-access/index.ts?raw'

const treeFunction = accessSource.slice(
  accessSource.indexOf('async function knowledgeSkillTree'),
  accessSource.indexOf('async function selfStudyCatalog'),
)
const treeDispatch = accessSource.slice(
  accessSource.indexOf('if (body.action === "knowledge_skill_tree" && identity.role === "student"'),
  accessSource.indexOf('if (body.action === "preview_self_study"'),
)

describe('lazy knowledge skill tree backend contract', () => {
  it('returns only the latest approved card for an active skill in the target student’s grade', () => {
    expect(treeFunction).toContain('profile.data.record_status !== "active"')
    expect(treeFunction).toContain('.eq("grade_band", grade).eq("active", true)')
    expect(treeFunction).toContain('.eq("skill_id", skillId).eq("review_status", "approved")')
    expect(treeFunction).toContain('.order("updated_at", { ascending: false })')
    expect(treeFunction).toContain('.limit(1).maybeSingle()')
  })

  it('removes source assets and blocks malformed or unsafe instructional content', () => {
    expect(treeFunction).toContain('validOptionalStructuredKnowledgeContent(cardResult.data.structured_content)')
    expect(treeFunction).toContain('studentProvenanceFreeCardShape(cardResult.data')
    expect(treeFunction).toContain('studentInstructionalCardTextIsSafe(card)')
    expect(treeFunction).not.toMatch(/\.insert\(|\.upsert\(|\.update\(|\.rpc\(/)
  })

  it('allows only self or permitted demo student access and requires a student for teacher preview', () => {
    expect(treeDispatch).toContain('resolveDemoTarget(identity.studentId, body.data?.studentId')
    expect(treeDispatch).toContain('if (!targetId) return reply(req, { error: "无权查看这个学生的知识点。" }, 403)')
    expect(treeDispatch).toContain('if (!validUuid(targetId)) return reply(req, { error: "请选择要预览的学生。" }, 400)')
    expect(treeDispatch).toContain('if (body.action === "knowledge_skill_tree") return reply(req, { error: "无权查看这个知识点。" }, 403)')
    expect(treeDispatch).toContain('{ card: await knowledgeSkillTree(targetId, String(body.data?.skillId || "")) }')
  })
})
