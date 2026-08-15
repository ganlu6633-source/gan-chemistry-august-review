-- Source-backed REVIEW questions keep their public-safe citation on the
-- question row, while exact source crops remain in a server-only table.
-- No browser role receives direct access to the binary payload.

create table if not exists app_private.chem_question_source_releases (
  id uuid primary key,
  manifest_sha256 text not null unique check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  grade_band text not null default '高三' check (grade_band = '高三'),
  status text not null default 'staged' check (status in ('staged','active','retired')),
  expected_question_count integer not null default 275 check (expected_question_count = 275),
  verification_status text not null default 'pending'
    check (verification_status in ('pending','full_visual_verified')),
  verification_manifest_sha256 text
    check (verification_manifest_sha256 is null or verification_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  verification_actor text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  retired_at timestamptz
);

alter table app_private.chem_question_source_releases enable row level security;
revoke all on table app_private.chem_question_source_releases from public, anon, authenticated, service_role;
create unique index if not exists chem_question_source_releases_one_active_h3_uidx
  on app_private.chem_question_source_releases(grade_band)
  where status = 'active';

-- One immutable ledger row per exact source item binds the release manifest to
-- the values that actually landed in Postgres.  The public question table does
-- not expose canonical source identifiers, while activation recomputes every
-- item digest from the real question row and both real binary asset digests.
create table if not exists app_private.chem_question_source_release_items (
  release_id uuid not null
    references app_private.chem_question_source_releases(id) on delete restrict,
  question_id text not null
    references public.chem_questions(id) on delete restrict,
  canonical_source_id text not null check (
    length(canonical_source_id) between 3 and 160
    and canonical_source_id ~ '^[A-Za-z0-9._:-]+$'
  ),
  question_asset_sha256 text not null check (question_asset_sha256 ~ '^[0-9a-f]{64}$'),
  analysis_asset_sha256 text not null check (analysis_asset_sha256 ~ '^[0-9a-f]{64}$'),
  item_sha256 text not null check (item_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (release_id, question_id),
  unique (release_id, canonical_source_id),
  unique (release_id, item_sha256)
);

alter table app_private.chem_question_source_release_items enable row level security;
revoke all on table app_private.chem_question_source_release_items from public, anon, authenticated, service_role;

alter table public.chem_questions
  add column if not exists source_info jsonb,
  add column if not exists asset_refs jsonb not null default '[]'::jsonb,
  add column if not exists render_mode text not null default 'native',
  add column if not exists source_item_key text,
  add column if not exists content_fingerprint text,
  add column if not exists question_revision_token text,
  add column if not exists source_release_id uuid,
  add column if not exists usable_for_demo boolean not null default false;

-- Public demo accounts must never enumerate the licensed High-3 source bank.
-- They retain a separate, teacher-authored demonstration pool; real students
-- and teacher previews of real students use the active source release instead.
update public.chem_questions
set usable_for_demo = true
where grade_band = '高三'
  and source_kind = 'teacher_original'
  and id like 'Q5R_H3_%';

alter table public.chem_questions
  drop constraint if exists chem_questions_source_release_fk,
  add constraint chem_questions_source_release_fk
    foreign key (source_release_id)
    references app_private.chem_question_source_releases(id)
    on delete restrict;

alter table public.chem_questions
  drop constraint if exists chem_questions_source_info_object,
  add constraint chem_questions_source_info_object
    check (source_info is null or jsonb_typeof(source_info) = 'object'),
  drop constraint if exists chem_questions_source_info_has_no_local_path,
  add constraint chem_questions_source_info_has_no_local_path check (
    source_info is null
    or source_info::text !~* '([a-z]:[\\/]|file:[\\/]|\\\\\\\\|/(users|home)/|appdata)'
  ),
  drop constraint if exists chem_questions_asset_refs_array,
  add constraint chem_questions_asset_refs_array
    check (jsonb_typeof(asset_refs) = 'array'),
  drop constraint if exists chem_questions_render_mode_check,
  add constraint chem_questions_render_mode_check
    check (render_mode in ('native','image_assist','image_primary')),
  drop constraint if exists chem_questions_revision_token_shape,
  add constraint chem_questions_revision_token_shape
    check (question_revision_token is null or question_revision_token ~ '^[0-9a-f]{64}$'),
  drop constraint if exists chem_questions_licensed_not_demo,
  add constraint chem_questions_licensed_not_demo
    check (source_kind <> 'licensed_local' or not usable_for_demo),
  drop constraint if exists chem_questions_licensed_local_provenance,
  add constraint chem_questions_licensed_local_provenance check (
    source_kind <> 'licensed_local'
    or (
      source_info is not null
      and length(btrim(coalesce(source_info->>'title', ''))) > 0
      and length(btrim(coalesce(source_info->>'exam', ''))) > 0
      and length(btrim(coalesce(source_info->>'questionNo', ''))) > 0
      and length(btrim(coalesce(source_info->>'locator', ''))) > 0
      and length(btrim(coalesce(source_item_key, ''))) >= 16
      and coalesce(content_fingerprint, '') ~ '^[0-9a-f]{64}$'
      and coalesce(question_revision_token, '') ~ '^[0-9a-f]{64}$'
      and (
        render_mode = 'native'
        or jsonb_array_length(asset_refs) > 0
      )
    )
  );

create unique index if not exists chem_questions_h3_review_original_source_item_uidx
  on public.chem_questions(source_item_key)
  where grade_band = '高三'
    and source_kind = 'licensed_local'
    and review_status = 'approved'
    and usable_for_review;

create unique index if not exists chem_questions_h3_review_original_fingerprint_uidx
  on public.chem_questions(content_fingerprint)
  where grade_band = '高三'
    and source_kind = 'licensed_local'
    and review_status = 'approved'
    and usable_for_review;

create unique index if not exists chem_questions_h3_review_original_mother_uidx
  on public.chem_questions(mother_id)
  where grade_band = '高三'
    and source_kind = 'licensed_local'
    and review_status = 'approved'
    and usable_for_review;

create table if not exists app_private.chem_question_assets (
  asset_path text primary key,
  question_id text not null references public.chem_questions(id) on delete restrict,
  asset_kind text not null check (asset_kind in ('question_image','formula_fallback','source_scan','analysis_image')),
  mime_type text not null check (mime_type in ('image/png','image/jpeg','image/webp')),
  payload_base64 text not null check (
    length(payload_base64) between 16 and 4000000
    and payload_base64 ~ '^[A-Za-z0-9+/]+={0,2}$'
  ),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  width integer not null check (width between 1 and 6000),
  height integer not null check (height between 1 and 12000),
  created_at timestamptz not null default now(),
  unique (question_id, sha256)
);

create index if not exists chem_question_assets_question_idx
  on app_private.chem_question_assets(question_id);

alter table app_private.chem_question_assets enable row level security;
revoke all on table app_private.chem_question_assets from public, anon, authenticated, service_role;

create or replace function app_private.chem_release_manifest_field(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.length(coalesce(p_value, ''))::text
    || ':' || coalesce(p_value, '');
$$;

-- Duplicate detection is semantic: normalize the transcribed stem/options,
-- but never mix a crop hash into the content fingerprint.  The explicit
-- whitespace set mirrors build_private_release.py exactly and avoids
-- locale-dependent regular-expression behaviour.
create or replace function app_private.chem_h3_normalized_content_text(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.replace(
    pg_catalog.replace(
      pg_catalog.translate(
        coalesce(p_value, ''),
        ' '
          || pg_catalog.chr(9)
          || pg_catalog.chr(10)
          || pg_catalog.chr(11)
          || pg_catalog.chr(12)
          || pg_catalog.chr(13)
          || pg_catalog.chr(160)
          || pg_catalog.chr(12288),
        ''
      ),
      pg_catalog.chr(61480),
      '('
    ),
    pg_catalog.chr(61481),
    ')'
  );
$$;

create or replace function app_private.chem_h3_content_fingerprint(
  p_stem text,
  p_options jsonb
)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        app_private.chem_release_manifest_field(
          app_private.chem_h3_normalized_content_text(p_stem)
        )
        || app_private.chem_release_manifest_field(
          app_private.chem_h3_normalized_content_text(p_options->>0)
        )
        || app_private.chem_release_manifest_field(
          app_private.chem_h3_normalized_content_text(p_options->>1)
        )
        || app_private.chem_release_manifest_field(
          app_private.chem_h3_normalized_content_text(p_options->>2)
        )
        || app_private.chem_release_manifest_field(
          app_private.chem_h3_normalized_content_text(p_options->>3)
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

-- The browser receives this revision token, not the semantic fingerprint.
-- Re-cropping either source image or changing any rendering descriptor creates
-- a new token, so an already-open question fails closed with HTTP 409.
create or replace function app_private.chem_h3_question_revision_sha256(
  p_question public.chem_questions,
  p_question_asset_sha256 text,
  p_analysis_asset_sha256 text
)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        app_private.chem_release_manifest_field(p_question.content_fingerprint)
        || app_private.chem_release_manifest_field(p_question.render_mode)
        || app_private.chem_release_manifest_field((
          select ref->>'kind' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'path' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'alt' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'width' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'height' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field(p_question_asset_sha256)
        || app_private.chem_release_manifest_field((
          select ref->>'kind' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'path' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'alt' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'width' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'height' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field(p_analysis_asset_sha256),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function app_private.chem_h3_release_item_sha256(
  p_question public.chem_questions,
  p_canonical_source_id text,
  p_question_asset_sha256 text,
  p_analysis_asset_sha256 text
)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        app_private.chem_release_manifest_field(p_question.id)
        || app_private.chem_release_manifest_field(p_question.mother_id)
        || app_private.chem_release_manifest_field(p_question.skill_id)
        || app_private.chem_release_manifest_field(p_question.concept_key)
        || app_private.chem_release_manifest_field(p_question.level::text)
        || app_private.chem_release_manifest_field(p_question.grade_band)
        || app_private.chem_release_manifest_field(p_question.stem)
        || app_private.chem_release_manifest_field(p_question.options->>0)
        || app_private.chem_release_manifest_field(p_question.options->>1)
        || app_private.chem_release_manifest_field(p_question.options->>2)
        || app_private.chem_release_manifest_field(p_question.options->>3)
        || app_private.chem_release_manifest_field(p_question.correct_option::text)
        || app_private.chem_release_manifest_field(p_question.explanation)
        || app_private.chem_release_manifest_field(p_question.scaffold)
        || app_private.chem_release_manifest_field(p_question.source_kind)
        || app_private.chem_release_manifest_field(p_question.render_mode)
        || app_private.chem_release_manifest_field(p_question.source_item_key)
        || app_private.chem_release_manifest_field(p_question.content_fingerprint)
        || app_private.chem_release_manifest_field(p_question.question_revision_token)
        || app_private.chem_release_manifest_field(p_question.source_info->>'title')
        || app_private.chem_release_manifest_field(p_question.source_info->>'exam')
        || app_private.chem_release_manifest_field(p_question.source_info->>'questionNo')
        || app_private.chem_release_manifest_field(p_question.source_info->>'locator')
        || app_private.chem_release_manifest_field(p_question.source_info->>'year')
        || app_private.chem_release_manifest_field(p_question.source_info->>'conceptLabel')
        || app_private.chem_release_manifest_field(p_question.source_info->>'sourceMarkerStyle')
        || app_private.chem_release_manifest_field(p_question.source_info->>'transcriptionPolicy')
        || app_private.chem_release_manifest_field(p_question.source_info->>'optionTranscriptionPolicy')
        || app_private.chem_release_manifest_field(p_question.source_info->>'transcriptionAuditMethod')
        || app_private.chem_release_manifest_field(p_question.source_info->>'sourcePairingStatus')
        || app_private.chem_release_manifest_field(p_question.source_info->>'sourceMarkerLabel')
        || app_private.chem_release_manifest_field((
          select ref->>'path' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'alt' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'width' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'height' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'question_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'path' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'alt' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'width' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field((
          select ref->>'height' from pg_catalog.jsonb_array_elements(p_question.asset_refs) ref
          where ref->>'kind' = 'analysis_image'
        ))
        || app_private.chem_release_manifest_field(p_canonical_source_id)
        || app_private.chem_release_manifest_field(p_question_asset_sha256)
        || app_private.chem_release_manifest_field(p_analysis_asset_sha256),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function app_private.chem_release_manifest_field(text) from public, anon, authenticated, service_role;
revoke all on function app_private.chem_h3_normalized_content_text(text) from public, anon, authenticated, service_role;
revoke all on function app_private.chem_h3_content_fingerprint(text,jsonb) from public, anon, authenticated, service_role;
revoke all on function app_private.chem_h3_question_revision_sha256(public.chem_questions,text,text) from public, anon, authenticated, service_role;
revoke all on function app_private.chem_h3_release_item_sha256(public.chem_questions,text,text,text) from public, anon, authenticated, service_role;

create or replace function app_private.chem_guard_source_asset_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_question_id text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if tg_op = 'UPDATE' and (
    new.question_id is distinct from old.question_id
    or new.asset_path is distinct from old.asset_path
  ) then
    raise exception 'source asset identity cannot be changed; insert a new staged asset instead';
  end if;
  v_question_id := case when tg_op = 'INSERT' then new.question_id else old.question_id end;
  if exists (
    select 1
    from public.chem_attempt_answers aa
    where aa.question_id = v_question_id
  ) or exists (
    select 1
    from public.chem_questions q
    join app_private.chem_question_source_releases r on r.id = q.source_release_id
    where q.id = v_question_id and r.status in ('active','retired')
  ) then
    raise exception 'source assets become immutable after release activation or student use';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists chem_question_assets_guard_update on app_private.chem_question_assets;
create trigger chem_question_assets_guard_update
before insert or update or delete on app_private.chem_question_assets
for each row execute function app_private.chem_guard_source_asset_mutation();

create or replace function app_private.chem_guard_source_question_content_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_source_kind text := case when tg_op = 'INSERT' then new.source_kind else old.source_kind end;
  v_release_id uuid := case when tg_op = 'INSERT' then new.source_release_id else old.source_release_id end;
  v_question_id text := case when tg_op = 'INSERT' then new.id else old.id end;
  v_touches_source_identity boolean := case
    when tg_op = 'INSERT' then new.source_kind = 'licensed_local' or new.source_release_id is not null
    when tg_op = 'DELETE' then old.source_kind = 'licensed_local' or old.source_release_id is not null
    else old.source_kind = 'licensed_local'
      or new.source_kind = 'licensed_local'
      or old.source_release_id is not null
      or new.source_release_id is not null
  end;
begin
  if v_touches_source_identity then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
    if tg_op = 'UPDATE' and (
      new.id is distinct from old.id
      or new.source_kind is distinct from old.source_kind
      or new.source_release_id is distinct from old.source_release_id
    ) then
      raise exception 'source question identity cannot be changed; insert a new staged revision instead';
    end if;
    if tg_op = 'INSERT' and (
      new.source_kind <> 'licensed_local'
      or new.source_release_id is null
      or not exists (
      select 1
      from app_private.chem_question_source_releases r
      where r.id = v_release_id and r.status = 'staged'
      )
    ) then
      raise exception 'source-backed questions can only be inserted into a staged release';
    end if;
    if tg_op <> 'INSERT' and (
      exists (
        select 1 from public.chem_attempt_answers aa where aa.question_id = v_question_id
      )
      or exists (
        select 1
        from app_private.chem_question_source_releases r
        where r.id = v_release_id and r.status in ('active','retired')
      )
    ) then
      raise exception 'an activated or answered source-backed question is immutable; create a new revision instead';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists chem_questions_guard_source_content_update on public.chem_questions;
create trigger chem_questions_guard_source_content_update
before update of id,mother_id,skill_id,concept_key,level,grade_band,stem,options,correct_option,
  explanation,scaffold,source_kind,source_info,asset_refs,render_mode,source_item_key,
  content_fingerprint,question_revision_token,source_release_id
on public.chem_questions
for each row execute function app_private.chem_guard_source_question_content_mutation();

drop trigger if exists chem_questions_guard_source_insert on public.chem_questions;
create trigger chem_questions_guard_source_insert
before insert on public.chem_questions
for each row execute function app_private.chem_guard_source_question_content_mutation();

drop trigger if exists chem_questions_guard_source_delete on public.chem_questions;
create trigger chem_questions_guard_source_delete
before delete on public.chem_questions
for each row execute function app_private.chem_guard_source_question_content_mutation();

revoke all on function app_private.chem_guard_source_asset_mutation() from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_source_question_content_mutation() from public, anon, authenticated, service_role;

create or replace function app_private.chem_guard_release_item_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_release_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if tg_op = 'UPDATE' and (
    new.release_id is distinct from old.release_id
    or new.question_id is distinct from old.question_id
  ) then
    raise exception 'release ledger identity cannot be changed';
  end if;
  v_release_id := case when tg_op = 'INSERT' then new.release_id else old.release_id end;
  if not exists (
    select 1
    from app_private.chem_question_source_releases r
    where r.id = v_release_id and r.status = 'staged'
  ) then
    raise exception 'release ledger items can only be changed while the release is staged';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists chem_question_release_items_guard_mutation on app_private.chem_question_source_release_items;
create trigger chem_question_release_items_guard_mutation
before insert or update or delete on app_private.chem_question_source_release_items
for each row execute function app_private.chem_guard_release_item_mutation();

revoke all on function app_private.chem_guard_release_item_mutation() from public, anon, authenticated, service_role;

create or replace function app_private.chem_guard_active_source_question_eligibility()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.source_release_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  end if;
  if old.source_release_id is not null
    and coalesce(pg_catalog.current_setting('app.chem_release_activation', true), '') <> 'on'
    and exists (
      select 1
      from app_private.chem_question_source_releases r
      where r.id = old.source_release_id and r.status in ('active','retired')
    )
  then
    raise exception 'active source releases cannot be edited one question at a time; activate a complete new release';
  end if;
  return new;
end;
$$;

drop trigger if exists chem_questions_guard_active_source_eligibility on public.chem_questions;
create trigger chem_questions_guard_active_source_eligibility
before update of review_status,scope_status,usable_for_review,usable_for_class_quiz,usable_for_exam_sprint,usable_for_demo
on public.chem_questions
for each row execute function app_private.chem_guard_active_source_question_eligibility();

revoke all on function app_private.chem_guard_active_source_question_eligibility() from public, anon, authenticated, service_role;

create or replace function public.chem_get_question_assets(p_asset_paths text[])
returns table (
  asset_path text,
  question_id text,
  asset_kind text,
  mime_type text,
  payload_base64 text,
  sha256 text,
  width integer,
  height integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(array_length(p_asset_paths, 1), 0) not between 1 and 20 then
    raise exception 'asset request must contain between 1 and 20 paths';
  end if;
  if exists (
    select 1 from unnest(p_asset_paths) p
    where length(p) not between 16 and 200 or p !~ '^[a-zA-Z0-9/_-]+$'
  ) then
    raise exception 'invalid asset path';
  end if;

  return query
  select
    a.asset_path,
    a.question_id,
    a.asset_kind,
    a.mime_type,
    a.payload_base64,
    a.sha256,
    a.width,
    a.height
  from app_private.chem_question_assets a
  where a.asset_path = any(p_asset_paths);
end;
$$;

revoke all on function public.chem_get_question_assets(text[]) from public, anon, authenticated;
grant execute on function public.chem_get_question_assets(text[]) to service_role;

-- A licensed High-3 question is issued without its answer.  The Edge Function
-- atomically records the student's first selection before returning feedback.
-- Keeping this in app_private prevents browser roles from reading, changing or
-- pre-seeding another student's locked answer through the Data API.
create table if not exists app_private.chem_question_answer_locks (
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  plan_day_id uuid not null references public.chem_learning_plans(id) on delete cascade,
  attempt_sequence integer not null check (attempt_sequence between 0 and 7),
  question_id text not null references public.chem_questions(id) on delete restrict,
  selected_option smallint not null check (selected_option between 0 and 9),
  uncertain boolean not null default false,
  duration_sec integer not null default 0 check (duration_sec between 0 and 3600),
  revision_token text check (revision_token is null or revision_token ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (student_id, plan_day_id, attempt_sequence, question_id)
);

create index if not exists chem_question_answer_locks_plan_idx
  on app_private.chem_question_answer_locks(student_id, plan_day_id, attempt_sequence);

alter table app_private.chem_question_answer_locks enable row level security;
revoke all on table app_private.chem_question_answer_locks from public, anon, authenticated, service_role;

create or replace function public.chem_lock_question_answer(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_id text,
  p_selected_option integer,
  p_uncertain boolean,
  p_duration_sec integer,
  p_revision_token text
)
returns table (
  selected_option integer,
  uncertain boolean,
  duration_sec integer,
  revision_token text,
  created_at timestamptz,
  is_new boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer := 0;
begin
  if p_student_id is null
    or p_plan_day_id is null
    or p_attempt_sequence is null
    or p_attempt_sequence not between 0 and 7
    or length(coalesce(p_question_id, '')) not between 1 and 160
    or p_selected_option is null
    or p_selected_option not between 0 and 9
    or p_duration_sec is null
    or p_duration_sec not between 0 and 3600
  then
    raise exception 'invalid answer lock request';
  end if;

  if not exists (
    select 1
    from public.chem_learning_plans p
    where p.id = p_plan_day_id
      and p.student_id = p_student_id
  ) then
    raise exception 'plan does not belong to student';
  end if;

  if not exists (
    select 1
    from public.chem_questions q
    where q.id = p_question_id
      and q.grade_band = '高三'
      and q.source_kind = 'licensed_local'
      and q.review_status = 'approved'
      and q.scope_status = 'IN'
      and q.usable_for_review
      and q.question_revision_token is not distinct from nullif(p_revision_token, '')
  ) then
    raise exception 'question revision is stale or not eligible for an answer lock';
  end if;

  insert into app_private.chem_question_answer_locks (
    student_id,
    plan_day_id,
    attempt_sequence,
    question_id,
    selected_option,
    uncertain,
    duration_sec,
    revision_token
  ) values (
    p_student_id,
    p_plan_day_id,
    p_attempt_sequence,
    p_question_id,
    p_selected_option,
    coalesce(p_uncertain, false),
    p_duration_sec,
    nullif(p_revision_token, '')
  )
  on conflict (student_id, plan_day_id, attempt_sequence, question_id) do nothing;
  get diagnostics v_inserted = row_count;

  return query
  select
    l.selected_option::integer,
    l.uncertain,
    l.duration_sec,
    l.revision_token,
    l.created_at,
    v_inserted = 1
  from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_attempt_sequence
    and l.question_id = p_question_id;
end;
$$;

create or replace function public.chem_get_question_answer_locks(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_ids text[]
)
returns table (
  question_id text,
  selected_option integer,
  uncertain boolean,
  duration_sec integer,
  revision_token text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_student_id is null
    or p_plan_day_id is null
    or p_attempt_sequence is null
    or p_attempt_sequence not between 0 and 7
    or coalesce(array_length(p_question_ids, 1), 0) not between 1 and 10
  then
    raise exception 'invalid answer lock lookup';
  end if;

  return query
  select
    l.question_id,
    l.selected_option::integer,
    l.uncertain,
    l.duration_sec,
    l.revision_token,
    l.created_at
  from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_attempt_sequence
    and l.question_id = any(p_question_ids);
end;
$$;

create or replace function public.chem_delete_question_answer_locks(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_attempt_sequence;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.chem_has_current_question_answer_lock(
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_sequence integer,
  p_question_id text,
  p_revision_token text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from app_private.chem_question_answer_locks l
    join public.chem_learning_plans p
      on p.id = l.plan_day_id
     and p.student_id = l.student_id
    where l.student_id = p_student_id
      and l.plan_day_id = p_plan_day_id
      and l.attempt_sequence = p_attempt_sequence
      and l.question_id = p_question_id
      and l.revision_token is not distinct from nullif(p_revision_token, '')
      and l.attempt_sequence = (
        select count(*)::integer
        from public.chem_learning_attempts a
        where a.student_id = l.student_id
          and a.plan_day_id = l.plan_day_id
      )
  );
$$;

-- Finalizing a learning round is one database transaction.  The Edge
-- Function still recomputes and validates the exact server-issued question
-- set, but a process interruption can no longer leave an attempt without all
-- answers, mismatched skill state, or uncleared first-answer locks.
create or replace function public.chem_finalize_learning_attempt(
  p_attempt_id uuid,
  p_student_id uuid,
  p_plan_day_id uuid,
  p_attempt_kind text,
  p_sequence integer,
  p_mode text,
  p_started_at timestamptz,
  p_completed_at timestamptz,
  p_first_score integer,
  p_answers jsonb,
  p_skill_states jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_answer_count integer;
  v_correct_count integer;
  v_current_sequence integer;
  v_inserted_answers integer;
  v_inserted_states integer;
begin
  if p_attempt_id is null
    or p_student_id is null
    or p_plan_day_id is null
    or p_attempt_kind not in ('scheduled', 'review')
    or p_sequence is null
    or p_sequence not between 0 and 7
    or p_mode not in ('REVIEW', 'CLASS_QUIZ', 'EXAM_SPRINT')
    or p_started_at is null
    or p_completed_at is null
    or p_completed_at < p_started_at
    or jsonb_typeof(p_answers) <> 'array'
    or jsonb_typeof(p_skill_states) <> 'array'
  then
    raise exception 'invalid learning attempt finalization request';
  end if;

  v_answer_count := jsonb_array_length(p_answers);
  if v_answer_count not between 1 and 10
    or jsonb_array_length(p_skill_states) not between 1 and 10
    or p_first_score not between 0 and v_answer_count
  then
    raise exception 'invalid learning attempt finalization cardinality';
  end if;

  if not exists (
    select 1
    from public.chem_learning_plans p
    where p.id = p_plan_day_id
      and p.student_id = p_student_id
      and p.mode = p_mode
  ) then
    raise exception 'plan does not belong to student or mode';
  end if;

  select count(*)::integer
  into v_current_sequence
  from public.chem_learning_attempts a
  where a.student_id = p_student_id
    and a.plan_day_id = p_plan_day_id;

  if p_sequence <> v_current_sequence
    or p_attempt_kind <> (case when p_sequence = 0 then 'scheduled' else 'review' end)
  then
    raise exception 'attempt sequence changed';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_answers) as x(
      question_id text,
      selected_option integer,
      correct boolean
    )
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null
      or x.selected_option is null
      or x.correct is distinct from (x.selected_option = q.correct_option)
  ) then
    raise exception 'answer correctness does not match server question';
  end if;

  select (count(*) filter (where x.correct))::integer
  into v_correct_count
  from jsonb_to_recordset(p_answers) as x(correct boolean);
  if v_correct_count <> p_first_score then
    raise exception 'first score does not match canonical answers';
  end if;

  if p_mode = 'REVIEW' and exists (
    select 1
    from jsonb_to_recordset(p_answers) as x(
      question_id text,
      selected_option integer,
      uncertain boolean,
      duration_sec integer,
      revision_token text
    )
    join public.chem_questions q on q.id = x.question_id
    where q.grade_band = '高三'
      and q.source_kind = 'licensed_local'
      and (
        x.revision_token is distinct from q.question_revision_token
        or not exists (
        select 1
        from app_private.chem_question_answer_locks l
        where l.student_id = p_student_id
          and l.plan_day_id = p_plan_day_id
          and l.attempt_sequence = p_sequence
          and l.question_id = x.question_id
          and l.selected_option = x.selected_option
          and l.uncertain = coalesce(x.uncertain, false)
          and l.duration_sec = coalesce(x.duration_sec, 0)
          and l.revision_token is not distinct from nullif(x.revision_token, '')
        )
      )
  ) then
    raise exception 'licensed answer is not backed by the immutable first-answer lock';
  end if;

  insert into public.chem_learning_attempts (
    id, student_id, plan_day_id, attempt_kind, sequence, mode,
    started_at, completed_at, first_score
  ) values (
    p_attempt_id, p_student_id, p_plan_day_id, p_attempt_kind, p_sequence,
    p_mode, p_started_at, p_completed_at, p_first_score
  );

  insert into public.chem_attempt_answers (
    attempt_id, question_id, mother_id, skill_id, concept_key, level,
    correct, uncertain, duration_sec, selected_option, question_snapshot
  )
  select
    p_attempt_id,
    x.question_id,
    x.mother_id,
    x.skill_id,
    nullif(x.concept_key, ''),
    x.level::smallint,
    x.correct,
    coalesce(x.uncertain, false),
    x.duration_sec,
    x.selected_option::smallint,
    x.question_snapshot
  from jsonb_to_recordset(p_answers) as x(
    question_id text,
    mother_id text,
    skill_id text,
    concept_key text,
    level integer,
    correct boolean,
    uncertain boolean,
    duration_sec integer,
    selected_option integer,
    revision_token text,
    question_snapshot jsonb
  );
  get diagnostics v_inserted_answers = row_count;
  if v_inserted_answers <> v_answer_count then
    raise exception 'not every answer was inserted';
  end if;

  insert into public.chem_student_skill_state (
    student_id, skill_id, verified_level, candidate_level, stability,
    consecutive_errors, next_review_at, review_interval_index,
    last_reviewed_at, teacher_intervention, updated_at
  )
  select
    p_student_id,
    x.skill_id,
    x.verified_level::smallint,
    x.candidate_level::smallint,
    x.stability,
    x.consecutive_errors,
    x.next_review_at,
    x.review_interval_index::smallint,
    x.last_reviewed_at,
    x.teacher_intervention,
    x.updated_at
  from jsonb_to_recordset(p_skill_states) as x(
    skill_id text,
    verified_level integer,
    candidate_level integer,
    stability text,
    consecutive_errors integer,
    next_review_at timestamptz,
    review_interval_index integer,
    last_reviewed_at timestamptz,
    teacher_intervention boolean,
    updated_at timestamptz
  )
  on conflict (student_id, skill_id) do update set
    verified_level = excluded.verified_level,
    candidate_level = excluded.candidate_level,
    stability = excluded.stability,
    consecutive_errors = excluded.consecutive_errors,
    next_review_at = excluded.next_review_at,
    review_interval_index = excluded.review_interval_index,
    last_reviewed_at = excluded.last_reviewed_at,
    teacher_intervention = excluded.teacher_intervention,
    updated_at = excluded.updated_at;
  get diagnostics v_inserted_states = row_count;
  if v_inserted_states <> jsonb_array_length(p_skill_states) then
    raise exception 'not every skill state was written';
  end if;

  delete from app_private.chem_question_answer_locks l
  where l.student_id = p_student_id
    and l.plan_day_id = p_plan_day_id
    and l.attempt_sequence = p_sequence;

  return true;
end;
$$;

revoke all on function public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text) from public, anon, authenticated;
revoke all on function public.chem_get_question_answer_locks(uuid,uuid,integer,text[]) from public, anon, authenticated;
revoke all on function public.chem_delete_question_answer_locks(uuid,uuid,integer) from public, anon, authenticated;
revoke all on function public.chem_has_current_question_answer_lock(uuid,uuid,integer,text,text) from public, anon, authenticated;
revoke all on function public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz,integer,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.chem_lock_question_answer(uuid,uuid,integer,text,integer,boolean,integer,text) to service_role;
grant execute on function public.chem_get_question_answer_locks(uuid,uuid,integer,text[]) to service_role;
grant execute on function public.chem_delete_question_answer_locks(uuid,uuid,integer) to service_role;
grant execute on function public.chem_has_current_question_answer_lock(uuid,uuid,integer,text,text) to service_role;
grant execute on function public.chem_finalize_learning_attempt(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz,integer,jsonb,jsonb) to service_role;

-- The exact crops stay off the public repository.  These narrowly scoped
-- service-role RPCs let an authenticated teacher import a *staged* release
-- through a temporary server endpoint, while all deep integrity checks remain
-- in the atomic activation function below.
create or replace function public.chem_reset_h3_original_staged_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release manifest digest';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id = p_release_id and r.status in ('active','retired')
  ) then
    raise exception 'an active or retired release cannot be reset';
  end if;

  delete from app_private.chem_question_source_release_items where release_id = p_release_id;
  delete from app_private.chem_question_assets a
  using public.chem_questions q
  where q.source_release_id = p_release_id and a.question_id = q.id;
  delete from public.chem_questions where source_release_id = p_release_id;
  delete from app_private.chem_question_source_releases where id = p_release_id;

  insert into app_private.chem_question_source_releases(
    id, manifest_sha256, grade_band, status, expected_question_count,
    verification_status, verification_manifest_sha256, verification_actor, verified_at
  ) values (
    p_release_id, p_manifest_sha256, '高三', 'staged', 275,
    'pending', null, null, null
  );
end;
$$;

create or replace function public.chem_stage_h3_original_assets(
  p_release_id uuid,
  p_assets jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected integer;
  v_inserted integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id = p_release_id and r.status = 'staged'
  ) then
    raise exception 'assets can only be added to a staged release';
  end if;
  if p_assets is null or jsonb_typeof(p_assets) <> 'array' then
    raise exception 'invalid source asset batch';
  end if;
  if jsonb_array_length(p_assets) not between 1 and 20
    or coalesce((
      select sum(length(e->>'payload_base64')) from jsonb_array_elements(p_assets) e
    ), 0) > 4000000
    or exists (
      select 1 from jsonb_array_elements(p_assets) e
      where (select count(*) from pg_catalog.jsonb_object_keys(e)) <> 8
        or not (e ?& array['asset_path','question_id','asset_kind','mime_type','payload_base64','sha256','width','height'])
    )
  then
    raise exception 'invalid source asset batch';
  end if;
  v_expected := jsonb_array_length(p_assets);
  if exists (
    select 1
    from jsonb_to_recordset(p_assets) as x(question_id text)
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null or q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'an asset does not belong to this staged release';
  end if;

  insert into app_private.chem_question_assets(
    asset_path, question_id, asset_kind, mime_type, payload_base64, sha256, width, height
  )
  select x.asset_path, x.question_id, x.asset_kind, x.mime_type,
    x.payload_base64, x.sha256, x.width, x.height
  from jsonb_to_recordset(p_assets) as x(
    asset_path text, question_id text, asset_kind text, mime_type text,
    payload_base64 text, sha256 text, width integer, height integer
  );
  get diagnostics v_inserted = row_count;
  if v_inserted <> v_expected then raise exception 'source asset batch was not inserted completely'; end if;
  return v_inserted;
end;
$$;

create or replace function public.chem_stage_h3_original_release_items(
  p_release_id uuid,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected integer;
  v_inserted integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if not exists (
    select 1 from app_private.chem_question_source_releases r
    where r.id = p_release_id and r.status = 'staged'
  ) then
    raise exception 'release items can only be added to a staged release';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid release item batch';
  end if;
  if jsonb_array_length(p_items) not between 1 and 275
    or exists (
      select 1 from jsonb_array_elements(p_items) e
      where (select count(*) from pg_catalog.jsonb_object_keys(e)) <> 5
        or not (e ?& array['question_id','canonical_source_id','question_asset_sha256','analysis_asset_sha256','item_sha256'])
    )
  then
    raise exception 'invalid release item batch';
  end if;
  v_expected := jsonb_array_length(p_items);
  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(question_id text)
    left join public.chem_questions q on q.id = x.question_id
    where q.id is null or q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'a release item does not belong to this staged release';
  end if;

  insert into app_private.chem_question_source_release_items(
    release_id, question_id, canonical_source_id,
    question_asset_sha256, analysis_asset_sha256, item_sha256
  )
  select p_release_id, x.question_id, x.canonical_source_id,
    x.question_asset_sha256, x.analysis_asset_sha256, x.item_sha256
  from jsonb_to_recordset(p_items) as x(
    question_id text, canonical_source_id text,
    question_asset_sha256 text, analysis_asset_sha256 text, item_sha256 text
  );
  get diagnostics v_inserted = row_count;
  if v_inserted <> v_expected then raise exception 'release item batch was not inserted completely'; end if;
  return v_inserted;
end;
$$;

create or replace function public.chem_mark_h3_original_release_visually_verified(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_verification_actor text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if p_verification_actor is distinct from 'codex-full-visual-qa' then
    raise exception 'verification actor is not the server-owned full visual QA identity';
  end if;
  update app_private.chem_question_source_releases
  set verification_status = 'full_visual_verified',
      verification_manifest_sha256 = p_manifest_sha256,
      verification_actor = btrim(p_verification_actor),
      verified_at = now()
  where id = p_release_id
    and status = 'staged'
    and manifest_sha256 = p_manifest_sha256;
  if not found then raise exception 'staged release and verified manifest do not match'; end if;
end;
$$;

create or replace function public.chem_preflight_h3_original_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (
  status text,
  "verificationStatus" text,
  questions integer,
  assets integer,
  items integer,
  active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));
  if not exists (
    select 1
    from app_private.chem_question_source_releases r
    where r.id = p_release_id
      and r.manifest_sha256 = p_manifest_sha256
      and r.grade_band = '高三'
  ) then
    raise exception 'source release and manifest do not match';
  end if;

  return query
  select
    r.status,
    r.verification_status,
    (
      select count(*)::integer
      from public.chem_questions q
      where q.source_release_id = r.id
    ),
    (
      select count(*)::integer
      from app_private.chem_question_assets a
      join public.chem_questions q on q.id = a.question_id
      where q.source_release_id = r.id
    ),
    (
      select count(*)::integer
      from app_private.chem_question_source_release_items ri
      where ri.release_id = r.id
    ),
    r.status = 'active'
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.manifest_sha256 = p_manifest_sha256;
end;
$$;

revoke all on function public.chem_reset_h3_original_staged_release(uuid,text) from public, anon, authenticated;
revoke all on function public.chem_stage_h3_original_assets(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.chem_stage_h3_original_release_items(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.chem_mark_h3_original_release_visually_verified(uuid,text,text) from public, anon, authenticated;
revoke all on function public.chem_preflight_h3_original_release(uuid,text) from public, anon, authenticated;
grant execute on function public.chem_reset_h3_original_staged_release(uuid,text) to service_role;
grant execute on function public.chem_stage_h3_original_assets(uuid,jsonb) to service_role;
grant execute on function public.chem_stage_h3_original_release_items(uuid,jsonb) to service_role;
grant execute on function public.chem_mark_h3_original_release_visually_verified(uuid,text,text) to service_role;
grant execute on function public.chem_preflight_h3_original_release(uuid,text) to service_role;

create or replace function public.chem_activate_h3_original_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (release_id uuid, activated_questions integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question_count integer;
  v_distinct_count integer;
  v_computed_manifest text;
  v_release_manifest text;
  v_release_status text;
  v_release_expected integer;
  v_verification_status text;
  v_verification_manifest text;
  v_verification_actor text;
  v_verified_at timestamptz;
  v_skill_ids text[];
  v_expected_skill_ids constant text[] := array[
    'H3_AQ',
    'H3_ELECTRO',
    'H3_EQUILIBRIUM',
    'H3_EXPERIMENT',
    'H3_INORGANIC',
    'H3_ION_REDOX',
    'H3_ORGANIC',
    'H3_PROCESS',
    'H3_STOICH',
    'H3_STRUCTURE',
    'H3_THERMO_RATE'
  ]::text[];
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;

  -- Serialize release switches.  Every assertion and both the old/new pool
  -- updates run in this function's transaction, so a failed assertion leaves
  -- the currently active REVIEW pool unchanged.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release', 0));

  select r.manifest_sha256, r.status, r.expected_question_count,
    r.verification_status, r.verification_manifest_sha256,
    r.verification_actor, r.verified_at
  into v_release_manifest, v_release_status, v_release_expected,
    v_verification_status, v_verification_manifest,
    v_verification_actor, v_verified_at
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.grade_band = '高三'
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or v_release_expected <> 275
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

  -- Freeze the entire staged release while it is being verified.  The parent
  -- release row lock also blocks concurrent FK inserts; these deterministic
  -- child locks close the check-to-activate race for updates and deletes.
  perform q.id
  from public.chem_questions q
  where q.source_release_id = p_release_id
  order by q.id
  for update;

  perform a.asset_path
  from app_private.chem_question_assets a
  join public.chem_questions q on q.id = a.question_id
  where q.source_release_id = p_release_id
  order by a.asset_path
  for update of a;

  perform ri.question_id
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id
  order by ri.question_id
  for update;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_question_count <> 275 then
    raise exception 'release must contain exactly 275 questions, found %', v_question_count;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        q.grade_band <> '高三'
        or q.source_kind <> 'licensed_local'
        or q.review_status <> 'approved'
        or q.scope_status <> 'IN'
        or q.usable_for_review
        or q.usable_for_class_quiz
        or q.usable_for_exam_sprint
        or q.usable_for_demo
        or q.mother_id is null
        or q.concept_key is null
        or q.concept_key not in (
          q.skill_id || '__C01', q.skill_id || '__C02', q.skill_id || '__C03',
          q.skill_id || '__C04', q.skill_id || '__C05'
        )
        or length(btrim(coalesce(q.stem, ''))) = 0
        or length(btrim(coalesce(q.explanation, ''))) = 0
        or jsonb_typeof(q.options) <> 'array'
        or case when jsonb_typeof(q.options) = 'array' then
          jsonb_array_length(q.options) <> 4
          or exists (
            select 1 from jsonb_array_elements(q.options) option_value
            where jsonb_typeof(option_value) <> 'string'
          )
          else true end
        or q.correct_option not between 0 and 3
        or coalesce(q.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
        or coalesce(q.question_revision_token, '') !~ '^[0-9a-f]{64}$'
        or q.render_mode <> 'image_primary'
        or jsonb_array_length(q.asset_refs) <> 2
      )
  ) then
    raise exception 'release contains an unapproved, ineligible, non-four-option, or prematurely enabled question';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements_text(q.options) option_text
    where q.source_release_id = p_release_id
      and length(btrim(option_text)) = 0
  ) then
    raise exception 'release contains an empty answer option';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        select count(distinct btrim(option_text))
        from jsonb_array_elements_text(q.options) option_text
      ) <> 4
  ) then
    raise exception 'release contains duplicated answer options';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.content_fingerprint is distinct from
        app_private.chem_h3_content_fingerprint(q.stem, q.options)
  ) then
    raise exception 'content fingerprint must equal the normalized stem and four options';
  end if;

  select array_agg(distinct q.skill_id order by q.skill_id)
  into v_skill_ids
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_skill_ids is distinct from v_expected_skill_ids then
    raise exception 'release does not contain the exact eleven High-3 REVIEW skills';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
    group by q.skill_id
    having count(*) <> 25 or count(distinct q.concept_key) <> 5
  ) then
    raise exception 'every High-3 skill must contain 25 questions across exactly five concepts';
  end if;

  if (
    select count(*)
    from (
      select q.skill_id, q.concept_key
      from public.chem_questions q
      where q.source_release_id = p_release_id
      group by q.skill_id, q.concept_key
      having count(*) = 5
    ) concept_groups
  ) <> 55 then
    raise exception 'every High-3 fine concept must contain exactly five questions';
  end if;

  select count(distinct q.id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> 275 then raise exception 'question ids are not unique inside release'; end if;
  select count(distinct q.mother_id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> 275 then raise exception 'mother ids are not unique inside release'; end if;
  select count(distinct q.source_item_key) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> 275 then raise exception 'source item identities are not unique inside release'; end if;
  select count(distinct q.content_fingerprint) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> 275 then raise exception 'content fingerprints are not unique inside release'; end if;
  select count(distinct q.question_revision_token) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> 275 then raise exception 'question revision tokens are not unique inside release'; end if;

  select count(*) into v_question_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_question_count <> 275 then
    raise exception 'release ledger must contain exactly 275 items, found %', v_question_count;
  end if;

  select count(distinct ri.canonical_source_id) into v_distinct_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_distinct_count <> 275 then
    raise exception 'canonical source identities are not unique inside release';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join app_private.chem_question_source_release_items ri
      on ri.release_id = p_release_id
     and ri.question_id = q.id
    where q.source_release_id = p_release_id
      and ri.question_id is null
  ) then
    raise exception 'release ledger is missing a staged question';
  end if;

  -- Every descriptor must resolve to the exact binary metadata recorded on
  -- that question.  A non-native question additionally needs a question-side
  -- visual; an analysis image alone is not enough to make the stem readable.
  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    where q.source_release_id = p_release_id
      and (
        coalesce(btrim(ref->>'alt'), '') = ''
        or coalesce(ref->>'path', '') !~ '^[a-zA-Z0-9/_-]{16,200}$'
        or coalesce(ref->>'kind', '') not in ('question_image','formula_fallback','source_scan','analysis_image')
        or coalesce(ref->>'sha256', '') !~ '^[0-9a-f]{64}$'
        or (select count(*) from jsonb_object_keys(ref)) <> 6
        or exists (
          select 1 from jsonb_object_keys(ref) key_name
          where key_name not in ('kind','path','alt','sha256','width','height')
        )
      )
  ) then
    raise exception 'release contains a malformed or inaccessible asset descriptor';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        (select count(*) from jsonb_object_keys(q.source_info)) <> 12
        or exists (
          select 1 from jsonb_object_keys(q.source_info) key_name
          where key_name not in (
            'title','exam','year','questionNo','locator','transcriptionPolicy',
            'optionTranscriptionPolicy','transcriptionAuditMethod','sourcePairingStatus',
            'sourceMarkerStyle','sourceMarkerLabel','conceptLabel'
          )
        )
        or coalesce(q.source_info->>'transcriptionPolicy', '') <> 'source_image_authoritative'
        or coalesce(btrim(q.source_info->>'optionTranscriptionPolicy'), '') = ''
        or coalesce(btrim(q.source_info->>'transcriptionAuditMethod'), '') = ''
        or coalesce(q.source_info->>'sourcePairingStatus', '') not in ('EXACT','SOURCE_NATIVE_PAIR')
        or coalesce(q.source_info->>'sourceMarkerStyle', '') not in ('bracketed','plain_answer_analysis')
        or coalesce(btrim(q.source_info->>'sourceMarkerLabel'), '') = ''
        or coalesce(btrim(q.source_info->>'conceptLabel'), '') = ''
      )
  ) then
    raise exception 'release contains an incomplete or non-canonical public source record';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        jsonb_array_length(q.asset_refs) <> 2
        or jsonb_array_length(q.asset_refs) <> (
          select count(distinct ref->>'path')
          from jsonb_array_elements(q.asset_refs) ref
        )
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'question_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' = 'analysis_image') <> 1
        or (select count(*) from jsonb_array_elements(q.asset_refs) ref where ref->>'kind' not in ('question_image','analysis_image')) <> 0
      )
  ) then
    raise exception 'every release question must have exactly one question image and one analysis image';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    cross join lateral jsonb_array_elements(q.asset_refs) ref
    left join app_private.chem_question_assets a
      on a.question_id = q.id
     and a.asset_path = ref->>'path'
     and a.asset_kind = ref->>'kind'
     and a.sha256 = ref->>'sha256'
     and a.width::text = ref->>'width'
     and a.height::text = ref->>'height'
    where q.source_release_id = p_release_id
      and a.asset_path is null
  ) then
    raise exception 'release contains a missing or metadata-mismatched private asset';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and encode(extensions.digest(decode(a.payload_base64, 'base64'), 'sha256'), 'hex') <> a.sha256
  ) then
    raise exception 'private asset payload does not match its SHA-256 digest';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    left join lateral (
      select
        count(*) as asset_count,
        count(*) filter (where a.asset_kind = 'question_image') as question_count,
        count(*) filter (where a.asset_kind = 'analysis_image') as analysis_count
      from app_private.chem_question_assets a
      where a.question_id = q.id
    ) counts on true
    where q.source_release_id = p_release_id
      and (
        counts.asset_count <> 2
        or counts.question_count <> 1
        or counts.analysis_count <> 1
      )
  ) then
    raise exception 'private asset store must contain exactly the two declared images per question';
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets a
    join public.chem_questions q on q.id = a.question_id
    where q.source_release_id = p_release_id
      and a.mime_type <> 'image/webp'
  ) then
    raise exception 'release assets must use the audited lossless WebP transport';
  end if;

  if exists (
    select 1
    from app_private.chem_question_source_release_items ri
    join public.chem_questions q
      on q.id = ri.question_id
     and q.source_release_id = ri.release_id
    join app_private.chem_question_assets question_asset
      on question_asset.question_id = q.id
     and question_asset.asset_kind = 'question_image'
    join app_private.chem_question_assets analysis_asset
      on analysis_asset.question_id = q.id
     and analysis_asset.asset_kind = 'analysis_image'
    where ri.release_id = p_release_id
      and (
        ri.question_asset_sha256 <> question_asset.sha256
        or ri.analysis_asset_sha256 <> analysis_asset.sha256
        or q.question_revision_token is distinct from
          app_private.chem_h3_question_revision_sha256(
            q,
            question_asset.sha256,
            analysis_asset.sha256
          )
        or ri.item_sha256 <> app_private.chem_h3_release_item_sha256(
          q,
          ri.canonical_source_id,
          question_asset.sha256,
          analysis_asset.sha256
        )
      )
  ) then
    raise exception 'release revision token or ledger digest does not match the staged question and assets';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.string_agg(ri.item_sha256, E'\n' order by ri.question_id),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_computed_manifest
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;

  if v_computed_manifest is distinct from v_release_manifest
    or v_computed_manifest is distinct from p_manifest_sha256
  then
    raise exception 'release manifest does not match the 275 staged source items';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and q.render_mode <> 'native'
      and not exists (
        select 1
        from jsonb_array_elements(q.asset_refs) ref
        join app_private.chem_question_assets a
          on a.question_id = q.id
         and a.asset_path = ref->>'path'
         and a.asset_kind = ref->>'kind'
        where ref->>'kind' in ('question_image','formula_fallback','source_scan')
      )
  ) then
    raise exception 'every non-native question must have a verified question-side asset';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'question_image'
          where ref->>'kind' = 'question_image'
        )
        or not exists (
          select 1
          from jsonb_array_elements(q.asset_refs) ref
          join app_private.chem_question_assets a
            on a.question_id = q.id
           and a.asset_path = ref->>'path'
           and a.asset_kind = 'analysis_image'
          where ref->>'kind' = 'analysis_image'
        )
      )
  ) then
    raise exception 'every source-backed question must have both question and analysis images';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions
  set usable_for_review = false,
      updated_at = now()
  where grade_band = '高三'
    and usable_for_review
    and source_release_id is distinct from p_release_id;

  update public.chem_questions
  set usable_for_review = true,
      updated_at = now()
  where source_release_id = p_release_id;
  get diagnostics v_question_count = row_count;
  if v_question_count <> 275 then
    raise exception 'activation updated %, expected 275', v_question_count;
  end if;

  update app_private.chem_question_source_releases
  set status = 'retired', retired_at = now()
  where grade_band = '高三' and status = 'active' and id <> p_release_id;

  update app_private.chem_question_source_releases
  set status = 'active', activated_at = now(), retired_at = null
  where id = p_release_id;
  get diagnostics v_distinct_count = row_count;
  if v_distinct_count <> 1 then
    raise exception 'release activation status update affected %, expected 1', v_distinct_count;
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.grade_band = '高三'
    and q.usable_for_review
    and q.source_release_id = p_release_id;
  if v_question_count <> 275 then
    raise exception 'postcondition failed: active release exposes %, expected 275', v_question_count;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.grade_band = '高三'
      and q.usable_for_review
      and q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'postcondition failed: an older High-3 REVIEW question remains enabled';
  end if;

  select count(*) into v_distinct_count
  from app_private.chem_question_source_releases r
  where r.grade_band = '高三' and r.status = 'active';
  if v_distinct_count <> 1 then
    raise exception 'postcondition failed: High-3 must have exactly one active source release';
  end if;

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$$;

revoke all on function public.chem_activate_h3_original_release(uuid, text) from public, anon, authenticated;
grant execute on function public.chem_activate_h3_original_release(uuid, text) to service_role;

comment on column public.chem_questions.source_info is
  'Public-safe source title/exam/question number/locator. Never store local drive paths.';
comment on column public.chem_questions.asset_refs is
  'Stable private asset descriptors. Never store signed URLs or local drive paths.';
comment on column public.chem_questions.source_item_key is
  'Stable identity derived from source document fingerprint plus source item locator.';
comment on column public.chem_questions.content_fingerprint is
  'Semantic duplicate key: SHA-256 of the explicitly normalized stem and four options only; independent of crop bytes.';
comment on column public.chem_questions.question_revision_token is
  'Issued revision key: SHA-256 binding semantic fingerprint, exact question/analysis asset hashes, render mode and both asset descriptors.';
comment on column public.chem_questions.source_release_id is
  'Private manifest release that staged and atomically activated this source-backed question.';
comment on table app_private.chem_question_assets is
  'Server-only exact question crops for source-backed REVIEW questions.';
comment on table app_private.chem_question_source_releases is
  'Server-only manifest ledger for atomic High-3 source-backed REVIEW releases.';
