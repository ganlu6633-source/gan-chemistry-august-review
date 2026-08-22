import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { QuestionAssetRef, SessionIdentity } from '../domain/types'
import { loadQuestionAsset } from '../lib/api'
import { QuestionSourceMedia, type SourceBackedQuestionView } from './QuestionSourceMedia'

vi.mock('../lib/api', () => ({ loadQuestionAsset: vi.fn() }))

const session: SessionIdentity = { role: 'student', token: 'session-token', displayName: '高三学生', expiresAt: '2099-01-01T00:00:00Z' }
const asset = (assetId: string, kind: string, alt: string) => ({ assetId, kind, alt, sha256: `${assetId}-sha`, width: 900, height: 520 }) as unknown as QuestionAssetRef

const question: SourceBackedQuestionView = {
  id: 'licensed-q1',
  stem: '原题逐字转写',
  options: ['选项甲', '选项乙', '选项丙', '选项丁'],
  renderMode: 'image_primary',
  sourceInfo: { title: '2025年高考化学真题分类汇编', exam: '2025年福建省质检', year: 2025, questionNo: '第8题', locator: '第3页' },
  assetRefs: [asset('problem-asset', 'question_image', '2025年福建省质检第8题题面原图'), asset('analysis-asset', 'analysis_image', '2025年福建省质检第8题原解析图')],
}

describe('QuestionSourceMedia', () => {
  beforeEach(() => {
    vi.mocked(loadQuestionAsset).mockImplementation(async (_session, _questionId, assetId) => ({ asset: { dataUrl: `data:image/png;base64,${assetId}`, mimeType: 'image/png', sha256: `${assetId}-sha`, width: 900, height: 520 } }))
  })
  afterEach(() => { cleanup(); vi.clearAllMocks() })

  it('shows one source citation and never requests the analysis image before feedback', async () => {
    const ready = vi.fn()
    const view = render(<QuestionSourceMedia question={question} enabled session={session} onPrimaryReadyChange={ready} />)

    expect(screen.getAllByLabelText('原题来源')).toHaveLength(1)
    expect(screen.getByText('2025年福建省质检')).toBeInTheDocument()
    expect(await screen.findByAltText('2025年福建省质检第8题题面原图')).toBeInTheDocument()
    expect(loadQuestionAsset).toHaveBeenCalledTimes(1)
    expect(loadQuestionAsset).toHaveBeenCalledWith(session, 'licensed-q1', 'problem-asset', 'question', undefined)
    expect(screen.queryByText('原题解析图')).not.toBeInTheDocument()
    await waitFor(() => expect(ready).toHaveBeenLastCalledWith(true))

    view.rerender(<QuestionSourceMedia question={question} enabled session={session} feedback onPrimaryReadyChange={ready} />)
    expect(await screen.findByRole('heading', { name: '原题解析图' })).toBeInTheDocument()
    expect(await screen.findByAltText('2025年福建省质检第8题原解析图')).toBeInTheDocument()
    expect(loadQuestionAsset).toHaveBeenCalledWith(session, 'licensed-q1', 'analysis-asset', 'analysis', undefined)
  })

  it('blocks readiness when the primary image fails and recovers only after retry succeeds', async () => {
    vi.mocked(loadQuestionAsset)
      .mockRejectedValueOnce(new Error('网络中断'))
      .mockResolvedValueOnce({ asset: { dataUrl: 'data:image/png;base64,retry', mimeType: 'image/png', sha256: 'problem-asset-sha', width: 900, height: 520 } })
    const ready = vi.fn()
    render(<QuestionSourceMedia question={{ ...question, assetRefs: [asset('problem-asset', 'question_image', '题面主图')] }} enabled session={session} onPrimaryReadyChange={ready} />)

    expect(await screen.findByText('原题主图加载失败，暂不能提交')).toBeInTheDocument()
    expect(ready).toHaveBeenLastCalledWith(false)
    fireEvent.click(screen.getByRole('button', { name: /重试/ }))
    expect(await screen.findByAltText('题面主图')).toBeInTheDocument()
    await waitFor(() => expect(ready).toHaveBeenLastCalledWith(true))
  })

  it('uses neutral learner-facing image labels when source display is disabled', async () => {
    render(<QuestionSourceMedia question={{ ...question, assetRefs: [asset('problem-asset', 'question_image', '2025年福建省质检第8题题面原图')] }} enabled session={session} showSource={false} />)

    expect(screen.queryByLabelText('原题来源')).not.toBeInTheDocument()
    expect(await screen.findByAltText('本题原题题面图')).toBeInTheDocument()
    expect(screen.queryByAltText('2025年福建省质检第8题题面原图')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: '放大查看本题原题题面图' })).toBeInTheDocument()
    expect(screen.queryByText('查看文字辅助稿（公式、图示以原题图为准）')).not.toBeInTheDocument()
    expect(screen.queryByText('原题逐字转写')).not.toBeInTheDocument()
  })

  it('defers archived source images, expands transcription, and opens a closable zoom dialog', async () => {
    render(<QuestionSourceMedia question={{ ...question, assetRefs: [asset('problem-asset', 'source_scan', '档案中的原题图')] }} enabled session={session} deferLoad readOnly />)
    expect(loadQuestionAsset).not.toHaveBeenCalled()
    fireEvent.click(screen.getByText('查看文字辅助稿（公式、图示以原题图为准）'))
    expect(screen.getByText('原题逐字转写')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: '加载当时的原题图' }))
    const image = await screen.findByAltText('档案中的原题图')
    fireEvent.click(image.closest('button')!)
    const dialog = screen.getByRole('dialog', { name: '放大查看原题图' })
    await waitFor(() => expect(dialog).toHaveAttribute('open'))
    fireEvent.click(screen.getByRole('button', { name: '关闭原题大图' }))
    await waitFor(() => expect(dialog).not.toHaveAttribute('open'))
  })
})
