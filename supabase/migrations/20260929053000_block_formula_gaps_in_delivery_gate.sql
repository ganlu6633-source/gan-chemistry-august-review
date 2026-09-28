-- Visual review is necessary but cannot override a known structural OCR
-- defect. Apply the same formula-gap predicate to both existing active items
-- and future release activation so a mistaken attestation cannot publish one.
begin;

create or replace function app_private.chem_question_formula_gap_flags(
  p_stem text, p_options jsonb, p_explanation text
) returns text[]
language sql immutable set search_path='' as $fn$
  select array_cat(
    app_private.chem_question_ocr_gap_flags(p_stem,p_options),
    array_remove(array[
      case when position(chr(65533) in
             (coalesce(p_stem,'') || coalesce(p_options::text,'') ||
              coalesce(p_explanation,''))) > 0
           then 'replacement_character_in_question' end,
      case when (coalesce(p_stem,'') || coalesce(p_options::text,'') ||
                 coalesce(p_explanation,'')) ~
                '(6[.]02|1[.]505)[[:space:]]*[×xX][[:space:]]*10(23|22|24)([^0-9]|$)'
           then 'flattened_scientific_exponent' end,
      case when (select count(*) from regexp_matches(
                  coalesce(p_stem,''),
                  '反应[ⅠⅡⅢⅣIVX0-9]+[：:]', 'g')) >= 2
                and coalesce(p_stem,'') !~ '[→⟶⇌⇄↔=＝]'
           then 'reaction_table_arrows_missing' end
    ]::text[], null::text)
  );
$fn$;
revoke all on function app_private.chem_question_formula_gap_flags(text,jsonb,text)
  from public, anon, authenticated;

create or replace function app_private.chem_question_item_delivery_review_ready(
  p_question_id text
) returns boolean
language plpgsql stable security definer set search_path='' as $fn$
declare
  v_state text;
  v_flags text[];
begin
  select app_private.chem_question_formula_gap_flags(
           q.stem,q.options,q.explanation)
    into v_flags
  from public.chem_questions q where q.id=p_question_id;
  if v_flags is null or cardinality(v_flags)>0 then return false; end if;

  select review_state into v_state
  from app_private.chem_question_item_visual_reviews
  where question_id=p_question_id;
  if v_state='verified' then
    return app_private.chem_question_item_visual_reviewed(p_question_id);
  end if;
  if v_state='legacy_carried' then
    return app_private.chem_question_item_legacy_carried(p_question_id);
  end if;
  return false;
end;
$fn$;

create or replace view app_private.chem_question_quality_audit_queue as
with source_questions as materialized (
  select q.id, q.grade_band, q.source_release_id, q.source_item_key,
         q.stem, q.options, q.explanation
  from public.chem_questions q
  join app_private.chem_question_source_releases release
    on release.id=q.source_release_id
  where release.status='active'
    and q.review_status='approved' and q.scope_status='IN'
    and q.usable_for_review
), checked as materialized (
  select q.*,
         app_private.chem_question_item_delivery_review_ready(q.id)
           as item_review_ready,
         app_private.chem_question_formula_gap_flags(
           q.stem,q.options,q.explanation) as flags
  from source_questions q
)
select q.id as question_id, q.grade_band, q.source_release_id,
       q.source_item_key,
       not q.item_review_ready as needs_manual_visual_review,
       cardinality(q.flags)>0 as suspected_formula_gap,
       coalesce(review.review_state,'no_item_review') as review_state,
       q.flags as suspected_formula_gap_flags
from checked q
left join app_private.chem_question_item_visual_reviews review
  on review.question_id=q.id
where not q.item_review_ready or cardinality(q.flags)>0;
revoke all on app_private.chem_question_quality_audit_queue
  from public, anon, authenticated, service_role;

create or replace function app_private.chem_require_item_visual_reviews_before_activation()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_count integer;
  v_verified integer;
  v_suspect_id text;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op='UPDATE' and old.status='active' then return new; end if;

  select q.id into v_suspect_id
  from public.chem_questions q
  where q.source_release_id=new.id
    and cardinality(app_private.chem_question_formula_gap_flags(
          q.stem,q.options,q.explanation))>0
  limit 1;
  if v_suspect_id is not null then
    raise exception '题目 % 疑似公式或符号缺失：须对照本地原卷修复后重新核验，发布版 % 不得激活',
      v_suspect_id,new.id;
  end if;

  select count(*) into v_count
  from public.chem_questions q where q.source_release_id=new.id;
  select count(*) into v_verified
  from public.chem_questions q
  where q.source_release_id=new.id
    and app_private.chem_question_item_delivery_review_ready(q.id);
  if v_count <> new.expected_question_count or v_verified <> v_count then
    raise exception '逐题原图核验或严格历史继承未满足：发布版 % 已通过 % / %',
      new.id,v_verified,v_count;
  end if;
  return new;
end;
$fn$;

commit;
