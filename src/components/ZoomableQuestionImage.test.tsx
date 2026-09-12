import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ZoomableQuestionImage } from './ZoomableQuestionImage'

describe('question image controls', () => {
  afterEach(cleanup)
  it('supports a continuous slider, wheel zoom and fit reset without replacing reviewed pixels', () => {
    const src = 'data:image/png;base64,reviewed'
    render(<ZoomableQuestionImage dataUrl={src} alt="已审核原题" width={1200} height={600} />)
    const image = screen.getByAltText('已审核原题')
    fireEvent.change(screen.getByRole('slider'), { target: { value: '2.347' } })
    expect(screen.getByText('235%')).toBeInTheDocument()
    expect(image.style.transform).toContain('scale(2.347)')
    fireEvent.wheel(screen.getByLabelText('原题图片缩放区域'), { deltaY: -80, clientX: 20, clientY: 30 })
    expect(Number((screen.getByRole('slider') as HTMLInputElement).value)).toBeGreaterThan(2.347)
    fireEvent.click(screen.getByRole('button', { name: '适应屏幕' }))
    expect(image.style.transform).toBe('translate(-50%, -50%) translate(0px, 0px) scale(1)')
    expect(image).toHaveAttribute('src', src)
  })
})
