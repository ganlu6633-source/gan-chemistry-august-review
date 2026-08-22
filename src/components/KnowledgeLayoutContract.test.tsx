import { fireEvent, render } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import type { KnowledgeVisualSummary, StructuredKnowledgeContent } from '../domain/types'
import { StructuredKnowledgeMap } from './StudentApp'

const longCopy = '先确认研究对象和限定条件，再逐层判断并用对应的化学事实校验，不能因为版面宽度而省略任何一步。'.repeat(6)
const styles = readFileSync('src/styles.css', 'utf8')

const longContent: StructuredKnowledgeContent = {
  version: 4,
  intro: '长文本与深层展开布局回归',
  visualSummary: {
    kind: 'tree',
    title: '物质分类总树与多条彼此独立的横向分类轴',
    tree: {
      label: '物质',
      children: [{
        label: '纯净物',
        children: [{
          label: '化合物',
          children: [{
            label: '无机化合物',
            children: [{ label: '氧化物、酸、碱、盐还要继续按各自标准展开' }],
          }],
        }],
      }],
    },
    axes: [{ label: '电离分类轴', items: ['电解质', '非电解质', longCopy] }],
  },
  rootTree: {
    label: '物质',
    rule: longCopy,
    examples: [`完整示范：${longCopy}`],
    visualSteps: ['先定对象', longCopy, '再逐层判断', '最后校验'],
    children: [{
      label: '纯净物与混合物的判断必须保留完整限定条件',
      rule: longCopy,
      examples: [`边界示范：${longCopy}`],
      visualSteps: ['样品', '所含物质种类', longCopy],
      children: [{
        label: '化合物继续展开',
        rule: longCopy,
        examples: [`具体物质：${longCopy}`],
        children: [{
          label: '无机化合物继续展开氧化物、酸、碱和盐',
          rule: longCopy,
          examples: [`完整路径：${longCopy}`],
        }],
      }],
    }],
  },
  sections: [{
    title: '每一个知识点都能独立展开',
    summary: longCopy,
    items: [{
      label: '长标题仍须完整显示并允许换行',
      rule: longCopy,
      caution: longCopy,
      examples: [`示范一：${longCopy}`, `示范二：${longCopy}`],
      visualSteps: ['定义', longCopy, '例子', '自查'],
    }],
  }],
  workedExamples: [{ substance: '完整例题', path: longCopy, labels: ['第一步', longCopy, '第三步'] }],
  checkpoints: [longCopy],
  scopeNote: longCopy,
}

function contentForVisual(visual: KnowledgeVisualSummary): StructuredKnowledgeContent {
  return { version: 4, intro: '图形布局回归', visualSummary: visual, sections: [] }
}

function compactCss() {
  return styles.replace(/\s+/g, ' ').replace(/\s*([{}:;,>])\s*/g, '$1').trim()
}

