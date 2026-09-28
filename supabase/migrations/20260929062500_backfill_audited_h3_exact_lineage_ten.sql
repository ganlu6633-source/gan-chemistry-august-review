-- One-time high-three exact-source lineage backfill. Pair-by-pair source
-- evidence was checked in audited-lineage-ten.json and the cited private JSONs.
-- This migration does not update any question content, answers, images, or hold state.
-- It temporarily extends the lineage guard inside this single transaction for exactly
-- these ten reviewed pairs, then restores the original guard before commit.
begin;
lock table app_private.chem_question_source_release_lineage in access exclusive mode;
create temp table _approved_h3_exact_lineage (
  new_release uuid not null,
  new_id text primary key,
  old_release uuid not null,
  old_id text unique not null,
  canonical text not null,
  new_locator text not null,
  original_pdf_sha256 text not null,
  teacher_pdf_sha256 text not null,
  private_evidence_file text not null
) on commit drop;
insert into _approved_h3_exact_lineage values
('2d02d223-60a6-57c8-b9c4-3f98f9b9ff09','QH3FZ26_H3SRC7_FIX_636439d689b9da09','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_d297e15d4bc5cdf9b3cd64eb','GQC00116','2025湖南卷，专题03真题第23题；本地原卷PDF物理页6–7、教师版PDF物理页12–13','d9f39cbfccf030f0b36c19ba22dae5eac4098522b450d1258f8597119946b743','bb6c2f2f2bac8b3da296f2c690b2cd935b307218b8946183b8f942c7c0576d39','recovered-five.json'),
('2d02d223-60a6-57c8-b9c4-3f98f9b9ff09','QH3FZ26_H3SRC7_FIX_69872b9f1ddfea6d','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_6b8e13f1518185072e0bbdea','GQC00169','2025北京房山三模，专题04第10题；本地原卷PDF物理页7、教师版PDF物理页14–15','d8237fb8e756b129c9be8bbb65007cb6aec9d415d66e7d1fa920a17bdca5f473','ac829292491b310af103ea6f5ef05e6ddc8a18db2aa2a44b103e4a12e80843ef','recovered-five.json'),
('2d02d223-60a6-57c8-b9c4-3f98f9b9ff09','QH3FZ26_H3SRC7_FIX_9281f520ad879e39','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_7495c100b6b5cfa33c347be1','GQC00343','2025江苏卷，专题08第1题；本地原卷PDF物理页1、教师版PDF物理页1','e82e67a2925fd34cd2bf1d8e8445ad315115e85c02a2b26fd241aa46665249e6','bafc2cdb321700a701fbc340ab517f712bb773eaaeb4560f1f840d10c2dec717','recovered-five.json'),
('2d02d223-60a6-57c8-b9c4-3f98f9b9ff09','QH3FZ26_H3SRC7_FIX_9a42ba80f50bdeb0','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_4184559abfcedd57a0ec9a84','GQC00365','2025河北衡水一模，专题08第8题；本地原卷PDF物理页11–12、教师版PDF物理页19–20','e82e67a2925fd34cd2bf1d8e8445ad315115e85c02a2b26fd241aa46665249e6','bafc2cdb321700a701fbc340ab517f712bb773eaaeb4560f1f840d10c2dec717','recovered-five.json'),
('2d02d223-60a6-57c8-b9c4-3f98f9b9ff09','QH3FZ26_H3SRC7_FIX_341d2688efc3faa2','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_068a968fe1548a286d7ba2e6','GQC00387','2025贵州毕节二模，专题08第30题；本地原卷PDF物理页20–21、教师版PDF物理页37–38','e82e67a2925fd34cd2bf1d8e8445ad315115e85c02a2b26fd241aa46665249e6','bafc2cdb321700a701fbc340ab517f712bb773eaaeb4560f1f840d10c2dec717','recovered-five.json'),
('05489c5d-1cbc-5108-8aa1-bb5f2ae20b4b','QH3FZ26_H3T07_18_FIX_2ccf063843178232','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_3cae3571cffa8a35a503ae32','GQC00330','2025天津一模，专题07第18题；本地原卷PDF物理页15、教师版PDF物理页25–26','f24e2b916defdc56b81e0ef5a12b3935322755813f1db27deff7c8097d488ca2','c58afa7ceead58ce55d6202d8612a3dd8dc87a1f2944ef29a71b94a50a1d58c0','recovered-gqc00330.json'),
('6cea7d8e-9606-5e7f-bb90-83566475b725','QH3FZ26_H3HR4_FIX_b6d026a210f23ce5','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_0c29ae50b1adc1db43744949','GQC00292','2025福建厦门二模，专题06第32题；本地原卷PDF物理页20、教师解析版PDF物理页39–40','7ec3b70d57deb5b60c7bd18b4cfa3c12ff85ef9bf31622d687f3d2e6b49a6e06','64a518489268e74d2cf49dc53225bcc0428064997efc3501ccd9cf12090b6dc7','highrisk-ten-source/recovered-four.json'),
('6cea7d8e-9606-5e7f-bb90-83566475b725','QH3FZ26_H3HR4_FIX_b62a620a4ac36210','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_157b58af4e9c5d5a4e262db1','GQC00351','2025重庆卷，专题08第10题；本地原卷PDF物理页5、教师解析版PDF物理页8–9','e82e67a2925fd34cd2bf1d8e8445ad315115e85c02a2b26fd241aa46665249e6','bafc2cdb321700a701fbc340ab517f712bb773eaaeb4560f1f840d10c2dec717','highrisk-ten-source/recovered-four.json'),
('6cea7d8e-9606-5e7f-bb90-83566475b725','QH3FZ26_H3HR4_FIX_1a1a9fcd3f94c73f','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_0babf0741fce9fc233cb559e','GQC00372','2025河南开封三模，专题08第15题；本地原卷PDF物理页14、教师解析版PDF物理页24–25','e82e67a2925fd34cd2bf1d8e8445ad315115e85c02a2b26fd241aa46665249e6','bafc2cdb321700a701fbc340ab517f712bb773eaaeb4560f1f840d10c2dec717','highrisk-ten-source/recovered-four.json'),
('6cea7d8e-9606-5e7f-bb90-83566475b725','QH3FZ26_H3HR4_FIX_7f2ac8722ef87c68','07be42f6-49fc-5aa3-9ff5-7a8dcb774d1d','QH3FZ26_RET_195377846b5636a6b695c69f','GQC00374','2025北京顺义一模，专题08第17题；本地原卷PDF物理页15、教师解析版PDF物理页26–27','e82e67a2925fd34cd2bf1d8e8445ad315115e85c02a2b26fd241aa46665249e6','bafc2cdb321700a701fbc340ab517f712bb773eaaeb4560f1f840d10c2dec717','highrisk-ten-source/recovered-four.json');

