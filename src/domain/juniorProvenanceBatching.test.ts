import { describe, expect, it } from 'vitest'

import {
  JUNIOR_PROVENANCE_RPC_BATCH_LIMIT,
  juniorProvenanceBatches,
  juniorVerifiedReleaseByKnowledge,
} from '../../supabase/functions/chemistry-access/junior-provenance'

function provenanceRow(knowledgeId: string, releaseSuffix: number) {
  return {
    knowledge_id: knowledgeId,
    textbook_version: '科粤版',
    verification_status: 'verified',
    source_release_ready: true,
    source_release_id: `00000000-0000-4000-8000-${String(releaseSuffix).padStart(12, '0')}`,
  }
}

describe('junior learning-record provenance batching', () => {
  it('keeps the 21st reached route in a bounded second RPC batch', () => {
    const ids = Array.from({ length: 21 }, (_, index) => `K${index + 1}`)
    const batches = juniorProvenanceBatches(ids)
    expect(JUNIOR_PROVENANCE_RPC_BATCH_LIMIT).toBe(20)
    expect(batches.map((batch) => batch.length)).toEqual([20, 1])
    expect(batches.flat()).toEqual(ids)
  })

  it('merges readiness per skill instead of clearing valid siblings', () => {
    const rows = [
      provenanceRow('K1', 1),
      provenanceRow('K2', 2),
      provenanceRow('K2', 3),
      { ...provenanceRow('K3', 4), verification_status: 'pending' },
    ]
    const ready = juniorVerifiedReleaseByKnowledge(rows, ['K1', 'K2', 'K3'], '科粤版')
    expect([...ready.keys()]).toEqual(['K1'])
  })
})
