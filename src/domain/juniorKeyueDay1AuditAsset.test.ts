import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

const RIGHTS_STATUS = 'user_provided_private_use_unverified_for_redistribution'
const MISSING_RAW_SOURCE_IDS = [
  'SRC-0F19B6A90C06F406',
  'SRC-6612FB539E135179',
  'SRC-857A34A76EEAF3DD',
  'SRC-C20DAF7A7343F429',
  'SRC-C5D0AC4683DB3958',
  'SRC-CCD28041A950F412',
  'SRC-E03E3A7836F94655',
]

type Difficulty = 'D1' | 'D2'

interface AuditedQuestion {
  question_id: string
  knowledge_id: string
  difficulty: Difficulty
  question_type: 'single_choice'
  source_item_token: string
  parent_source_item_token: string
  content_fingerprint: string
  source_id: string
  source_status: string
  answer_source_id: string
  answer_status: 'verified'
  explanation_status: 'verified_or_independent_chemistry_crosscheck'
  hint_presence: 'null'
  hint_verification_status: 'not_independently_verified'
  source_leak_status: 'pass'
  verification_status: 'verified'
  production_ready: boolean
}

interface AuditedCard {
  card_id: string
  knowledge_id: string
  content_fingerprint: string
  source_id: string
  source_status: string
  verification_status: string
}

interface AuditedSource {
  source_id: string
  sha256: string
  manifest_hash_status: 'sha256_full'
  current_raw_file_status:
    | 'missing_pending_recovery'
    | 'present_hash_match'
    | 'canonical_copy_present_hash_match'
  current_hash_status: string
  content_verification_status: string
}

interface AuditManifest {
  asset_id: string
  release_id: string
  asset_status: 'staged_not_published'
  publication: {
    auto_publish: boolean
    requires_explicit_private_import_and_release_step: boolean
    runtime_import_status: 'not_imported'
  }
  rights_status: string
  tracked_payload_policy: Record<string, boolean>
  curriculum: {
    edition: string
    knowledge_ids: string[]
  }
  counts: {
    knowledge_cards: number
    questions: number
    unique_question_ids: number
    unique_source_item_tokens: number
    unique_content_fingerprints: number
    four_option_questions: number
    sources: number
    raw_sources_missing_pending_recovery: number
  }
  distribution_by_knowledge: Record<string, { total: number; D1: number; D2: number }>
  fingerprint_contract: {
    question_content_fingerprint: string
    knowledge_card_content_fingerprint: string
  }
  verification_snapshot: {
    historical_release_status: 'verified'
    student_payload_scan_status: 'passed'
    source_leak_scan_contract_version: number
    canonical_answer_join_status: '21_verified'
    canonical_explanation_join_status: '21_nonempty'
    hint_status: '21_null_not_independently_verified'
  }
  knowledge_cards: AuditedCard[]
  questions: AuditedQuestion[]
  sources: AuditedSource[]
}

const audit = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/junior/keyue_9up_1_1_day1.audit.json'), 'utf8'),
) as AuditManifest

function collectKeys(value: unknown, keys = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) collectKeys(item, keys)
    return keys
  }
  if (!value || typeof value !== 'object') return keys
  for (const [key, child] of Object.entries(value)) {
    keys.add(key)
    collectKeys(child, keys)
  }
  return keys
}

