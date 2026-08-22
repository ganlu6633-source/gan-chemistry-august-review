import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import type { LearningRecordData, LearningRecordSkill } from '../domain/types'
import { LearningRecordPanel } from './LearningRecordPanel'

const makeSkill = (overrides: Partial<LearningRecordSkill>): LearningRecordSkill => ({
  skillId: 'H1_CLASSIFY',
  title: '物质的分类',
  moduleId: 'H1_FOUNDATION',
  maxLevel: 4,
  verifiedLevel: 2,
  candidateLevel: null,
  evidenceStatus: 'partial',
  exposure: 'learned',
  retentionStatus: 'forming',
  lastReviewedAt: '2026-08-13T08:00:00Z',
  nextReviewAt: '2026-08-17T08:00:00Z',
  teacherIntervention: false,
  attemptCount: 1,
  answeredQuestionCount: 1,
  correctQuestionCount: 0,
  uniqueMotherCount: 1,
  learnedTopics: ['混合物与纯净物', '单质与化合物'],
  knowledgeSections: [{ id: 'classification-tree', title: '分类总树', summary: '从物质一路向下判断', points: [{ id: 'pure', title: '纯净物', rule: '纯净物继续分为单质和化合物。' }] }],
  knowledgeEvidenceScope: 'module_directory_only',
  recentQuestions: [{ questionId: 'q1', motherId: 'm1', level: 2, stem: '下列物质属于纯净物的是', options: ['空气', '液氯', '盐酸', '漂白粉'], selectedOption: 0, correctOption: 1, explanation: '液氯只含Cl₂一种物质，属于纯净物。', correct: false, uncertain: true, durationSec: 38, answeredAt: '2026-08-13T08:00:00Z', snapshotAvailable: true, currentQuestionStatus: 'retired' }],
  recentQuestionsTruncated: false,
  nextPlan: { id: 'plan-1', date: '2026-08-17', title: '分类树与电解质' },
  ...overrides,
})

const record: LearningRecordData = {
  generatedAt: '2026-08-14T08:00:00Z',
  evidenceScope: '技能级证据；知识点列表仅说明模块包含什么，不代表每个知识点都已逐项验证。',
  summary: { total: 5, learned: 4, full: 1, partial: 2, unlit: 1, due: 1, recovered: 0, answeredQuestions: 4 },
  historyWindow: { attemptLimit: 500, answerLimit: 500, recentQuestionsPerSkillLimit: 20, loadedAttempts: 8, totalAttempts: 9, loadedAnswers: 4, totalAnswersInLoadedAttempts: 4, attemptsTruncated: true, answersTruncated: false, hasMore: true },
  skills: [
    makeSkill({}),
    makeSkill({ skillId: 'H1_PERIODIC', title: '元素周期律', evidenceStatus: 'full', verifiedLevel: 4, retentionStatus: 'stable', recentQuestions: [], answeredQuestionCount: 2, correctQuestionCount: 2, uniqueMotherCount: 2, knowledgeSections: [] }),
    makeSkill({ skillId: 'H1_REDOX', title: '氧化还原', evidenceStatus: 'unlit', verifiedLevel: 0, retentionStatus: 'unknown', recentQuestions: [], answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0 }),
    makeSkill({ skillId: 'H1_MOLE_INTRO', title: '物质的量基础', evidenceStatus: 'partial', verifiedLevel: 1, retentionStatus: 'due', recentQuestions: [], answeredQuestionCount: 1, correctQuestionCount: 1 }),
    makeSkill({ skillId: 'H1_ELECTROLYTE', title: '离子反应', evidenceStatus: 'unlit', verifiedLevel: 0, exposure: 'future', retentionStatus: 'unknown', recentQuestions: [], answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0 }),
  ],
}

