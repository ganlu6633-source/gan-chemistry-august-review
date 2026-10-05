/** Images have a separately reviewed original-source release. Their knowledge
 * card remains bound to the one verified textbook release for that skill. */
export type JuniorImageProof = {
  question_id: string;
  revision_token: string;
  source_release_id: string;
  knowledge_id: string;
  textbook_version: string;
  card_source_release_id: string;
  card_id: string;
};

const sha = (value: unknown) => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
const uuid = (value: unknown) => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

export function juniorImageProofMap(values: unknown): Map<string, JuniorImageProof> {
  if (!Array.isArray(values)) throw new Error("Junior image proof response is unavailable");
  const result = new Map<string, JuniorImageProof>();
  for (const raw of values) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("Invalid junior image proof");
    const proof = raw as JuniorImageProof;
    if (!proof.question_id || !sha(proof.revision_token) || !uuid(proof.source_release_id)
      || !proof.knowledge_id || proof.textbook_version !== "科粤版"
      || !uuid(proof.card_source_release_id) || !proof.card_id || result.has(proof.question_id)) {
      throw new Error("Junior image proof is incomplete or ambiguous");
    }
    result.set(proof.question_id, proof);
  }
  return result;
}

/** Structural check is also used for the public DTO AFTER the source proof and
 * atomic issue/resume have succeeded. It never grants delivery by itself. */
export function juniorImageQuestionStructureIsSafe(row: Record<string, unknown>) {
  const options = Array.isArray(row.options) ? row.options : [];
  const refs = Array.isArray(row.asset_refs) ? row.asset_refs : [];
  const correct = Number(row.correct_option);
  return row.grade_band === "初三" && row.textbook_version === "科粤版"
    && row.source_kind === "licensed_local" && row.render_mode === "image_primary"
    && row.image_url == null && row.skill_id === row.knowledge_id && Boolean(row.knowledge_id)
    && row.review_status === "approved" && row.scope_status === "IN" && row.usable_for_review === true
    && row.usable_for_class_quiz === false && row.usable_for_exam_sprint === false && row.usable_for_demo === false
    && typeof row.stem === "string" && row.stem.trim().length > 0
    && typeof row.explanation === "string" && row.explanation.trim().length > 0
    && options.length === 4 && options.every((option) => typeof option === "string" && option.trim())
    && new Set(options.map((option) => String(option).trim())).size === 4
    && Number.isInteger(correct) && correct >= 0 && correct <= 3 && sha(row.question_revision_token)
    && refs.length === 2 && new Set(refs.map((ref) => ref?.kind)).size === 2
    && refs.every((ref) => ref && typeof ref === "object"
      && ["question_image", "analysis_image"].includes(ref.kind)
      && /^[a-zA-Z0-9/_-]{16,200}$/.test(String(ref.path || "")) && sha(ref.sha256)
      && typeof ref.alt === "string" && ref.alt.trim().length > 0
      && Number.isInteger(ref.width) && ref.width > 0 && Number.isInteger(ref.height) && ref.height > 0);
}

export function juniorReviewedImageQuestionIsSafe(
  row: Record<string, unknown>, proofs: Map<string, JuniorImageProof>, releaseByKnowledge: Map<string, string>,
) {
  const proof = proofs.get(String(row.id || ""));
  return juniorImageQuestionStructureIsSafe(row) && Boolean(proof)
    && proof!.question_id === row.id && proof!.revision_token === row.question_revision_token
    && proof!.source_release_id === row.source_release_id && proof!.knowledge_id === row.knowledge_id
    && proof!.textbook_version === row.textbook_version
    && proof!.card_source_release_id === releaseByKnowledge.get(String(row.knowledge_id));
}

/** A whole original question is its own parent; explicit subquestion / revision
 * lineage always wins. This does not rewrite the raw snapshotted source value. */
export function juniorParentSourceIdentity(row: Record<string, unknown>): string {
  return String(row.parent_source_item_key || (row.source_kind === "licensed_local" ? row.source_item_key : "") || "");
}
