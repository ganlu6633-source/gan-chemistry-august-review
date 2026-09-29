type CardRow = Record<string, unknown>;
type BoundCardFetcher = (args: { p_textbook_version: string; p_knowledge_ids: string[] | null }) =>
  PromiseLike<{ data: unknown; error: unknown }>;

/** The service RPC validates the active release's exact card id and content
 * hash. Never fall back to newest/first approved cards of the same skill. */
export async function loadJuniorKnowledgeCards(
  skillIds: string[] | null,
  textbookVersion: string,
  fetchBoundCards: BoundCardFetcher,
) {
  const uniqueIds = [...new Set((skillIds ?? []).map((id) => id.trim()).filter(Boolean))];
  const batches: Array<string[] | null> = skillIds === null ? [null] : [];
  for (let offset = 0; skillIds !== null && offset < uniqueIds.length; offset += 20) {
    batches.push(uniqueIds.slice(offset, offset + 20));
  }
  const cards: CardRow[] = [];
  for (const batch of batches) {
    const result = await fetchBoundCards({ p_textbook_version: textbookVersion, p_knowledge_ids: batch });
    if (result.error) throw result.error;
    if (!Array.isArray(result.data)) throw new Error('已绑定知识卡的读取结果无效。');
    for (const card of result.data as CardRow[]) {
      if (!card || !String(card.id || '') || !String(card.skill_id || '') || card.review_status !== 'approved'
        || (batch !== null && !batch.includes(String(card.skill_id)))
        || cards.some((prior) => prior.id === card.id || prior.skill_id === card.skill_id)) {
        throw new Error('已绑定知识卡版本不唯一或与请求知识点不符。');
      }
      cards.push(card);
    }
  }
  return { data: cards, error: null };
}

const normalizedLabel = (value: string) => value.normalize('NFKC').replace(/\s+/gu, '').trim();

/** Send only the scheduled cards and the current recovery leaf's exact card.
 * Cross-skill leaves may be valid; a broad title or ambiguous label is not. */
export function juniorDisplayKnowledgeCards(cards: CardRow[], skillIds: string[], knowledgePoint?: string) {
  const selected = skillIds.flatMap((id) => cards.filter((card) => String(card.skill_id) === id));
  if (!knowledgePoint) return selected;
  const label = normalizedLabel(knowledgePoint);
  const matchingCards = cards.flatMap((card) => {
    const structured = card.structured_content as { sections?: Array<{ items?: Array<{ label?: string }> }> } | null;
    if (!structured || !Array.isArray(structured.sections)) return [];
    return structured.sections.flatMap((section) => Array.isArray(section.items)
      ? section.items.filter((item) => typeof item.label === 'string' && normalizedLabel(item.label) === label).map(() => card)
      : []);
  });
  if (matchingCards.length !== 1) throw new Error('这个错项的小知识点尚未绑定唯一的已审核知识卡，已保留练习进度。');
  if (!selected.some((card) => card.id === matchingCards[0].id)) selected.push(matchingCards[0]);
  return selected;
}
