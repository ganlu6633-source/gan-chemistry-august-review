-- Audited one-time backfill: exactly five H2_EQUIL old -> active repaired question pairs.
-- Item-level evidence, local PDF/page references and independently checked WebP
-- digests: private-import/high1-gap-qa-20260929/h2-300-samples/
-- h2-equil-five-active-lineage-evidence.json. The visible source PDF loses
-- reversible-arrow glyphs in four of these items; reviewed revisions explicitly
-- mark the resulting formula restoration as errata.
-- Only lineage is inserted. Question content, answers, holds, readiness and
-- student history are untouched. The staged-only mutation guard is restored
-- inside this same transaction before commit.
begin;
lock table app_private.chem_question_source_release_lineage in access exclusive mode;

create temp table _approved_h2_equil_exact_lineage (
  new_release uuid not null,
  new_id text primary key,
  old_release uuid not null,
  old_id text not null unique,
  canonical text not null unique,
  old_source_item_key text not null,
  new_source_item_key text not null,
  correct_option_index smallint not null,
  revision_token text not null,
  item_sha256 text not null,
  question_asset_sha256 text not null,
  analysis_asset_sha256 text not null,
  source_locator text not null
) on commit drop;

insert into _approved_h2_equil_exact_lineage values
('d0f1f685-6aae-4f8e-b462-d93a46b1c0ad'::uuid, 'QH2EQERR29_07F3C55F72EA93BBA0D6AF13A4036673', '64f11679-c5ba-5fe9-9c5b-503e4d7ecaac'::uuid, 'QH2R2_20260908_07F3C55F72EA93BBA0D6AF13A4036673',
 'H2_EQUIL-29f4708d3752be09', 'c5dc5efad512c86f06b34d3c774afb19cb266e40dd5ea9b66b9e4e991764da93', 'abcdc0377f1a53c59635c3c2dac5ae9e4f7fea39e7b89e8c0099d55ed623e7a5', 2,
 '6d23a174aba5f7e0cdbfe3ca38920f7f10758b00950d7d13695a009eeea18c0b', 'd52d8dc56eccd229f8569db02940e50ce55138c4b1f73db0a5ed9eef0746c8ed', '4b2525010b49cd0bbdb3f5050a04b2a6d77664a0d176f1226fd7f255a558da7a',
 'de8f2d9b98e88092e9c79427bb19fae74fadc13bb20593b20200d0bdd2724090', 'H2_EQUIL.pdf p25–26 第1题'),
('ff44f116-dd9c-43b3-8f2e-499199f08c2d'::uuid, 'QH2EQERR29_173A7EB4DCAC34DC25201B6C6BAD86FE', '64f11679-c5ba-5fe9-9c5b-503e4d7ecaac'::uuid, 'QH2R2_20260908_173A7EB4DCAC34DC25201B6C6BAD86FE',
 'H2_EQUIL-08e6c9de91c5da70', 'c1b88de02d8477d70501e047fe59b7faebd42a2f244206fd5858475da79ad8ed', '1327e86dc02f12fdb79b9eeb9d4088f59911f5f1d0d3d098170a3c7222a3ed09', 3,
 '0469905597c27969e4fb9a8994ebabadd2b683c27b6637128f1ab5d949a5f2c1', '3af503eb3a41ccd100f692e421e2ccb63abcecb50fef16ca8ec67da0c2ddc1df', '1450435509bda143ac14dea0ee5a229a78824a54e99292f42343eb8c98124ee9',
 '9a403ea86cae69de3997fb06e2d5b0b336c810866cb8e50daf7a96da1e7bb08f', 'H2_EQUIL.pdf p5 第2题'),
