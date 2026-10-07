import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { IssuedJuniorQuestion, JuniorAdaptivePayload, LearningPlanDay, QuestionAssetRef, SessionIdentity } from '../domain/types'
import { accessApi, submitJuniorAdaptiveStep } from '../lib/api'
import { JuniorAdaptiveSession } from './JuniorAdaptiveSession'

// These tests exercise the real component with a mocked HTTP boundary. They do
// not prove a logged-in production session, original crop pixels, or DB rights.
vi.mock('../lib/api', () => ({ accessApi: vi.fn(), submitJuniorAdaptiveStep: vi.fn(), loadQuestionAsset: vi.fn() }))
vi.mock('../domain/compactImageWhitespace', () => ({ inspectImageWhitespaceOffThread: vi.fn().mockResolvedValue(null) }))

const student: SessionIdentity = { role: 'student', token: 'unit-student-session', displayName: '初三学生', expiresAt: '2099-01-01T00:00:00Z' }
const teacher: SessionIdentity = { ...student, role: 'teacher', token: 'unit-teacher-session' }
const studentId = '11111111-1111-4111-8111-111111111111'
const planId = '22222222-2222-4222-8222-222222222222'
const stepId = '33333333-3333-4333-8333-333333333333'
const revision = '7b060cf1503c8775fd2a30946f11123fff7fee5ea8ccc61fdb5a35c59710a7c6'
const auxiliary: QuestionAssetRef = { assetId: 'JCAUX022_ORIG_56D757684D49F25C', kind: 'question_image',
  sha256: '56d757684d49f25ca4ed1186d81ebf39e51ed754028c1b7acf85ee30bc04be43', width: 235, height: 325,
  alt: '白磷和红磷燃烧条件对照实验原图' }
const plan: LearningPlanDay = { id: planId, studentId, date: '2026-10-07', mode: 'REVIEW', title: '燃烧条件',
  skillIds: ['J_KY_COMBUSTION'], knowledgeSummaries: [], estimatedMinutes: 20, source: 'course', isScheduled: true,
  attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 8, roundLimit: 1,
  maxQuestionLevel: 2, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'active', hardQuestionCap: 15,
  isResolved: false, isComplete: false, roundsRemaining: 1 }
const originalQuestion: IssuedJuniorQuestion = { skillId: 'J_KY_COMBUSTION', level: 2, gradeBand: '初三', renderMode: 'native',
  mediaId: stepId, revisionToken: revision, assetRefs: [], auxiliaryAssetRefs: [auxiliary],
  stem: '实验中白磷1和红磷分别放在两支充有空气、管口套气球的试管内，两支试管均放在同一烧杯的80 ℃热水中加热；白磷2直接放在这杯热水中（试管外）。已知白磷着火点40 ℃，红磷着火点240 ℃。观察到白磷1燃烧，红磷和白磷2不燃烧。下列说法错误的是（ ）',
  options: ['白磷1燃烧而白磷2不燃烧说明燃烧需要空气', '白磷1燃烧而红磷不燃烧说明燃烧需要温度达到着火点',
    '气球的作用是防止燃烧产生的五氧化二磷污染空气', '通氧气可使白磷2燃烧，升高热水温度可使红磷燃烧'] }
const makePayload = (question = originalQuestion): JuniorAdaptivePayload => ({ deliveryMode: 'junior_adaptive', plan, cards: [],
  session: { id: '44444444-4444-4444-8444-444444444444', status: 'active', initialQuestionTarget: 8, hardQuestionCap: 15,
    issuedCount: 1, answeredCount: 0, correctCount: 0 }, currentStepId: stepId, currentQuestion: question, completed: false })
// A small valid PNG is an HTTP unit fixture, not the reviewed 235x325 crop.
const imageUrl = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVQImWP8////fwYGBgYmBiAFAAA7AAO8f2YuAAAAAElFTkSuQmCC'
const mediaResult = { asset: { kind: 'question_image', mimeType: 'image/png', dataUrl: imageUrl,
  sha256: auxiliary.sha256, width: auxiliary.width, height: auxiliary.height } }
const renderSession = (question = originalQuestion, preview = false) => render(<JuniorAdaptiveSession
  session={preview ? teacher : student} previewStudentId={preview ? studentId : undefined}
  initialPayload={makePayload(question)} onExit={vi.fn()} onComplete={vi.fn()} />)
const chooseD = () => fireEvent.click(screen.getByRole('button', { name: `D. ${originalQuestion.options[3]}` }))

