-- Complete verified High-1 explanation revisions. Ordinary 175+added expansion stays unchanged.
create table app_private.chem_h1_source_release_revisions (
 release_id uuid primary key references app_private.chem_question_source_releases(id),
 base_release_id uuid not null references app_private.chem_question_source_releases(id),
 base_manifest_sha256 text not null check(base_manifest_sha256 ~ '^[0-9a-f]{64}$'),
 expected_question_count integer not null check(expected_question_count=264),
 expected_correction_count integer not null check(expected_correction_count=2),
 review_reason text not null check(length(btrim(review_reason))>=20),
 created_at timestamptz not null default now(),
 check(release_id<>base_release_id)
);
create table app_private.chem_h1_source_release_revision_items (
 release_id uuid not null references app_private.chem_h1_source_release_revisions(release_id),
 question_id text not null references public.chem_questions(id),
 previous_question_id text not null references public.chem_questions(id),
 primary key(release_id,question_id),unique(release_id,previous_question_id),
 check(question_id<>previous_question_id)
);
create table app_private.chem_h1_source_release_revision_changes (
 release_id uuid not null references app_private.chem_h1_source_release_revisions(release_id),
 previous_question_id text not null references public.chem_questions(id),
 old_explanation_sha256 text not null check(old_explanation_sha256 ~ '^[0-9a-f]{64}$'),
 new_explanation_sha256 text not null check(new_explanation_sha256 ~ '^[0-9a-f]{64}$'),
 old_analysis_sha256 text not null check(old_analysis_sha256 ~ '^[0-9a-f]{64}$'),
 new_analysis_sha256 text not null check(new_analysis_sha256 ~ '^[0-9a-f]{64}$'),
 reason text not null check(length(btrim(reason))>=20),
 primary key(release_id,previous_question_id),
 foreign key(release_id,previous_question_id) references app_private.chem_h1_source_release_revision_items(release_id,previous_question_id),
 check(old_explanation_sha256<>new_explanation_sha256),
 check(old_analysis_sha256<>new_analysis_sha256)
);
alter table app_private.chem_h1_source_release_revisions enable row level security;
alter table app_private.chem_h1_source_release_revision_items enable row level security;
alter table app_private.chem_h1_source_release_revision_changes enable row level security;
revoke all on app_private.chem_h1_source_release_revisions,app_private.chem_h1_source_release_revision_items,app_private.chem_h1_source_release_revision_changes from public,anon,authenticated,service_role;

create function app_private.chem_guard_h1_source_revision_mutation()
returns trigger language plpgsql set search_path='' as $guard$
declare v_release uuid; v_status text; v_verification text;
begin
 v_release:=case when TG_OP='DELETE' then OLD.release_id else NEW.release_id end;
 if TG_OP='UPDATE' and NEW.release_id is distinct from OLD.release_id then raise exception 'revision registration cannot move releases'; end if;
 select status,verification_status into v_status,v_verification
 from app_private.chem_question_source_releases where id=v_release for share;
 if not found or v_status<>'staged' or v_verification<>'pending' then raise exception 'revision registration is mutable only while staged and pending'; end if;
 if TG_OP='DELETE' then return OLD; end if;
 return NEW;
end;$guard$;
create trigger chem_guard_h1_revision_registry before insert or update or delete on app_private.chem_h1_source_release_revisions for each row execute function app_private.chem_guard_h1_source_revision_mutation();
create trigger chem_guard_h1_revision_items before insert or update or delete on app_private.chem_h1_source_release_revision_items for each row execute function app_private.chem_guard_h1_source_revision_mutation();
create trigger chem_guard_h1_revision_changes before insert or update or delete on app_private.chem_h1_source_release_revision_changes for each row execute function app_private.chem_guard_h1_source_revision_mutation();

