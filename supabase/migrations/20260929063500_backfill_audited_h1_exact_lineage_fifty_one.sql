-- One-time backfill of 51 individually source-checked High-1 original repairs.
-- The source pages and review evidence are recorded in the private
-- h1-active-release-exact-lineage-audit-20260929.json. A duplicate revision
-- of old 517 was held first; only the authoritative ready revision is linked.
begin;
lock table app_private.chem_question_source_release_lineage in access exclusive mode;
create temp table _h1_exact_lineage_candidate(
  release_id uuid not null, old_id text primary key, new_id text not null unique
) on commit drop;
insert into _h1_exact_lineage_candidate(release_id,old_id,new_id) values
('bf43a588-b144-4bb8-9f5c-e589a21d7f40'::uuid,'QH1R_20260908_269F4DAD5050CD8BC8FFEC57F0D19E06','QH1EXP29_269F4DAD5050CD8BC8FFEC57F0D19E06'),
('bf43a588-b144-4bb8-9f5c-e589a21d7f40'::uuid,'QH1R_20260908_2E58C31DC803D4759C0B9E70A50B9090','QH1EXP29_2E58C31DC803D4759C0B9E70A50B9090'),
('bf43a588-b144-4bb8-9f5c-e589a21d7f40'::uuid,'QH1R_20260908_4BE09C77545E0302F4B22934E3E5F27B','QH1EXP29_4BE09C77545E0302F4B22934E3E5F27B'),
('cf5c449e-42af-4c1a-a8cc-4a18d61004bd'::uuid,'QH1R_20260908_52B273A647500E5817D25EE0E896016D','QH1GAS29_52B273A647500E5817D25EE0E896016D'),
('cf5c449e-42af-4c1a-a8cc-4a18d61004bd'::uuid,'QH1R_20260908_C1769FA1A9D237D00A22E6ECBDFA3151','QH1GAS29_C1769FA1A9D237D00A22E6ECBDFA3151'),
('cf5c449e-42af-4c1a-a8cc-4a18d61004bd'::uuid,'QH1R_20260908_D8114C9E520184BA670A1F8B38831390','QH1GAS29_D8114C9E520184BA670A1F8B38831390'),
('cf5c449e-42af-4c1a-a8cc-4a18d61004bd'::uuid,'QH1R_20260908_00F680B68F924DA13EFF10BDE418AC7B','QH1GAS29_00F680B68F924DA13EFF10BDE418AC7B'),
('cf5c449e-42af-4c1a-a8cc-4a18d61004bd'::uuid,'QH1R_20260908_DB179B2C32E1A958166671DDB9646AB0','QH1GAS29_DB179B2C32E1A958166671DDB9646AB0'),
('d41a1a71-21f0-42e1-93dc-c78b5992c24f'::uuid,'QH1R_20260908_895BAA10515C8CBE971CFA8CED091C6E','QH1FIG29_895BAA10515C8CBE971CFA8CED091C6E'),
('d41a1a71-21f0-42e1-93dc-c78b5992c24f'::uuid,'QH1R_20260908_9DCB5B68AC5528191419CF3D641B260A','QH1FIG29_9DCB5B68AC5528191419CF3D641B260A'),
('8e514425-d6e3-44b8-9906-048079ef8aed'::uuid,'QH1R_20260908_33A83084F3AD6BED35EB57D6D04E09CD','QH1MC29_33A83084F3AD6BED35EB57D6D04E09CD'),
('8e514425-d6e3-44b8-9906-048079ef8aed'::uuid,'QH1R_20260908_517DE739C767A2DFC5C12C9761A95FBB','QH1MC29_517DE739C767A2DFC5C12C9761A95FBB'),
('6a1c58e4-f21a-4e74-8dac-98281c425538'::uuid,'QH1R_20260908_96DFDAF89A21A9BC0BA1174C7D972827','QH1PRIV29_96DFDAF89A21A9BC0BA1174C7D972827'),
('6a1c58e4-f21a-4e74-8dac-98281c425538'::uuid,'QH1R_20260908_A2D5208F9452E8E121836F35E440D948','QH1PRIV29_A2D5208F9452E8E121836F35E440D948'),
('e7893cfd-5f6c-4b24-a70b-ab63add275ca'::uuid,'QH1R_20260908_662789E266DD04D8E4AA160CDCFD441D','QH1PRIV29_662789E266DD04D8E4AA160CDCFD441D'),
('e7893cfd-5f6c-4b24-a70b-ab63add275ca'::uuid,'QH1R_20260908_A7B6D274AD194A8708E4619C38770DD2','QH1PRIV29_A7B6D274AD194A8708E4619C38770DD2'),
('e7893cfd-5f6c-4b24-a70b-ab63add275ca'::uuid,'QH1R_20260908_F2346CE64D2FC37236B50E5FF683E481','QH1PRIV29_F2346CE64D2FC37236B50E5FF683E481'),
('b5b27d89-7bfe-4c21-9b85-48d91b28a88f'::uuid,'QH1R_20260908_275ACE2176874557B593EE5BDDA3A758','QH1PRIV29_275ACE2176874557B593EE5BDDA3A758'),
('b5b27d89-7bfe-4c21-9b85-48d91b28a88f'::uuid,'QH1R_20260908_5F43F0612F9898CD99F4CEC9851AF2D4','QH1PRIV29_5F43F0612F9898CD99F4CEC9851AF2D4'),
('cec43192-578f-460c-8311-699c82a972da'::uuid,'QH1R_20260908_9A651FBECA3D92C2A9A60B1BCC001ABB','QH1HIST29_9A651FBECA3D92C2A9A60B1BCC001ABB'),
('cec43192-578f-460c-8311-699c82a972da'::uuid,'QH1R_20260908_2A7A8E0DF6D0C179A4DE4AB6ED5176AE','QH1HIST29_2A7A8E0DF6D0C179A4DE4AB6ED5176AE'),
('cec43192-578f-460c-8311-699c82a972da'::uuid,'QH1R_20260908_CC6EBE92A39F6E2F90F25657D4AB1901','QH1HIST29_CC6EBE92A39F6E2F90F25657D4AB1901'),
('a2f10da7-43fd-46d5-a85c-3a8fe36fc7fe'::uuid,'QH1R_20260908_11B9EB3D56FD8058B747EE101B5D8FF8','QH1LOC29_11B9EB3D56FD8058B747EE101B5D8FF8'),
('a2f10da7-43fd-46d5-a85c-3a8fe36fc7fe'::uuid,'QH1R_20260908_1A7E61815DE9AB947BF7D59206676CF1','QH1LOC29_1A7E61815DE9AB947BF7D59206676CF1'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_3D65712D5155D895F6C609EA79FF3328','QH1LEGACY29_3D65712D5155D895F6C609EA79FF3328'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_425FE55B28F93506C0D5EC3EA61A8E84','QH1LEGACY29_425FE55B28F93506C0D5EC3EA61A8E84'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_841A825A91F1220CDB57B0401DD6CBBA','QH1LEGACY29_841A825A91F1220CDB57B0401DD6CBBA'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_B029F695CCE12B6C00059054C5FF6F16','QH1LEGACY29_B029F695CCE12B6C00059054C5FF6F16'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_B4D8B8AFC0CD6A509589EDE4231F8B3C','QH1LEGACY29_B4D8B8AFC0CD6A509589EDE4231F8B3C'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_CE3A277A2802CB2DFD516D2BD73E805A','QH1LEGACY29_CE3A277A2802CB2DFD516D2BD73E805A'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_D5B4DE9AD191D5AC8B9A28C66F80FA9B','QH1LEGACY29_D5B4DE9AD191D5AC8B9A28C66F80FA9B'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_F0F3CBD305C78FDFECD077F4F05BF148','QH1LEGACY29_F0F3CBD305C78FDFECD077F4F05BF148'),
('48e8a858-7c40-49e3-95d0-60a86d568dc6'::uuid,'QH1R_20260908_FBCB4A9F5A77A512537AEF2DEFE1AFCC','QH1LEGACY29_FBCB4A9F5A77A512537AEF2DEFE1AFCC'),
('8b166245-06ba-4521-bbce-3006530508ca'::uuid,'QH1R_20260908_0CAD8F7C0C99D991B2380A4899FC9EB5','QH1PAST29_0CAD8F7C0C99D991B2380A4899FC9EB5'),
('8b166245-06ba-4521-bbce-3006530508ca'::uuid,'QH1R_20260908_0ECD58B993E32110BA7697DE01F17EE2','QH1PAST29_0ECD58B993E32110BA7697DE01F17EE2'),
('8b166245-06ba-4521-bbce-3006530508ca'::uuid,'QH1R_20260908_1E9A162E1D6A798FA20F851E55686D8C','QH1PAST29_1E9A162E1D6A798FA20F851E55686D8C'),
('8b166245-06ba-4521-bbce-3006530508ca'::uuid,'QH1R_20260908_5AA10D668660A779E7A050BD904DE095','QH1PAST29_5AA10D668660A779E7A050BD904DE095'),
('7f5b2f8e-449d-4c5f-a174-9d74193c9938'::uuid,'QH1R_20260908_C22571093696376F0461636763B08788','QH1OCR26_C22571093696376F0461636763B08788'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_55E5748E670F0FC7517B28393FD393D3','QH1OCR29_55E5748E670F0FC7517B28393FD393D3'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_ABC3F530D01893243CDF1C16388B3EA2','QH1OCR29_ABC3F530D01893243CDF1C16388B3EA2'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_C0E17AD20BC7122C57EA8CC497B06476','QH1OCR29_C0E17AD20BC7122C57EA8CC497B06476'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_D18930DBB87AF19C36506B9203573D27','QH1OCR29_D18930DBB87AF19C36506B9203573D27'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_3BFF3FF7BEC042AF0D139F7A37FB13EA','QH1OCR29_3BFF3FF7BEC042AF0D139F7A37FB13EA'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_A30651019D6281DA928E14294D9AEF43','QH1OCR29_A30651019D6281DA928E14294D9AEF43'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_F2EFE1B15663A8EE61231F677920813D','QH1OCR29_F2EFE1B15663A8EE61231F677920813D'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_A57D2A2E63BA278FE0ABEF8D70AB574B','QH1OCR29_A57D2A2E63BA278FE0ABEF8D70AB574B'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_A9E053A5675BEA72A21155E90A45CA8C','QH1OCR29_A9E053A5675BEA72A21155E90A45CA8C'),
('fdd64b7e-b481-405f-b270-81fa7442d2cc'::uuid,'QH1R_20260908_E25836BF9DD1FCD8A198C6635791E71D','QH1OCR29_E25836BF9DD1FCD8A198C6635791E71D'),
('a7b78f2a-d24e-4d26-9c50-96e4d9ec762e'::uuid,'QH1R_20260908_01BAFD119EDDF431F1748134EA9693CB','QH1SRC29_01BAFD119EDDF431F1748134EA9693CB'),
('a7b78f2a-d24e-4d26-9c50-96e4d9ec762e'::uuid,'QH1R_20260908_6CFC06F5FFBFA2E331A212B245B81EB6','QH1SRC29_6CFC06F5FFBFA2E331A212B245B81EB6'),
('a7b78f2a-d24e-4d26-9c50-96e4d9ec762e'::uuid,'QH1R_20260908_7759FF55FF4FF0D0E48B6E3C77746770','QH1SRC29_7759FF55FF4FF0D0E48B6E3C77746770');
do $guard$ begin
 if (select count(*) from _h1_exact_lineage_candidate)<>51
 then raise exception 'expected 51 exact H1 candidates'; end if;
 if exists(
   select 1 from _h1_exact_lineage_candidate m
   left join public.chem_questions old_q on old_q.id=m.old_id
   left join public.chem_questions new_q on new_q.id=m.new_id
   left join app_private.chem_question_source_releases release on release.id=m.release_id
   left join app_private.chem_question_source_release_items old_item
     on old_item.release_id=old_q.source_release_id and old_item.question_id=old_q.id
   left join app_private.chem_question_source_release_items new_item
     on new_item.release_id=new_q.source_release_id and new_item.question_id=new_q.id
   where old_q.id is null or new_q.id is null or release.id is null
     or release.status<>'active' or release.release_kind<>'teaching_material'
     or new_q.source_release_id is distinct from m.release_id
     or old_q.source_release_id=new_q.source_release_id
     or old_q.grade_band<>'高一' or new_q.grade_band<>'高一'
     or new_q.parent_source_item_key is distinct from old_q.source_item_key
     or old_q.correct_option is distinct from new_q.correct_option
     or old_item.canonical_source_id is null
     or old_item.canonical_source_id is distinct from new_item.canonical_source_id
     or not exists(select 1 from app_private.chem_question_delivery_holds h
       where h.anchor_question_id=old_q.id and h.resolved_at is null)
     or exists(select 1 from app_private.chem_teaching_ready_questions ready_old
       where ready_old.id=old_q.id)
     or not exists(select 1 from app_private.chem_teaching_ready_questions ready_new
       where ready_new.id=new_q.id)
     or not app_private.chem_question_item_visual_reviewed(new_q.id)
 ) then raise exception 'one or more source-lineage QA predicates failed'; end if;
 if exists(select 1 from app_private.chem_question_source_release_lineage l
   join _h1_exact_lineage_candidate m on m.release_id=l.release_id and m.new_id=l.question_id)
 then raise exception 'lineage already present; recalculate expected inserts'; end if;
 if exists(select 1 from app_private.chem_h1_source_release_revision_items h
   join _h1_exact_lineage_candidate m on m.release_id=h.release_id and m.new_id=h.question_id)
 then raise exception 'H1 revision item already present; recalculate expected inserts'; end if;
 if exists(select 1 from app_private.chem_teaching_ready_questions
   where id='QH1OCR26_517DE739C767A2DFC5C12C9761A95FBB')
 then raise exception 'duplicate 517 revision must remain held'; end if;
end $guard$;
select 51::integer expected_insert_rows,count(*) candidate_rows,
       count(distinct release_id) target_releases,
       count(distinct old_id) unique_old_questions,
       count(distinct new_id) unique_new_questions
from _h1_exact_lineage_candidate;

-- The original guard permits only staged releases. Transactional DDL extends
-- it for this exact allowlist only; no other session sees the temporary rule.
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
      select 1 from pg_temp._h1_exact_lineage_candidate candidate
      join public.chem_questions old_question on old_question.id=candidate.old_id
      where candidate.release_id=new.release_id
        and candidate.new_id=new.question_id
        and candidate.old_id=new.previous_question_id
        and old_question.source_release_id=new.previous_release_id
    ) then return new; end if;
    raise exception 'question lineage may change only while the target release is staged';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$backfill_guard$;

insert into app_private.chem_question_source_release_lineage
  (release_id,question_id,previous_release_id,previous_question_id)
select candidate.release_id,candidate.new_id,old_question.source_release_id,candidate.old_id
from _h1_exact_lineage_candidate candidate
join public.chem_questions old_question on old_question.id=candidate.old_id;

do $postcheck$ begin
  if (select count(*)
      from _h1_exact_lineage_candidate candidate
      join public.chem_questions old_question on old_question.id=candidate.old_id
      join app_private.chem_question_source_release_lineage link
        on link.release_id=candidate.release_id
       and link.question_id=candidate.new_id
       and link.previous_release_id=old_question.source_release_id
       and link.previous_question_id=candidate.old_id)<>51
  then raise exception '51 exact High-1 lineage links were not inserted'; end if;
end $postcheck$;

-- Restore the staged-only guard before commit.
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

commit;
