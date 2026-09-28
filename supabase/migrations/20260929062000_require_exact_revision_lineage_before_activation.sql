-- A repaired teaching-material question must preserve a database-verifiable
-- link to the exact earlier source item. The new item's source text may change
-- when broken formulas are restored, so compare its declared parent key and
-- canonical source rather than requiring identical text fingerprints.
begin;

create or replace function app_private.chem_require_item_visual_reviews_before_activation()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_count integer;
  v_verified integer;
  v_suspect_id text;
  v_unlinked_id text;
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

  if new.release_kind='teaching_material' then
    select q.id into v_unlinked_id
    from public.chem_questions q
    join app_private.chem_question_source_release_items item
      on item.release_id=new.id and item.question_id=q.id
    where q.source_release_id=new.id
      and exists (
        select 1
        from app_private.chem_question_source_release_items prior_item
        join app_private.chem_question_source_releases prior_release
          on prior_release.id=prior_item.release_id
        where prior_item.canonical_source_id=item.canonical_source_id
          and prior_item.question_id<>q.id
          and prior_release.id<>new.id
          and prior_release.status='active'
      )
      and not exists (
        select 1
        from app_private.chem_question_source_release_lineage link
        join public.chem_questions prior_q
          on prior_q.id=link.previous_question_id
        join app_private.chem_question_source_release_items prior_item
          on prior_item.release_id=link.previous_release_id
         and prior_item.question_id=link.previous_question_id
        where link.release_id=new.id and link.question_id=q.id
          and prior_q.source_release_id=link.previous_release_id
          and prior_q.grade_band=q.grade_band
          and q.parent_source_item_key=prior_q.source_item_key
          and prior_item.canonical_source_id=item.canonical_source_id
      )
    limit 1;
    if v_unlinked_id is not null then
      raise exception '题目 % 已有同原题旧版，须在 staged 阶段登记并核对旧题→新题精确追溯，发布版 % 不得激活',
        v_unlinked_id,new.id;
    end if;
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
