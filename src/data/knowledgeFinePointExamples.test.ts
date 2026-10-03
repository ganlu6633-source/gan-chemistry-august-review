import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import type { KnowledgeCard, KnowledgeTreeNode, StructuredKnowledgeContent } from '../domain/types'
import { getKnowledgeReviewLeaves, getKnowledgeReviewPoints } from '../domain/knowledgeReviewPoints'
import { knowledgeFinePointExamples } from './knowledgeFinePointExamples'
import openingCards from '../../content/knowledge/h1_opening_knowledge_cards.json'
import ionsRedoxFinePoints from '../../content/knowledge/h1-ions-redox-fine-points-20261002.json'
// @ts-expect-error The authored content generator is an ESM JavaScript module without declarations.
import { zeroForgettingCards } from '../../scripts/zero-forgetting-content.mjs'

type GeneratedContent = StructuredKnowledgeContent & { skillId: string }
type OpeningRecord = { id: string; skill_id: string; title: string; core: string;
  structured_content: StructuredKnowledgeContent }

const postCoreAddresses = [
  ['H1_ELECTROLYTE', 's2:i1:p63', '离子个数的系数能写进下标吗'],
  ['H1_REDOX', 's7:i8:p0', '生成物能称为这一次反应的氧化剂或还原剂吗'],
  ['H1_REDOX', 's7:i9:p0', '前一步用了原料，剩余量怎样表示'],
  ['H1_REDOX', 's7:i10:p0', '后一步两种原料分别来自哪里'],
  ['H1_REDOX', 's7:i11:p0', '余料与中间物是否正好满足下一步计量比'],
  ['H1_REDOX', 's7:i12:p0', '被氧化与被还原元素的质量怎样分别数'],
] as const

function generatedPoint(skill: string, address: string) {
  const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === skill)!
  const card: KnowledgeCard = { id: `KC_${skill}`, skillId: skill, title: skill,
    core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
    reviewStatus: 'approved', structuredContent: content }
  const points = getKnowledgeReviewPoints(card).filter((point) => point.id === `${card.id}:${address}`)
  expect(points).toHaveLength(1)
  return points[0]
}

function generatedNode(skill: string, itemIndex: number) {
  return (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === skill)!.sections[7].items[itemIndex]
}

function compositePartKeys(card: KnowledgeCard): string[] {
  const groups = new Map<string, string[]>()
  for (const point of getKnowledgeReviewPoints(card)) {
    const match = point.id.match(/:s(\d+):i(\d+):p(\d+)$/)
    if (!match) continue
    // Authored child leaves keep their examples on the node; p50–p99 are
    // independent addresses, not legacy composite parts in the static map.
    if (Number(match[3]) >= 50) continue
    const parentKey = `${card.skillId}:${match[1]}:${match[2]}`
    const keys = groups.get(parentKey) ?? []
    keys.push(`${parentKey}:${match[3]}`)
    groups.set(parentKey, keys)
  }
  return [...groups.values()].filter((keys) => keys.length > 1).flat()
}