create function app_private.chem_assert_h1_source_revision(p_release_id uuid)
returns void language plpgsql set search_path='' as $revision$
declare v app_private.chem_h1_source_release_revisions%rowtype; n integer;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
 select * into v from app_private.chem_h1_source_release_revisions where release_id=p_release_id for update;
 if not found then raise exception 'High-1 revision registration missing'; end if;
 if not exists(select 1 from app_private.chem_question_source_releases b join app_private.chem_question_source_releases t on t.id=v.release_id
 where b.id=v.base_release_id and b.status='active' and b.grade_band='高一' and b.expected_question_count=v.expected_question_count
 and b.manifest_sha256=v.base_manifest_sha256 and b.verification_status='full_visual_verified' and b.verification_manifest_sha256=b.manifest_sha256
 and b.revision_contract='v2_explanation_assets' and t.grade_band='高一' and t.status='staged'
 and t.expected_question_count=v.expected_question_count and t.revision_contract='v2_explanation_assets') then
 raise exception 'revision must inherit the current complete verified 264-question High-1 release';end if;
 perform id from app_private.chem_question_source_releases where id=v.base_release_id for update;
 perform question_id from app_private.chem_h1_source_release_revision_items where release_id=p_release_id order by question_id for update;
 perform previous_question_id from app_private.chem_h1_source_release_revision_changes where release_id=p_release_id order by previous_question_id for update;
 if exists(select 1 from app_private.chem_question_source_release_extensions where release_id=p_release_id)
 or exists(select 1 from app_private.chem_question_source_release_lineage where release_id=p_release_id) then
 raise exception 'revision and ordinary expansion lineage cannot be mixed';end if;
 if (select count(*) from public.chem_questions where source_release_id=v.base_release_id)<>264
 or (select count(*) from public.chem_questions where source_release_id=p_release_id)<>264
 or (select count(*) from app_private.chem_h1_source_release_revision_items where release_id=p_release_id)<>264
 or (select count(*) from app_private.chem_h1_source_release_revision_changes where release_id=p_release_id)<>2 then
 raise exception 'revision must cover exactly 264 source questions with exactly 2 registered corrections';end if;
 select count(*) into n from app_private.chem_h1_source_release_revision_items l
 join public.chem_questions o on o.id=l.previous_question_id and o.source_release_id=v.base_release_id
 join public.chem_questions q on q.id=l.question_id and q.source_release_id=p_release_id
 join app_private.chem_question_source_release_items oi on oi.release_id=v.base_release_id and oi.question_id=o.id
 join app_private.chem_question_source_release_items qi on qi.release_id=p_release_id and qi.question_id=q.id
 where l.release_id=p_release_id;
 if n<>264 then raise exception 'revision lineage is incomplete or crosses a source release';end if;
 if exists(
 select 1 from app_private.chem_h1_source_release_revision_items l
 join public.chem_questions o on o.id=l.previous_question_id
 join public.chem_questions q on q.id=l.question_id
 join app_private.chem_question_source_release_items oi on oi.release_id=v.base_release_id and oi.question_id=o.id
 join app_private.chem_question_source_release_items qi on qi.release_id=p_release_id and qi.question_id=q.id
 where l.release_id=p_release_id and (
 (to_jsonb(q)-array['id','created_at','updated_at','source_release_id','usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','explanation','asset_refs','question_revision_token'])
 is distinct from (to_jsonb(o)-array['id','created_at','updated_at','source_release_id','usable_for_review','usable_for_class_quiz','usable_for_exam_sprint','usable_for_demo','explanation','asset_refs','question_revision_token'])
 or qi.canonical_source_id is distinct from oi.canonical_source_id
 or qi.question_asset_sha256 is distinct from oi.question_asset_sha256
 or (select r-'path' from jsonb_array_elements(q.asset_refs) r where r->>'kind'='question_image') is distinct from
    (select r-'path' from jsonb_array_elements(o.asset_refs) r where r->>'kind'='question_image')
 )) then raise exception 'revision changed original question, answer, identity, taxonomy, source metadata, or question image';end if;
 if exists(
 select 1 from app_private.chem_h1_source_release_revision_items l
 join app_private.chem_question_assets oa on oa.question_id=l.previous_question_id and oa.asset_kind='question_image'
 join app_private.chem_question_assets qa on qa.question_id=l.question_id and qa.asset_kind='question_image'
 where l.release_id=p_release_id and (to_jsonb(oa)-array['asset_path','question_id','created_at','updated_at'])
 is distinct from (to_jsonb(qa)-array['asset_path','question_id','created_at','updated_at'])
 ) then raise exception 'revision changed original question image bytes or metadata';end if;
 if exists(
 select 1 from app_private.chem_h1_source_release_revision_items l
 join public.chem_questions o on o.id=l.previous_question_id join public.chem_questions q on q.id=l.question_id
 join app_private.chem_question_assets oa on oa.question_id=o.id and oa.asset_kind='analysis_image'
 join app_private.chem_question_assets qa on qa.question_id=q.id and qa.asset_kind='analysis_image'
 left join app_private.chem_h1_source_release_revision_changes c on c.release_id=l.release_id and c.previous_question_id=o.id
 where l.release_id=p_release_id and (
 (c.previous_question_id is null and (
 q.explanation is distinct from o.explanation
 or (to_jsonb(oa)-array['asset_path','question_id','created_at','updated_at']) is distinct from (to_jsonb(qa)-array['asset_path','question_id','created_at','updated_at'])
 or (select r-'path' from jsonb_array_elements(q.asset_refs) r where r->>'kind'='analysis_image') is distinct from (select r-'path' from jsonb_array_elements(o.asset_refs) r where r->>'kind'='analysis_image')
 ))
 or (c.previous_question_id is not null and (
 c.old_explanation_sha256<>encode(extensions.digest(convert_to(o.explanation,'UTF8'),'sha256'),'hex')
 or c.new_explanation_sha256<>encode(extensions.digest(convert_to(q.explanation,'UTF8'),'sha256'),'hex')
 or c.old_analysis_sha256<>oa.sha256 or c.new_analysis_sha256<>qa.sha256
 or qa.sha256<>encode(extensions.digest(decode(qa.payload_base64,'base64'),'sha256'),'hex')
 or (select r-array['path','sha256','width','height'] from jsonb_array_elements(q.asset_refs) r where r->>'kind'='analysis_image') is distinct from (select r-array['path','sha256','width','height'] from jsonb_array_elements(o.asset_refs) r where r->>'kind'='analysis_image')
 ))
 )) then raise exception 'revision exceeded the two exact registered explanation and analysis-image corrections';end if;
 if exists(select 1 from app_private.chem_question_answer_locks l join public.chem_questions q on q.id=l.question_id where q.source_release_id=v.base_release_id) then
 raise exception 'High-1 revision blocked by unfinished source answer locks';end if;
 -- Return only to the existing full asset/hash/manifest/grade/canonical/QA validator.