describe('J022 separate auxiliary figure through the actual JuniorAdaptiveSession', () => {
  beforeEach(() => { vi.mocked(accessApi).mockResolvedValue(mediaResult); vi.mocked(submitJuniorAdaptiveStep).mockReset() })
  afterEach(() => { cleanup(); vi.clearAllMocks() })

  it.each([false, true])('loads the separate figure with its original step/version/plan context (teacher preview=%s)', async (preview) => {
    const before = structuredClone(originalQuestion)
    renderSession(originalQuestion, preview)
    expect(await screen.findByRole('img', { name: '本题原题题面图' })).toHaveAttribute('src', imageUrl)
    expect(accessApi).toHaveBeenCalledWith(preview ? teacher : student, 'junior_auxiliary_asset', {
      questionId: stepId, assetId: auxiliary.assetId, phase: 'question', planId, attemptSequence: 0,
      revisionToken: revision, ...(preview ? { studentId } : {}) })
    expect(screen.getByRole('heading', { name: originalQuestion.stem })).toBeVisible()
    expect(screen.getAllByRole('button', { name: /^[ABCD]\. / })).toHaveLength(4)
    expect(originalQuestion).toEqual(before)
    expect(originalQuestion.assetRefs).toEqual([])
    expect(accessApi).not.toHaveBeenCalledWith(expect.anything(), 'junior_question_asset', expect.anything())
  })

  it('does not fetch an auxiliary when the response has none', async () => {
    renderSession({ ...originalQuestion, auxiliaryAssetRefs: [] })
    await act(async () => { await Promise.resolve() })
    expect(accessApi).not.toHaveBeenCalled()
    expect(screen.getByRole('heading', { name: originalQuestion.stem })).toBeVisible()
    chooseD(); expect(screen.getByRole('button', { name: '提交答案' })).toBeEnabled()
  })

  it('keeps native text answerable during auxiliary network failure and retries the same protected context', async () => {
    vi.mocked(accessApi).mockRejectedValueOnce(new Error('辅助原图网络中断')).mockResolvedValueOnce(mediaResult)
    renderSession()
    expect(await screen.findByText('辅助原图网络中断')).toBeVisible()
    chooseD(); expect(screen.getByRole('button', { name: '提交答案' })).toBeEnabled()
    fireEvent.click(screen.getByRole('button', { name: /重试/ }))
    expect(await screen.findByRole('img', { name: '本题原题题面图' })).toHaveAttribute('src', imageUrl)
    expect(vi.mocked(accessApi).mock.calls[0]).toEqual(vi.mocked(accessApi).mock.calls[1])
    expect(submitJuniorAdaptiveStep).not.toHaveBeenCalled()
  })

  it.each([{ sha256: '0'.repeat(64) }, { width: 236 }, { height: 326 }, { dataUrl: 'https://untrusted.invalid/crop.png' }])(
    'rejects a returned image that differs from the sealed auxiliary descriptor: %j', async (changed) => {
      vi.mocked(accessApi).mockResolvedValue({ asset: { ...mediaResult.asset, ...changed } })
      renderSession()
      expect(await screen.findByText('原题图片完整性校验未通过，请重试或联系甘老师。')).toBeVisible()
      expect(screen.queryByRole('img', { name: '本题原题题面图' })).not.toBeInTheDocument()
      chooseD(); expect(screen.getByRole('button', { name: '提交答案' })).toBeEnabled()
      expect(submitJuniorAdaptiveStep).not.toHaveBeenCalled()
    })

  it.each(['辅助原图的作答上下文已变化，请重新打开练习。', '辅助原图不属于当前账号的作答。'])(
    'shows a version/ownership server denial without substituting another image: %s', async (message) => {
      vi.mocked(accessApi).mockRejectedValue(new Error(message))
      renderSession()
      expect(await screen.findByText(message)).toBeVisible()
      expect(screen.queryByRole('img', { name: '本题原题题面图' })).not.toBeInTheDocument()
      expect(screen.getByRole('heading', { name: originalQuestion.stem })).toBeVisible()
      expect(accessApi).toHaveBeenCalledTimes(1)
    })

  it('opens the exact loaded image in zoom and closes it without another fetch or answer write', async () => {
    renderSession()
    const image = await screen.findByRole('img', { name: '本题原题题面图' })
    fireEvent.click(image.closest('button')!)
    expect(await screen.findByRole('img', { name: '放大查看：本题原题题面图' })).toHaveAttribute('src', imageUrl)
    fireEvent.click(screen.getByRole('button', { name: '关闭原题大图' }))
    expect(accessApi).toHaveBeenCalledTimes(1)
    expect(submitJuniorAdaptiveStep).not.toHaveBeenCalled()
  })

  it('restores a mounted practice step with the same auxiliary authorization context', async () => {
    const first = renderSession()
    await screen.findByRole('img', { name: '本题原题题面图' })
    const request = structuredClone(vi.mocked(accessApi).mock.calls[0])
    first.unmount(); renderSession()
    await screen.findByRole('img', { name: '本题原题题面图' })
    expect(vi.mocked(accessApi).mock.calls[1]).toEqual(request)
    expect(originalQuestion.assetRefs).toEqual([])
    expect(originalQuestion.revisionToken).toBe(revision)
    expect(submitJuniorAdaptiveStep).not.toHaveBeenCalled()
  })

  it('routes existing primary images to the old route and retains the original submit gate', async () => {
    let resolve!: (value: typeof mediaResult) => void
    vi.mocked(accessApi).mockImplementationOnce(() => new Promise((accept) => { resolve = accept }))
    const primary = { ...originalQuestion, renderMode: 'image_primary' as const, auxiliaryAssetRefs: [],
      assetRefs: [{ ...auxiliary, assetId: 'reviewed/source_primary_J022_unit' }] }
    renderSession(primary)
    chooseD(); expect(screen.getByRole('button', { name: '提交答案' })).toBeDisabled()
    expect(vi.mocked(accessApi).mock.calls[0][1]).toBe('junior_question_asset')
    await act(async () => resolve(mediaResult))
    await screen.findByRole('img', { name: '本题原题题面图' })
    await waitFor(() => expect(screen.getByRole('button', { name: '提交答案' })).toBeEnabled())
    expect(accessApi).not.toHaveBeenCalledWith(expect.anything(), 'junior_auxiliary_asset', expect.anything())
  })

  it('keeps original primary-image submission blocked after an image hash mismatch', async () => {
    vi.mocked(accessApi).mockResolvedValue({ asset: { ...mediaResult.asset, sha256: '0'.repeat(64) } })
    renderSession({ ...originalQuestion, renderMode: 'image_primary', auxiliaryAssetRefs: [], assetRefs: [auxiliary] })
    chooseD()
    expect(await screen.findByText('原题图片完整性校验未通过，请重试或联系甘老师。')).toBeVisible()
    expect(screen.getByRole('button', { name: '提交答案' })).toBeDisabled()
    expect(submitJuniorAdaptiveStep).not.toHaveBeenCalled()
  })
})