describe('examples for reviewed fine knowledge points', () => {
  it('covers every currently generated composite split and the released high-one opening card', () => {
    const generatedCards = (zeroForgettingCards as GeneratedContent[]).map((content) => ({
      id: `KC_${content.skillId}`, skillId: content.skillId, title: content.skillId,
      core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved' as const, structuredContent: content,
    }))
    const opening = (openingCards as unknown as OpeningRecord[]).map((record) => ({
      id: record.id, skillId: record.skill_id, title: record.title,
      core: record.core, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved' as const, structuredContent: record.structured_content,
    }))
    const gasSql = readFileSync('supabase/migrations/20260814125818_high_school_review_five_rounds.sql', 'utf8')
    const gasContent = JSON.parse(gasSql.split('$gas_card$')[1]) as StructuredKnowledgeContent
    const gasCard: KnowledgeCard = { id: 'KC_H1_GAS_MOLAR_VOLUME_ZERO', skillId: 'H1_GAS_MOLAR_VOLUME', title: '气体摩尔体积',
      core: gasContent.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: gasContent }
    const generatedKeys = generatedCards.flatMap(compositePartKeys)
    const openingKeys = opening.flatMap(compositePartKeys)
    const gasKeys = compositePartKeys(gasCard)
    expect(generatedKeys).toHaveLength(17)
    expect(openingKeys).toHaveLength(7)
    expect(gasKeys).toHaveLength(2)
    expect(Object.keys(knowledgeFinePointExamples).sort()).toEqual([...generatedKeys, ...openingKeys, ...gasKeys].sort())
    for (const [key, examples] of Object.entries(knowledgeFinePointExamples)) {
      expect(examples.length, key).toBeGreaterThan(0)
      expect(examples.every((example) => example.trim().length > 12), key).toBe(true)
    }
  })

  it('keeps each of the 56 authored ion/redox child leaves on its own example', () => {
    const contents = (zeroForgettingCards as GeneratedContent[])
      .filter((content) => ['H1_ELECTROLYTE', 'H1_REDOX'].includes(content.skillId))
    expect(contents).toHaveLength(2)
    let leafCount = 0
    for (const content of contents) {
      const card: KnowledgeCard = {
        id: `KC_${content.skillId}`, skillId: content.skillId, title: content.skillId,
        core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
        reviewStatus: 'approved', structuredContent: content,
      }
      const points = getKnowledgeReviewPoints(card)
      content.sections.forEach((section, sectionIndex) => section.items.forEach((item, itemIndex) => {
        const leaves = getKnowledgeReviewLeaves(item)
        const siblingExamples = new Set<string>()
        for (const { node, pointIndex } of leaves) {
          leafCount += 1
          const id = `${card.id}:s${sectionIndex}:i${itemIndex}:p${pointIndex}`
          const point = points.find((candidate) => candidate.id === id)
          expect(node.examples?.length, id).toBeGreaterThan(0)
          expect(node.examples?.every((example) => example.trim().length > 12), id).toBe(true)
          expect(point?.examples, id).toEqual(node.examples)
          for (const example of node.examples ?? []) {
            expect(item.examples ?? [], id).not.toContain(example)
            expect(siblingExamples.has(example), id).toBe(false)
            siblingExamples.add(example)
          }
          const staticKey = `${card.skillId}:${sectionIndex}:${itemIndex}:${pointIndex}`
          expect(knowledgeFinePointExamples, id).not.toHaveProperty(staticKey)
        }
      }))
    }
    expect(leafCount).toBe(56)
  })

  it('keeps the released electrolyte points at their original addresses', () => {
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_ELECTROLYTE')!
    const card: KnowledgeCard = { id: 'KC_H1_ELECTROLYTE', skillId: content.skillId, title: content.skillId,
      core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: content }
    const splitItem = content.sections[2].items[1]
    expect(getKnowledgeReviewLeaves(splitItem).map((leaf) => leaf.pointIndex)).toEqual([50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63])
    expect(splitItem.children?.slice(0, 8).map((node) => node.label)).toEqual([
      '可溶性强电解质盐怎样拆', '难溶盐为什么不拆', '强酸怎样拆', '可溶性强碱怎样拆',
      '弱电解质为什么不拆', '气体在离子式中怎样写', '水在离子式中怎样写', '单质在离子式中怎样写',
    ])
    expect(content.sections[6].items.slice(0, 4).map((node) => node.label)).toEqual([
      '先确认是不是化合物', '能导电的单质不是电解质', '盐酸为什么不是电解质', '氯化钠溶液为什么不是电解质',
    ])
    const points = getKnowledgeReviewPoints(card)
    const additions = [
      ['s2:i1:p58', '难溶碱为什么不拆'], ['s2:i1:p59', '氧化物在离子式中怎样写'],
      ['s2:i1:p60', '碳酸氢根为什么不能继续拆'], ['s2:i1:p61', '硫酸氢盐在水溶液中怎样拆'],
      ['s6:i4:p0', '溶液导电是否来自物质自身电离'], ['s6:i5:p0', '电解质一定处处都导电吗'],
      ['s6:i6:p0', '强电解质溶液一定更导电吗'],
    ]
    for (const [address, title] of additions) {
      const matches = points.filter((point) => point.id === `${card.id}:${address}`)
      expect(matches).toHaveLength(1)
      expect(matches[0].title).toBe(title)
      expect(matches[0].examples).toHaveLength(1)
      expect(matches[0].examples[0]).toMatch(/^教学例子：/)
    }
    for (const node of content.sections[6].items.slice(4)) expect(node.visualSteps?.length).toBeGreaterThanOrEqual(2)
  })

  it('keeps the twelve released option-specific points and six later additions at independent addresses', () => {
    const additions = [
      ['H1_ELECTROLYTE', 's2:i1:p62', '多原子酸根为什么要保持整体'],
      ['H1_ELECTROLYTE', 's6:i7:p0', '电离需要先通电吗'],
      ['H1_ELECTROLYTE', 's6:i8:p0', 'Na₂O入水后有哪些真实离子'],
      ['H1_REDOX', 's7:i0:p0', '同素异形体转化算氧化还原吗'],
      ['H1_REDOX', 's7:i1:p0', '同种产物怎样按来源数份额'],
      ['H1_REDOX', 's7:i2:p0', '化学方程式什么时候能拆成离子式'],
      ['H1_REDOX', 's7:i3:p0', '怎样用元素守恒确定缺失产物'],
      ['H1_REDOX', 's7:i4:p0', '酸化试剂会不会参与氧化还原'],
      ['H1_REDOX', 's5:i1:p56', '归中反应的氧化剂与还原剂比例'],
      ['H1_REDOX', 's7:i5:p0', '氧化还原反应的本质是什么'],
      ['H1_REDOX', 's7:i6:p0', '怎样判断是不是置换反应'],
      ['H1_REDOX', 's7:i7:p0', '理论产气量与实际收集量一样吗'],
    ]
    const authoredAddresses: string[] = []
    for (const patch of ionsRedoxFinePoints) {
      const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === patch.skillId)!
      const card: KnowledgeCard = { id: `KC_${patch.skillId}`, skillId: patch.skillId, title: patch.skillId,
        core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
        reviewStatus: 'approved', structuredContent: content }
      const points = getKnowledgeReviewPoints(card)
      for (const parent of patch.children) {
        for (const node of parent.children) authoredAddresses.push(`${card.id}:s${parent.sectionIndex}:i${parent.itemIndex}:p${node.reviewPointIndex}`)
      }
      for (const section of patch.appendSections) {
        const sectionIndex = content.sections.findIndex((entry) => entry.title === section.title)
        section.items.forEach((node, itemIndex) => {
          const leaves = getKnowledgeReviewLeaves(node)
          if (leaves.length) {
            for (const leaf of leaves) authoredAddresses.push(`${card.id}:s${sectionIndex}:i${itemIndex}:p${leaf.pointIndex}`)
          } else {
            authoredAddresses.push(`${card.id}:s${sectionIndex}:i${itemIndex}:p0`)
          }
        })
      }
      for (const [skill, address, title] of additions.filter(([skill]) => skill === patch.skillId)) {
        const found = points.filter((point) => point.id === `KC_${skill}:${address}`)
        expect(found).toHaveLength(1)
        expect(found[0].title).toBe(title)
        expect(found[0].examples).toHaveLength(1)
        expect(found[0].examples[0]).toMatch(/^教学例子：/)
      }
    }
    expect(authoredAddresses).toHaveLength(83)
    expect(new Set(authoredAddresses).size).toBe(83)
    const newAddresses = [...additions, ...postCoreAddresses,
      ['H1_REDOX', 's5:i1:p66', '等量H₂S在不同反应中，怎样比较电子数？'],
      ['H1_REDOX', 's6:i5:p67', '等量产物下，怎样比较反应物的用量？'],
      ['H1_REDOX', 's2:i0:p68', '等量O₂在不同反应中，怎样比较电子数？'],
      ['H1_REDOX', 's2:i0:p69', '已知产物的量，怎样换算转移电子的量？'],
      ['H1_REDOX', 's2:i0:p70', '怎样用电子守恒求未知系数？'],
      ['H1_REDOX', 's2:i0:p71', '已知电子的量，怎样反求产物的量？'],
      ['H1_REDOX', 's2:i0:p72', '同一侧有几种元素变价，电子数怎样合计？'],
    ].map(([skill, address]) => `KC_${skill}:${address}`)
    expect(authoredAddresses.filter((address) => !newAddresses.includes(address))).toHaveLength(58)
    const redox = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
    expect(redox.sections[7].items[1].examples?.[0]).toContain('按来源N原子数折合4份')
    expect(redox.sections[7].items[3].examples?.[0]).toContain('ZnCO₃+2C（高温）→Zn+3X↑')
    expect(redox.sections[7].items[4].rule).toContain('稀硫酸')
    const agentRatio = redox.sections[5].items[1].children?.find((node) => node.reviewPointIndex === 56)
    expect(agentRatio?.rule).toContain('较高价态物质作氧化剂、较低价态物质作还原剂')
    expect(agentRatio?.rule).toContain('真正参与变价的物质份额或平衡计量数')
    expect(agentRatio?.rule).toContain('比值以本题方程式为准')
    expect(agentRatio?.rule).not.toContain('1∶2')
    expect(agentRatio?.examples?.[0]).toContain('氧化剂∶还原剂=1∶2')
    expect(agentRatio?.caution).toContain('氧化产物S∶还原产物S的2∶1')
  })

  it('separates reaction essence, displacement and collection losses for independent self-ratings', () => {
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
    const card: KnowledgeCard = { id: 'KC_H1_REDOX', skillId: 'H1_REDOX', title: '氧化还原',
      core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: content }
    const leaves = getKnowledgeReviewPoints(card)
    const independent = [5, 6, 7].map((index) => leaves.find((point) => point.id === `${card.id}:s7:i${index}:p0`))
    expect(independent.every(Boolean)).toBe(true)
    expect(new Set(independent.map((point) => point!.id)).size).toBe(3)
    expect(independent[0]!.rule).toContain('电子转移')
    expect(independent[0]!.rule).not.toContain('实际收集量')
    expect(independent[1]!.rule).toContain('单质与一种化合物')
    expect(independent[1]!.rule).not.toContain('理论生成量')
    expect(independent[2]!.rule).toContain('理论生成量')
    expect(independent[2]!.examples[0]).toContain('原题明确给出1体积水可溶约2体积Cl₂')
    expect(independent[2]!.rule).not.toContain('置换反应')
  })

  it('restores the complete frozen 70-point input after removing only the later append-only updates', () => {
    const restored = structuredClone(ionsRedoxFinePoints)
    const currentRedox = restored.find((patch) => patch.skillId === 'H1_REDOX')!
    const currentSulfur = currentRedox.children.find((entry) => entry.sectionIndex === 5 && entry.itemIndex === 1)!
    expect(currentSulfur.children.at(-1)?.reviewPointIndex).toBe(66)
    currentSulfur.children.pop()
    const currentChlorine = currentRedox.appendSections.find((entry) => entry.title === '浓盐酸制氯气：只数真正变价的那一部分')!
    expect((currentChlorine.items.at(-1) as KnowledgeTreeNode).children?.[0].reviewPointIndex).toBe(67)
    currentChlorine.items.pop()
    const currentElectrons = currentRedox.children.find((entry) => entry.sectionIndex === 2 && entry.itemIndex === 0)!
    expect(currentElectrons.children.slice(3).map((node) => node.reviewPointIndex)).toEqual([68, 69, 70, 71, 72])
    currentElectrons.children.splice(3, 5)
    const electrolyte = restored.find((patch) => patch.skillId === 'H1_ELECTROLYTE')!
    const splitting = electrolyte.children.find((entry) => entry.sectionIndex === 2 && entry.itemIndex === 1)!
    expect(splitting.children.at(-1)?.reviewPointIndex).toBe(63)
    splitting.children.pop()
    const redox = restored.find((patch) => patch.skillId === 'H1_REDOX')!
    const section = redox.appendSections.find((entry) => entry.title === '逐项判断氧化还原的条件与数量')!
    expect(section.items).toHaveLength(13)
    section.items.splice(8, 5)
    // The digest is the full canonical JSON from released commit ce34ec5,
    // including every previous rule, example, address, guard and section field.
    expect(createHash('sha256').update(JSON.stringify(restored)).digest('hex'))
      .toBe('6713f8f035c47b0725f17281396abe434709b7d1fe1643c3b90d405b8639aad8')
  })

  it('restores every released 76-point field and address by removing only the seven new nodes', () => {
    const restored = structuredClone(ionsRedoxFinePoints)
    const redox = restored.find((patch) => patch.skillId === 'H1_REDOX')!
    const sulfur = redox.children.find((entry) => entry.sectionIndex === 5 && entry.itemIndex === 1)!
    expect(sulfur.children.at(-1)?.reviewPointIndex).toBe(66)
    sulfur.children.pop()
    const chlorine = redox.appendSections.find((entry) => entry.title === '浓盐酸制氯气：只数真正变价的那一部分')!
    expect(chlorine.items).toHaveLength(6)
    expect((chlorine.items.at(-1) as KnowledgeTreeNode).children?.[0].reviewPointIndex).toBe(67)
    chlorine.items.pop()
    const electrons = redox.children.find((entry) => entry.sectionIndex === 2 && entry.itemIndex === 0)!
    expect(electrons.children.slice(3).map((node) => node.reviewPointIndex)).toEqual([68, 69, 70, 71, 72])
    electrons.children.splice(3, 5)
    // Full authored input from released HEAD 5d7129b: no old rule, example,
    // section, guard, parent or address may change while adding this leaf.
    expect(createHash('sha256').update(JSON.stringify(restored)).digest('hex'))
      .toBe('a36ff5d8f8324d19de97056b5aa13755202f6c99b57d8bc5f1db7895f048d536')
  })

  it('separates the equal-H2S two-reaction comparison from the old whole-equation four-electron leaf', () => {
    const old = generatedPoint('H1_REDOX', 's5:i1:p53')
    const comparison = generatedPoint('H1_REDOX', 's5:i1:p66')
    expect(comparison.id).not.toBe(old.id)
    expect(comparison.title).toBe('等量H₂S在不同反应中，怎样比较电子数？')
    expect(comparison.rule).toContain('先统一该反应物的实际用量')
    expect(comparison.rule).toContain('每1 mol H₂S失去6 mol电子')
    expect(comparison.rule).toContain('每1 mol H₂S失去2 mol电子')
    expect(comparison.rule).toContain('Ⅰ∶Ⅱ的电子转移数为6∶2=3∶1')
    expect(comparison.rule).not.toContain('1∶3')
    expect(comparison.examples).toHaveLength(1)
    expect(comparison.examples[0]).toContain('2H₂S(g)+3O₂(g)=2SO₂(g)+2H₂O(g)')
    expect(comparison.examples[0]).toContain('2H₂S(g)+SO₂(g)=3S(l)+2H₂O(g)')
    expect(comparison.examples[0]).toContain('两反应均消耗1 mol H₂S')
    expect(comparison.examples).not.toEqual(old.examples)
    expect(old.rule).toBe('按所写SO₂+2H₂S=3S+2H₂O计量数，高价S得4e⁻，两个低价S共失4e⁻，转移数取4e⁻。')
    expect(old.examples).toEqual(['教学例子：1 mol SO₂与2 mol H₂S完全发生该反应时，转移4 mol电子；不能把得4 mol和失4 mol相加成8 mol。'])
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
    const parent = content.sections[5].items[1]
    expect(getKnowledgeReviewLeaves(parent).map((leaf) => leaf.pointIndex)).toEqual([50, 51, 52, 54, 55, 53, 56, 66])
    const node = parent.children!.find((leaf) => leaf.reviewPointIndex === 66)!
    expect(node.children).toBeUndefined()
    expect(node.caution).toContain('4 mol电子，对应消耗2 mol H₂S')
    expect(node.visualSteps).toEqual([
      '先把两反应统一到消耗1 mol H₂S',
      'Ⅰ：S由−2到+4，失6 mol电子',
      'Ⅱ：S由−2到0，失2 mol电子',
      '按Ⅰ∶Ⅱ求6∶2=3∶1',
    ])
    expect(node.visualSteps).not.toEqual(parent.visualSteps)
  })

  it('rates equal-product reactant amounts separately from chlorine electron counting and equal-H2S counting', () => {
    const amounts = generatedPoint('H1_REDOX', 's6:i5:p67')
    const electrons = generatedPoint('H1_REDOX', 's6:i4:p0')
    const h2s = generatedPoint('H1_REDOX', 's5:i1:p66')
    expect(new Set([amounts.id, electrons.id, h2s.id]).size).toBe(3)
    expect(amounts.title).toBe('等量产物下，怎样比较反应物的用量？')
    expect(amounts.rule).toContain('先统一产物的物质的量')
    expect(amounts.rule).toContain('MnO₂需1 mol，KMnO₄需2/5 mol')
    expect(amounts.rule).toContain('MnO₂∶KMnO₄=1∶(2/5)=5∶2')
    expect(amounts.rule).not.toContain('电子转移数')
    expect(amounts.examples).toHaveLength(1)
    expect(amounts.examples[0]).toContain('MnO₂+4HCl(浓)（加热）→MnCl₂+Cl₂↑+2H₂O')
    expect(amounts.examples[0]).toContain('2KMnO₄+16HCl(浓)（常温）→2KCl+2MnCl₂+5Cl₂↑+8H₂O')
    expect(amounts.examples[0]).toContain('KMnO₄∶MnO₂，则为2∶5')
    expect(amounts.examples).not.toEqual(electrons.examples)
    expect(amounts.examples).not.toEqual(h2s.examples)
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
    const parent = content.sections[6].items[5]
    expect(getKnowledgeReviewLeaves(parent).map((leaf) => leaf.pointIndex)).toEqual([67])
    const node = parent.children![0]
    expect(node.children).toBeUndefined()
    expect(node.caution).toContain('不能直接拿不同方程式中MnO₂的系数1与KMnO₄的系数2求1∶2')
    expect(node.visualSteps).toEqual([
      '先把两反应统一到生成1 mol Cl₂',
      '①：MnO₂∶Cl₂=1∶1，需1 mol MnO₂',
      '②：KMnO₄∶Cl₂=2∶5，需2/5 mol KMnO₄',
      '按MnO₂∶KMnO₄求1∶(2/5)=5∶2',
    ])
    // The wrapper is navigational; only its child has a familiarity rating.
    const card: KnowledgeCard = { id: 'KC_H1_REDOX', skillId: 'H1_REDOX', title: '氧化还原',
      core: content.intro, detail: '', steps: [], commonMistakes: [], microExample: '',
      reviewStatus: 'approved', structuredContent: content }
    expect(getKnowledgeReviewPoints(card).some((point) => point.id === 'KC_H1_REDOX:s6:i5:p0')).toBe(false)
  })

  it('compares electron amounts at the same oxygen yield without comparing unequal whole-equation yields', () => {
    const oxygen = generatedPoint('H1_REDOX', 's2:i0:p68')
    const h2s = generatedPoint('H1_REDOX', 's5:i1:p66')
    expect(oxygen.id).not.toBe(h2s.id)
    expect(oxygen.rule).toContain('H₂O₂生成1 mol O₂')
    expect(oxygen.rule).toContain('由−1升到0，失去2 mol电子')
    expect(oxygen.rule).toContain('由−2升到0，失去4 mol电子')
    expect(oxygen.rule).toContain('2∶4=1∶2')
    expect(oxygen.examples[0]).toContain('2H₂O₂（MnO₂催化）→2H₂O+O₂↑')
    expect(oxygen.examples[0]).toContain('2KClO₃（MnO₂催化、加热）→2KCl+3O₂↑')
    const node = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
      .sections[2].items[0].children!.find((leaf) => leaf.reviewPointIndex === 68)!
    expect(node.caution).toContain('两条整式生成的O₂量不同')
    expect(node.visualSteps).toEqual([
      '先把两反应统一到生成1 mol O₂',
      'H₂O₂：2 mol O由−1到0，失2 mol电子',
      'KClO₃：2 mol O由−2到0，失4 mol电子',
      '按③∶④求2∶4=1∶2',
    ])
    expect(node.visualSteps?.join(' ')).not.toContain('H₂S')
    expect(node.visualSteps?.join(' ')).not.toContain('MnO₂∶KMnO₄')
  })

  it('rates product-to-electrons and electrons-to-product as separate directed conversions', () => {
    const forward = generatedPoint('H1_REDOX', 's2:i0:p69')
    const product = generatedPoint('H1_REDOX', 's2:i0:p71')
    expect(forward.id).not.toBe(product.id)
    expect(forward.rule).toContain('n(e⁻)=n(产物)×每条方程式转移的电子数/该产物的系数')
    expect(forward.examples).toHaveLength(2)
    expect(forward.examples[0]).toContain('NaBH₄+2H₂O=NaBO₂+4H₂↑')
    expect(forward.examples[0]).toContain('n(e⁻)=1×4/4=1 mol')
    expect(forward.examples[0]).toContain('n(e⁻)=2×4/4=2 mol')
    expect(forward.examples[1]).toContain('K₂H₃IO₆+9HI=2KI+4I₂+6H₂O')
    expect(forward.examples[1]).toContain('n(e⁻)=0.05×7/4=0.0875 mol')
    expect(forward.examples.join(' ')).not.toContain('12.7 g')
    expect(product.rule).toContain('n(产物)=n(e⁻)×该产物的系数/每条方程式转移的电子数')
    expect(product.examples[0]).toContain('2MnO₄⁻+5H₂O₂+6H⁺=2Mn²⁺+5O₂↑+8H₂O')
    expect(product.examples[0]).toContain('n(O₂)=10×5/10=5 mol')
    expect(product.examples[0]).not.toContain('2H₂O₂=2H₂O')
    expect(forward.rule).not.toContain('n(产物)=n(e⁻)')
    expect(product.rule).not.toContain('n(e⁻)=n(产物)')
    const nodes = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
      .sections[2].items[0].children!.filter((node) => [69, 71].includes(node.reviewPointIndex!))
    expect(new Set(nodes.map((node) => JSON.stringify(node.visualSteps))).size).toBe(2)
    expect(nodes.every((node) => node.children === undefined)).toBe(true)
    for (const node of nodes) expect(node.visualSteps).toHaveLength(4)
  })

  it('totals all changing elements on one electron side without dropping copper or adding both sides', () => {
    const combined = generatedPoint('H1_REDOX', 's2:i0:p72')
    const oldWholeEquation = generatedPoint('H1_REDOX', 's2:i0:p52')
    expect(combined.id).not.toBe(oldWholeEquation.id)
    expect(combined.title).toBe('同一侧有几种元素变价，电子数怎样合计？')
    expect(combined.rule).toContain('两个Cu由+1降到0共得2e⁻')
    expect(combined.rule).toContain('两个O由0降到−2共得4e⁻')
    expect(combined.rule).toContain('同一得电子侧共得6e⁻')
    expect(combined.rule).toContain('S由−2升到+4失6e⁻')
    expect(combined.examples[0]).toContain('Cu₂S+O₂（高温）→2Cu+SO₂')
    expect(combined.examples[0]).toContain('0.4/6=1/15 mol')
    expect(combined.examples[0]).not.toContain('2.408')
    const node = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
      .sections[2].items[0].children!.find((leaf) => leaf.reviewPointIndex === 72)!
    expect(node.caution).toContain('会漏掉Cu得到的2份')
    expect(node.caution).toContain('误算消耗O₂为0.4/4=0.1 mol')
    expect(node.caution).toContain('不能再相加成12份')
    expect(node.visualSteps).toEqual([
      '先选同一得电子侧：Cu和O都降价',
      '两个Cu各由+1到0，共得2e⁻',
      '两个O各由0到−2，共得4e⁻',
      '同侧2+4=6e⁻；与S失6e⁻相等，转移数取6',
    ])
  })

  it('solves the unknown coefficient from electron balance independently of charge and atom conditions', () => {
    const coefficient = generatedPoint('H1_REDOX', 's2:i0:p70')
    const atomCount = generatedPoint('H1_REDOX', 's2:i0:p51')
    expect(coefficient.id).not.toBe(atomCount.id)
    expect(coefficient.rule).toContain('xR²⁺+yH⁺+O₂=mR³⁺+nH₂O')
    expect(coefficient.rule).toContain('x×1=4，x=4')
    expect(coefficient.examples[0]).toContain('O₂前的系数为1')
    expect(coefficient.examples[0]).toContain('x×1=2×2，得x=4')
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_REDOX')!
    const parent = content.sections[2].items[0]
    expect(getKnowledgeReviewLeaves(parent).map((leaf) => leaf.pointIndex)).toEqual([50, 51, 52, 68, 69, 70, 71, 72])
    const node = parent.children!.find((leaf) => leaf.reviewPointIndex === 70)!
    expect(node.visualSteps).toEqual([
      'R²⁺→R³⁺：每个失1e⁻，x个失xe⁻',
      '一个O₂有两个O，各由0到−2得2e⁻',
      '得电子总数为2×2=4e⁻',
      '令失电子=得电子：x×1=4，得x=4',
    ])
    expect(node.visualSteps?.join(' ')).not.toContain('电荷守恒')
    expect(node.visualSteps?.join(' ')).not.toContain('2x+y')
  })

  it('exposes six distinct ratings with their own examples and focused diagrams', () => {
    const points = postCoreAddresses.map(([skill, address, title]) => {
      const point = generatedPoint(skill, address)
      expect(point.title).toBe(title)
      expect(point.examples).toHaveLength(1)
      return point
    })
    expect(new Set(points.map((point) => point.id)).size).toBe(6)
    expect(new Set(points.flatMap((point) => point.examples)).size).toBe(6)
    const content = (zeroForgettingCards as GeneratedContent[]).find((entry) => entry.skillId === 'H1_ELECTROLYTE')!
    const ionNode = content.sections[2].items[1].children!.find((node) => node.reviewPointIndex === 63)!
    const nodes = [ionNode, ...[8, 9, 10, 11, 12].map((index) => generatedNode('H1_REDOX', index))]
    expect(new Set(nodes.map((node) => JSON.stringify(node.visualSteps))).size).toBe(6)
    for (const node of nodes) {
      expect(node.visualSteps).toHaveLength(3)
      expect(node.children).toBeUndefined()
    }
    expect(generatedNode('H1_REDOX', 9).visualSteps?.join(' ')).not.toContain('计量比')
    expect(generatedNode('H1_REDOX', 10).visualSteps?.join(' ')).not.toContain('n−x=2x')
    expect(generatedNode('H1_REDOX', 12).visualSteps?.join(' ')).not.toContain('SO₂')
  })

  it('requires the real ion species even when a fictitious ion passes atom and charge sums', () => {
    const point = generatedPoint('H1_ELECTROLYTE', 's2:i1:p63')
    expect(point.rule).toContain('实际电离产生的离子')
    expect(point.rule).toContain('不能把系数移进离子的下标或电荷')
    expect(point.examples[0]).toContain('Al³⁺和3Cl⁻')
    expect(point.examples[0]).toContain('不能改写为Cl₃³⁻')
    // AlCl3 -> Al3+ + Cl3^3- superficially has Al:1, Cl:3 and charge:0.
    // That arithmetic is insufficient: chloride must remain three Cl- ions.
    expect(point.examples[0]).toContain('原子数和总电荷看似守恒')
    expect(point.examples[0]).toContain('错误的离子')
    expect(point.rule).not.toContain('守恒就正确')
  })

  it('assigns agents to reactants within the stated reaction without banning SO2 as a reductant elsewhere', () => {
    const point = generatedPoint('H1_REDOX', 's7:i8:p0')
    const node = generatedNode('H1_REDOX', 8)
    expect(point.rule).toContain('反应物')
    expect(point.examples[0]).toContain('2H₂S+3O₂=2SO₂+2H₂O')
    expect(point.examples[0]).toContain('2H₂S+SO₂=3S+2H₂O')
    expect(point.examples[0]).toContain('S由+4降到0，SO₂作氧化剂')
    expect(node.caution).toContain('不把这个结论扩成SO₂在任何反应都不能作还原剂')
    expect(point.examples[0]).not.toContain('SO₂永远')
  })

  it('separates subtraction, intermediate origin and ideal stoichiometric matching instead of reusing one long chain', () => {
    const remaining = generatedPoint('H1_REDOX', 's7:i9:p0')
    const intermediate = generatedPoint('H1_REDOX', 's7:i10:p0')
    const matching = generatedPoint('H1_REDOX', 's7:i11:p0')
    expect(remaining.examples[0]).toContain('原有3 mol H₂S')
    expect(remaining.examples[0]).toContain('剩下2 mol')
    expect(remaining.examples[0]).not.toContain('n−x=2x')
    expect(intermediate.examples[0]).toContain('题给第一步2H₂S+3O₂=2SO₂+2H₂O')
    expect(intermediate.examples[0]).toContain('消耗x mol H₂S会生成x mol SO₂')
    expect(intermediate.examples[0]).not.toContain('x=n/3')
    expect(matching.examples[0]).toContain('题给第二步2H₂S+SO₂=3S+2H₂O')
    expect(matching.examples[0]).toContain('n−x=2x，所以x=n/3')
    expect(matching.rule).toContain('理想计量')
    expect(generatedNode('H1_REDOX', 11).caution).toContain('题目给出的两步反应和计量模型')
    expect(matching.rule).not.toContain('实际装置100%')
  })

  it('counts only the changing H atoms for elemental mass, independently of compound masses and doubled electron totals', () => {
    const point = generatedPoint('H1_REDOX', 's7:i12:p0')
    expect(point.rule).toContain('不计其所在化合物的整份质量')
    expect(point.examples[0]).toContain('NaBH₄+2H₂O=NaBO₂+4H₂')
    expect(point.examples[0]).toContain('NaBH₄的4个H由−1升到0')
    expect(point.examples[0]).toContain('2H₂O的4个H由+1降到0')
    expect(point.examples[0]).toContain('4Ar(H)∶4Ar(H)=1∶1')
    expect(generatedNode('H1_REDOX', 12).caution).toContain('不把得失电子两侧相加')
    expect(point.examples[0]).not.toContain('NaBH₄质量∶H₂O质量')
  })
})
