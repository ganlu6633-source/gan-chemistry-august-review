import { describe, expect, it, vi } from 'vitest'
import { loadJuniorKnowledgeCards, juniorDisplayKnowledgeCards } from '../../supabase/functions/chemistry-access/junior-knowledge-cards'

const card = (skill: string, id = `versioned-${skill}`, label = `leaf-${skill}`) => ({ id, skill_id: skill,
  review_status: 'approved', structured_content: { version: 1, sections: [{ items: [{ label, rule: 'exact rule' }] }] } })

describe('release-bound junior knowledge cards', () => {
  it('uses only the service-verified version, never an older approved card', async () => {
    const fetch = vi.fn().mockResolvedValue({ data: [card('INTRO', 'new-release-card')], error: null })
    const result = await loadJuniorKnowledgeCards(['INTRO'], '科粤版', fetch)
    expect(fetch).toHaveBeenCalledWith({ p_textbook_version: '科粤版', p_knowledge_ids: ['INTRO'] })
    expect(result.data.map((row) => row.id)).toEqual(['new-release-card'])
  })
  it('does not choose first/newest when the server returns ambiguous versions', async () => {
    await expect(loadJuniorKnowledgeCards(['INTRO'], '科粤版', async () => ({
      data: [card('INTRO', 'old'), card('INTRO', 'new')], error: null,
    }))).rejects.toThrow('版本不唯一')
  })
  it('does not fall back to an unbound card when no binding exists or RPC fails', async () => {
    expect((await loadJuniorKnowledgeCards(['MISSING'], '科粤版', async () => ({ data: [], error: null }))).data).toEqual([])
    await expect(loadJuniorKnowledgeCards(['INTRO'], '科粤版', async () => ({ data: null, error: new Error('offline') }))).rejects.toThrow('offline')
  })
  it('distinguishes all-current-bound cards from empty requests and batches a long record', async () => {
    const fetch = vi.fn(async ({ p_knowledge_ids }: { p_knowledge_ids: string[] | null }) => ({
      data: p_knowledge_ids === null ? [card('ACTIVE')] : p_knowledge_ids.map((id) => card(id)), error: null,
    }))
    expect((await loadJuniorKnowledgeCards(null, '科粤版', fetch)).data).toHaveLength(1)
    expect(fetch.mock.calls[0][0].p_knowledge_ids).toBeNull()
    fetch.mockClear()
    expect((await loadJuniorKnowledgeCards([], '科粤版', fetch)).data).toEqual([])
    expect(fetch).not.toHaveBeenCalled()
    expect((await loadJuniorKnowledgeCards(Array.from({ length: 21 }, (_, i) => `K${i}`), '科粤版', fetch)).data).toHaveLength(21)
    expect(fetch.mock.calls.map(([args]) => args.p_knowledge_ids?.length)).toEqual([20, 1])
  })
  it('includes one exact cross-skill review card while keeping unrelated cards off the phone', () => {
    const cards = ['A', 'B', 'C', 'TARGET', 'UNRELATED'].map((id) => card(id))
    expect(juniorDisplayKnowledgeCards(cards, ['A', 'B', 'C'], 'leaf-TARGET').map((row) => row.skill_id))
      .toEqual(['A', 'B', 'C', 'TARGET'])
    expect(juniorDisplayKnowledgeCards(cards, ['A', 'B', 'C']).map((row) => row.skill_id)).toEqual(['A', 'B', 'C'])
  })
  it('fails closed on absent or ambiguous fine points instead of returning a broad card', () => {
    expect(() => juniorDisplayKnowledgeCards([card('A')], ['A'], 'missing')).toThrow('唯一')
    expect(() => juniorDisplayKnowledgeCards([card('A', 'a', 'same'), card('B', 'b', 'same')], ['A'], 'same')).toThrow('唯一')
  })
})