end;$revision$;
revoke all on function app_private.chem_guard_h1_source_revision_mutation() from public,anon,authenticated,service_role;
revoke all on function app_private.chem_assert_h1_source_revision(uuid) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION app_private.chem_assert_h1_expanded_release(p_release_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_base_release_id uuid;
  v_expected integer;
begin
  if exists(select 1 from app_private.chem_h1_source_release_revisions where release_id=p_release_id) then
    perform app_private.chem_assert_h1_source_revision(p_release_id);
    return;
  end if;
  select extension_row.base_release_id,target.expected_question_count
  into v_base_release_id,v_expected
  from app_private.chem_question_source_release_extensions extension_row
  join app_private.chem_question_source_releases target
    on target.id=extension_row.release_id
  join app_private.chem_question_source_releases base
    on base.id=extension_row.base_release_id
  where extension_row.release_id=p_release_id
    and target.grade_band='高一'
    and target.status='staged'
    and target.expected_question_count between 211 and 275
    and target.expected_question_count
        =extension_row.retained_question_count+extension_row.added_question_count
    and base.grade_band='高一'
    and base.status='active'
    and base.expected_question_count=175
    and base.verification_status='full_visual_verified'
    and base.verification_manifest_sha256=base.manifest_sha256;
  if not found then
    raise exception 'expanded High-1 release does not declare the active verified 175-question baseline';
  end if;
  if (
    select count(*) from app_private.chem_question_source_release_lineage lineage
    where lineage.release_id=p_release_id
      and lineage.previous_release_id=v_base_release_id
  )<>175 then
    raise exception 'expanded High-1 release must carry exactly 175 one-to-one lineage rows';
  end if;
  if exists (
    select 1
    from app_private.chem_question_source_release_lineage lineage
    join public.chem_questions old_q
      on old_q.id=lineage.previous_question_id
     and old_q.source_release_id=lineage.previous_release_id
    join public.chem_questions new_q
      on new_q.id=lineage.question_id
     and new_q.source_release_id=lineage.release_id
    join app_private.chem_question_source_release_items old_item
      on old_item.release_id=lineage.previous_release_id
     and old_item.question_id=old_q.id
    join app_private.chem_question_source_release_items new_item
      on new_item.release_id=lineage.release_id
     and new_item.question_id=new_q.id
    where lineage.release_id=p_release_id
      and (
        new_q.id=old_q.id
        or new_q.mother_id is distinct from old_q.mother_id
        or new_q.source_item_key is distinct from old_q.source_item_key
        or new_q.content_fingerprint is distinct from old_q.content_fingerprint
        or new_q.skill_id is distinct from old_q.skill_id
        or new_q.concept_key is distinct from old_q.concept_key
        or new_q.level is distinct from old_q.level
        or new_q.grade_band is distinct from old_q.grade_band
        or new_q.stem is distinct from old_q.stem
        or new_q.options is distinct from old_q.options
        or new_q.correct_option is distinct from old_q.correct_option
        or new_q.explanation is distinct from old_q.explanation
        or new_q.scaffold is distinct from old_q.scaffold
        or new_q.source_kind is distinct from old_q.source_kind
        or new_q.source_info is distinct from old_q.source_info
        or new_q.render_mode is distinct from old_q.render_mode
        or new_q.image_url is distinct from old_q.image_url
        or (
          select jsonb_agg(ref-'path' order by ref->>'kind')
          from jsonb_array_elements(new_q.asset_refs) ref
        ) is distinct from (
          select jsonb_agg(ref-'path' order by ref->>'kind')
          from jsonb_array_elements(old_q.asset_refs) ref
        )
        or new_item.canonical_source_id is distinct from old_item.canonical_source_id
        or new_item.question_asset_sha256 is distinct from old_item.question_asset_sha256
        or new_item.analysis_asset_sha256 is distinct from old_item.analysis_asset_sha256
      )
  ) then
    raise exception 'a retained High-1 original changed content, provenance, identity, or verified image bytes';
  end if;
  if exists (
    select 1
    from public.chem_questions added
    left join app_private.chem_question_source_release_lineage lineage
      on lineage.release_id=p_release_id and lineage.question_id=added.id
    join public.chem_questions old_q
      on old_q.grade_band='高一'
     and old_q.source_kind='licensed_local'
     and old_q.source_release_id is distinct from p_release_id
     and (
       added.id=old_q.id
       or added.mother_id=old_q.mother_id
       or added.source_item_key=old_q.source_item_key
       or added.content_fingerprint=old_q.content_fingerprint
     )
    where added.source_release_id=p_release_id
      and lineage.question_id is null
  ) then
    raise exception 'an added High-1 question collides with a prior four-part source identity';
  end if;
  if exists (
    select 1
    from app_private.chem_question_answer_locks answer_lock
    join public.chem_questions old_q on old_q.id=answer_lock.question_id
    where old_q.source_release_id=v_base_release_id
  ) then
    raise exception 'High-1 activation is blocked while a baseline question has an unfinished answer lock';
  end if;
end;
$function$;
