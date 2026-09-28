-- An item-level visual attestation is essential, but a reviewer can still
-- overlook an OCR hole. Fail new release activation on the known structural
-- formula-gap signatures as an independent check. Existing active releases
-- stay subject to the student-delivery gate and the repair queue.
begin;

create or replace function app_private.chem_require_item_visual_reviews_before_activation()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_count integer;
  v_verified integer;
  v_suspect_id text;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op='UPDATE' and old.status='active' then return new; end if;

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

  select q.id into v_suspect_id
  from public.chem_questions q
  where q.source_release_id=new.id
    and (
      cardinality(app_private.chem_question_ocr_gap_flags(q.stem,q.options)) > 0
      or position(chr(65533) in
          (coalesce(q.stem,'') || coalesce(q.options::text,'') ||
           coalesce(q.explanation,''))) > 0
      or (coalesce(q.stem,'') || coalesce(q.options::text,'') ||
          coalesce(q.explanation,'')) ~
         '(6[.]02|1[.]505)[[:space:]]*[×xX][[:space:]]*10(23|22|24)([^0-9]|$)'
      or ((select count(*) from regexp_matches(
             coalesce(q.stem,''), '反应[ⅠⅡⅢⅣIVX0-9]+[：:]', 'g')) >= 2
          and coalesce(q.stem,'') !~ '[→⟶⇌⇄↔=＝]')
    )
  limit 1;
  if v_suspect_id is not null then
    raise exception '题目 % 疑似公式或符号缺失：须对照本地原卷修复后重新核验，发布版 % 不得激活',
      v_suspect_id,new.id;
  end if;

  return new;
end;
$fn$;

commit;
