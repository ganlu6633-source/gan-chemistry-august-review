export const JUNIOR_PROVENANCE_RPC_BATCH_LIMIT = 20;

function validUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function juniorProvenanceBatches(skillIds: string[]) {
  const uniqueIds = [...new Set(skillIds.map(String).map((value) => value.trim()).filter(Boolean))];
  const batches: string[][] = [];
  for (let offset = 0; offset < uniqueIds.length; offset += JUNIOR_PROVENANCE_RPC_BATCH_LIMIT) {
    batches.push(uniqueIds.slice(offset, offset + JUNIOR_PROVENANCE_RPC_BATCH_LIMIT));
  }
  return batches;
}

export function juniorVerifiedReleaseByKnowledge(
  provenanceRows: Array<Record<string, unknown>>,
  skillIds: string[],
  textbookVersion: string,
) {
  const releaseByKnowledge = new Map<string, string>();
  for (const skillId of skillIds) {
    const rows = provenanceRows.filter((row) => String(row.knowledge_id) === skillId
      && String(row.textbook_version) === textbookVersion
      && row.verification_status === "verified"
      && row.source_release_ready === true
      && validUuid(String(row.source_release_id || "")));
    if (rows.length === 1) releaseByKnowledge.set(skillId, String(rows[0].source_release_id));
  }
  return releaseByKnowledge;
}