do $precheck$ begin
  if (select count(*) from _approved_h3_exact_lineage)<>10 then
    raise exception 'expected ten individually audited source pairs';
  end if;
  if exists (
    select 1 from _approved_h3_exact_lineage a
    left join public.chem_questions n on n.id=a.new_id
    left join public.chem_questions o on o.id=a.old_id
    left join app_private.chem_question_source_release_items ni
      on ni.release_id=a.new_release and ni.question_id=a.new_id
    left join app_private.chem_question_source_release_items oi
      on oi.release_id=a.old_release and oi.question_id=a.old_id
    where n.id is null or o.id is null
       or n.source_release_id is distinct from a.new_release
       or o.source_release_id is distinct from a.old_release
       or n.grade_band is distinct from '高三'
       or o.grade_band is distinct from '高三'
       or n.parent_source_item_key is distinct from o.source_item_key
       or n.skill_id is distinct from o.skill_id
       or n.concept_key is distinct from o.concept_key
       or ni.canonical_source_id is distinct from a.canonical
       or oi.canonical_source_id is distinct from a.canonical
       or n.source_info->>'locator' is distinct from a.new_locator
       or not app_private.chem_question_item_visual_reviewed(n.id)
       or not exists(select 1 from app_private.chem_question_delivery_holds h
                     where h.anchor_question_id=o.id and h.resolved_at is null)
       or not exists(select 1 from app_private.chem_teaching_ready_questions r where r.id=n.id)
       or exists(select 1 from app_private.chem_teaching_ready_questions r where r.id=o.id)
  ) then raise exception 'a pair lacks exact source, locator, review, or hold evidence'; end if;
  if exists (
    select 1 from _approved_h3_exact_lineage a
    join app_private.chem_question_assets asset on asset.question_id=a.new_id
    where asset.asset_kind in ('question_image','analysis_image')
      and encode(extensions.digest(decode(asset.payload_base64,'base64'),'sha256'),'hex')
        is distinct from asset.sha256
  ) then raise exception 'a revised image payload SHA does not match'; end if;
  if (select count(*) from app_private.chem_question_assets asset
      join _approved_h3_exact_lineage a on a.new_id=asset.question_id
      where asset.asset_kind in ('question_image','analysis_image'))<>20
  then raise exception 'each revised question requires both source images'; end if;
  if exists(select 1 from _approved_h3_exact_lineage a
            join app_private.chem_question_source_release_lineage l
              on l.release_id=a.new_release and l.question_id=a.new_id)
  then raise exception 'lineage already exists for a reviewed pair'; end if;
end $precheck$;

-- The original H1 trigger only permits staged target releases. This one-time
-- amendment authorizes INSERT for the ten audited active H3 target pairs only;
-- the trigger remains in force. PostgreSQL transactional DDL means no other
-- session observes the temporary function definition before original restore.
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
    if tg_op='INSERT' and exists (
      select 1 from pg_temp._approved_h3_exact_lineage a
      where a.new_release=new.release_id and a.new_id=new.question_id
        and a.old_release=new.previous_release_id
        and a.old_id=new.previous_question_id
    ) then return new; end if;
    raise exception 'question lineage may change only while the target release is staged';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$guard$;

insert into app_private.chem_question_source_release_lineage
  (release_id,question_id,previous_release_id,previous_question_id)
select new_release,new_id,old_release,old_id
from _approved_h3_exact_lineage;

do $postcheck$ begin
  if (select count(*) from _approved_h3_exact_lineage a
      join app_private.chem_question_source_release_lineage l
        on l.release_id=a.new_release and l.question_id=a.new_id
       and l.previous_release_id=a.old_release
       and l.previous_question_id=a.old_id)<>10
  then raise exception 'ten exact lineage links were not inserted'; end if;
end $postcheck$;

-- Restore the original, narrow staged-only mutation guard before commit.
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

select count(*) as audited_exact_links
from app_private.chem_question_source_release_lineage l
join _approved_h3_exact_lineage a
  on l.release_id=a.new_release and l.question_id=a.new_id
 and l.previous_release_id=a.old_release and l.previous_question_id=a.old_id;
commit;
