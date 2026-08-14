import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { SessionIdentity, VideoRecommendation } from '../domain/types'
import { safeExternalVideoUrl, videoProgressView } from '../domain/videoLearning'
import { GuardianVideoSection, StudentVideoSection } from './VideoLearning'

const session: SessionIdentity = {
  role: 'student',
  token: 'student-token',
  displayName: '测试同学',
  expiresAt: '2026-08-15T00:00:00.000Z',
}

const video = (overrides: Partial<VideoRecommendation> = {}): VideoRecommendation => ({
  id: 'video-1',
  studentId: 'student-1',
  skillId: 'H1_PERIODIC',
  skillTitle: '元素周期律',
  title: '最高价氧化物对应水化物的酸碱性',
  provider: '甘老师录屏',
  url: 'https://example.com/periodic-law',
  teacherReason: '这条讲解把同周期的碱性、两性和酸性趋势连成一条线。',
  status: 'published',
  publishedAt: '2026-08-14T08:00:00.000Z',
  progress: {
    openedAt: null,
    lastEngagedAt: null,
    progressSeconds: 0,
    durationSeconds: null,
    completionPercent: null,
    completedAt: null,
    trackingMethod: null,
    eventCount: 0,
  },
  ...overrides,
})

describe('video learning presentation', () => {
  afterEach(cleanup)

  it('accepts only complete HTTPS links for external video opening', () => {
    expect(safeExternalVideoUrl('https://example.com/video')).toBe('https://example.com/video')
    expect(safeExternalVideoUrl('http://example.com/video')).toBeNull()
    expect(safeExternalVideoUrl('javascript:alert(1)')).toBeNull()
    expect(safeExternalVideoUrl('not-a-url')).toBeNull()
  })

  it('does not present a link-open event as completed learning', () => {
    const opened = video({ progress: { ...video().progress, openedAt: '2026-08-14T09:00:00.000Z', trackingMethod: 'link_open_only' } })
    expect(videoProgressView(opened)).toMatchObject({ label: '已打开', percent: 0 })
    expect(videoProgressView(opened).detail).toContain('不能据此判断已经看完')
  })

  it('lets a student report the minute reached without inventing a total duration', async () => {
    const onRecord = vi.fn().mockResolvedValue({ ok: true })
    render(<StudentVideoSection session={session} videos={[video()]} onRecord={onRecord} />)

    fireEvent.change(screen.getByRole('spinbutton'), { target: { value: '7.5' } })
    fireEvent.click(screen.getByRole('button', { name: '保存位置' }))

    await waitFor(() => expect(onRecord).toHaveBeenCalledWith({
      recommendationId: 'video-1',
      event: 'progress',
      progressSeconds: 450,
      trackingMethod: 'self_reported',
    }))
    expect(await screen.findByText('观看位置已保存，下次可以从这里接着看。')).toBeInTheDocument()
  })

  it('tells guardians exactly what the teacher and system each do', () => {
    const opened = video({ progress: { ...video().progress, openedAt: '2026-08-14T09:00:00.000Z', lastEngagedAt: '2026-08-14T09:00:00.000Z', trackingMethod: 'link_open_only' } })
    render(<GuardianVideoSection videos={[opened]} />)

    expect(screen.getByText(/讲解由甘老师依据课堂进度和复习规则安排/)).toBeInTheDocument()
    expect(screen.getByText(/系统负责辅助推送与记录/)).toBeInTheDocument()
    expect(screen.getByText(/不会把打开链接当成已经掌握/)).toBeInTheDocument()
    expect(screen.getByText('已打开')).toBeInTheDocument()
  })
})
