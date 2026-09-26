import assert from 'node:assert/strict'
import { zeroForgettingCards } from './zero-forgetting-content.mjs'
import { knowledgeItemExamplesH2 } from '../src/data/knowledgeItemExamplesH2.ts'

const cards = zeroForgettingCards.filter((card) => card.skillId.startsWith('H2_'))
const expected = cards.flatMap((card) => card.sections.flatMap((section, sectionIndex) =>
  section.items.map((item, itemIndex) => ({
    key: `${card.skillId}:${sectionIndex}:${itemIndex}`,
    sectionDemo: item.examples?.find((example) => example.startsWith('【示范：')),
  }))))
const expectedKeys = new Set(expected.map(({ key }) => key))

assert.equal(cards.length, 8, 'expected eight reviewed 高二 cards')
assert.equal(expected.length, 162, 'reviewed 高二 item count changed; audit overlay mappings')
assert.deepEqual(Object.keys(knowledgeItemExamplesH2).sort(), [...expectedKeys].sort(),
  'every reviewed 高二 item needs exactly one mapped key, with no orphan key')

for (const { key, sectionDemo } of expected) {
  const examples = knowledgeItemExamplesH2[key]
  assert.ok(Array.isArray(examples) && examples.length > 0, `${key}: missing item example`)
  for (const example of examples) {
    assert.ok(typeof example === 'string' && example.trim().length >= 20,
      `${key}: example should contain a concrete short explanation`)
    assert.ok(!example.startsWith('【示范：'), `${key}: repeated section demo is not item-specific`)
    assert.notEqual(example, sectionDemo, `${key}: copied section demo is not item-specific`)
  }
}

console.log(`高二逐点例子校验通过：${cards.length} 张卡，${expected.length} 个小点，${Object.values(knowledgeItemExamplesH2).flat().length} 条例子。`)