('99ff8c66-1dd9-4dc7-8b93-c6ecc9f4d09e'::uuid, 'QH2EQERR29_4DBD6BBFE3918A004F67A2B29292FADB', '64f11679-c5ba-5fe9-9c5b-503e4d7ecaac'::uuid, 'QH2R2_20260908_4DBD6BBFE3918A004F67A2B29292FADB',
 'H2_EQUIL-c74bb6a516920da4', '90427afff82644ec2252f62c772d851ecc5b00229e80fcb0502f6c33dd16b9f7', '3e36de65521a72a0925da882520fb465e8381a607981f0626049bb9d1b175f86', 1,
 'ee16ca4bbbdf979974a28f509ba3ddf471f0be6d21e3c158346f07f312762a6b', '4a0a0f481c27d0c9c41bf5915fc2cbc361729255e7802357d2ad18843a0e0f20', '79470c2ce77847cdcfed3d0361acbfb8db03abce6dfd83a6dac6edb7e3853d86',
 '3e5aecbc479c10a6e57f317a02e430ed7a22bad919c0a59d0067556dad883a9a', 'H2_EQUIL.pdf p4–5 第1题'),
('ae63f596-8a69-4d49-a65f-4a08ccab6e43'::uuid, 'QH2EQERR29_F2348E691AA485425D1B8FD5FACFAC73', '64f11679-c5ba-5fe9-9c5b-503e4d7ecaac'::uuid, 'QH2R2_20260908_F2348E691AA485425D1B8FD5FACFAC73',
 'H2_EQUIL-c2f0db8945ca6873', '0eac04d1a77eec1411dbf7fb274e3a5356265af8186864894b45fc7889d298af', '6c3bcde4518ad9daa889cc92778bb3eb727dc57c5916f51e3459e0870e577af7', 3,
 '62947497ae05e9d6745b5d7c0a257c1a2563fc46afbfe6c7ec95471989586966', '35ec8af33bf44157b3997d4fcd08e472126000bdd2112fb1e0dc762f17eae8da', '02ae9ce79d3c31371d4a2b1b8a5c12e5b2ad34727698679fc36e9a762f3cc161',
 '2269bd7b2adb16e479799e0a6d584bb8bad49fbe79340c1317fbf6676e9dc295', 'H2_EQUIL.pdf p26 第3题'),
('bf505d34-0bb8-4196-aa3f-fa04335fcc3f'::uuid, 'QH2EQREF29_B041963DE297A3E1C62393E6A5B2BF74', '64f11679-c5ba-5fe9-9c5b-503e4d7ecaac'::uuid, 'QH2R2_20260908_B041963DE297A3E1C62393E6A5B2BF74',
 'H2_EQUIL-e47840a99b89b1ce', '83e0044d914bb4a53ddf75f40434af00115f37a54ab0809bf83985d4b3db9913', 'c667203d053c0ccbcae20327a2d33661a05d49166473ce550d7a96c100d08f1f', 2,
 '6753464f0934b0131d3a0411e9075523b2737218b02e758b4f38e2517a4815c8', '5046a3ef0a65f3a179bd13c7704d6790036f03f39c850f9a1fae595bdabb3927', '75227eee66be1be3e559185a9aab86d2b44871fdec27978ba8a87e3f14b1f44e',
 '23f2f2d2d9266450af69e47f3bf3f0976201e56a86b1169f4858ee50eae0f699', 'H2_EQUIL.pdf p26 第2题');

