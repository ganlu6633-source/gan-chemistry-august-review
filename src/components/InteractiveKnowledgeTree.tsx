import { useId, useLayoutEffect, useRef, useState } from 'react'
import type { KnowledgeTreeNode } from '../domain/types'
import { ChemText } from './ChemText'
import './InteractiveKnowledgeTree.css'

type DetailView = 'knowledge' | 'examples'

function nodeAtPath(root: KnowledgeTreeNode, path: number[]) {
  if (path[0] !== 0) return undefined
  let node: KnowledgeTreeNode | undefined = root
  for (const index of path.slice(1)) node = node?.children?.[index]
  return node
}

function TreeBranch({
  node,
  path,
  expandedPaths,
  selectedPath,
  idPrefix,
  onSelect,
}: {
  node: KnowledgeTreeNode
  path: number[]
  expandedPaths: Set<string>
  selectedPath: string | null
  idPrefix: string
  onSelect: (path: number[]) => void
}) {
  const pathKey = path.join('-')
  const hasChildren = Boolean(node.children?.length)
  const expanded = expandedPaths.has(pathKey)
  const isCrossClassification = node.label.startsWith('横向轴')

  return <li className={`interactive-tree-branch${isCrossClassification ? ' is-cross-classification' : ''}${hasChildren && expanded ? ' has-open-children' : ''}`}>
    <button
      type="button"
      id={`${idPrefix}-node-${pathKey}`}
      className="interactive-tree-node"
      aria-label={node.label}
      aria-describedby={isCrossClassification ? `${idPrefix}-cross-${pathKey}` : undefined}
      aria-expanded={hasChildren ? expanded : undefined}
      aria-pressed={selectedPath === pathKey}
      aria-controls={hasChildren && expanded ? `${idPrefix}-children-${pathKey}` : undefined}
      onClick={() => onSelect(path)}
    >
      <span className="interactive-tree-node-label"><ChemText>{node.label}</ChemText></span>
      {isCrossClassification && <small className="interactive-tree-cross-tag" id={`${idPrefix}-cross-${pathKey}`}>交叉分类</small>}
      {hasChildren && <span className="interactive-tree-expand-icon" aria-hidden="true">{expanded ? '−' : '+'}</span>}
    </button>
    {hasChildren && expanded && <ul className="interactive-tree-children" id={`${idPrefix}-children-${pathKey}`}>
      {node.children!.map((child, index) => <TreeBranch
        key={`${pathKey}-${index}`}
        node={child}
        path={[...path, index]}
        expandedPaths={expandedPaths}
        selectedPath={selectedPath}
        idPrefix={idPrefix}
        onSelect={onSelect}
      />)}
    </ul>}
  </li>
}

/** One source of truth for both the horizontal tree and its node explanations. */
export function InteractiveKnowledgeTree({ root }: { root: KnowledgeTreeNode }) {
  const idPrefix = useId().replace(/:/g, '')
  const scrollRef = useRef<HTMLDivElement>(null)
  const [expandedPaths, setExpandedPaths] = useState<Set<string>>(() => new Set())
  const [selectedPath, setSelectedPath] = useState<number[] | null>(null)
  const [detailView, setDetailView] = useState<DetailView>('knowledge')
  const selectedNode = selectedPath ? nodeAtPath(root, selectedPath) : undefined
  const selectedPathKey = selectedPath?.join('-') ?? null

  useLayoutEffect(() => {
    if (!selectedPathKey || !expandedPaths.has(selectedPathKey)) return
    const viewport = scrollRef.current
    const children = document.getElementById(`${idPrefix}-children-${selectedPathKey}`)
    const firstChild = children?.querySelector(':scope > li > button')
    if (!viewport || !firstChild) return
    const viewportRect = viewport.getBoundingClientRect()
    const overflow = firstChild.getBoundingClientRect().right - viewportRect.right + 14
    if (overflow > 0) viewport.scrollLeft += overflow
    if (viewport.scrollHeight > viewport.clientHeight + 1) {
      const selectedButton = document.getElementById(`${idPrefix}-node-${selectedPathKey}`)
      if (selectedButton) viewport.scrollTop += selectedButton.getBoundingClientRect().top - viewportRect.top - viewport.clientHeight * 0.4
    }
  }, [expandedPaths, idPrefix, selectedPathKey])

  function selectNode(path: number[]) {
    const node = nodeAtPath(root, path)
    if (!node) return
    const pathKey = path.join('-')
    setSelectedPath(path)
    setDetailView('knowledge')
    if (node.children?.length) {
      setExpandedPaths((current) => {
        const next = new Set(current)
        if (next.has(pathKey)) next.delete(pathKey)
        else next.add(pathKey)
        return next
      })
    }
  }

  return <section className="interactive-knowledge-tree" aria-label="物质分类交互树">
    <div className="interactive-tree-heading">
      <div><b>物质分类总树</b><p>从起点点开分支；每个节点都能单独查看讲解和范例。</p></div>
      <span>左右、上下滑动看全图 ↔ ↕</span>
    </div>
    <div className="interactive-tree-scroll" ref={scrollRef} role="region" aria-label="知识树，可横向或纵向滚动查看分支" tabIndex={0}>
      <ul className="interactive-tree-root">
        <TreeBranch node={root} path={[0]} expandedPaths={expandedPaths} selectedPath={selectedPathKey} idPrefix={idPrefix} onSelect={selectNode} />
      </ul>
    </div>
    {selectedNode ? <section className="interactive-tree-detail" aria-labelledby={`${idPrefix}-detail-title`}>
      <div className="interactive-tree-detail-heading">
        <div><span>当前节点</span><h3 id={`${idPrefix}-detail-title`}><ChemText>{selectedNode.label}</ChemText></h3></div>
        <div className="interactive-tree-detail-switch" role="group" aria-label={`${selectedNode.label}的学习内容`}>
          <button type="button" aria-pressed={detailView === 'knowledge'} onClick={() => setDetailView('knowledge')}>知识点</button>
          <button type="button" aria-pressed={detailView === 'examples'} onClick={() => setDetailView('examples')}>范例</button>
        </div>
      </div>
      <div className="interactive-tree-detail-content">
        {detailView === 'knowledge' ? <>
          <p><ChemText>{selectedNode.rule}</ChemText></p>
          {selectedNode.caution && <p className="interactive-tree-caution"><b>注意：</b><ChemText>{selectedNode.caution}</ChemText></p>}
        </> : selectedNode.examples?.length ? <ul>
          {selectedNode.examples.map((example, index) => <li key={`${selectedPathKey}-${index}`}><ChemText>{example}</ChemText></li>)}
        </ul> : <p className="interactive-tree-no-examples">这个节点暂时没有单列范例，可以先看“知识点”中的判断依据。</p>}
      </div>
    </section> : <p className="interactive-tree-start-hint">点“{root.label}”，沿着分支一步步展开。</p>}
  </section>
}