describe('knowledge-card layout regression contract', () => {
  it('preserves long copy, examples, visual steps and every expanded tree level in the DOM', () => {
    const { container } = render(<StructuredKnowledgeMap content={longContent} />)

    fireEvent.click(container.querySelector('.full-explanation > summary')!)
    for (const detail of container.querySelectorAll<HTMLDetailsElement>('details.knowledge-branch-details, details.classification-item')) {
      if (!detail.open) fireEvent.click(detail.querySelector('summary')!)
    }

    expect(container.querySelectorAll('.knowledge-branch-details')).toHaveLength(4)
    expect(container.querySelectorAll('.point-with-demo')).toHaveLength(5)
    expect(container.querySelectorAll('.point-learning-aid')).toHaveLength(5)
    expect(container.querySelectorAll('.memory-flow')).toHaveLength(5)
    expect(container.querySelector('.classification-map')).toHaveTextContent(longCopy)
    expect(container.querySelector('.worked-example-grid')).toHaveTextContent(longCopy)
    expect([...container.querySelectorAll<HTMLDetailsElement>('details')].every((detail) => detail.open)).toBe(true)
  })

  it.each([
    ['tree', { kind: 'tree', title: longCopy, tree: { label: longCopy, children: [{ label: longCopy }] }, axes: [{ label: longCopy, items: [longCopy] }] }],
    ['flow', { kind: 'flow', title: longCopy, steps: [{ label: longCopy }, { label: longCopy }] }],
    ['cycle', { kind: 'cycle', title: longCopy, steps: [{ label: longCopy }, { label: longCopy }] }],
    ['compare', { kind: 'compare', title: longCopy, groups: [{ label: longCopy, items: [longCopy] }] }],
    ['network', { kind: 'network', title: longCopy, center: longCopy, groups: [{ label: longCopy, items: [longCopy] }] }],
    ['balance', { kind: 'balance', title: longCopy, center: '=', groups: [{ label: `${longCopy}左`, items: [longCopy] }, { label: `${longCopy}右`, items: [longCopy] }] }],
  ] as const)('renders the %s visual with its complete content and responsive class', (kind, visual) => {
    const { container } = render(<StructuredKnowledgeMap content={contentForVisual(visual as unknown as KnowledgeVisualSummary)} />)
    expect(container.querySelector(`.quick-visual-${kind}`)).toBeInTheDocument()
    expect(container.querySelector('.quick-visual')).toHaveTextContent(longCopy)
  })

  it.each([
    ['H1_MOLE_INTRO', '物质的量、阿伏加德罗常数与摩尔质量关系图'],
    ['H1_GAS_MOLAR_VOLUME', '气体摩尔体积的条件闸门与换算关系图'],
    ['H1_REDOX', '氧化还原反应双轨关系与电子守恒图'],
  ] as const)('keeps the source-informed %s figure fluid, shrinkable and free of text truncation', (skillId, label) => {
    const { container } = render(<StructuredKnowledgeMap content={contentForVisual({ kind: 'flow', title: '占位图', steps: [] })} skillId={skillId} />)
    const figure = container.querySelector<HTMLElement>(`figure[aria-label="${label}"]`)

    expect(figure).toBeInTheDocument()
    expect(figure?.style.width).toBe('100%')
    expect(figure?.style.minWidth).toBe('0')
    expect(figure?.style.overflowWrap).toBe('anywhere')
    expect([...figure!.querySelectorAll<HTMLElement>('*')].every((node) => node.style.textOverflow !== 'ellipsis' && node.style.webkitLineClamp === '')).toBe(true)

    const responsiveGrids = [...figure!.querySelectorAll<HTMLElement>('[style*="grid-template-columns"]')]
    expect(responsiveGrids.length).toBeGreaterThan(0)
    expect(responsiveGrids.every((grid) => grid.style.gridTemplateColumns.includes('min(100%'))).toBe(true)
    expect([...figure!.querySelectorAll<SVGElement>('svg')].every((svg) => svg.hasAttribute('viewBox') && svg.style.maxWidth !== 'none')).toBe(true)
  })

  it('keeps the shrink-and-reflow CSS invariants that prevent clipping and page-level horizontal overflow', () => {
    const css = compactCss()

    expect(css).toContain('*{box-sizing:border-box}')
    expect(css).toContain('.learning-stage{max-width:820px;margin:0 auto}')
    expect(css).toContain('.classification-items{grid-template-columns:1fr}')
    expect(css).toContain('.point-with-demo{display:grid;grid-template-columns:minmax(0,1fr);gap:12px;align-items:start;min-width:0}')
    expect(css).toContain('.point-copy,.point-learning-aid,.point-demo,.memory-diagram{min-width:0;max-width:100%}')
    expect(css).toMatch(/\.point-copy>p\{[^}]*overflow-wrap:anywhere/)
    expect(css).toMatch(/\.point-demo>p\{[^}]*overflow-wrap:anywhere/)

    expect(css).toMatch(/\.memory-flow\{[^}]*width:100%;min-width:0;overflow:visible/)
    expect(css).toMatch(/\.memory-flow span\{[^}]*flex:1 1 0;min-width:0;[^}]*overflow-wrap:anywhere/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.quick-flow\{display:grid;grid-template-columns:1fr/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.memory-flow\{display:grid;grid-template-columns:minmax\(0,1fr\)/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.memory-flow span\{width:100%;min-width:0\}/)

    expect(css).toMatch(/\.quick-flow li\{[^}]*min-width:0/)
    expect(css).toMatch(/\.quick-compare\{[^}]*repeat\(auto-fit,minmax\(150px,1fr\)\)/)
    expect(css).toMatch(/\.network-branches\{[^}]*width:100%;[^}]*repeat\(auto-fit,minmax\(125px,1fr\)\)/)
    expect(css).toMatch(/\.periodic-row\{[^}]*min-width:0/)
    expect(css).toMatch(/\.periodic-row>\*\{[^}]*min-width:0;[^}]*overflow-wrap:anywhere/)
    expect(css).toMatch(/\.energy-profile svg\{[^}]*width:100%;height:auto/)
    expect(css).toMatch(/\.worked-example-grid article\.worked-example-with-visual\{[^}]*grid-column:1\/-1;min-width:0/)
    expect(css).toMatch(/\.hydrogen-energy-visual\{[^}]*min-width:0;max-width:100%;[^}]*overflow:hidden/)
    expect(css).toMatch(/\.hydrogen-energy-visual svg\{[^}]*width:100%;height:auto;max-width:100%/)
    expect(css).toMatch(/\.hydrogen-energy-svg-mobile\{display:none!important\}/)
    expect(css).toMatch(/\.hydrogen-energy-key\{[^}]*repeat\(auto-fit,minmax\(min\(100%,160px\),1fr\)\)/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.bond-energy-ledger\{grid-template-columns:1fr\}/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.hydrogen-energy-key\{grid-template-columns:1fr\}/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.hydrogen-energy-svg-desktop\{display:none!important\}[\s\S]*\.hydrogen-energy-svg-mobile\{display:block!important\}/)
    expect(css).toMatch(/\.redox-balance-visual\{[^}]*min-width:0;max-width:100%;[^}]*overflow:hidden/)
    expect(css).toMatch(/\.redox-balance-steps\{[^}]*repeat\(2,minmax\(0,1fr\)\)/)
    expect(css).toMatch(/\.redox-final-equation\{[^}]*word-break:normal;overflow-wrap:normal/)
    expect(css).toMatch(/\.redox-check-grid\{[^}]*repeat\(3,minmax\(0,1fr\)\)/)
    expect(css).toMatch(/@media\(max-width:700px\)\{[\s\S]*\.redox-balance-steps,\.redox-change-lanes\{grid-template-columns:1fr\}[\s\S]*\.redox-check-grid\{grid-template-columns:1fr\}/)
    expect(css).toMatch(/\.source-image-zoom img\{max-height:none\}/)
    expect(css).toMatch(/\.source-image-dialog>div\{overflow:auto\}/)
    expect(css).toMatch(/\.source-image-dialog>div>img\{width:auto;min-width:100%;max-width:none;max-height:none\}/)
    expect(css).toMatch(/@media\(max-width:430px\)\{\.source-image-dialog>div>img\{width:auto;min-width:max\(100%,900px\);max-width:none;max-height:none\}\}/)
  })
})
