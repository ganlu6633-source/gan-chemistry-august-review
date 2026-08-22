-- Version the source-question revision contract without changing any existing
-- release.  Historical releases keep the exact v1 asset-bound digest.  New
-- releases may opt in at INSERT time to v2, which additionally binds the
-- student-facing explanation.

alter table app_private.chem_question_source_releases
  add column if not exists revision_contract text;

update app_private.chem_question_source_releases
set revision_contract = 'v1_assets'
where revision_contract is null;

alter table app_private.chem_question_source_releases
  alter column revision_contract set default 'v1_assets',
  alter column revision_contract set not null;

alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_revision_contract_check;

alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_revision_contract_check
  check (revision_contract in ('v1_assets', 'v2_explanation_assets'));

create or replace function app_private.chem_question_revision_sha256_v1_assets(
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

create or replace function app_private.chem_question_revision_sha256_v2_explanation_assets(
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
        || app_private.chem_release_manifest_field(p_question.explanation)
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

-- Keep the established function name so every existing activation function
-- continues to call the same OID/name, while dispatching by the release row.
create or replace function app_private.chem_h3_question_revision_sha256(
  p_question public.chem_questions,
  p_question_asset_sha256 text,
  p_analysis_asset_sha256 text
)
returns text
language sql
stable
set search_path = ''
as $$
  select case coalesce(
    (
      select release.revision_contract
      from app_private.chem_question_source_releases release
      where release.id = p_question.source_release_id
    ),
    'v1_assets'
  )
    when 'v2_explanation_assets' then
      app_private.chem_question_revision_sha256_v2_explanation_assets(
        p_question,
        p_question_asset_sha256,
        p_analysis_asset_sha256
      )
    else
      app_private.chem_question_revision_sha256_v1_assets(
        p_question,
        p_question_asset_sha256,
        p_analysis_asset_sha256
      )
  end;
$$;

create or replace function app_private.chem_guard_source_release_revision_contract()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.revision_contract is distinct from old.revision_contract
     and (
       old.status <> 'staged'
       or exists (
         select 1
         from public.chem_questions question_row
         where question_row.source_release_id = old.id
       )
     ) then
    raise exception 'source release revision contract is immutable after question staging';
  end if;
  return new;
end;
$$;

drop trigger if exists chem_guard_source_release_revision_contract
  on app_private.chem_question_source_releases;
create trigger chem_guard_source_release_revision_contract
before update of revision_contract on app_private.chem_question_source_releases
for each row execute function app_private.chem_guard_source_release_revision_contract();

revoke all on function app_private.chem_question_revision_sha256_v1_assets(public.chem_questions,text,text)
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_question_revision_sha256_v2_explanation_assets(public.chem_questions,text,text)
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_h3_question_revision_sha256(public.chem_questions,text,text)
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_source_release_revision_contract()
  from public, anon, authenticated, service_role;

comment on column app_private.chem_question_source_releases.revision_contract is
  'Immutable digest contract selected when a source release is inserted. v1 binds source assets; v2 also binds the student explanation.';
comment on function app_private.chem_question_revision_sha256_v2_explanation_assets(public.chem_questions,text,text) is
  'Revision v2: SHA-256 over content fingerprint, student explanation, render metadata, and both private source-asset digests.';
