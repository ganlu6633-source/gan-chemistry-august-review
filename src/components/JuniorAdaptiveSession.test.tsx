import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { IssuedJuniorQuestion, JuniorAdaptivePayload, JuniorQuestionFeedback, KnowledgeCard, LearningPlanDay, SessionIdentity } from '../domain/types'
import { JuniorAdaptiveSession } from './JuniorAdaptiveSession'

const session: SessionIdentity = { role: 'student', token: 'junior-session', displayName: '初三学生', expiresAt: '2099-01-01T00:00:00Z' }

const plan: LearningPlanDay = {
  id: 'junior-plan', studentId: 'student-junior', date: '2026-08-29', mode: 'REVIEW', title: '今日初中自适应学习',
  skillIds: ['J3_MASS_CONSERVATION'], knowledgeSummaries: ['质量守恒定律'], estimatedMinutes: 20, source: 'course', isScheduled: true,
  attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 12, roundLimit: 1,
  maxQuestionLevel: 2, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'active', hardQuestionCap: 15,
  isResolved: false, isComplete: false, roundsRemaining: 1,
}

const card: KnowledgeCard = {
  id: 'junior-card', skillId: 'J3_MASS_CONSERVATION', title: '质量守恒定律', core: '化学反应前后原子的种类、数目和质量不变。',
  detail: '先确认发生了化学反应，再比较反应前后。', steps: ['确认反应', '逐项比较'], commonMistakes: ['物质种类可以改变。'],
  microExample: '反应前后总质量相等。', reviewStatus: 'approved',
}

function question(revisionLabel: string, stem: string): IssuedJuniorQuestion {
  return {
    skillId: 'J3_MASS_CONSERVATION', level: 1, gradeBand: '初三', stem,
    options: ['原子种类和数目不变', '物质种类完全不变', '原子总数增加', '原子质量变小'], revisionToken: `revision-${revisionLabel}`,
  }
}

function payload(currentQuestion: IssuedJuniorQuestion | null, answeredCount = 0): JuniorAdaptivePayload {
  return {
    deliveryMode: 'junior_adaptive', plan, cards: [card],
    session: { id: 'adaptive-session', status: currentQuestion ? 'active' : 'completed', initialQuestionTarget: 12, hardQuestionCap: 15, issuedCount: answeredCount + (currentQuestion ? 1 : 0), answeredCount, correctCount: answeredCount },
    currentStepId: currentQuestion ? `step-${answeredCount + 1}` : undefined,
    currentQuestion,
    completed: currentQuestion === null,
  }
}

