import type { VideoRecommendation, VideoRecommendationProgress } from './types'

export const EMPTY_VIDEO_PROGRESS: VideoRecommendationProgress = {
  openedAt: null,
  lastEngagedAt: null,
  progressSeconds: 0,
  durationSeconds: null,
  completionPercent: null,
  completedAt: null,
  trackingMethod: null,
  eventCount: 0,
}

export const getVideoProgress = (video: VideoRecommendation) => video.progress ?? EMPTY_VIDEO_PROGRESS

const clampPercent = (value: number | null | undefined) => Math.max(0, Math.min(100, typeof value === 'number' && Number.isFinite(value) ? value : 0))

export function safeExternalVideoUrl(value: string) {
  try {
    const parsed = new URL(value)
    return parsed.protocol === 'https:' ? parsed.toString() : null
  } catch {
    return null
  }
}

export function formatVideoDuration(seconds: number) {
  const safeSeconds = Math.max(0, Math.round(seconds))
  const minutes = Math.floor(safeSeconds / 60)
  const remainder = safeSeconds % 60
  if (!minutes) return `${remainder}秒`
  return remainder ? `${minutes}分${remainder}秒` : `${minutes}分钟`
}

export function videoProgressView(video: VideoRecommendation) {
  const progress = getVideoProgress(video)
  if (progress.completedAt) return { tone: 'complete', label: '已反馈看完', detail: '这是一条完成反馈，甘老师可以复核后续掌握情况。', percent: 100 }
  if (progress.progressSeconds > 0) {
    const percent = clampPercent(progress.completionPercent)
    return {
      tone: 'progress',
      label: percent > 0 ? `已看到约 ${Math.round(percent)}%` : `已看到约 ${formatVideoDuration(progress.progressSeconds)}`,
      detail: progress.trackingMethod === 'player_tracked' ? '由播放器同步的进度。' : '由学生主动反馈的观看位置。',
      percent,
    }
  }
  if (progress.openedAt) return { tone: 'opened', label: '已打开', detail: '这里只能确认链接被打开，不能据此判断已经看完。', percent: 0 }
  return { tone: 'waiting', label: '尚未打开', detail: '讲解已经推送，等待学生按自己的节奏查看。', percent: 0 }
}

export function formatVideoEngagementTime(value: string | null) {
  if (!value) return ''
  return new Date(value).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}