do $precheck$ begin
  if (select count(*) from _approved_h2_equil_exact_lineage) <> 5
  then raise exception 'expected exactly five audited H2_EQUIL lineage pairs'; end if;

  if exists (
    select 1
    from _approved_h2_equil_exact_lineage a
    left join public.chem_questions old_q on old_q.id=a.old_id
    left join public.chem_questions new_q on new_q.id=a.new_id
    left join app_private.chem_question_source_releases release on release.id=a.new_release
    left join app_private.chem_question_source_release_items old_i
      on old_i.release_id=a.old_release and old_i.question_id=a.old_id
    left join app_private.chem_question_source_release_items new_i
      on new_i.release_id=a.new_release and new_i.question_id=a.new_id
    left join app_private.chem_question_item_visual_reviews review
      on review.question_id=a.new_id
    where old_q.id is null or new_q.id is null
      or old_q.source_release_id is distinct from a.old_release
      or new_q.source_release_id is distinct from a.new_release
      or old_q.grade_band is distinct from '高二'
      or new_q.grade_band is distinct from '高二'
      or release.status is distinct from 'active'
      or release.release_kind is distinct from 'teaching_material'
      or release.grade_band is distinct from '高二'
      or old_q.source_item_key is distinct from a.old_source_item_key
      or new_q.parent_source_item_key is distinct from a.old_source_item_key
      or new_q.source_item_key is distinct from a.new_source_item_key
      or old_i.canonical_source_id is distinct from a.canonical
      or new_i.canonical_source_id is distinct from a.canonical
      or old_q.correct_option is distinct from a.correct_option_index
      or new_q.correct_option is distinct from a.correct_option_index
      or new_q.question_revision_token is distinct from a.revision_token
      or new_i.item_sha256 is distinct from a.item_sha256
      or new_i.question_asset_sha256 is distinct from a.question_asset_sha256
      or new_i.analysis_asset_sha256 is distinct from a.analysis_asset_sha256
      or new_q.source_info->>'locator' is distinct from a.source_locator
      or review.review_state is distinct from 'verified'
      or review.source_release_id is distinct from a.new_release
      or review.revision_token is distinct from a.revision_token
      or review.source_item_sha256 is distinct from a.item_sha256
      or review.question_image_sha256 is distinct from a.question_asset_sha256
      or review.analysis_image_sha256 is distinct from a.analysis_asset_sha256
      or review.source_locator is distinct from a.source_locator
      -- This historical batch stored the independently rehashed source-PDF SHA
      -- in the review note, not in source_document_sha256.
      or position(
        '3ace5c3d99fe9d51a79782a3c3439faf73fa2c539ec58d659bdae4ffb23c5ffc'
        in lower(coalesce(review.review_note, ''))
      ) = 0
      or not coalesce(app_private.chem_question_item_visual_reviewed(a.new_id), false)
      or not exists (
        select 1 from app_private.chem_question_delivery_holds hold
        where hold.anchor_question_id=a.old_id and hold.resolved_at is null
      )
      or exists (
        select 1 from app_private.chem_teaching_ready_questions ready
        where ready.id=a.old_id
      )
      or not exists (
        select 1 from app_private.chem_teaching_ready_questions ready
        where ready.id=a.new_id
      )
      or exists (
        select 1
        from app_private.chem_teaching_ready_questions other_ready
        join app_private.chem_question_source_release_items other_i
          on other_i.release_id=other_ready.source_release_id
         and other_i.question_id=other_ready.id
        where other_i.canonical_source_id=a.canonical
          and other_ready.id<>a.new_id
      )
      or exists (
        select 1 from app_private.chem_question_source_release_lineage link
        where (link.release_id=a.new_release and link.question_id=a.new_id)
           or (link.previous_release_id=a.old_release and link.previous_question_id=a.old_id)
      )
  ) then raise exception 'H2_EQUIL exact-source, SHA, hold, ready, review or uniqueness precheck failed'; end if;

  if exists (
    select 1 from _approved_h2_equil_exact_lineage a
    where (select count(*) from app_private.chem_question_assets asset
           where asset.question_id=a.new_id and asset.asset_kind='question_image') <> 1
       or (select count(*) from app_private.chem_question_assets asset
           where asset.question_id=a.new_id and asset.asset_kind='analysis_image') <> 1
       or not exists (
         select 1 from app_private.chem_question_assets asset
         where asset.question_id=a.new_id and asset.asset_kind='question_image'
           and asset.sha256=a.question_asset_sha256
           and pg_catalog.encode(extensions.digest(
                 pg_catalog.decode(asset.payload_base64, 'base64'), 'sha256'), 'hex')
               =a.question_asset_sha256
       )
       or not exists (
         select 1 from app_private.chem_question_assets asset
         where asset.question_id=a.new_id and asset.asset_kind='analysis_image'
           and asset.sha256=a.analysis_asset_sha256
           and pg_catalog.encode(extensions.digest(
                 pg_catalog.decode(asset.payload_base64, 'base64'), 'sha256'), 'hex')
               =a.analysis_asset_sha256
       )
  ) then raise exception 'H2_EQUIL current question/analysis image payload SHA failed'; end if;