const feedback: JuniorQuestionFeedback = {
  stepId: 'step-1', selectedOption: 0, correct: true, correctOption: 0, uncertain: false, durationSec: 4,
  explanation: 'A. 化学反应前后原子的种类和数目不变。\nB. 物质种类可以发生改变。', analysisAssetRefs: [],
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function deferredResponse() {
  let resolve!: (response: Response) => void
  const promise = new Promise<Response>((accept) => { resolve = accept })
  return { promise, resolve }
}

describe('JuniorAdaptiveSession keyboard and safe exit UX', () => {
  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it.each([false, true])('shows the reviewed question image and blocks premature answer submission (preview=%s)', async (preview) => {
    const imageResponse = deferredResponse()
    const imageQuestion = { ...question('image', '题目文字稿'), mediaId: 'opaque-issued-step', renderMode: 'image_primary' as const,
      assetRefs: [{ kind: 'question_image' as const, assetId: 'reviewed/source_question_001', alt: '完整原题',
        sha256: '2'.repeat(64), width: 2, height: 2 }] }
    const fetchMock = vi.fn<typeof fetch>().mockReturnValueOnce(imageResponse.promise)
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: null, continuation: { status: 'unavailable' } }))
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={preview ? { ...session, role: 'teacher' } : session}
      previewStudentId={preview ? 'selected-junior-student' : undefined}
      initialPayload={payload(imageQuestion)} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    expect(screen.getByRole('button', { name: '提交答案' })).toBeDisabled()
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
    expect(request.action).toBe('junior_question_asset')
    expect(request.data.questionId).toBe('opaque-issued-step')
    expect(request.data.phase).toBe('question')
    expect(request.data.studentId).toBe(preview ? 'selected-junior-student' : undefined)
    await act(async () => imageResponse.resolve(jsonResponse({ asset: { kind: 'question_image', mimeType: 'image/png',
      sha256: '2'.repeat(64), width: 2, height: 2,
      dataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVQImWP8////fwYGBgYmBiAFAAA7AAO8f2YuAAAAAElFTkSuQmCC' } })))
    expect(await screen.findByRole('img', { name: '本题原题题面图' })).toBeVisible()
    expect(screen.queryByRole('heading', { name: '题目文字稿' })).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: '提交答案' })).toBeEnabled())
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeVisible()
    expect(screen.getByText('物质种类可以发生改变。')).toBeVisible()
    const submitted = JSON.parse(String(fetchMock.mock.calls[1][1]?.body))
    expect(submitted.action).toBe(preview ? 'preview_junior_submit_step' : 'junior_submit_step')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('keeps the question blocked when the returned image does not match the reviewed asset', async () => {
    vi.stubGlobal('fetch', vi.fn<typeof fetch>().mockResolvedValue(jsonResponse({ asset: {
      kind: 'question_image', mimeType: 'image/png', dataUrl: 'data:image/png;base64,AAAA',
      sha256: '3'.repeat(64), width: 2, height: 2,
    } })))
    render(<JuniorAdaptiveSession session={session} initialPayload={payload({ ...question('image', '题目文字稿'),
      mediaId: 'opaque-issued-step', renderMode: 'image_primary', assetRefs: [{ kind: 'question_image',
        assetId: 'reviewed/source_question_001', alt: '完整原题', sha256: '2'.repeat(64), width: 2, height: 2 }] })}
      onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    expect(await screen.findByText('原题图片完整性校验未通过，请重试或联系甘老师。')).toBeVisible()
    expect(screen.getByRole('button', { name: '提交答案' })).toBeDisabled()
    expect(screen.queryByText('回答正确')).not.toBeInTheDocument()
  })

  it('reveals only confirmed feedback immediately while the next original is still preparing', async () => {
    const confirm = deferredResponse()
    const continuation = deferredResponse()
    const fetchMock = vi.fn<typeof fetch>().mockReturnValueOnce(confirm.promise).mockReturnValueOnce(continuation.promise)
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('first', '先看第一题'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(screen.getByRole('button', { name: '正在提交答案…' }))
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(screen.queryByText('回答正确')).not.toBeInTheDocument()
    expect(screen.queryByText('物质种类可以发生改变。')).not.toBeInTheDocument()
    await act(async () => confirm.resolve(jsonResponse({ feedback, payload: null, continuation: { status: 'pending' } })))
    expect(screen.getByText('回答正确')).toBeVisible()
    expect(screen.getByText('物质种类可以发生改变。')).toBeVisible()
    expect(screen.getByRole('button', { name: '稍后继续 / 返回计划' })).toBeEnabled()
    expect(screen.getByRole('button', { name: '下一题（准备中…）' })).toBeEnabled()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).data.feedbackOnly).toBe(true)
    expect(JSON.parse(String(fetchMock.mock.calls[1][1]?.body)).data.feedbackOnly).toBe(false)
    await act(async () => continuation.resolve(jsonResponse({ feedback, payload: payload(question('second', '后台准备好了'), 1) })))
    expect(screen.getByRole('button', { name: '下一题' })).toBeEnabled()
    expect(screen.getByRole('heading', { name: '先看第一题' })).toBeVisible()
    expect(screen.queryByRole('heading', { name: '后台准备好了' })).not.toBeInTheDocument()
  })

  it('queues one next click during preparation and advances exactly once when ready', async () => {
    const continuation = deferredResponse()
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: null, continuation: { status: 'pending' } }))
      .mockReturnValueOnce(continuation.promise)
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('first', '第一题'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(await screen.findByRole('button', { name: '下一题（准备中…）' }))
    const queued = screen.getByRole('button', { name: '正在打开下一题…' })
    expect(queued).toBeDisabled()
    fireEvent.click(queued)
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    await act(async () => continuation.resolve(jsonResponse({ feedback, payload: payload(question('second', '只前进到第二题'), 1) })))
    expect(screen.getByRole('heading', { name: '只前进到第二题' })).toBeVisible()
    expect(screen.queryByText('回答正确')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: '提交答案' })).toBeDisabled()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it.each([false, true])('keeps the completed dashboard with a queued final next click (preview=%s)', async (preview) => {
    const continuation = deferredResponse()
    const nextDashboard = {
      profile: { id: plan.studentId, displayName: '学生', gradeBand: '初三', enrollmentStartDate: plan.date, needsInitialDiagnostic: false },
      plans: [plan], skillStates: [], skillDefinitions: [], todayQuestionCount: 8, achievements: [],
    }
    const onComplete = vi.fn()
    const onExit = vi.fn()
    vi.stubGlobal('fetch', vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: null, continuation: { status: 'pending' } }))
      .mockReturnValueOnce(continuation.promise))
    render(<JuniorAdaptiveSession session={preview ? { ...session, role: 'teacher' } : session}
      previewStudentId={preview ? plan.studentId : undefined} initialPayload={payload(question('last', '最后一题'), 7)} onExit={onExit} onComplete={onComplete} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(await screen.findByRole('button', { name: '下一题（准备中…）' }))
    await act(async () => continuation.resolve(jsonResponse({ feedback, payload: payload(null, 8), dashboard: nextDashboard })))
    fireEvent.click(screen.getByRole('button', { name: '查看今日成果' }))
    expect(onComplete).toHaveBeenCalledTimes(1)
    expect(onComplete.mock.calls[0][0]).toMatchObject(preview
      ? { plans: [{ id: plan.id, isComplete: true, attemptCount: 1, latestScore: 8 }] }
      : nextDashboard)
    expect(onExit).not.toHaveBeenCalled()
  })

  it('passes only a confirmed completed payload to the exit fallback when the dashboard is unavailable', async () => {
    const onExit = vi.fn()
    const onComplete = vi.fn()
    const complete = payload(null, 8)
    vi.stubGlobal('fetch', vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: null, continuation: { status: 'pending' } }))
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: complete })))
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('last', '最后一题'), 7)} onExit={onExit} onComplete={onComplete} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(await screen.findByRole('button', { name: '完成今天学习' }))
    fireEvent.click(screen.getByRole('button', { name: '查看今日成果' }))
    expect(onExit).toHaveBeenCalledTimes(1)
    expect(onExit).toHaveBeenCalledWith(complete)
    expect(onComplete).not.toHaveBeenCalled()
  })

  it('keeps feedback after background failure and retries the confirmed answer without another first-stage submit', async () => {
    const confirmed = { ...feedback, selectedOption: 1, correct: false, durationSec: 9, uncertain: true, revisionToken: 'revision-first' }
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback: confirmed, payload: null, continuation: { status: 'pending' } }))
      .mockRejectedValueOnce(new Error('slow next failed'))
      .mockResolvedValueOnce(jsonResponse({ feedback: confirmed, payload: payload(question('next', '重试后的下一题'), 1) }))
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('first', '已保存这道题'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /B\. 物质种类完全不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('答案已保存，解析仍可查看')
    expect(screen.getByText('回答错误，正确选项是 A')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: '重试获取下一题' }))
    expect(await screen.findByRole('button', { name: '下一题' })).toBeEnabled()
    for(const call of fetchMock.mock.calls.slice(1)) expect(JSON.parse(String(call[1]?.body))).toMatchObject({
      action: 'junior_submit_step', data: { stepId: 'step-1', selectedOption: 1, durationSec: 9, uncertain: true, revisionToken: 'revision-first', feedbackOnly: false },
    })
  })

  it('aborts continuation on exit and ignores a late next response even before the parent unmounts', async () => {
    const continuation = deferredResponse()
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: null, continuation: { status: 'pending' } }))
      .mockReturnValueOnce(continuation.promise)
    vi.stubGlobal('fetch', fetchMock)
    const onExit = vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('first', '离开前的题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    fireEvent.click(await screen.findByRole('button', { name: '下一题（准备中…）' }))
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)
    expect(onExit).toHaveBeenCalledWith()
    expect(fetchMock.mock.calls[1][1]?.signal?.aborted).toBe(true)
    await act(async () => continuation.resolve(jsonResponse({ feedback, payload: payload(question('late', '不应覆盖离开的界面'), 1) })))
    expect(screen.queryByRole('heading', { name: '不应覆盖离开的界面' })).not.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('uses identical replay-only preview transcripts for both feedback and preparation', async () => {
    const continuation = deferredResponse()
    const teacher: SessionIdentity = { ...session, role: 'teacher' }
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: null, continuation: { status: 'pending' }, simulated: true }))
      .mockReturnValueOnce(continuation.promise)
    vi.stubGlobal('fetch', fetchMock)
    const view = render(<JuniorAdaptiveSession session={teacher} previewStudentId="preview-child"
      initialPayload={payload(question('first', '老师模拟第一题'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeVisible()
    const requests=fetchMock.mock.calls.map(call=>JSON.parse(String(call[1]?.body)))
    expect(requests.map(r=>r.action)).toEqual(['preview_junior_submit_step','preview_junior_submit_step'])
    expect(requests.map(r=>r.data.feedbackOnly)).toEqual([true,false])
    expect(requests[0].data.answers).toEqual(requests[1].data.answers)
    expect(requests[1].data).toMatchObject({studentId:'preview-child',planId:'junior-plan'})
    view.unmount()
    expect(fetchMock.mock.calls[1][1]?.signal?.aborted).toBe(true)
    await act(async()=>continuation.resolve(jsonResponse({feedback,payload:payload(null,8)})))
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('pins the first submitted fields after a network failure and never reveals an unconfirmed answer', async () => {
    const fetchMock=vi.fn<typeof fetch>().mockRejectedValueOnce(new Error('connection lost'))
      .mockResolvedValueOnce(jsonResponse({feedback,payload:payload(question('next','安全重试后的下一题'),1)}))
    vi.stubGlobal('fetch',fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('first','首个请求断网'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button',{name:/A\. 原子种类和数目不变/}))
    fireEvent.click(screen.getByRole('button',{name:'提交答案'}))
    expect(await screen.findByRole('alert')).toHaveTextContent('connection lost')
    expect(screen.queryByText('回答正确')).not.toBeInTheDocument()
    const b=screen.getByRole('button',{name:/B\. 物质种类完全不变/})
    expect(b).toBeDisabled()
    fireEvent.click(b)
    fireEvent.click(screen.getByRole('button',{name:'提交答案'}))
    expect(await screen.findByText('回答正确')).toBeVisible()
    expect(JSON.parse(String(fetchMock.mock.calls[1][1]?.body))).toEqual(JSON.parse(String(fetchMock.mock.calls[0][1]?.body)))
  })

  it('labels a real due review without describing an unseen question as review', () => {
    const current = { ...question('due', '复习质量守恒'), learningPurpose: 'spaced_review' as const, lastAnsweredDate: '2026-09-20' }
    const view = render(<JuniorAdaptiveSession session={session} initialPayload={payload(current)} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByText('到期复习 · 上次练习 2026-09-20')).toBeInTheDocument()
    view.unmount()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload({ ...question('fresh', '第一次练习'), learningPurpose: 'new_learning' })} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.queryByText(/到期复习/)).not.toBeInTheDocument()
  })

  it('keeps coefficient/formula spans inside the option text so they cannot become letter badges or separate flex columns', () => {
    const current = question('formula', '选择配平正确的制氧方程式')
    current.options = ['2H₂O₂ = 2H₂O＋O₂↑（条件：MnO₂）', 'H₂O₂ = H₂O＋O₂↑', '2KMnO₄ = K₂MnO₄＋MnO₂＋O₂↑（条件：加热）', '2H']
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(current)} onExit={vi.fn()} onComplete={vi.fn()} />)
    const option = screen.getByRole('button', { name: `A. ${current.options[0]}` })
    expect(option.querySelector(':scope > .chem-symbol')).toBeNull()
    expect(option.querySelector('.junior-option-copy')).toHaveTextContent(current.options[0])
    expect(option.querySelector('.junior-option-copy .chem-symbol')).not.toBeNull()
    expect(option.querySelectorAll(':scope > span')).toHaveLength(1)
  })

  it('preserves separate experiment rows in a multiline question at a readable text size', () => {
    const current = question('table-rows', '比较下列实验记录。\n5%溶液：50 ℃无明显气泡；70 ℃极少量气泡。\n15%溶液：50 ℃无明显气泡；70 ℃较多气泡。\n分析正确的是')
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(current)} onExit={vi.fn()} onComplete={vi.fn()} />)
    const heading = screen.getByRole('heading', { name: /比较下列实验记录/ })
    expect(heading.textContent).toBe(current.stem)
    expect(heading).toHaveStyle({ whiteSpace: 'pre-line', fontSize: 'clamp(18px, 2.5vw, 23px)', lineHeight: '1.65' })
  })

  it('reviews the actual weak knowledge before each new recovery round without changing answers', () => {
    const current = question('repair-1', '用另一道原题检验质量守恒')
    current.optionPractice = { anchorStepId: 'first-error', optionIndex: 1, knowledgePoint: '原子数守恒', position: 1, total: 3, recoveryRound: 1 }
    const initial = payload(current, 8)
    initial.session = { ...initial.session, initialQuestionTarget: 8, hardQuestionCap: 30, recoveryRoundLimit: 3 }
    initial.cards = [{ ...card, structuredContent: { version: 1, intro: '分清每一个小点', sections: [{ title: '守恒', items: [
      { label: '原子数守恒', rule: '每种原子的数目守恒。', examples: ['左边4个氢原子，右边也有4个。'] },
      { label: '物质种类', rule: '反应后物质种类改变。', examples: ['新物质有新的性质。'] },
    ] }] } }]
    initial.optionPractice = [{ anchorStepId: 'first-error', optionIndex: 1, knowledgePoint: '原子数守恒', skillId: card.skillId,
      status: 'practicing', answered: 0, correct: 0, total: 3, pendingReason: '', recoveryRound: 1 }]
    render(<JuniorAdaptiveSession session={session} initialPayload={initial} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByText('第 1 轮补练前，先把错点理一理')).toBeVisible()
    expect(screen.getByText('每种原子的数目守恒。')).toBeVisible()
    expect(screen.getByText('左边4个氢原子，右边也有4个。')).toBeVisible()
    expect(screen.getByTestId('junior-micro-review')).not.toHaveTextContent('物质种类改变')
    expect(screen.getByTestId('junior-micro-review')).not.toHaveTextContent(card.microExample)
    expect(screen.getByText('还想看相关知识？展开完整知识树').closest('details')).not.toHaveAttribute('open')
    expect(screen.queryByRole('heading', { name: '用另一道原题检验质量守恒' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '开始第 1 轮补练' }))
    expect(screen.getByRole('heading', { name: '用另一道原题检验质量守恒' })).toBeVisible()
    expect(screen.getByText('第 1 轮错点补练')).toBeVisible()
    expect(screen.getByText(/每天合计不超过 30 题/)).toBeVisible()
  })

  it('reviews another weak option separately when the branch changes within the same round', async () => {
    const first = question('one', '第一小点的补练题')
    first.optionPractice = { anchorStepId: 'first-error', optionIndex: 1, knowledgePoint: '原子数守恒', position: 1, total: 3, recoveryRound: 1 }
    const second = question('two', '第二小点的补练题')
    second.optionPractice = { anchorStepId: 'second-error', optionIndex: 2, knowledgePoint: '原子种类守恒', position: 1, total: 3, recoveryRound: 1 }
    const prepare = (q: IssuedJuniorQuestion, n: number) => {
      const result = payload(q, n)
      result.session = { ...result.session, initialQuestionTarget: 8, hardQuestionCap: 30, recoveryRoundLimit: 3 }
      return result
    }
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ feedback, payload: prepare(second, 11) })))
    render(<JuniorAdaptiveSession session={session} initialPayload={prepare(first, 8)} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: '开始第 1 轮补练' }))
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    await screen.findByText('回答正确')
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByTestId('junior-micro-review')).toHaveTextContent('原子种类守恒')
    expect(screen.queryByRole('heading', { name: second.stem })).not.toBeInTheDocument()
  })

  it('opens the exact micro review and its tree from another course card', () => {
    const current = question('cross-skill', '催化剂实验中的文字表达式')
    current.optionPractice = { anchorStepId: 'cross-error', optionIndex: 1, knowledgePoint: '过氧化氢的文字表达式', position: 1, total: 3, recoveryRound: 1 }
    const initial = payload(current, 8)
    initial.session = { ...initial.session, initialQuestionTarget: 8, hardQuestionCap: 30, recoveryRoundLimit: 3 }
    initial.cards.push({ ...card, id: 'symbols-card', skillId: 'J_KY_OXY_SYMBOLS', title: '制氧文字表达式',
      structuredContent: { version: 1, intro: '符号表达', sections: [{ title: '文字表达式', items: [
        { label: '过氧化氢的文字表达式', rule: '过氧化氢生成水和氧气。', examples: ['二氧化锰写在条件位置。'] },
      ] }] } })
    render(<JuniorAdaptiveSession session={session} initialPayload={initial} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByTestId('junior-micro-review')).toHaveTextContent('过氧化氢生成水和氧气。')
    expect(screen.getByTestId('junior-micro-review')).toHaveTextContent('二氧化锰写在条件位置。')
    fireEvent.click(screen.getByText('还想看相关知识？展开完整知识树'))
    expect(screen.getByRole('button', { name: '制氧文字表达式' })).toBeVisible()
    expect(screen.queryByRole('button', { name: '质量守恒定律' })).not.toBeInTheDocument()
  })

  it('shows unresolved practice on the result at the cap instead of claiming mastery', () => {
    const initial = payload(null, 30)
    initial.session = { ...initial.session, correctCount: 12, initialQuestionTarget: 8, hardQuestionCap: 30, recoveryRoundLimit: 3 }
    initial.optionPractice = [{ anchorStepId: 'unresolved', optionIndex: 1, knowledgePoint: '原子数守恒', status: 'pending',
      answered: 1, correct: 0, total: 3, pendingReason: 'daily_limit_carry_forward', recoveryRound: 3 }]
    render(<JuniorAdaptiveSession session={session} initialPayload={initial} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByText('还有 1 个错项考点待继续练习，进度已经保留。')).toBeVisible()
    expect(screen.getByText(/还没练稳的考点会留在后续复习中/)).toBeVisible()
    expect(screen.queryByText(/已掌握/)).not.toBeInTheDocument()
  })

  it('shows fresh review entrances for rounds two and three using the same choice interaction', async () => {
    const roundPayload = (round: number) => {
      const current = question(`repair-${round}`, `第${round}轮原题`)
      current.optionPractice = { anchorStepId: `error-${round}`, optionIndex: 1, knowledgePoint: '原子数守恒', position: 1, total: 3, recoveryRound: round }
      const result = payload(current, 8 + (round - 1) * 3)
      result.session = { ...result.session, initialQuestionTarget: 8, hardQuestionCap: 30, recoveryRoundLimit: 3 }
      return result
    }
    vi.stubGlobal('fetch', vi.fn()
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: roundPayload(2) }))
      .mockResolvedValueOnce(jsonResponse({ feedback, payload: roundPayload(3) })))
    render(<JuniorAdaptiveSession session={session} initialPayload={roundPayload(1)} onExit={vi.fn()} onComplete={vi.fn()} />)
    for (const round of [1, 2]) {
      fireEvent.click(screen.getByRole('button', { name: `开始第 ${round} 轮补练` }))
      fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
      fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
      await screen.findByText('回答正确')
      fireEvent.click(screen.getByRole('button', { name: '下一题' }))
      expect(screen.getByRole('button', { name: `开始第 ${round + 1} 轮补练` })).toBeVisible()
      expect(screen.queryByRole('heading', { name: `第${round + 1}轮原题` })).not.toBeInTheDocument()
    }
    fireEvent.click(screen.getByRole('button', { name: '开始第 3 轮补练' }))
    expect(screen.getByRole('heading', { name: '第3轮原题' })).toBeVisible()
  })

  it('keeps the junior knowledge tree folded above the question until the student chooses to explore it', () => {
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题：质量守恒的微观原因是什么？'))} onExit={vi.fn()} onComplete={vi.fn()} />)

    const disclosure = screen.getByText('拆开看知识点').closest('details')
    expect(disclosure).not.toHaveAttribute('open')
    expect(screen.getByRole('heading', { name: '第一题：质量守恒的微观原因是什么？' })).toBeInTheDocument()

    fireEvent.click(screen.getByText('拆开看知识点'))
    expect(disclosure).toHaveAttribute('open')
    const root = screen.getByRole('button', { name: '质量守恒定律' })
    fireEvent.click(root)
    expect(screen.getByText('化学反应前后原子的种类、数目和质量不变。')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '范例' }))
    expect(screen.getByText('反应前后总质量相等。')).toBeInTheDocument()
  })

  it('submits and advances with Enter while keeping the answered choice immutable after feedback', async () => {
    const nextPayload = payload(question('question-2', '第二题：反应前后哪一项保持不变？'), 1)
    const fetchMock = vi.fn(async () => jsonResponse({ feedback, payload: nextPayload }))
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题：质量守恒的微观原因是什么？'))} onExit={vi.fn()} onComplete={vi.fn()} />)

    expect(screen.getByRole('button', { name: '稍后继续 / 返回计划' })).toBeVisible()
    const submitButton = screen.getByRole('button', { name: '提交答案' })
    expect(submitButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    expect(submitButton).toBeDisabled()
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(fetchMock).not.toHaveBeenCalled()

    const firstOption = screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })
    const secondOption = screen.getByRole('button', { name: /B\. 物质种类完全不变/ })
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    fireEvent.click(firstOption)
    fireEvent.keyDown(window, { key: 'Enter' })

    expect(await screen.findByText('回答正确')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(firstOption).toBeDisabled()
    expect(secondOption).toBeDisabled()
    secondOption.click()
    expect(firstOption).toHaveClass('selected')
    expect(secondOption).not.toHaveClass('selected')

    const nextButton = screen.getByRole('button', { name: /下一题/ })
    expect(nextButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    expect(await screen.findByRole('heading', { name: '第二题：反应前后哪一项保持不变？' })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('uses the same junior question and feedback UI while teacher answers stay in a replay-only request', async () => {
    const teacher: SessionIdentity = { ...session, role: 'teacher', token: 'teacher-session' }
    const nextPayload = payload(question('question-2', '下一道原题'), 1)
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => {
      void _input
      void _init
      return jsonResponse({ feedback, payload: nextPayload, simulated: true })
    })
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={teacher} initialPayload={payload(question('question-1', '第一道原题'))}
      previewStudentId="student-junior" onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByRole('heading', { name: '第一道原题' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeInTheDocument()
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body))
    expect(request).toMatchObject({ action: 'preview_junior_submit_step', data: {
      studentId: 'student-junior', planId: 'junior-plan', answers: [{ stepId: 'step-1', selectedOption: 0, revisionToken: 'revision-question-1' }],
    } })
    expect(fetchMock.mock.calls.some((call) => JSON.parse(String(call[1]?.body)).action === 'junior_submit_step')).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByRole('heading', { name: '下一道原题' })).toBeInTheDocument()
  })

  it('submits only the selected option with uncertain false and labels a wrong answer explicitly', async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => {
      void _input
      void _init
      return jsonResponse({ feedback: { ...feedback, selectedOption: 1, correct: false, uncertain: true },
        payload: payload(question('question-2', '下一道练习'), 1) })
    })
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '当前题'))} onExit={vi.fn()} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /B\. 物质种类完全不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答错误，正确选项是 A')).toBeInTheDocument()
    const init = fetchMock.mock.calls[0][1] as RequestInit
    expect(JSON.parse(String(init.body))).toMatchObject({ action: 'junior_submit_step', data: {
      selectedOption: 1, uncertain: false, stepId: 'step-1', revisionToken: 'revision-question-1',
    } })
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(screen.queryByText(/已掌握|提高难度/)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByRole('heading', { name: '下一道练习' })).toBeInTheDocument()
  })

  it('leaves Enter on a focused answer button to native keyboard selection without submitting the old choice', () => {
    const fetchMock = vi.fn(async () => jsonResponse({ feedback, payload: payload(null, 12) }))
    vi.stubGlobal('fetch', fetchMock)
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题'))} onExit={vi.fn()} onComplete={vi.fn()} />)

    const firstOption = screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })
    const secondOption = screen.getByRole('button', { name: /B\. 物质种类完全不变/ })
    fireEvent.click(firstOption)
    secondOption.focus()

    expect(fireEvent.keyDown(secondOption, { key: 'Enter' })).toBe(true)
    // jsdom does not synthesize the browser's native button click from Enter,
    // so model that default action after proving the global shortcut did not
    // cancel it or submit the previously selected answer.
    fireEvent.click(secondOption)

    expect(secondOption).toHaveClass('selected')
    expect(firstOption).not.toHaveClass('selected')
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('keeps the committed feedback visible and retries only the locked answer when the next question fails', async () => {
    const lockedFeedback = { ...feedback, selectedOption: 1, correct: false, uncertain: true, durationSec: 7, revisionToken: 'revision-question-1' }
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ feedback: lockedFeedback, payload: null, continuation: { status: 'unavailable', message: '本题答案已保存，下一题暂不可用。' } }))
      .mockRejectedValueOnce(new Error('network unavailable'))
      .mockResolvedValueOnce(jsonResponse({ feedback: lockedFeedback, payload: payload(question('question-2', '恢复后的下一题'), 1), replayed: true }))
    vi.stubGlobal('fetch', fetchMock)
    const onExit = vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '当前题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /B\. 物质种类完全不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答错误，正确选项是 A')).toBeVisible()
    expect(screen.getByText('物质种类可以发生改变。')).toBeVisible()
    expect(screen.getByRole('alert')).toHaveTextContent('本题答案已保存')
    expect(screen.getByRole('button', { name: /B\. 物质种类完全不变/ })).toBeDisabled()
    expect(screen.getByRole('button', { name: '重试获取下一题' })).toBeEnabled()

    fireEvent.click(screen.getByRole('button', { name: '重试获取下一题' }))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('解析仍可查看'))
    expect(screen.getByText('回答错误，正确选项是 A')).toBeVisible()
    expect(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: '重试获取下一题' }))
    expect(await screen.findByRole('button', { name: '下一题' })).toBeEnabled()
    for (const call of fetchMock.mock.calls.slice(1)) {
      expect(JSON.parse(String(call[1]?.body))).toMatchObject({ action: 'junior_submit_step', data: {
        stepId: 'step-1', selectedOption: 1, revisionToken: 'revision-question-1', uncertain: true, durationSec: 7,
      } })
    }
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: '下一题' }))
    expect(screen.getByRole('heading', { name: '恢复后的下一题' })).toBeVisible()
    expect(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ })).toBeEnabled()
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)
  })

  it('allows returning to the plan while the saved feedback is available but the next question is not', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ feedback, payload: null })))
    const onExit = vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '当前题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /A\. 原子种类和数目不变/ }))
    fireEvent.click(screen.getByRole('button', { name: '提交答案' }))
    expect(await screen.findByText('回答正确')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)
  })

  it('shows an exact-option reserve in the same four-option UI and keeps a daily-limit carry visible', () => {
    const current = question('reserve-2', '具体考点补练')
    current.optionPractice = { anchorStepId: 'opaque-first-step', optionIndex: 1, knowledgePoint: '源头减污', position: 2, total: 4 }
    const initial = payload(current, 14)
    initial.optionPractice = [{ anchorStepId: 'another-opaque-step', optionIndex: 2, knowledgePoint: '物质组成', status: 'pending', answered: 1, correct: 1, total: 3, pendingReason: 'daily_limit_carry_forward' }]
    render(<JuniorAdaptiveSession session={session} initialPayload={initial} onExit={vi.fn()} onComplete={vi.fn()} />)
    expect(screen.getByText('源头减污 · 第 2/4 题')).toBeVisible()
    expect(screen.getByText('有 1 个错项考点的后续补练待准备或待续，进度已经保留。')).toBeVisible()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    for (const label of ['A.','B.','C.','D.']) expect(screen.getByRole('button',{name:new RegExp(`^${label}`)})).toBeEnabled()
    expect(screen.queryByText(/已掌握|需帮助/)).not.toBeInTheDocument()
  })

  it('preserves feedback and offers the plan when the honest reserve gap leaves no next question', async () => {
    const gap = { ...payload(null, 4), completed: false, session: { ...payload(null,4).session, status: 'active' as const }, pendingMessage: '已保留你的答题和补练进度，后续题目正在准备。' }
    vi.stubGlobal('fetch',vi.fn(async()=>jsonResponse({feedback,payload:gap})))
    const onExit=vi.fn()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1','当前题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button',{name:/A\. 原子种类和数目不变/}))
    fireEvent.click(screen.getByRole('button',{name:'提交答案'}))
    expect(await screen.findByText('回答正确')).toBeVisible()
    expect(screen.getByRole('alert')).toHaveTextContent('后续题目正在准备')
    fireEvent.click(screen.getByRole('button',{name:'返回学习计划'}))
    expect(onExit).toHaveBeenCalledTimes(1)
  })

  it('offers a visible non-destructive return action and supports Enter on the completed result', async () => {
    const onExit = vi.fn()
    const view = render(<JuniorAdaptiveSession session={session} initialPayload={payload(question('question-1', '第一题'))} onExit={onExit} onComplete={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: '稍后继续 / 返回计划' }))
    expect(onExit).toHaveBeenCalledTimes(1)

    view.unmount()
    render(<JuniorAdaptiveSession session={session} initialPayload={payload(null, 12)} onExit={onExit} onComplete={vi.fn()} />)
    const resultButton = screen.getByRole('button', { name: /查看今日成果/ })
    expect(resultButton).toHaveAttribute('aria-keyshortcuts', 'Enter')
    fireEvent.keyDown(window, { key: 'Enter' })
    await waitFor(() => expect(onExit).toHaveBeenCalledTimes(2))
  })
})