describe('tracked Keyue Grade 9 section 1.1 day-one audit manifest', () => {
  it('is private-use, explicitly staged, and cannot trigger publication', () => {
    expect(audit.asset_status).toBe('staged_not_published')
    expect(audit.publication).toEqual({
      auto_publish: false,
      requires_explicit_private_import_and_release_step: true,
      runtime_import_status: 'not_imported',
    })
    expect(audit.rights_status).toBe(RIGHTS_STATUS)
    expect(JSON.stringify(audit)).not.toMatch(/licensed/i)
  })

  it('contains metadata only, never the copyrighted learning payload', () => {
    expect(Object.values(audit.tracked_payload_policy).every((included) => included === false)).toBe(true)

    const keys = collectKeys(audit)
    for (const prohibitedKey of [
      'stem',
      'options',
      'answer',
      'correct_option',
      'explanation',
      'hint',
      'source_path',
      'source_filename',
      'original_number',
      'page',
      'locator',
    ]) {
      expect(keys.has(prohibitedKey), prohibitedKey).toBe(false)
    }

    const serialized = JSON.stringify(audit)
    expect(serialized).not.toMatch(/[A-Za-z]:[\\/]/)
    expect(serialized).not.toMatch(/(?:BaiduNetdiskDownload|初三化学_分类整理)/i)
    expect(serialized).not.toMatch(/\.(?:pdf|docx?|pptx?)(?:\b|$)/i)
  })

  it('records three cards and three pools of five D1 plus two D2 questions', () => {
    expect(audit.curriculum.edition).toBe('科粤版')
    expect(audit.curriculum.knowledge_ids).toEqual(['1.1-K01', '1.1-K02', '1.1-K03'])
    expect(audit.counts).toMatchObject({
      knowledge_cards: 3,
      questions: 21,
      unique_question_ids: 21,
      unique_source_item_tokens: 21,
      unique_content_fingerprints: 21,
      four_option_questions: 21,
    })
    expect(audit.knowledge_cards).toHaveLength(3)
    expect(audit.questions).toHaveLength(21)

    for (const knowledgeId of audit.curriculum.knowledge_ids) {
      expect(audit.distribution_by_knowledge[knowledgeId], knowledgeId).toEqual({
        total: 7,
        D1: 5,
        D2: 2,
      })
      const pool = audit.questions.filter((question) => question.knowledge_id === knowledgeId)
      expect(pool).toHaveLength(7)
      expect(pool.filter((question) => question.difficulty === 'D1')).toHaveLength(5)
      expect(pool.filter((question) => question.difficulty === 'D2')).toHaveLength(2)
    }
  })

  it('proves 21 unique four-option candidates by identity and content fingerprint', () => {
    expect(new Set(audit.questions.map((question) => question.question_id)).size).toBe(21)
    expect(new Set(audit.questions.map((question) => question.source_item_token)).size).toBe(21)
    expect(new Set(audit.questions.map((question) => question.content_fingerprint)).size).toBe(21)

    for (const question of audit.questions) {
      expect(question.question_type).toBe('single_choice')
      expect(question.source_item_token).toMatch(/^[a-f0-9]{64}$/)
      expect(question.parent_source_item_token).toMatch(/^[a-f0-9]{64}$/)
      expect(question.content_fingerprint).toMatch(/^[a-f0-9]{64}$/)
      expect(question.answer_status).toBe('verified')
      expect(question.explanation_status).toBe('verified_or_independent_chemistry_crosscheck')
      expect(question.hint_presence).toBe('null')
      expect(question.hint_verification_status).toBe('not_independently_verified')
      expect(question.source_leak_status).toBe('pass')
      expect(question.verification_status).toBe('verified')
      expect(question.production_ready).toBe(true)
    }
  })

  it('records successful private-payload checks without making CI depend on that payload', () => {
    expect(audit.fingerprint_contract).toEqual({
      question_content_fingerprint: 'historical_sha256_sorted_json_stem_options_v1',
      knowledge_card_content_fingerprint: 'sha256_utf8_length_framed_student_card_payload_v1',
    })
    expect(audit.verification_snapshot).toEqual({
      historical_release_status: 'verified',
      student_payload_scan_status: 'passed',
      source_leak_scan_contract_version: 1,
      canonical_answer_join_status: '21_verified',
      canonical_explanation_join_status: '21_nonempty',
      hint_status: '21_null_not_independently_verified',
    })

    expect(new Set(audit.knowledge_cards.map((card) => card.card_id)).size).toBe(3)
    expect(new Set(audit.knowledge_cards.map((card) => card.content_fingerprint)).size).toBe(3)
    for (const card of audit.knowledge_cards) {
      expect(card.content_fingerprint).toMatch(/^[a-f0-9]{64}$/)
      expect(card.verification_status).toMatch(/^verified/)
    }
  })

  it('keeps ten path-free source records and flags exactly seven missing raw Word sources', () => {
    expect(audit.counts.sources).toBe(10)
    expect(audit.counts.raw_sources_missing_pending_recovery).toBe(7)
    expect(audit.sources).toHaveLength(10)
    expect(new Set(audit.sources.map((source) => source.source_id)).size).toBe(10)

    const sourceIds = new Set(audit.sources.map((source) => source.source_id))
    const missing = audit.sources
      .filter((source) => source.current_raw_file_status === 'missing_pending_recovery')
      .map((source) => source.source_id)
      .sort()
    expect(missing).toEqual([...MISSING_RAW_SOURCE_IDS].sort())
    expect(audit.sources.filter((source) => source.current_raw_file_status !== 'missing_pending_recovery')).toHaveLength(3)

    for (const source of audit.sources) {
      expect(Object.keys(source).sort()).toEqual([
        'content_verification_status',
        'current_hash_status',
        'current_raw_file_status',
        'manifest_hash_status',
        'sha256',
        'source_id',
      ])
      expect(source.sha256).toMatch(/^[a-f0-9]{64}$/)
      expect(source.manifest_hash_status).toBe('sha256_full')
      expect(source.current_hash_status.trim()).not.toBe('')
      expect(source.content_verification_status.trim()).not.toBe('')
    }

    for (const card of audit.knowledge_cards) expect(sourceIds.has(card.source_id)).toBe(true)
    for (const question of audit.questions) {
      expect(sourceIds.has(question.source_id)).toBe(true)
      expect(sourceIds.has(question.answer_source_id)).toBe(true)
    }
  })
})
