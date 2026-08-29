import { fireEvent, render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import type { StructuredKnowledgeContent } from '../domain/types'
import { StructuredKnowledgeMap } from './StudentApp'
import h1OpeningMigration from '../../supabase/migrations/20260829173000_publish_h1_opening_knowledge_cards.sql?raw'

type CandidateCard = {
  skill_id: string
  concept_manifest: Array<{ id: string; title: string }>
  structured_content: StructuredKnowledgeContent
}

const cards = JSON.parse(readFileSync(resolve(process.cwd(), 'content/knowledge/h1_opening_knowledge_cards.json'), 'utf8')) as CandidateCard[]

describe('H1 opening knowledge-card candidate uses the real StudentApp contract', () => {
  it.each(cards)('$skill_id renders without throwing and exposes all five fine points', (card) => {
    const { container } = render(<main style={{ width: 390, maxWidth: 390 }}><StructuredKnowledgeMap content={card.structured_content} skillId={card.skill_id} /></main>)

    expect(container.querySelector('.quick-visual')).toBeInTheDocument()
    const conceptItems = [...container.querySelectorAll<HTMLDetailsElement>('details.classification-item')]
    expect(conceptItems).toHaveLength(5)
    expect(card.structured_content.sections.map((section) => section.title)).toEqual(card.concept_manifest.map((concept) => concept.title))

    fireEvent.click(container.querySelector('.full-explanation > summary')!)
    for (const detail of conceptItems) {
      fireEvent.click(detail.querySelector('summary')!)
      expect(detail.open).toBe(true)
      expect(detail.querySelector('.point-demo')).not.toBeEmptyDOMElement()
      expect(detail.querySelector('.memory-flow')).not.toBeEmptyDOMElement()
    }

    for (const concept of card.concept_manifest) expect(container).toHaveTextContent(concept.title)
    expect(container.querySelectorAll('.classification-section')).toHaveLength(7)
  })

  it('uses only visuals the StudentApp renderer implements and no placeholder asset list', () => {
    const visualKinds = cards.map((card) => card.structured_content.visualSummary?.kind)
    expect(visualKinds).toEqual(['tree', 'flow'])
    expect(JSON.stringify(cards)).not.toContain('required_assets')
    expect(JSON.stringify(cards)).not.toContain('tree_and_network')
    expect(JSON.stringify(cards)).not.toContain('flow_and_error_tree')
    expect(JSON.stringify(cards)).not.toContain(`N${String.fromCodePoint(0x2090)}`)
  })

  it('stores all three skill levels with the typed student goal and required ability fields', () => {
    const skillSeed = h1OpeningMigration.slice(0, h1OpeningMigration.indexOf('with reviewed_cards'))
    expect((skillSeed.match(/"studentFacingGoal"/g) || [])).toHaveLength(6)
    expect((skillSeed.match(/"requiredAbility"/g) || [])).toHaveLength(6)
    expect(skillSeed).not.toMatch(/"goal"\s*:/)
    expect(h1OpeningMigration).toContain('H1 opening skill level criteria do not match the typed three-level contract')
  })
})