end $precheck$;

-- Extend the existing trigger inside this transaction for the exact white list.
-- The active-release exception requires all four lineage identity columns.
-- PostgreSQL keeps the function replacement invisible to other sessions until
-- commit, at which point the original staged-only body has been restored.
create or replace function app_private.chem_guard_h1_source_release_lineage_mutation()
returns trigger language plpgsql security definer set search_path to '' as $backfill_guard$
declare
  v_release_id uuid := case when tg_op='DELETE' then old.release_id else new.release_id end;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
  if tg_op='UPDATE' and (
    new.release_id is distinct from old.release_id
    or new.question_id is distinct from old.question_id
    or new.previous_release_id is distinct from old.previous_release_id
    or new.previous_question_id is distinct from old.previous_question_id
  ) then raise exception 'question lineage identity is immutable'; end if;
  if not exists(select 1 from app_private.chem_question_source_releases release
                where release.id=v_release_id and release.status='staged') then
    if tg_op='INSERT' and exists (
      select 1 from pg_temp._approved_h2_equil_exact_lineage a
      where a.new_release=new.release_id
        and a.new_id=new.question_id
        and a.old_release=new.previous_release_id
        and a.old_id=new.previous_question_id
    ) then return new; end if;
    raise exception 'question lineage may change only while the target release is staged';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$backfill_guard$;

insert into app_private.chem_question_source_release_lineage
  (release_id, question_id, previous_release_id, previous_question_id)
select new_release, new_id, old_release, old_id
from _approved_h2_equil_exact_lineage;

do $postcheck$ begin
  if (select count(*)
      from _approved_h2_equil_exact_lineage a
      join app_private.chem_question_source_release_lineage link
        on link.release_id=a.new_release and link.question_id=a.new_id
       and link.previous_release_id=a.old_release
       and link.previous_question_id=a.old_id) <> 5
  then raise exception 'five audited H2_EQUIL lineage links were not inserted exactly'; end if;
end $postcheck$;

-- Restore the exact current staged-only guard before commit.
create or replace function app_private.chem_guard_h1_source_release_lineage_mutation()
returns trigger language plpgsql security definer set search_path to '' as $guard$
declare
  v_release_id uuid := case when tg_op='DELETE' then old.release_id else new.release_id end;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
  if tg_op='UPDATE' and (
    new.release_id is distinct from old.release_id
    or new.question_id is distinct from old.question_id
    or new.previous_release_id is distinct from old.previous_release_id
    or new.previous_question_id is distinct from old.previous_question_id
  ) then raise exception 'question lineage identity is immutable'; end if;
  if not exists(select 1 from app_private.chem_question_source_releases release
                where release.id=v_release_id and release.status='staged') then
    raise exception 'question lineage may change only while the target release is staged';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$guard$;

do $final_guard_check$ begin
  if position('pg_temp._approved_h2_equil_exact_lineage' in
      pg_catalog.pg_get_functiondef(
        'app_private.chem_guard_h1_source_release_lineage_mutation()'::pg_catalog.regprocedure
      )) > 0
  then raise exception 'temporary H2_EQUIL lineage exception was not removed'; end if;
end $final_guard_check$;

select count(*) as audited_exact_links
from app_private.chem_question_source_release_lineage link
join _approved_h2_equil_exact_lineage a
  on link.release_id=a.new_release and link.question_id=a.new_id
 and link.previous_release_id=a.old_release and link.previous_question_id=a.old_id;
commit;
