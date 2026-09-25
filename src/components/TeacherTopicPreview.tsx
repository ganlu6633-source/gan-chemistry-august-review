import { useState } from 'react'
import { ChevronRight } from 'lucide-react'
import type { Question, SessionIdentity } from '../domain/types'
import { ChemText } from './ChemText'
import { QuestionSourceMedia } from './QuestionSourceMedia'

export type TeacherTopicPreviewData = { topic: string; questions: Question[] }

/** Teacher-only, local answer simulation. It never creates a plan or an attempt. */
export function TeacherTopicPreview({ session, studentName, preview, onExit }: {
  session: SessionIdentity
  studentName: string
  preview: TeacherTopicPreviewData
  onExit: () => void
}) {
  const [index, setIndex] = useState(0)
  const [selected, setSelected] = useState<number | null>(null)
  const [revealed, setRevealed] = useState(false)
  const [imageReady, setImageReady] = useState(false)
  const question = preview.questions[index]
  if (!question) return <section className="learning-stage"><button className="text-button" onClick={onExit}>← 返回知识点目录</button><p>这组原题暂时无法预览。</p></section>
  const imagePrimary = question.renderMode === 'image_primary'
  const isCorrect = selected === question.correctOption
  const next = () => {
    if (index + 1 >= preview.questions.length) return onExit()
    setIndex((current) => current + 1)
    setSelected(null)
    setRevealed(false)
    setImageReady(false)
  }
  return <section className="learning-stage teacher-topic-preview" data-testid="teacher-topic-preview">
    <button className="text-button" onClick={onExit}>← 返回知识点目录</button>
    <div className="page-title"><span className="eyebrow">{studentName} · 教师只读模拟</span><h1><ChemText>{preview.topic}</ChemText></h1><p>这里可以像学生一样选 A、B、C、D；答案只在本页显示，不会写入学生档案。</p></div>
    <div className="quiz-head"><span>原题 {index + 1}/{preview.questions.length}</span><span>纸上演算后再选择</span></div>
    <article className="question-card" key={question.id}>
      <QuestionSourceMedia question={question} enabled={question.sourceKind === 'licensed_local'} session={session}
        nativeContent={<h2><ChemText>{question.stem}</ChemText></h2>} showSource={false}
        readOnly feedback={revealed} onPrimaryReadyChange={setImageReady} />
      <div className={`option-list ${imagePrimary ? 'source-letter-options' : ''}`}>
        {question.options.map((option, optionIndex) => {
          const letter = String.fromCharCode(65 + optionIndex)
          return <button type="button" key={`${optionIndex}-${option}`} disabled={revealed || (imagePrimary && !imageReady)}
            aria-label={imagePrimary ? `${letter} 选项，内容见原题图` : `${letter}. ${option}`}
            className={`${selected === optionIndex ? 'selected' : ''} ${revealed && question.correctOption === optionIndex ? 'correct' : ''} ${revealed && selected === optionIndex && !isCorrect ? 'wrong' : ''}`}
            onClick={() => setSelected(optionIndex)}><span>{letter}</span>{!imagePrimary && <ChemText>{option}</ChemText>}</button>
        })}
      </div>
      {revealed && <div className={`answer-feedback ${isCorrect ? 'good' : 'needs-work'}`} role="status">
        <b>{isCorrect ? '选对了' : `正确选项：${String.fromCharCode(65 + Number(question.correctOption))}`}</b>
        <p><ChemText>{question.explanation || '解析暂不可用。'}</ChemText></p>
      </div>}
    </article>
    <div className="stage-actions">{revealed
      ? <button type="button" className="primary-button" onClick={next}>{index + 1 < preview.questions.length ? '下一题' : '返回知识点目录'}<ChevronRight size={18} /></button>
      : <button type="button" className="primary-button" disabled={selected === null || (imagePrimary && !imageReady)} onClick={() => setRevealed(true)}>查看答案和解析</button>}
    </div>
  </section>
}