describe('LearningRecordPanel', () => {
  afterEach(cleanup)

  it('separates future learning from learned skills awaiting evidence', () => {
    render(<LearningRecordPanel record={record} gradeBand="高一" />)

    const summary = screen.getByLabelText('学习证据摘要')
    expect(within(summary).getByText('完全点亮').previousElementSibling).toHaveTextContent('1')
    expect(within(summary).getByText('点亮一部分').previousElementSibling).toHaveTextContent('2')
    expect(within(summary).getByText('待建立证据').previousElementSibling).toHaveTextContent('1')
    expect(within(summary).getByText('需要回看').previousElementSibling).toHaveTextContent('1')
    expect(within(summary).getByText('后续学习').previousElementSibling).toHaveTextContent('1')
    expect(screen.getByText('4/5')).toBeInTheDocument()
    expect(screen.getByText(/当前显示最近记录：已读取 8\/9 轮学习/)).toBeInTheDocument()
  })

  it('groups skills along the ability-map stages and filters without relabeling future skills', () => {
    render(<LearningRecordPanel record={record} gradeBand="高一" />)

    expect(screen.getByRole('heading', { name: '认识物质' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: '理解微粒与变化' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /后续学习 1/ }))
    expect(screen.getByText('离子反应')).toBeInTheDocument()
    expect(screen.queryByText('氧化还原')).not.toBeInTheDocument()
    expect(screen.getAllByText('后续学习').length).toBeGreaterThan(0)
  })

  it('opens a skill into its knowledge checklist and exact answered-question evidence', () => {
    render(<LearningRecordPanel record={record} gradeBand="高一" audience="guardian" />)

    const skillCard = screen.getByText('物质的分类').closest('details')!
    fireEvent.click(within(skillCard).getByText('物质的分类').closest('summary')!)
    expect(within(skillCard).getByText('分类总树')).toBeInTheDocument()
    expect(within(skillCard).getByText('纯净物继续分为单质和化合物。')).toBeInTheDocument()
    expect(screen.getByText(/知识点列表仅说明模块包含什么/)).toBeInTheDocument()

    fireEvent.click(within(skillCard).getByText(/真实作答 1/).closest('summary')!)
    expect(within(skillCard).getAllByText('下列物质属于纯净物的是').length).toBeGreaterThan(0)
    const optionRows = [...skillCard.querySelectorAll<HTMLElement>('.record-option-list li')]
    const airOption = optionRows.find((row) => row.textContent?.includes('空气'))
    const chlorineOption = optionRows.find((row) => row.textContent?.includes('液氯'))
    expect(airOption).toBeDefined()
    expect(chlorineOption).toBeDefined()
    expect(within(airOption!).getByText('A')).toBeInTheDocument()
    expect(within(chlorineOption!).getByText('B')).toBeInTheDocument()
    expect(within(skillCard).getByText('液氯只含Cl₂一种物质，属于纯净物。')).toBeInTheDocument()
    expect(within(skillCard).getByText(/本题作答时标记了“不确定”/)).toBeInTheDocument()
    expect(within(skillCard).getByText(/这道历史题已退出当前使用版本/)).toBeInTheDocument()
  })

  it('formats chemistry notation in historical question evidence', () => {
    const formulaQuestion = {
      ...record.skills[0].recentQuestions[0],
      stem: '比较NO2和N2的性质',
      options: ['Fe2+', 'NH4+'],
      explanation: 'SO4^2-中硫元素的化合价需要结合电荷守恒判断。',
    }
    const formulaRecord = { ...record, skills: [makeSkill({ recentQuestions: [formulaQuestion] })] }
    render(<LearningRecordPanel record={formulaRecord} gradeBand="高一" audience="guardian" />)

    const skillCard = screen.getByText('物质的分类').closest('details')!
    fireEvent.click(within(skillCard).getByText('物质的分类').closest('summary')!)
    fireEvent.click(within(skillCard).getByText(/真实作答 1/).closest('summary')!)
    expect(within(skillCard).getAllByLabelText('NO2')[0].querySelector('sub')?.textContent).toBe('2')
    expect(within(skillCard).getAllByLabelText('Fe2+')[0].querySelector('sup')?.textContent).toBe('2+')
    expect(within(skillCard).getAllByLabelText('NH4+')[0].querySelector('sub')?.textContent).toBe('4')
    expect(within(skillCard).getByLabelText('SO4^2-').querySelector('sup')?.textContent).toBe('2-')
  })

  it('keeps option-by-option explanations separated in the historical record', () => {
    const segmentedQuestion = {
      ...record.skills[0].recentQuestions[0],
      explanation: 'A：空气含多种物质，错误；B：液氯只含Cl₂一种物质，正确；C：盐酸是混合物，错误；D：漂白粉是混合物，错误。',
    }
    const segmentedRecord = { ...record, skills: [makeSkill({ recentQuestions: [segmentedQuestion] })] }
    render(<LearningRecordPanel record={segmentedRecord} gradeBand="高一" audience="guardian" />)

    const skillCard = screen.getByText('物质的分类').closest('details')!
    fireEvent.click(within(skillCard).getByText('物质的分类').closest('summary')!)
    fireEvent.click(within(skillCard).getByText(/真实作答 1/).closest('summary')!)
    const paragraphs = [...skillCard.querySelectorAll<HTMLElement>('.record-explanation .answer-explanation>p')]
    expect(paragraphs).toHaveLength(4)
    expect(paragraphs.map((paragraph) => paragraph.querySelector('.answer-option-label')?.textContent)).toEqual(['A', 'B', 'C', 'D'])
  })

  it('shows only the historical question image without exposing source details or analysis artwork', () => {
    const originalEvidence = {
      ...makeSkill({}).recentQuestions[0],
      questionId: 'h3-source-q1',
      sourceKind: 'licensed_local' as const,
      mode: 'REVIEW' as const,
      sourceInfo: { title: '高考真题分类汇编', exam: '2025年福建省质检', year: 2025, questionNo: '第8题', locator: '第3页' },
      renderMode: 'image_primary' as const,
      assetRefs: [
        { assetId: 'source/questions/h3-q1', kind: 'question_image' as const, alt: '第8题原题图', sha256: 'a'.repeat(64), width: 900, height: 500 },
        { assetId: 'source/analysis/h3-q1', kind: 'analysis_image' as const, alt: '第8题原解析图', sha256: 'b'.repeat(64), width: 900, height: 700 },
      ],
    }
    const high3Record: LearningRecordData = {
      ...record,
      summary: { ...record.summary, total: 1, learned: 1 },
      skills: [makeSkill({ skillId: 'H3_STOICH', title: '化学计量', recentQuestions: [originalEvidence] })],
    }
    render(<LearningRecordPanel record={high3Record} gradeBand="高三" audience="guardian" />)

    const skillCard = screen.getByText('化学计量').closest('details')!
    fireEvent.click(within(skillCard).getByText('化学计量').closest('summary')!)
    fireEvent.click(within(skillCard).getByText(/真实作答 1/).closest('summary')!)
    expect(within(skillCard).queryByLabelText('原题来源')).not.toBeInTheDocument()
    expect(within(skillCard).queryByText('2025年福建省质检')).not.toBeInTheDocument()
    expect(within(skillCard).getByRole('button', { name: '加载当时的原题图' })).toBeInTheDocument()
  })
})
