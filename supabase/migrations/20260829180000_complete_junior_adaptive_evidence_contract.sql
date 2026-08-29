begin;

-- Junior releases share the audited source-release ledger with the three
-- high-school grades.  Keep every existing high-school count contract intact,
-- while allowing a junior batch only when it can fund the minimum adaptive
-- evidence matrix: at least three knowledge routes x (five foundation + two
-- higher) independent originals.  The upper bound prevents an unreviewably large
-- batch from bypassing the release audit as a single manifest.
alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_grade_band_check,
  drop constraint if exists chem_question_source_releases_expected_question_count_check;

alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_grade_band_check
    check (grade_band in ('初三','高一','高二','高三')),
  add constraint chem_question_source_releases_expected_question_count_check
    check (
      (grade_band = '初三' and expected_question_count between 21 and 2000)
      or (grade_band = '高一' and (
        expected_question_count in (125, 175)
        or expected_question_count between 211 and 275
      ))
      or (grade_band = '高二' and expected_question_count between 200 and 2000)
      or (grade_band = '高三' and expected_question_count between 275 and 2000)
    );

-- A completed junior session must be represented by the same immutable
-- attempt/answer ledger used by every student, guardian and teacher view.
alter table public.chem_learning_attempts
  add column if not exists junior_session_id uuid;

alter table public.chem_learning_attempts
  drop constraint if exists chem_learning_attempts_junior_session_fk;

alter table public.chem_learning_attempts
  add constraint chem_learning_attempts_junior_session_fk
  foreign key (junior_session_id)
  references public.chem_junior_daily_sessions(id)
  on delete cascade;

alter table public.chem_learning_attempts
  drop constraint if exists chem_learning_attempts_junior_session_key;

alter table public.chem_learning_attempts
  add constraint chem_learning_attempts_junior_session_key
  unique (junior_session_id);

comment on column public.chem_learning_attempts.junior_session_id is
  'One-to-one link from a finalized junior-adaptive session to the unified immutable learning-attempt ledger.';

-- Prevent concurrent dashboard refreshes from funding two adaptive plans for
-- the same student and Shanghai calendar day.
create unique index if not exists chem_learning_plans_one_junior_adaptive_per_day_uidx
  on public.chem_learning_plans (student_id, plan_date)
  where delivery_mode = 'junior_adaptive';

-- A learner can have only one source-selecting junior session at a time. This
-- serializes cross-day identity exclusion even if two old plan ids are opened
-- concurrently through direct API calls.
create unique index if not exists chem_junior_daily_sessions_one_active_student_uidx
  on public.chem_junior_daily_sessions (student_id)
  where status = 'active';

alter table public.chem_junior_daily_sessions
  add column if not exists blocked_reason_code text,
  add column if not exists blocked_reason_detail text,
  add column if not exists blocked_at timestamptz;

alter table public.chem_junior_daily_sessions
  drop constraint if exists chem_junior_daily_sessions_blocked_metadata_check;

alter table public.chem_junior_daily_sessions
  add constraint chem_junior_daily_sessions_blocked_metadata_check
  check (
    (
      status = 'blocked'
      and blocked_reason_code is not null
      and blocked_reason_code in (
        'question_revision_changed',
        'source_capacity_exhausted',
        'knowledge_contract_unavailable',
        'source_release_unavailable',
        'manual_pause'
      )
      and length(btrim(coalesce(blocked_reason_detail, ''))) between 1 and 1000
      and blocked_at is not null
    )
    or (
      status <> 'blocked'
      and blocked_reason_code is null
      and blocked_reason_detail is null
      and blocked_at is null
    )
  );

comment on column public.chem_junior_daily_sessions.blocked_reason_code is
  'Machine-readable fail-closed reason; blocked sessions also require a human-readable detail and timestamp.';

-- The same knowledge id can legitimately occur in more than one textbook.
-- Every verified mapping must point to an immutable, audited source release.
do $$
begin
  if exists (
    select 1
    from app_private.chem_junior_knowledge_provenance
    where source_release_id is null
  ) then
    raise exception 'Junior knowledge provenance cannot be hardened while a source release is missing';
  end if;
end;
$$;

alter table app_private.chem_junior_knowledge_provenance
  alter column source_release_id set not null;

alter table app_private.chem_junior_knowledge_provenance
  drop constraint if exists chem_junior_knowledge_provenance_pkey;

alter table app_private.chem_junior_knowledge_provenance
  add constraint chem_junior_knowledge_provenance_pkey
  primary key (textbook_version, knowledge_id);

-- Junior releases are scoped by confirmed textbook version.  High-school
-- release rows remain NULL here and retain exactly one active release per
-- grade; junior can safely keep one active batch per confirmed textbook.
alter table app_private.chem_question_source_releases
  add column if not exists textbook_version text;

alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_textbook_scope_check;

alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_textbook_scope_check
  check (
    (
      grade_band = '初三'
      and textbook_version is not null
      and textbook_version in ('苏教版', '人教版', '通用')
    )
    or (
      grade_band in ('高一', '高二', '高三')
      and textbook_version is null
    )
  );

drop index if exists app_private.chem_question_source_releases_one_active_grade_uidx;
create unique index chem_question_source_releases_one_active_grade_uidx
  on app_private.chem_question_source_releases (grade_band)
  where status = 'active' and grade_band in ('高一', '高二', '高三');

create unique index if not exists chem_question_source_releases_one_active_junior_textbook_uidx
  on app_private.chem_question_source_releases (textbook_version)
  where status = 'active' and grade_band = '初三';

alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_revision_contract_check;

alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_revision_contract_check
  check (revision_contract in (
    'v1_assets',
    'v2_explanation_assets',
    'v3_junior_native_text'
  ));

-- The release spec freezes the textbook and its complete reviewed adaptive
-- route set (at least three routes; a curriculum day selects exactly three)
-- before the first original is staged.  A separate release-versioned
-- provenance table lets a replacement batch be reviewed while the current
-- active mapping remains available to learners.
create table if not exists app_private.chem_junior_source_release_specs (
  release_id uuid primary key
    references app_private.chem_question_source_releases(id) on delete cascade,
  textbook_version text not null
    check (textbook_version in ('苏教版', '人教版', '通用')),
  knowledge_ids text[] not null,
  created_at timestamptz not null default now(),
  check (cardinality(knowledge_ids) between 3 and 200)
);

create table if not exists app_private.chem_junior_source_release_provenance (
  release_id uuid not null
    references app_private.chem_question_source_releases(id) on delete cascade,
  textbook_version text not null
    check (textbook_version in ('苏教版', '人教版', '通用')),
  knowledge_id text not null
    references public.chem_skills(id) on delete restrict,
  source_id text not null check (length(btrim(source_id)) between 3 and 160),
  source_locator text not null check (length(btrim(source_locator)) between 3 and 500),
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  verification_status text not null default 'pending_review'
    check (verification_status in ('pending_review', 'verified')),
  verification_actor text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (release_id, knowledge_id)
);

alter table app_private.chem_junior_source_release_specs enable row level security;
alter table app_private.chem_junior_source_release_provenance enable row level security;
revoke all on table app_private.chem_junior_source_release_specs
  from public, anon, authenticated, service_role;
revoke all on table app_private.chem_junior_source_release_provenance
  from public, anon, authenticated, service_role;

-- The Edge function must not receive SELECT privilege on either private
-- provenance or release ledgers. Expose only the minimum identifiers and one
-- release-readiness bit required by the junior fail-closed gate.
create or replace function public.chem_junior_verified_provenance_rows(
  p_textbook_version text,
  p_knowledge_ids text[]
)
returns table (
  knowledge_id text,
  textbook_version text,
  source_release_id uuid,
  verification_status text,
  source_release_ready boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    provenance.knowledge_id,
    provenance.textbook_version,
    provenance.source_release_id,
    provenance.verification_status,
    (
      release.grade_band = '初三'
      and release.textbook_version = provenance.textbook_version
      and release.status = 'active'
      and release.verification_status = 'full_visual_verified'
      and release.verification_manifest_sha256 = release.manifest_sha256
    ) as source_release_ready
  from app_private.chem_junior_knowledge_provenance as provenance
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
  where length(btrim(coalesce(p_textbook_version, ''))) between 1 and 80
    and cardinality(p_knowledge_ids) between 1 and 20
    and provenance.textbook_version = btrim(p_textbook_version)
    and provenance.knowledge_id = any(p_knowledge_ids)
  order by provenance.knowledge_id;
$$;

revoke all on function public.chem_junior_verified_provenance_rows(text, text[])
  from public, anon, authenticated, service_role;
grant execute on function public.chem_junior_verified_provenance_rows(text, text[])
  to service_role;

comment on function public.chem_junior_verified_provenance_rows(text, text[]) is
  'Server-only minimal allowlist for junior textbook provenance; never exposes private locators, hashes, manifests, or source assets.';

-- A junior licensed original must use one canonical id for both the adaptive
-- knowledge route and the shared skill-state ledger.
alter table public.chem_questions
  drop constraint if exists chem_questions_junior_source_contract;

alter table public.chem_questions
  add constraint chem_questions_junior_source_contract
  check (
    grade_band <> '初三'
    or source_kind <> 'licensed_local'
    or (
      textbook_version is not null and length(btrim(textbook_version)) > 0
      and knowledge_id is not null and length(btrim(knowledge_id)) > 0
      and skill_id = knowledge_id
      and same_type_key is not null and length(btrim(same_type_key)) > 0
      and source_item_key is not null and length(btrim(source_item_key)) >= 16
      and parent_source_item_key is not null and length(btrim(parent_source_item_key)) >= 16
      and content_fingerprint is not null
      and content_fingerprint ~ '^[0-9a-f]{64}$'
      and question_revision_token is not null
      and question_revision_token ~ '^[0-9a-f]{64}$'
      and source_release_id is not null
      and review_status = 'approved'
      and scope_status = 'IN'
      and render_mode = 'native'
      and coalesce(btrim(image_url), '') = ''
      and asset_refs = '[]'::jsonb
      and not usable_for_class_quiz
      and not usable_for_exam_sprint
      and not usable_for_demo
    )
  );

create unique index if not exists chem_questions_junior_release_mother_uidx
  on public.chem_questions (source_release_id, mother_id)
  where grade_band = '初三' and source_kind = 'licensed_local';

create unique index if not exists chem_questions_junior_release_source_item_uidx
  on public.chem_questions (source_release_id, source_item_key)
  where grade_band = '初三' and source_kind = 'licensed_local';

create unique index if not exists chem_questions_junior_release_parent_source_item_uidx
  on public.chem_questions (source_release_id, parent_source_item_key)
  where grade_band = '初三' and source_kind = 'licensed_local';

create unique index if not exists chem_questions_junior_release_fingerprint_uidx
  on public.chem_questions (source_release_id, content_fingerprint)
  where grade_band = '初三' and source_kind = 'licensed_local';

create unique index if not exists chem_questions_junior_release_revision_uidx
  on public.chem_questions (source_release_id, question_revision_token)
  where grade_band = '初三' and source_kind = 'licensed_local';

-- The original content-mutation trigger predates the junior identity fields.
-- Rebuild its column list so an activated or answered junior original cannot
-- silently change textbook, route, same-type family, or parent source identity.
drop trigger if exists chem_questions_guard_source_content_update
  on public.chem_questions;
create trigger chem_questions_guard_source_content_update
before update of
  id,
  mother_id,
  skill_id,
  knowledge_id,
  concept_key,
  level,
  grade_band,
  textbook_version,
  stem,
  options,
  correct_option,
  explanation,
  scaffold,
  source_kind,
  source_info,
  asset_refs,
  render_mode,
  image_url,
  same_type_key,
  source_item_key,
  parent_source_item_key,
  content_fingerprint,
  question_revision_token,
  source_release_id
on public.chem_questions
for each row execute function app_private.chem_guard_source_question_content_mutation();

-- Native junior originals deliberately have no binary assets.  Their own
-- digest contract therefore binds every delivered field and every adaptive
-- source identity directly, including the four fields added after the legacy
-- image-primary digest was designed.
create or replace function app_private.chem_junior_native_revision_sha256(
  p_question public.chem_questions
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
        || app_private.chem_release_manifest_field(p_question.knowledge_id)
        || app_private.chem_release_manifest_field(p_question.concept_key)
        || app_private.chem_release_manifest_field(p_question.level::text)
        || app_private.chem_release_manifest_field(p_question.grade_band)
        || app_private.chem_release_manifest_field(p_question.textbook_version)
        || app_private.chem_release_manifest_field(p_question.stem)
        || app_private.chem_release_manifest_field(p_question.options->>0)
        || app_private.chem_release_manifest_field(p_question.options->>1)
        || app_private.chem_release_manifest_field(p_question.options->>2)
        || app_private.chem_release_manifest_field(p_question.options->>3)
        || app_private.chem_release_manifest_field(p_question.correct_option::text)
        || app_private.chem_release_manifest_field(p_question.explanation)
        || app_private.chem_release_manifest_field(p_question.scaffold)
        || app_private.chem_release_manifest_field(p_question.review_status)
        || app_private.chem_release_manifest_field(p_question.scope_status)
        || app_private.chem_release_manifest_field(p_question.source_kind)
        || app_private.chem_release_manifest_field(p_question.render_mode)
        || app_private.chem_release_manifest_field(p_question.image_url)
        || app_private.chem_release_manifest_field(p_question.asset_refs::text)
        || app_private.chem_release_manifest_field(p_question.same_type_key)
        || app_private.chem_release_manifest_field(p_question.source_item_key)
        || app_private.chem_release_manifest_field(p_question.parent_source_item_key)
        || app_private.chem_release_manifest_field(p_question.content_fingerprint)
        || app_private.chem_release_manifest_field(p_question.source_release_id::text)
        || app_private.chem_release_manifest_field(p_question.source_info::text),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function app_private.chem_junior_native_release_item_sha256(
  p_question public.chem_questions,
  p_canonical_source_id text
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
        || app_private.chem_release_manifest_field(p_question.knowledge_id)
        || app_private.chem_release_manifest_field(p_question.concept_key)
        || app_private.chem_release_manifest_field(p_question.level::text)
        || app_private.chem_release_manifest_field(p_question.grade_band)
        || app_private.chem_release_manifest_field(p_question.textbook_version)
        || app_private.chem_release_manifest_field(p_question.stem)
        || app_private.chem_release_manifest_field(p_question.options->>0)
        || app_private.chem_release_manifest_field(p_question.options->>1)
        || app_private.chem_release_manifest_field(p_question.options->>2)
        || app_private.chem_release_manifest_field(p_question.options->>3)
        || app_private.chem_release_manifest_field(p_question.correct_option::text)
        || app_private.chem_release_manifest_field(p_question.explanation)
        || app_private.chem_release_manifest_field(p_question.scaffold)
        || app_private.chem_release_manifest_field(p_question.review_status)
        || app_private.chem_release_manifest_field(p_question.scope_status)
        || app_private.chem_release_manifest_field(p_question.source_kind)
        || app_private.chem_release_manifest_field(p_question.render_mode)
        || app_private.chem_release_manifest_field(p_question.image_url)
        || app_private.chem_release_manifest_field(p_question.asset_refs::text)
        || app_private.chem_release_manifest_field(p_question.same_type_key)
        || app_private.chem_release_manifest_field(p_question.source_item_key)
        || app_private.chem_release_manifest_field(p_question.parent_source_item_key)
        || app_private.chem_release_manifest_field(p_question.content_fingerprint)
        || app_private.chem_release_manifest_field(p_question.question_revision_token)
        || app_private.chem_release_manifest_field(p_question.source_release_id::text)
        || app_private.chem_release_manifest_field(p_question.source_info::text)
        || app_private.chem_release_manifest_field(p_canonical_source_id)
        || app_private.chem_release_manifest_field(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        )
        || app_private.chem_release_manifest_field(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function app_private.chem_junior_native_revision_sha256(public.chem_questions)
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_junior_native_release_item_sha256(public.chem_questions,text)
  from public, anon, authenticated, service_role;

-- Deny every generic or direct mutation path for junior source releases.
-- The dedicated SECURITY DEFINER lifecycle enables this transaction-local
-- guard only around its own validated statements.  Private assets are never
-- insertable for junior; reset may only delete legacy contamination.
create or replace function app_private.chem_guard_junior_release_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
      (tg_op = 'INSERT' and new.grade_band = '初三')
      or (tg_op = 'DELETE' and old.grade_band = '初三')
      or (tg_op = 'UPDATE' and (old.grade_band = '初三' or new.grade_band = '初三'))
    )
    and coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
  then
    raise exception 'junior source releases may change only through the dedicated server lifecycle';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function app_private.chem_guard_junior_question_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
      (
        tg_op = 'INSERT'
        and (
          new.grade_band = '初三'
          or exists (
            select 1
            from app_private.chem_question_source_releases as release_row
            where release_row.id = new.source_release_id and release_row.grade_band = '初三'
          )
        )
      )
      or (
        tg_op = 'DELETE'
        and (
          old.grade_band = '初三'
          or exists (
            select 1
            from app_private.chem_question_source_releases as release_row
            where release_row.id = old.source_release_id and release_row.grade_band = '初三'
          )
        )
      )
      or (
        tg_op = 'UPDATE'
        and (
          old.grade_band = '初三'
          or new.grade_band = '初三'
          or exists (
            select 1
            from app_private.chem_question_source_releases as release_row
            where release_row.grade_band = '初三'
              and release_row.id in (old.source_release_id, new.source_release_id)
          )
        )
      )
    )
    and coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
  then
    raise exception 'junior source questions may change only through the dedicated server lifecycle';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function app_private.chem_guard_junior_release_item_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
      (tg_op = 'INSERT' and exists (
        select 1 from app_private.chem_question_source_releases as release_row
        where release_row.id = new.release_id and release_row.grade_band = '初三'
      ))
      or (tg_op = 'DELETE' and exists (
        select 1 from app_private.chem_question_source_releases as release_row
        where release_row.id = old.release_id and release_row.grade_band = '初三'
      ))
      or (tg_op = 'UPDATE' and exists (
        select 1 from app_private.chem_question_source_releases as release_row
        where release_row.grade_band = '初三'
          and release_row.id in (old.release_id, new.release_id)
      ))
    )
    and coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
  then
    raise exception 'junior release items may change only through the dedicated server lifecycle';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function app_private.chem_guard_junior_private_asset_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
      (tg_op = 'INSERT' and exists (
        select 1
        from public.chem_questions as question
        join app_private.chem_question_source_releases as release_row
          on release_row.id = question.source_release_id
        where question.id = new.question_id and release_row.grade_band = '初三'
      ))
      or (tg_op = 'DELETE' and exists (
        select 1
        from public.chem_questions as question
        join app_private.chem_question_source_releases as release_row
          on release_row.id = question.source_release_id
        where question.id = old.question_id and release_row.grade_band = '初三'
      ))
      or (tg_op = 'UPDATE' and exists (
        select 1
        from public.chem_questions as question
        join app_private.chem_question_source_releases as release_row
          on release_row.id = question.source_release_id
        where question.id in (old.question_id, new.question_id)
          and release_row.grade_band = '初三'
      ))
    )
    and (
      tg_op <> 'DELETE'
      or coalesce(pg_catalog.current_setting('app.chem_junior_release_lifecycle', true), '') <> 'on'
    )
  then
    raise exception 'junior native-text releases cannot contain private assets';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists chem_guard_junior_release_lifecycle
  on app_private.chem_question_source_releases;
create trigger chem_guard_junior_release_lifecycle
before insert or update or delete on app_private.chem_question_source_releases
for each row execute function app_private.chem_guard_junior_release_lifecycle();

drop trigger if exists chem_guard_junior_question_lifecycle
  on public.chem_questions;
create trigger chem_guard_junior_question_lifecycle
before insert or update or delete on public.chem_questions
for each row execute function app_private.chem_guard_junior_question_lifecycle();

drop trigger if exists chem_guard_junior_release_item_lifecycle
  on app_private.chem_question_source_release_items;
create trigger chem_guard_junior_release_item_lifecycle
before insert or update or delete on app_private.chem_question_source_release_items
for each row execute function app_private.chem_guard_junior_release_item_lifecycle();

drop trigger if exists chem_guard_junior_private_asset_lifecycle
  on app_private.chem_question_assets;
create trigger chem_guard_junior_private_asset_lifecycle
before insert or update or delete on app_private.chem_question_assets
for each row execute function app_private.chem_guard_junior_private_asset_lifecycle();

revoke all on function app_private.chem_guard_junior_release_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_junior_question_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_junior_release_item_lifecycle()
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_junior_private_asset_lifecycle()
  from public, anon, authenticated, service_role;

create or replace function public.chem_prepare_junior_source_release(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_textbook_version text,
  p_knowledge_ids text[],
  p_expected_question_count integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_knowledge_ids text[];
begin
  if p_release_id is null
    or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$'
    or coalesce(p_textbook_version, '') not in ('苏教版', '人教版', '通用')
    or coalesce(cardinality(p_knowledge_ids), 0) not between 3 and 200
    or coalesce(p_expected_question_count, 0) not between 21 and 2000
  then
    raise exception 'invalid junior source release specification';
  end if;

  select pg_catalog.array_agg(route.knowledge_id order by route.knowledge_id)
  into v_knowledge_ids
  from (
    select distinct btrim(knowledge_id) as knowledge_id
    from pg_catalog.unnest(p_knowledge_ids) as knowledge_id
    where length(btrim(coalesce(knowledge_id, ''))) between 1 and 160
  ) as route;

  if coalesce(cardinality(v_knowledge_ids), 0) <> cardinality(p_knowledge_ids)
    or p_expected_question_count < 7 * cardinality(v_knowledge_ids)
    or exists (
      select 1
      from pg_catalog.unnest(v_knowledge_ids) as requested(knowledge_id)
      left join public.chem_skills as skill
        on skill.id = requested.knowledge_id
       and skill.grade_band = '初三'
       and skill.active
      where skill.id is null
    )
  then
    raise exception 'junior release requires 3-200 distinct active routes and at least seven originals per route';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  if exists (
    select 1
    from app_private.chem_question_source_releases as release_row
    where release_row.id = p_release_id
      and release_row.status in ('active', 'retired')
  ) then
    raise exception 'an active or retired junior release cannot be reset';
  end if;
  if exists (
    select 1
    from app_private.chem_question_source_releases as release_row
    where release_row.manifest_sha256 = p_manifest_sha256
      and release_row.id <> p_release_id
  ) then
    raise exception 'junior release manifest already belongs to another release';
  end if;
  if exists (
    select 1
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.source_release_id = p_release_id
  ) then
    raise exception 'a staged release cannot be reset after becoming the active provenance mapping';
  end if;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);

  delete from app_private.chem_question_assets as asset
  using public.chem_questions as question
  where question.source_release_id = p_release_id
    and asset.question_id = question.id;
  delete from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id;
  delete from public.chem_questions as question
  where question.source_release_id = p_release_id;
  delete from app_private.chem_question_source_releases as release_row
  where release_row.id = p_release_id;

  insert into app_private.chem_question_source_releases (
    id,
    manifest_sha256,
    grade_band,
    textbook_version,
    status,
    expected_question_count,
    verification_status,
    verification_manifest_sha256,
    verification_actor,
    verified_at,
    revision_contract
  ) values (
    p_release_id,
    p_manifest_sha256,
    '初三',
    p_textbook_version,
    'staged',
    p_expected_question_count,
    'pending',
    null,
    null,
    null,
    'v3_junior_native_text'
  );

  insert into app_private.chem_junior_source_release_specs (
    release_id,
    textbook_version,
    knowledge_ids
  ) values (
    p_release_id,
    p_textbook_version,
    v_knowledge_ids
  );

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);
end;
$$;

create or replace function public.chem_stage_junior_source_release_item(
  p_release_id uuid,
  p_item jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_textbook_version text;
  v_knowledge_ids text[];
  v_expected integer;
  v_fingerprint text;
  v_revision_token text;
  v_item_sha256 text;
  v_question public.chem_questions%rowtype;
  v_empty_asset_sha256 constant text :=
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
begin
  if p_release_id is null or p_item is null or pg_catalog.jsonb_typeof(p_item) <> 'object' then
    raise exception 'invalid junior source item';
  end if;
  if (select count(*) from pg_catalog.jsonb_object_keys(p_item)) <> 18
    or not (p_item ?& array[
      'question_id',
      'mother_id',
      'knowledge_id',
      'concept_key',
      'level',
      'stem',
      'options',
      'correct_option',
      'explanation',
      'scaffold',
      'same_type_key',
      'source_item_key',
      'parent_source_item_key',
      'canonical_source_id',
      'source_title',
      'source_exam',
      'source_question_no',
      'source_locator_label'
    ])
  then
    raise exception 'junior source item has an unexpected field set';
  end if;
  if exists (
    select 1
    from pg_catalog.unnest(array[
      'question_id',
      'mother_id',
      'knowledge_id',
      'concept_key',
      'stem',
      'explanation',
      'same_type_key',
      'source_item_key',
      'parent_source_item_key',
      'canonical_source_id',
      'source_title',
      'source_exam',
      'source_question_no',
      'source_locator_label'
    ]::text[]) as required(field_name)
    where pg_catalog.jsonb_typeof(p_item->required.field_name) is distinct from 'string'
  )
    or pg_catalog.jsonb_typeof(p_item->'level') is distinct from 'number'
    or pg_catalog.jsonb_typeof(p_item->'correct_option') is distinct from 'number'
    or pg_catalog.jsonb_typeof(p_item->'scaffold') not in ('string', 'null')
  then
    raise exception 'junior source item field types are invalid';
  end if;
  if pg_catalog.jsonb_typeof(p_item->'options') is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_item->'options') <> 4
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_item->'options') as option_value
      where pg_catalog.jsonb_typeof(option_value) <> 'string'
        or length(btrim(option_value #>> '{}')) = 0
    )
    or (
      select count(distinct btrim(option_value))
      from pg_catalog.jsonb_array_elements_text(p_item->'options') as option_value
    ) <> 4
  then
    raise exception 'junior source item requires four distinct non-empty text options';
  end if;
  if coalesce(p_item->>'level', '') !~ '^[1-8]$'
    or coalesce(p_item->>'correct_option', '') !~ '^[0-3]$'
    or length(btrim(coalesce(p_item->>'question_id', ''))) not between 1 and 160
    or length(btrim(coalesce(p_item->>'mother_id', ''))) not between 1 and 160
    or length(btrim(coalesce(p_item->>'knowledge_id', ''))) not between 1 and 160
    or length(btrim(coalesce(p_item->>'concept_key', ''))) not between 1 and 160
    or length(btrim(coalesce(p_item->>'same_type_key', ''))) not between 1 and 200
    or length(btrim(coalesce(p_item->>'source_item_key', ''))) not between 16 and 240
    or length(btrim(coalesce(p_item->>'parent_source_item_key', ''))) not between 16 and 240
    or coalesce(p_item->>'canonical_source_id', '') !~ '^[A-Za-z0-9._:-]{3,160}$'
    or length(btrim(coalesce(p_item->>'stem', ''))) not between 1 and 12000
    or length(btrim(coalesce(p_item->>'explanation', ''))) not between 1 and 12000
    or length(coalesce(p_item->>'scaffold', '')) > 12000
    or length(btrim(coalesce(p_item->>'source_title', ''))) not between 1 and 300
    or length(btrim(coalesce(p_item->>'source_exam', ''))) not between 1 and 300
    or length(btrim(coalesce(p_item->>'source_question_no', ''))) not between 1 and 100
    or length(btrim(coalesce(p_item->>'source_locator_label', ''))) not between 1 and 500
    or concat_ws(
      ' ',
      p_item->>'stem',
      (p_item->'options')::text,
      p_item->>'explanation',
      p_item->>'scaffold'
    ) ~ '(来源|出处|选自|题源|中考|模拟|真题)'
    or concat_ws(
      ' ',
      p_item->>'source_title',
      p_item->>'source_exam',
      p_item->>'source_question_no',
      p_item->>'source_locator_label'
    ) ~* '([a-z]:[\\/]|file:[\\/]|\\\\\\\\|/(users|home)/|appdata)'
  then
    raise exception 'junior source item violates its native-text or provenance contract';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select
    spec.textbook_version,
    spec.knowledge_ids,
    release_row.expected_question_count
  into v_textbook_version, v_knowledge_ids, v_expected
  from app_private.chem_question_source_releases as release_row
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = release_row.textbook_version
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.status = 'staged'
    and release_row.revision_contract = 'v3_junior_native_text'
  for update of release_row, spec;

  if not found
    or not (btrim(p_item->>'knowledge_id') = any(v_knowledge_ids))
    or not exists (
      select 1
      from public.chem_skills as skill
      where skill.id = btrim(p_item->>'knowledge_id')
        and skill.grade_band = '初三'
        and skill.active
        and (p_item->>'level')::smallint <= skill.max_level
    )
  then
    raise exception 'junior source item is outside the staged textbook knowledge spec';
  end if;
  if exists (
    select 1
    from public.chem_questions as question
    where question.id = btrim(p_item->>'question_id')
      and question.source_release_id is distinct from p_release_id
  ) then
    raise exception 'junior source question id already belongs to another release';
  end if;
  if (
    select count(*)
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and question.id <> btrim(p_item->>'question_id')
  ) >= v_expected then
    raise exception 'junior staged release already contains its exact declared item count';
  end if;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);

  if exists (
    select 1
    from app_private.chem_question_assets as asset
    where asset.question_id = btrim(p_item->>'question_id')
  ) then
    raise exception 'junior source item cannot replace a question with private assets';
  end if;
  delete from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id
    and item.question_id = btrim(p_item->>'question_id');
  delete from public.chem_questions as question
  where question.source_release_id = p_release_id
    and question.id = btrim(p_item->>'question_id');

  v_fingerprint := app_private.chem_h3_content_fingerprint(
    btrim(p_item->>'stem'),
    p_item->'options'
  );

  insert into public.chem_questions (
    id,
    mother_id,
    skill_id,
    knowledge_id,
    concept_key,
    level,
    grade_band,
    textbook_version,
    stem,
    options,
    correct_option,
    explanation,
    scaffold,
    review_status,
    scope_status,
    source_kind,
    source_info,
    image_url,
    asset_refs,
    render_mode,
    same_type_key,
    source_item_key,
    parent_source_item_key,
    content_fingerprint,
    question_revision_token,
    source_release_id,
    usable_for_class_quiz,
    usable_for_review,
    usable_for_exam_sprint,
    usable_for_demo
  ) values (
    btrim(p_item->>'question_id'),
    btrim(p_item->>'mother_id'),
    btrim(p_item->>'knowledge_id'),
    btrim(p_item->>'knowledge_id'),
    btrim(p_item->>'concept_key'),
    (p_item->>'level')::smallint,
    '初三',
    v_textbook_version,
    btrim(p_item->>'stem'),
    p_item->'options',
    (p_item->>'correct_option')::smallint,
    btrim(p_item->>'explanation'),
    nullif(btrim(coalesce(p_item->>'scaffold', '')), ''),
    'approved',
    'IN',
    'licensed_local',
    pg_catalog.jsonb_build_object(
      'title', btrim(p_item->>'source_title'),
      'exam', btrim(p_item->>'source_exam'),
      'questionNo', btrim(p_item->>'source_question_no'),
      'locator', btrim(p_item->>'source_locator_label')
    ),
    null,
    '[]'::jsonb,
    'native',
    btrim(p_item->>'same_type_key'),
    btrim(p_item->>'source_item_key'),
    btrim(p_item->>'parent_source_item_key'),
    v_fingerprint,
    v_empty_asset_sha256,
    p_release_id,
    false,
    false,
    false,
    false
  );

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = btrim(p_item->>'question_id')
  for update;

  v_revision_token := app_private.chem_junior_native_revision_sha256(v_question);
  update public.chem_questions as question
  set question_revision_token = v_revision_token,
      updated_at = now()
  where question.id = v_question.id;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = btrim(p_item->>'question_id');

  v_item_sha256 := app_private.chem_junior_native_release_item_sha256(
    v_question,
    btrim(p_item->>'canonical_source_id')
  );

  insert into app_private.chem_question_source_release_items (
    release_id,
    question_id,
    canonical_source_id,
    question_asset_sha256,
    analysis_asset_sha256,
    item_sha256
  ) values (
    p_release_id,
    v_question.id,
    btrim(p_item->>'canonical_source_id'),
    v_empty_asset_sha256,
    v_empty_asset_sha256,
    v_item_sha256
  );

  update app_private.chem_question_source_releases as release_row
  set verification_status = 'pending',
      verification_manifest_sha256 = null,
      verification_actor = null,
      verified_at = null
  where release_row.id = p_release_id;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);

  return pg_catalog.jsonb_build_object(
    'question_id', v_question.id,
    'content_fingerprint', v_fingerprint,
    'question_revision_token', v_revision_token,
    'item_sha256', v_item_sha256
  );
end;
$$;

create or replace function public.chem_stage_junior_source_release_provenance(
  p_release_id uuid,
  p_knowledge_id text,
  p_source_id text,
  p_source_locator text,
  p_source_sha256 text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_textbook_version text;
  v_knowledge_ids text[];
begin
  if p_release_id is null
    or length(btrim(coalesce(p_knowledge_id, ''))) not between 1 and 160
    or length(btrim(coalesce(p_source_id, ''))) not between 3 and 160
    or length(btrim(coalesce(p_source_locator, ''))) not between 3 and 500
    or coalesce(p_source_sha256, '') !~ '^[0-9a-f]{64}$'
    or concat_ws(' ', p_source_id, p_source_locator)
      ~* '([a-z]:[\\/]|file:[\\/]|\\\\\\\\|/(users|home)/|appdata)'
  then
    raise exception 'invalid junior source provenance';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select spec.textbook_version, spec.knowledge_ids
  into v_textbook_version, v_knowledge_ids
  from app_private.chem_question_source_releases as release_row
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = release_row.textbook_version
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.status = 'staged'
    and release_row.revision_contract = 'v3_junior_native_text'
  for update of release_row, spec;

  if not found or not (btrim(p_knowledge_id) = any(v_knowledge_ids)) then
    raise exception 'junior provenance is outside the staged textbook knowledge spec';
  end if;

  insert into app_private.chem_junior_source_release_provenance (
    release_id,
    textbook_version,
    knowledge_id,
    source_id,
    source_locator,
    source_sha256,
    verification_status,
    verification_actor,
    reviewed_at,
    updated_at
  ) values (
    p_release_id,
    v_textbook_version,
    btrim(p_knowledge_id),
    btrim(p_source_id),
    btrim(p_source_locator),
    p_source_sha256,
    'pending_review',
    null,
    null,
    now()
  )
  on conflict (release_id, knowledge_id) do update set
    textbook_version = excluded.textbook_version,
    source_id = excluded.source_id,
    source_locator = excluded.source_locator,
    source_sha256 = excluded.source_sha256,
    verification_status = 'pending_review',
    verification_actor = null,
    reviewed_at = null,
    updated_at = now();

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);
  update app_private.chem_question_source_releases as release_row
  set verification_status = 'pending',
      verification_manifest_sha256 = null,
      verification_actor = null,
      verified_at = null
  where release_row.id = p_release_id;
  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);
end;
$$;

create or replace function public.chem_verify_junior_source_release_provenance(
  p_release_id uuid,
  p_knowledge_id text,
  p_source_sha256 text,
  p_verification_actor text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_release_id is null
    or length(btrim(coalesce(p_knowledge_id, ''))) not between 1 and 160
    or coalesce(p_source_sha256, '') !~ '^[0-9a-f]{64}$'
    or p_verification_actor is distinct from 'codex-source-provenance-qa'
  then
    raise exception 'invalid junior provenance verification';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  perform provenance.knowledge_id
  from app_private.chem_junior_source_release_provenance as provenance
  join app_private.chem_question_source_releases as release_row
    on release_row.id = provenance.release_id
   and release_row.grade_band = '初三'
   and release_row.status = 'staged'
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = provenance.textbook_version
   and provenance.knowledge_id = any(spec.knowledge_ids)
  where provenance.release_id = p_release_id
    and provenance.knowledge_id = btrim(p_knowledge_id)
    and provenance.source_sha256 = p_source_sha256
  for update of release_row, provenance, spec;

  if not found then
    raise exception 'staged junior provenance and source digest do not match';
  end if;

  update app_private.chem_junior_source_release_provenance as provenance
  set verification_status = 'verified',
      verification_actor = p_verification_actor,
      reviewed_at = now(),
      updated_at = now()
  where provenance.release_id = p_release_id
    and provenance.knowledge_id = btrim(p_knowledge_id)
    and provenance.source_sha256 = p_source_sha256;
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'junior provenance verification affected %, expected 1', v_updated;
  end if;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);
  update app_private.chem_question_source_releases as release_row
  set verification_status = 'pending',
      verification_manifest_sha256 = null,
      verification_actor = null,
      verified_at = null
  where release_row.id = p_release_id;
  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);
end;
$$;

create or replace function app_private.chem_assert_junior_source_release(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_require_full_visual_verified boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_textbook_version text;
  v_knowledge_ids text[];
  v_expected integer;
  v_status text;
  v_verification_status text;
  v_verification_manifest text;
  v_verification_actor text;
  v_verified_at timestamptz;
  v_question_count integer;
  v_item_count integer;
  v_provenance_count integer;
  v_distinct_count integer;
  v_computed_manifest text;
  v_empty_asset_sha256 constant text :=
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
begin
  if p_release_id is null
    or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$'
    or p_require_full_visual_verified is null
  then
    raise exception 'invalid junior release preflight identity';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select
    release_row.textbook_version,
    spec.knowledge_ids,
    release_row.expected_question_count,
    release_row.status,
    release_row.verification_status,
    release_row.verification_manifest_sha256,
    release_row.verification_actor,
    release_row.verified_at
  into
    v_textbook_version,
    v_knowledge_ids,
    v_expected,
    v_status,
    v_verification_status,
    v_verification_manifest,
    v_verification_actor,
    v_verified_at
  from app_private.chem_question_source_releases as release_row
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = release_row.textbook_version
  where release_row.id = p_release_id
    and release_row.manifest_sha256 = p_manifest_sha256
    and release_row.grade_band = '初三'
    and release_row.revision_contract = 'v3_junior_native_text'
  for update of release_row, spec;

  if not found
    or v_status <> 'staged'
    or v_expected not between 21 and 2000
    or cardinality(v_knowledge_ids) not between 3 and 200
    or v_expected < 7 * cardinality(v_knowledge_ids)
    or (
      p_require_full_visual_verified
      and (
        v_verification_status <> 'full_visual_verified'
        or v_verification_manifest is distinct from p_manifest_sha256
        or v_verification_actor is distinct from 'codex-full-visual-qa'
        or v_verified_at is null
      )
    )
  then
    raise exception 'junior release is missing, not staged, or not bound to its verified manifest';
  end if;

  -- The parent row lock blocks new FK children.  Deterministic child locks
  -- close update/delete races before any count, digest or provenance check.
  perform question.id
  from public.chem_questions as question
  where question.source_release_id = p_release_id
  order by question.id
  for update;

  perform item.question_id
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id
  order by item.question_id
  for update;

  perform provenance.knowledge_id
  from app_private.chem_junior_source_release_provenance as provenance
  where provenance.release_id = p_release_id
  order by provenance.knowledge_id
  for update;

  perform asset.asset_path
  from app_private.chem_question_assets as asset
  join public.chem_questions as question on question.id = asset.question_id
  where question.source_release_id = p_release_id
  order by asset.asset_path
  for update of asset;

  -- Curriculum publication is rare and must not race a source activation.
  -- SHARE blocks concurrent ready-day INSERT/UPDATE until this transaction's
  -- full subset check and atomic release switch have completed.
  lock table public.chem_junior_curriculum_days in share mode;

  if exists (
    select 1
    from public.chem_junior_curriculum_days as curriculum
    cross join lateral pg_catalog.unnest(curriculum.knowledge_skill_ids)
      as requested(knowledge_id)
    where curriculum.textbook_version = v_textbook_version
      and curriculum.release_status = 'ready'
      and not (requested.knowledge_id = any(v_knowledge_ids))
  ) or exists (
    select 1
    from public.chem_junior_daily_sessions as session
    cross join lateral pg_catalog.unnest(session.knowledge_skill_ids)
      as requested(knowledge_id)
    where session.textbook_version = v_textbook_version
      and session.status = 'active'
      and not (requested.knowledge_id = any(v_knowledge_ids))
  ) then
    raise exception 'junior release spec does not fund every ready curriculum or active-session route';
  end if;

  select count(*)::integer
  into v_question_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_question_count <> v_expected then
    raise exception 'junior release must contain exactly % questions, found %',
      v_expected, v_question_count;
  end if;

  select count(*)::integer
  into v_item_count
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id;
  if v_item_count <> v_expected then
    raise exception 'junior release ledger must contain exactly % items, found %',
      v_expected, v_item_count;
  end if;

  if exists (
    select 1
    from app_private.chem_question_assets as asset
    join public.chem_questions as question on question.id = asset.question_id
    where question.source_release_id = p_release_id
  ) then
    raise exception 'junior native-text release must contain zero private assets';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    left join public.chem_skills as skill on skill.id = question.skill_id
    where question.source_release_id = p_release_id
      and (
        question.grade_band <> '初三'
        or question.textbook_version is distinct from v_textbook_version
        or not (question.knowledge_id = any(v_knowledge_ids))
        or question.skill_id is distinct from question.knowledge_id
        or skill.id is null
        or skill.grade_band <> '初三'
        or not skill.active
        or question.level not between 1 and skill.max_level
        or question.source_kind <> 'licensed_local'
        or question.review_status <> 'approved'
        or question.scope_status <> 'IN'
        or question.usable_for_review
        or question.usable_for_class_quiz
        or question.usable_for_exam_sprint
        or question.usable_for_demo
        or question.render_mode <> 'native'
        or coalesce(btrim(question.image_url), '') <> ''
        or question.asset_refs <> '[]'::jsonb
        or length(btrim(coalesce(question.mother_id, ''))) = 0
        or length(btrim(coalesce(question.concept_key, ''))) = 0
        or length(btrim(coalesce(question.same_type_key, ''))) = 0
        or length(btrim(coalesce(question.source_item_key, ''))) < 16
        or length(btrim(coalesce(question.parent_source_item_key, ''))) < 16
        or length(btrim(coalesce(question.stem, ''))) = 0
        or length(btrim(coalesce(question.explanation, ''))) = 0
        or pg_catalog.jsonb_typeof(question.options) <> 'array'
        or case when pg_catalog.jsonb_typeof(question.options) = 'array'
          then pg_catalog.jsonb_array_length(question.options) <> 4
          else true
        end
        or question.correct_option not between 0 and 3
        or coalesce(question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
        or coalesce(question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
        or pg_catalog.jsonb_typeof(question.source_info) <> 'object'
        or length(btrim(coalesce(question.source_info->>'title', ''))) = 0
        or length(btrim(coalesce(question.source_info->>'exam', ''))) = 0
        or length(btrim(coalesce(question.source_info->>'questionNo', ''))) = 0
        or length(btrim(coalesce(question.source_info->>'locator', ''))) = 0
      )
  ) then
    raise exception 'junior release contains an ineligible native-text question';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    cross join lateral pg_catalog.jsonb_array_elements(question.options) as option_value
    where question.source_release_id = p_release_id
      and (
        pg_catalog.jsonb_typeof(option_value) <> 'string'
        or length(btrim(option_value #>> '{}')) = 0
      )
  ) then
    raise exception 'junior release contains a non-text or empty option';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and (
        select count(distinct btrim(option_text))
        from pg_catalog.jsonb_array_elements_text(question.options) as option_text
      ) <> 4
  ) then
    raise exception 'junior release contains duplicated answer options';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and concat_ws(
        ' ',
        question.stem,
        question.options::text,
        question.explanation,
        question.scaffold
      ) ~ '(来源|出处|选自|题源|中考|模拟|真题)'
  ) then
    raise exception 'junior release contains a visible source label';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and question.content_fingerprint is distinct from
        app_private.chem_h3_content_fingerprint(question.stem, question.options)
  ) then
    raise exception 'junior content fingerprint does not match normalized stem and options';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
      and question.question_revision_token is distinct from
        app_private.chem_junior_native_revision_sha256(question)
  ) then
    raise exception 'junior revision token does not match the native-text question';
  end if;

  if (
    select pg_catalog.array_agg(distinct question.knowledge_id order by question.knowledge_id)
    from public.chem_questions as question
    where question.source_release_id = p_release_id
  ) is distinct from v_knowledge_ids then
    raise exception 'junior release does not contain the exact declared textbook knowledge routes';
  end if;

  if exists (
    with foundation as (
      select question.knowledge_id, min(question.level) as foundation_level
      from public.chem_questions as question
      where question.source_release_id = p_release_id
      group by question.knowledge_id
    ), route_counts as (
      select
        question.knowledge_id,
        count(*) as total_count,
        count(*) filter (where question.level = foundation.foundation_level) as foundation_count,
        count(*) filter (where question.level > foundation.foundation_level) as higher_count
      from public.chem_questions as question
      join foundation on foundation.knowledge_id = question.knowledge_id
      where question.source_release_id = p_release_id
      group by question.knowledge_id
    )
    select 1
    from route_counts
    where total_count < 7 or foundation_count < 5 or higher_count < 2
  ) or (
    select count(distinct question.knowledge_id)
    from public.chem_questions as question
    where question.source_release_id = p_release_id
  ) <> cardinality(v_knowledge_ids) then
    raise exception 'each junior route requires at least five foundation and two higher-level originals';
  end if;

  -- Any source original may become an error/uncertainty.  Keep at least one
  -- same-knowledge, same-type, five-identity-distinct recovery candidate for
  -- every item, otherwise the next-day recovery contract is unsatisfiable.
  if exists (
    select 1
    from public.chem_questions as question
    where question.source_release_id = p_release_id
    group by
      question.textbook_version,
      question.knowledge_id,
      question.same_type_key
    having count(*) < 2
      or count(distinct question.id) < 2
      or count(distinct question.mother_id) < 2
      or count(distinct question.source_item_key) < 2
      or count(distinct question.parent_source_item_key) < 2
      or count(distinct question.content_fingerprint) < 2
  ) then
    raise exception 'every junior original requires a five-identity-distinct same-type recovery partner';
  end if;

  select count(distinct question.mother_id)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior mother identities are not unique inside the release';
  end if;
  select count(distinct question.source_item_key)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior source-item identities are not unique inside the release';
  end if;
  select count(distinct question.parent_source_item_key)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior parent-source identities are not unique inside the release';
  end if;
  select count(distinct question.content_fingerprint)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior content fingerprints are not unique inside the release';
  end if;
  select count(distinct question.question_revision_token)::integer
  into v_distinct_count
  from public.chem_questions as question
  where question.source_release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior revision identities are not unique inside the release';
  end if;

  if exists (
    select 1
    from public.chem_questions as question
    left join app_private.chem_question_source_release_items as item
      on item.release_id = question.source_release_id
     and item.question_id = question.id
    where question.source_release_id = p_release_id
      and (
        item.question_id is null
        or item.question_asset_sha256 <> v_empty_asset_sha256
        or item.analysis_asset_sha256 <> v_empty_asset_sha256
        or item.item_sha256 is distinct from
          app_private.chem_junior_native_release_item_sha256(
            question,
            item.canonical_source_id
          )
      )
  ) then
    raise exception 'junior release ledger digest or zero-asset attestation is invalid';
  end if;

  select count(distinct item.canonical_source_id)::integer
  into v_distinct_count
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id;
  if v_distinct_count <> v_expected then
    raise exception 'junior canonical source identities are not unique inside the release';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.string_agg(item.item_sha256, E'\n' order by item.question_id),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_computed_manifest
  from app_private.chem_question_source_release_items as item
  where item.release_id = p_release_id;

  if v_computed_manifest is distinct from p_manifest_sha256 then
    raise exception 'junior release manifest does not match the exact staged item ledger';
  end if;

  select count(*)::integer
  into v_provenance_count
  from app_private.chem_junior_source_release_provenance as provenance
  where provenance.release_id = p_release_id;
  if v_provenance_count <> cardinality(v_knowledge_ids) or exists (
    select 1
    from app_private.chem_junior_source_release_provenance as provenance
    where provenance.release_id = p_release_id
      and (
        provenance.textbook_version is distinct from v_textbook_version
        or not (provenance.knowledge_id = any(v_knowledge_ids))
        or provenance.verification_status <> 'verified'
        or provenance.verification_actor is distinct from 'codex-source-provenance-qa'
        or provenance.reviewed_at is null
        or coalesce(provenance.source_sha256, '') !~ '^[0-9a-f]{64}$'
      )
  ) then
    raise exception 'junior release requires one verified provenance row for every textbook route';
  end if;
end;
$$;

revoke all on function app_private.chem_assert_junior_source_release(uuid,text,boolean)
  from public, anon, authenticated, service_role;

create or replace function public.chem_preflight_junior_source_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (
  release_status text,
  verification_status text,
  questions integer,
  items integer,
  private_assets integer,
  verified_provenance integer,
  manifest_matches boolean,
  ready boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.chem_assert_junior_source_release(
    p_release_id,
    p_manifest_sha256,
    false
  );

  return query
  select
    release_row.status,
    release_row.verification_status,
    (
      select count(*)::integer
      from public.chem_questions as question
      where question.source_release_id = p_release_id
    ),
    (
      select count(*)::integer
      from app_private.chem_question_source_release_items as item
      where item.release_id = p_release_id
    ),
    (
      select count(*)::integer
      from app_private.chem_question_assets as asset
      join public.chem_questions as question on question.id = asset.question_id
      where question.source_release_id = p_release_id
    ),
    (
      select count(*)::integer
      from app_private.chem_junior_source_release_provenance as provenance
      where provenance.release_id = p_release_id
        and provenance.verification_status = 'verified'
    ),
    release_row.manifest_sha256 = p_manifest_sha256,
    true
  from app_private.chem_question_source_releases as release_row
  where release_row.id = p_release_id
    and release_row.grade_band = '初三';
end;
$$;

create or replace function public.chem_mark_junior_source_release_full_visual_verified(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_verification_actor text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_verification_actor is distinct from 'codex-full-visual-qa' then
    raise exception 'verification actor is not the server-owned full visual QA identity';
  end if;

  perform app_private.chem_assert_junior_source_release(
    p_release_id,
    p_manifest_sha256,
    false
  );

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);
  update app_private.chem_question_source_releases as release_row
  set verification_status = 'full_visual_verified',
      verification_manifest_sha256 = p_manifest_sha256,
      verification_actor = p_verification_actor,
      verified_at = now()
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.status = 'staged'
    and release_row.manifest_sha256 = p_manifest_sha256
    and release_row.revision_contract = 'v3_junior_native_text';
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'junior visual verification affected %, expected 1', v_updated;
  end if;
  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);
end;
$$;

create or replace function public.chem_activate_junior_source_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (
  release_id uuid,
  activated_questions integer,
  textbook_version text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_textbook_version text;
  v_knowledge_ids text[];
  v_expected integer;
  v_activated integer;
  v_status_count integer;
begin
  perform app_private.chem_assert_junior_source_release(
    p_release_id,
    p_manifest_sha256,
    true
  );

  select
    spec.textbook_version,
    spec.knowledge_ids,
    release_row.expected_question_count
  into v_textbook_version, v_knowledge_ids, v_expected
  from app_private.chem_question_source_releases as release_row
  join app_private.chem_junior_source_release_specs as spec
    on spec.release_id = release_row.id
   and spec.textbook_version = release_row.textbook_version
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.status = 'staged'
    and release_row.manifest_sha256 = p_manifest_sha256
  for update of release_row, spec;

  if not found then
    raise exception 'junior release changed after preflight';
  end if;

  -- Serialize with atomic issue/resume: those RPCs SHARE-lock the active
  -- release and UPDATE-lock the learner session.  Whichever transaction wins
  -- determines whether the old step is issued or this switch proceeds; there
  -- is no check-to-retire window that can strand a freshly issued question.
  perform session.id
  from public.chem_junior_daily_sessions as session
  where session.textbook_version = v_textbook_version
    and session.status = 'active'
  order by session.id
  for update;

  perform old_release.id
  from app_private.chem_question_source_releases as old_release
  where old_release.grade_band = '初三'
    and old_release.textbook_version = v_textbook_version
    and old_release.status = 'active'
    and old_release.id <> p_release_id
  order by old_release.id
  for update;

  -- Do not strand a learner who has already received an original from the old
  -- active batch.  A zero-step active session may safely select from the new
  -- batch after this transaction commits.
  if exists (
    select 1
    from public.chem_junior_daily_sessions as session
    join public.chem_junior_session_steps as step on step.session_id = session.id
    join public.chem_questions as question on question.id = step.question_id
    join app_private.chem_question_source_releases as old_release
      on old_release.id = question.source_release_id
    where session.status = 'active'
      and session.textbook_version = v_textbook_version
      and old_release.grade_band = '初三'
      and old_release.status = 'active'
      and old_release.id <> p_release_id
  ) then
    raise exception 'junior activation is blocked while an old-release session has issued steps';
  end if;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'on', true);
  perform pg_catalog.set_config('app.chem_release_activation', 'on', true);

  update public.chem_questions as question
  set usable_for_review = false,
      updated_at = now()
  where question.grade_band = '初三'
    and question.textbook_version = v_textbook_version
    and question.source_kind = 'licensed_local'
    and question.usable_for_review
    and question.source_release_id is distinct from p_release_id;

  update app_private.chem_question_source_releases as old_release
  set status = 'retired',
      retired_at = now()
  where old_release.grade_band = '初三'
    and old_release.textbook_version = v_textbook_version
    and old_release.status = 'active'
    and old_release.id <> p_release_id;

  update app_private.chem_junior_knowledge_provenance as old_provenance
  set verification_status = 'retired'
  where old_provenance.textbook_version = v_textbook_version
    and old_provenance.source_release_id <> p_release_id;

  insert into app_private.chem_junior_knowledge_provenance (
    textbook_version,
    knowledge_id,
    source_release_id,
    source_id,
    source_locator,
    source_sha256,
    verification_status,
    reviewed_at
  )
  select
    provenance.textbook_version,
    provenance.knowledge_id,
    provenance.release_id,
    provenance.source_id,
    provenance.source_locator,
    provenance.source_sha256,
    'verified',
    provenance.reviewed_at
  from app_private.chem_junior_source_release_provenance as provenance
  where provenance.release_id = p_release_id
    and provenance.textbook_version = v_textbook_version
    and provenance.knowledge_id = any(v_knowledge_ids)
    and provenance.verification_status = 'verified'
  on conflict (textbook_version, knowledge_id) do update set
    source_release_id = excluded.source_release_id,
    source_id = excluded.source_id,
    source_locator = excluded.source_locator,
    source_sha256 = excluded.source_sha256,
    verification_status = 'verified',
    reviewed_at = excluded.reviewed_at;

  update public.chem_questions as question
  set usable_for_review = true,
      updated_at = now()
  where question.source_release_id = p_release_id
    and question.grade_band = '初三'
    and question.textbook_version = v_textbook_version
    and question.skill_id = question.knowledge_id
    and question.knowledge_id = any(v_knowledge_ids);
  get diagnostics v_activated = row_count;
  if v_activated <> v_expected then
    raise exception 'junior activation enabled %, expected %', v_activated, v_expected;
  end if;

  update app_private.chem_question_source_releases as release_row
  set status = 'active',
      activated_at = now(),
      retired_at = null
  where release_row.id = p_release_id
    and release_row.grade_band = '初三'
    and release_row.textbook_version = v_textbook_version
    and release_row.status = 'staged'
    and release_row.verification_status = 'full_visual_verified'
    and release_row.verification_manifest_sha256 = p_manifest_sha256;
  get diagnostics v_status_count = row_count;
  if v_status_count <> 1 then
    raise exception 'junior activation status update affected %, expected 1', v_status_count;
  end if;

  if (
    select count(*)
    from app_private.chem_question_source_releases as release_row
    where release_row.grade_band = '初三'
      and release_row.textbook_version = v_textbook_version
      and release_row.status = 'active'
  ) <> 1 then
    raise exception 'junior textbook must have exactly one active source release';
  end if;
  if (
    select count(*)
    from public.chem_questions as question
    where question.grade_band = '初三'
      and question.textbook_version = v_textbook_version
      and question.source_kind = 'licensed_local'
      and question.usable_for_review
      and question.source_release_id = p_release_id
  ) <> v_expected
    or exists (
      select 1
      from public.chem_questions as question
      where question.grade_band = '初三'
        and question.textbook_version = v_textbook_version
        and question.source_kind = 'licensed_local'
        and question.usable_for_review
        and question.source_release_id is distinct from p_release_id
    )
  then
    raise exception 'junior activation postcondition did not expose only the new exact batch';
  end if;
  if (
    select count(*)
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.textbook_version = v_textbook_version
      and provenance.knowledge_id = any(v_knowledge_ids)
      and provenance.source_release_id = p_release_id
      and provenance.verification_status = 'verified'
  ) <> cardinality(v_knowledge_ids) then
    raise exception 'junior activation postcondition did not bind all verified provenance rows';
  end if;

  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);
  perform pg_catalog.set_config('app.chem_junior_release_lifecycle', 'off', true);

  return query select p_release_id, v_activated, v_textbook_version;
end;
$$;

revoke all on function public.chem_prepare_junior_source_release(uuid,text,text,text[],integer)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_stage_junior_source_release_item(uuid,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_stage_junior_source_release_provenance(uuid,text,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_verify_junior_source_release_provenance(uuid,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_preflight_junior_source_release(uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_mark_junior_source_release_full_visual_verified(uuid,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_activate_junior_source_release(uuid,text)
  from public, anon, authenticated, service_role;

grant execute on function public.chem_prepare_junior_source_release(uuid,text,text,text[],integer)
  to service_role;
grant execute on function public.chem_stage_junior_source_release_item(uuid,jsonb)
  to service_role;
grant execute on function public.chem_stage_junior_source_release_provenance(uuid,text,text,text,text)
  to service_role;
grant execute on function public.chem_verify_junior_source_release_provenance(uuid,text,text,text)
  to service_role;
grant execute on function public.chem_preflight_junior_source_release(uuid,text)
  to service_role;
grant execute on function public.chem_mark_junior_source_release_full_visual_verified(uuid,text,text)
  to service_role;
grant execute on function public.chem_activate_junior_source_release(uuid,text)
  to service_role;

comment on function public.chem_prepare_junior_source_release(uuid,text,text,text[],integer) is
  'Service-only idempotent reset/prepare entrypoint for one confirmed-textbook junior native-text release.';
comment on function public.chem_stage_junior_source_release_item(uuid,jsonb) is
  'Service-only one-original staging entrypoint; computes immutable content, revision and ledger digests server-side.';
comment on function public.chem_activate_junior_source_release(uuid,text) is
  'Atomically retires only the old release for this junior textbook, swaps verified provenance, and enables exactly the new manifest.';

alter table public.chem_junior_session_steps
  drop constraint if exists chem_junior_session_steps_skill_matches_knowledge;

alter table public.chem_junior_session_steps
  add constraint chem_junior_session_steps_skill_matches_knowledge
  check (skill_id = knowledge_id);

alter table public.chem_junior_session_steps
  drop constraint if exists chem_junior_session_steps_snapshot_contract;

alter table public.chem_junior_session_steps
  add constraint chem_junior_session_steps_snapshot_contract
  check (
    jsonb_typeof(question_snapshot) = 'object'
    and question_snapshot ?& array[
      'questionId',
      'motherId',
      'skillId',
      'knowledgeId',
      'level',
      'stem',
      'options',
      'correctOption',
      'explanation',
      'sourceReleaseId',
      'sameTypeKey',
      'sourceItemKey',
      'parentSourceItemKey',
      'contentFingerprint',
      'revisionToken',
      'renderMode',
      'routeKind',
      'routeReason'
    ]
    and jsonb_typeof(question_snapshot -> 'options') = 'array'
    and jsonb_typeof(question_snapshot -> 'correctOption') = 'number'
  );

-- The selector already avoids these five source identities.  Database-level
-- uniqueness closes the race between two simultaneous "next question" calls.
create unique index if not exists chem_junior_session_steps_session_mother_uidx
  on public.chem_junior_session_steps (session_id, mother_id);

create unique index if not exists chem_junior_session_steps_session_source_item_uidx
  on public.chem_junior_session_steps (session_id, source_item_key);

create unique index if not exists chem_junior_session_steps_session_parent_source_item_uidx
  on public.chem_junior_session_steps (session_id, parent_source_item_key);

create unique index if not exists chem_junior_session_steps_session_fingerprint_uidx
  on public.chem_junior_session_steps (session_id, content_fingerprint);

-- Lock one answer and record only conservative in-progress state.  A single
-- correct answer must never establish a verified mastery level.
create or replace function public.chem_junior_record_step(
  p_session_id uuid,
  p_student_id uuid,
  p_step_id uuid,
  p_selected_option smallint,
  p_uncertain boolean,
  p_duration_sec integer,
  p_revision_token text
)
returns table (
  step_id uuid,
  question_id text,
  selected_option smallint,
  uncertain boolean,
  duration_sec integer,
  correct boolean,
  answered_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_step public.chem_junior_session_steps%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_required_knowledge_count integer;
  v_required_card_count integer;
  v_correct boolean;
  v_duration integer;
begin
  if p_session_id is null
    or p_student_id is null
    or p_step_id is null
    or p_selected_option is null
    or p_uncertain is null
    or p_duration_sec is null
    or p_duration_sec < 0
    or p_duration_sec > 3600 then
    raise exception 'invalid junior step answer';
  end if;

  -- Match activation/issue lock order.  The source locks prevent a release
  -- swap while an answer is being authorized; the session row then
  -- serializes issue, resume, answer and finalization for this learner.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and session.study_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session step is unavailable';
  end if;

  -- The session is only an execution snapshot.  Re-lock and reassert its
  -- complete parent-plan authorization before reading a mutable profile,
  -- curriculum/card approval or any source-bearing row.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1
  for share;

  if not found then
    raise exception 'junior session plan contract changed before answer recording';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The session lock makes this required-skill set stable even though the
  -- step rows are deliberately not locked until after the cards.  Include
  -- recovery knowledge outside today's three and require one, not merely at
  -- least one, approved card for every required skill.
  perform card.id
  from public.chem_knowledge_cards as card
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = card.skill_id
  where card.review_status = 'approved'
  order by card.skill_id, card.id
  for share of card;

  select count(*)::integer
  into v_required_knowledge_count
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required_knowledge;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct required.skill_id
      from (
        select requested.skill_id
        from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
        union all
        select existing.knowledge_id
        from public.chem_junior_session_steps as existing
        where existing.session_id = p_session_id
      ) as required
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before answer recording';
  end if;

  -- Lock source-bearing rows only after all current authorization rows.  The
  -- separate statements make the step -> question -> provenance -> release
  -- order explicit and keep every source/snapshot gate ahead of writes.
  select step.*
  into v_step
  from public.chem_junior_session_steps as step
  where step.id = p_step_id
    and step.session_id = p_session_id
  for update;

  if not found then
    raise exception 'junior session step is unavailable';
  end if;
  if v_step.answered_at is not null then
    raise exception 'junior session step is already locked';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = v_step.question_id
  for share;

  if not found then
    raise exception 'junior source question is unavailable';
  end if;

  if v_question.grade_band is distinct from '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.source_kind is distinct from 'licensed_local'
    or v_question.review_status is distinct from 'approved'
    or v_question.scope_status is distinct from 'IN'
    or v_question.usable_for_review is distinct from true
    or v_question.render_mode is distinct from 'native'
    or v_question.image_url is not null
    or v_question.asset_refs is distinct from '[]'::jsonb
    or v_question.skill_id is distinct from v_step.skill_id
    or v_question.knowledge_id is distinct from v_step.knowledge_id
    or v_question.skill_id is distinct from v_question.knowledge_id
    or v_question.mother_id is distinct from v_step.mother_id
    or v_question.same_type_key is distinct from v_step.same_type_key
    or v_question.source_item_key is distinct from v_step.source_item_key
    or v_question.parent_source_item_key is distinct from v_step.parent_source_item_key
    or v_question.content_fingerprint is distinct from v_step.content_fingerprint
    or v_question.level is distinct from v_step.level
    or v_question.source_release_id is null
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option not between 0 and 3
  then
    raise exception 'junior question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior question contains duplicated options';
  end if;

  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      app_private.chem_junior_native_revision_sha256(v_question)
  then
    raise exception 'junior question content digest is stale';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_step.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior textbook knowledge provenance is not verified';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  where release.id = v_question.source_release_id
    and release.id = v_provenance.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share;

  if not found then
    raise exception 'junior source release is not active and fully verified';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', v_step.route_kind,
    'routeReason', v_step.route_reason
  );

  if v_step.question_snapshot is distinct from v_snapshot
    or coalesce(v_step.question_snapshot ->> 'revisionToken', '')
      <> coalesce(v_question.question_revision_token, '')
  then
    raise exception 'junior immutable question snapshot changed';
  end if;
  if p_selected_option not between 0 and 3 then
    raise exception 'junior selected option is outside the immutable option set';
  end if;
  if v_question.question_revision_token is distinct from p_revision_token then
    raise exception 'junior source question revision changed';
  end if;

  v_duration := least(3600, greatest(0, p_duration_sec));
  v_correct := p_selected_option = v_question.correct_option;

  perform pg_catalog.set_config('app.chem_junior_step_answer', 'on', true);
  update public.chem_junior_session_steps as updated
  set selected_option = p_selected_option,
      uncertain = p_uncertain,
      duration_sec = v_duration,
      correct = v_correct,
      answered_at = now(),
      updated_at = now()
  where updated.id = p_step_id
  returning
    updated.id,
    updated.question_id,
    updated.selected_option,
    updated.uncertain,
    updated.duration_sec,
    updated.correct,
    updated.answered_at
  into
    step_id,
    question_id,
    selected_option,
    uncertain,
    duration_sec,
    correct,
    answered_at;
  perform pg_catalog.set_config('app.chem_junior_step_answer', 'off', true);

  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    stability,
    consecutive_errors,
    next_review_at,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  ) values (
    p_student_id,
    v_step.skill_id,
    'learning',
    case when v_correct and not p_uncertain then 0 else 1 end,
    now() + interval '1 day',
    now(),
    false,
    now()
  )
  on conflict (student_id, skill_id) do update set
    stability = 'learning',
    consecutive_errors = case
      when v_correct and not p_uncertain
        then public.chem_student_skill_state.consecutive_errors
      else public.chem_student_skill_state.consecutive_errors + 1
    end,
    next_review_at = least(
      coalesce(public.chem_student_skill_state.next_review_at, now() + interval '1 day'),
      now() + interval '1 day'
    ),
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or (
        (not v_correct or p_uncertain)
        and public.chem_student_skill_state.consecutive_errors + 1 >= 3
      ),
    updated_at = now();

  return next;
end;
$$;

-- Finalization is the only place where junior mastery may be established.  It
-- is transactionally coupled to the unified attempt and answer snapshots, so
-- every audience reads the same evidence and retries are harmless.
create or replace function public.chem_junior_finalize_session(
  p_session_id uuid,
  p_student_id uuid
)
returns table (
  completed boolean,
  total_questions integer,
  correct_questions integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_plan_mode text;
  v_profile_id uuid;
  v_total integer;
  v_answered integer;
  v_correct integer;
  v_attempt_id uuid;
  v_answer_ledger_count integer;
  v_completed_at timestamptz;
  v_required_skill_count integer;
  v_required_card_count integer;
  v_verified_provenance_count integer;
  v_current_contract_count integer;
begin
  if p_session_id is null or p_student_id is null then
    raise exception 'invalid junior session finalization';
  end if;

  -- Use the same global lifecycle locks as activation, issue, validation and
  -- answer recording before taking the per-session serialization lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status in ('active', 'completed')
    and session.study_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  for update;

  if not found
    or pg_catalog.length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable';
  end if;

  -- Re-lock the complete authorization snapshot before touching steps or an
  -- existing attempt.  Even an idempotent retry must prove that the current
  -- plan/profile/curriculum/card contract still authorizes this student.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1
  for share;

  if not found then
    raise exception 'junior session plan contract changed before finalization';
  end if;
  v_plan_mode := v_plan.mode;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- The locked session makes the union stable before step locks are taken.
  -- It includes the current three skills plus every actual recovery skill.
  perform card.id
  from public.chem_knowledge_cards as card
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = card.skill_id
  where card.review_status = 'approved'
  order by card.skill_id, card.id
  for share of card;

  select count(*)::integer
  into v_required_skill_count
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required_knowledge;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct required.skill_id
      from (
        select requested.skill_id
        from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
        union all
        select existing.knowledge_id
        from public.chem_junior_session_steps as existing
        where existing.session_id = p_session_id
      ) as required
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_skill_count then
    raise exception 'junior knowledge-card approval contract changed before finalization';
  end if;

  -- Lock all issued steps, then their question, provenance and release rows in
  -- that order.  The following validation reads only rows held by these locks.
  perform step.id
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id
  order by step.sequence
  for update;

  select
    count(*)::integer,
    (count(*) filter (where step.answered_at is not null))::integer,
    (count(*) filter (where step.correct))::integer
  into v_total, v_answered, v_correct
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_total not between v_session.initial_question_target and v_session.hard_question_cap
    or v_answered <> v_total then
    raise exception 'junior session is not ready to finalize';
  end if;

  perform question.id
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by question.id
  for share of question;

  perform provenance.knowledge_id
  from app_private.chem_junior_knowledge_provenance as provenance
  join (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
    on required.skill_id = provenance.knowledge_id
  where provenance.textbook_version = v_session.textbook_version
  order by provenance.knowledge_id
  for share of provenance;

  perform release.id
  from app_private.chem_question_source_releases as release
  where release.id in (
    select provenance.source_release_id
    from app_private.chem_junior_knowledge_provenance as provenance
    where provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id in (
        select required.skill_id
        from (
          select requested.skill_id
          from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
          union
          select existing.knowledge_id
          from public.chem_junior_session_steps as existing
          where existing.session_id = p_session_id
        ) as required
      )
    union
    select question.source_release_id
    from public.chem_junior_session_steps as step
    join public.chem_questions as question
      on question.id = step.question_id
    where step.session_id = p_session_id
  )
  order by release.id
  for share of release;

  -- Every current or recovery knowledge route must still resolve to one
  -- verified provenance row on an active, fully verified native release.
  perform provenance.knowledge_id
  from (
    select distinct required.skill_id
    from (
      select requested.skill_id
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
      union all
      select existing.knowledge_id
      from public.chem_junior_session_steps as existing
      where existing.session_id = p_session_id
    ) as required
  ) as required
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = required.skill_id
   and provenance.verification_status = 'verified'
   and provenance.reviewed_at is not null
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null;
  get diagnostics v_verified_provenance_count = row_count;
  if v_verified_provenance_count <> v_required_skill_count then
    raise exception 'junior verified provenance is no longer active';
  end if;

  -- Revalidate every original and its exact issue snapshot while all source
  -- rows remain locked.  The CASE wrappers keep malformed JSON fail-closed
  -- without invoking array functions on a non-array value.
  select count(*)::integer
  into v_current_contract_count
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  join app_private.chem_junior_knowledge_provenance as provenance
    on provenance.textbook_version = v_session.textbook_version
   and provenance.knowledge_id = step.knowledge_id
   and provenance.source_release_id = question.source_release_id
   and provenance.verification_status = 'verified'
  join app_private.chem_question_source_releases as release
    on release.id = provenance.source_release_id
   and release.grade_band = '初三'
   and release.textbook_version = v_session.textbook_version
   and release.status = 'active'
   and release.verification_status = 'full_visual_verified'
   and release.verification_manifest_sha256 = release.manifest_sha256
   and release.revision_contract = 'v3_junior_native_text'
   and release.verified_at is not null
   and pg_catalog.length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
   and release.activated_at is not null
  where step.session_id = p_session_id
    and step.answered_at is not null
    and question.grade_band = '初三'
    and question.textbook_version = v_session.textbook_version
    and question.source_kind = 'licensed_local'
    and question.review_status = 'approved'
    and question.scope_status = 'IN'
    and question.usable_for_review
    and question.render_mode = 'native'
    and question.image_url is null
    and question.asset_refs = '[]'::jsonb
    and question.skill_id = step.skill_id
    and question.knowledge_id = step.knowledge_id
    and question.skill_id = question.knowledge_id
    and question.mother_id = step.mother_id
    and question.same_type_key = step.same_type_key
    and question.source_item_key = step.source_item_key
    and question.parent_source_item_key = step.parent_source_item_key
    and question.content_fingerprint = step.content_fingerprint
    and question.level = step.level
    and question.source_release_id is not null
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.stem, ''))) > 0
    and pg_catalog.length(pg_catalog.btrim(coalesce(question.explanation, ''))) > 0
    and pg_catalog.jsonb_typeof(question.options) = 'array'
    and case
      when pg_catalog.jsonb_typeof(question.options) = 'array'
        then pg_catalog.jsonb_array_length(question.options)
      else -1
    end = 4
    and question.correct_option between 0 and 3
    and not exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
      where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
        or pg_catalog.length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
    )
    and (
      select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
      from pg_catalog.jsonb_array_elements(
        case
          when pg_catalog.jsonb_typeof(question.options) = 'array' then question.options
          else '[]'::jsonb
        end
      ) as option_value(value)
    ) = 4
    and question.content_fingerprint =
      app_private.chem_h3_content_fingerprint(question.stem, question.options)
    and question.question_revision_token =
      app_private.chem_junior_native_revision_sha256(question)
    and step.question_snapshot = pg_catalog.jsonb_build_object(
      'questionId', question.id,
      'motherId', question.mother_id,
      'skillId', question.skill_id,
      'knowledgeId', question.knowledge_id,
      'conceptKey', question.concept_key,
      'level', question.level,
      'gradeBand', question.grade_band,
      'textbookVersion', question.textbook_version,
      'stem', question.stem,
      'options', question.options,
      'correctOption', question.correct_option,
      'explanation', question.explanation,
      'scaffold', question.scaffold,
      'reviewStatus', question.review_status,
      'scopeStatus', question.scope_status,
      'sourceKind', question.source_kind,
      'renderMode', question.render_mode,
      'imageUrl', question.image_url,
      'assetRefs', question.asset_refs,
      'sourceReleaseId', question.source_release_id,
      'sourceItemKey', question.source_item_key,
      'parentSourceItemKey', question.parent_source_item_key,
      'sameTypeKey', question.same_type_key,
      'contentFingerprint', question.content_fingerprint,
      'revisionToken', question.question_revision_token,
      'routeKind', step.route_kind,
      'routeReason', step.route_reason
    )
    and coalesce(step.question_snapshot ->> 'revisionToken', '') =
      coalesce(question.question_revision_token, '');

  if v_current_contract_count <> v_total then
    raise exception 'junior source evidence contract changed before finalization';
  end if;

  -- Only now may a completed retry return.  The existing attempt lookup is
  -- intentionally after all present-tense authorization and source locks so
  -- completion never bypasses a revoked plan/profile/curriculum/card/release.
  select attempt.id
  into v_attempt_id
  from public.chem_learning_attempts as attempt
  where attempt.junior_session_id = p_session_id
    and attempt.student_id = p_student_id
    and attempt.plan_day_id = v_session.plan_day_id
  for share;

  if v_attempt_id is not null then
    if v_session.status <> 'completed' then
      raise exception 'junior attempt exists for a session that is not completed';
    end if;
    select count(*)::integer
    into v_answer_ledger_count
    from public.chem_attempt_answers as answer
    where answer.attempt_id = v_attempt_id;
    if v_answer_ledger_count <> v_total then
      raise exception 'junior immutable answer ledger is incomplete';
    end if;
    return query select true, v_total, v_correct;
    return;
  end if;

  if v_session.status = 'completed' then
    raise exception 'completed junior session has no immutable attempt ledger';
  end if;

  v_completed_at := coalesce(v_session.completed_at, now());
  v_attempt_id := gen_random_uuid();

  insert into public.chem_learning_attempts (
    id,
    student_id,
    plan_day_id,
    attempt_kind,
    sequence,
    mode,
    started_at,
    completed_at,
    first_score,
    junior_session_id
  ) values (
    v_attempt_id,
    p_student_id,
    v_session.plan_day_id,
    'scheduled',
    0,
    v_plan_mode,
    v_session.started_at,
    v_completed_at,
    v_correct,
    p_session_id
  );

  insert into public.chem_attempt_answers (
    attempt_id,
    question_id,
    mother_id,
    skill_id,
    concept_key,
    level,
    correct,
    uncertain,
    duration_sec,
    selected_option,
    question_snapshot,
    created_at
  )
  select
    v_attempt_id,
    step.question_id,
    step.mother_id,
    step.skill_id,
    coalesce(nullif(step.question_snapshot ->> 'conceptKey', ''), question.concept_key),
    step.level,
    step.correct,
    step.uncertain,
    step.duration_sec,
    step.selected_option,
    coalesce(step.question_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'version', 2,
        'source', 'junior_adaptive_session',
        'capturedAt', step.created_at,
        'answeredAt', step.answered_at,
        'questionId', step.question_id,
        'motherId', step.mother_id,
        'skillId', step.skill_id,
        'knowledgeId', step.knowledge_id,
        'level', step.level,
        'gradeBand', coalesce(nullif(step.question_snapshot ->> 'gradeBand', ''), question.grade_band),
        'textbookVersion', v_session.textbook_version,
        'stem', coalesce(nullif(step.question_snapshot ->> 'stem', ''), question.stem),
        'options', case
          when jsonb_typeof(step.question_snapshot -> 'options') = 'array'
            then step.question_snapshot -> 'options'
          else question.options
        end,
        'correctOption', case
          when jsonb_typeof(step.question_snapshot -> 'correctOption') = 'number'
            then (step.question_snapshot ->> 'correctOption')::smallint
          else question.correct_option
        end,
        'explanation', coalesce(nullif(step.question_snapshot ->> 'explanation', ''), question.explanation),
        'scaffold', coalesce(step.question_snapshot ->> 'scaffold', question.scaffold),
        'sourceKind', 'licensed_local',
        'sourceReleaseId', coalesce(
          nullif(step.question_snapshot ->> 'sourceReleaseId', ''),
          question.source_release_id::text
        ),
        'sameTypeKey', step.same_type_key,
        'sourceItemKey', step.source_item_key,
        'parentSourceItemKey', step.parent_source_item_key,
        'contentFingerprint', step.content_fingerprint,
        'revisionToken', coalesce(
          nullif(step.question_snapshot ->> 'revisionToken', ''),
          question.question_revision_token
        ),
        'renderMode', coalesce(nullif(step.question_snapshot ->> 'renderMode', ''), question.render_mode),
        'routeKind', step.route_kind,
        'routeReason', step.route_reason,
        'sequence', step.sequence
      ),
    step.answered_at
  from public.chem_junior_session_steps as step
  join public.chem_questions as question
    on question.id = step.question_id
  where step.session_id = p_session_id
  order by step.sequence;

  select count(*)::integer
  into v_answer_ledger_count
  from public.chem_attempt_answers as answer
  where answer.attempt_id = v_attempt_id;

  if v_answer_ledger_count <> v_total then
    raise exception 'junior immutable answer ledger is incomplete';
  end if;

  with requested_skills as (
    select distinct unnest(v_session.knowledge_skill_ids) as skill_id
  ),
  verified_provenance as (
    select requested.skill_id, provenance.source_release_id
    from requested_skills as requested
    join app_private.chem_junior_knowledge_provenance as provenance
      on provenance.textbook_version = v_session.textbook_version
      and provenance.knowledge_id = requested.skill_id
      and provenance.verification_status = 'verified'
    join app_private.chem_question_source_releases as release
      on release.id = provenance.source_release_id
      and release.grade_band = '初三'
      and release.status = 'active'
      and release.verification_status = 'full_visual_verified'
  ),
  foundation_levels as (
    select provenance.skill_id, min(question.level)::smallint as foundation_level
    from verified_provenance as provenance
    join public.chem_questions as question
      on question.source_release_id = provenance.source_release_id
      and question.skill_id = provenance.skill_id
      and question.knowledge_id = provenance.skill_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.source_kind = 'licensed_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'native'
      and coalesce(btrim(question.image_url), '') = ''
      and question.asset_refs = '[]'::jsonb
    group by provenance.skill_id
  ),
  original_evidence as (
    select step.*
    from public.chem_junior_session_steps as step
    join verified_provenance as provenance
      on provenance.skill_id = step.skill_id
    join public.chem_questions as question
      on question.id = step.question_id
      and question.source_release_id = provenance.source_release_id
      and question.skill_id = step.skill_id
      and question.knowledge_id = step.knowledge_id
      and question.grade_band = '初三'
      and question.textbook_version = v_session.textbook_version
      and question.source_kind = 'licensed_local'
      and question.review_status = 'approved'
      and question.scope_status = 'IN'
      and question.usable_for_review
      and question.render_mode = 'native'
      and coalesce(btrim(question.image_url), '') = ''
      and question.asset_refs = '[]'::jsonb
      and question.mother_id = step.mother_id
      and question.source_item_key = step.source_item_key
      and question.parent_source_item_key = step.parent_source_item_key
      and question.content_fingerprint = step.content_fingerprint
      and question.question_revision_token is not distinct from nullif(step.question_snapshot ->> 'revisionToken', '')
    where step.session_id = p_session_id
  ),
  evidence as (
    select
      requested.skill_id,
      foundation.foundation_level,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_question_count,
      count(distinct original.mother_id) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_mother_count,
      count(distinct original.source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_source_count,
      count(distinct original.parent_source_item_key) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_parent_count,
      count(distinct original.content_fingerprint) filter (
        where original.correct
          and not original.uncertain
          and original.level = foundation.foundation_level
      ) as foundation_fingerprint_count,
      count(distinct original.question_id) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      ) as higher_question_count,
      max(original.level) filter (
        where original.correct
          and not original.uncertain
          and original.level > foundation.foundation_level
      )::smallint as achieved_level,
      (
        select count(*)::integer
        from public.chem_junior_session_steps as all_step
        where all_step.session_id = p_session_id
          and all_step.skill_id = requested.skill_id
          and (not all_step.correct or all_step.uncertain)
      ) as error_or_uncertain_count
    from requested_skills as requested
    left join foundation_levels as foundation
      on foundation.skill_id = requested.skill_id
    left join original_evidence as original
      on original.skill_id = requested.skill_id
    group by requested.skill_id, foundation.foundation_level
  ),
  mastery as (
    select
      evidence.*,
      evidence.foundation_level is not null
        and evidence.foundation_question_count >= 2
        and evidence.foundation_mother_count >= 2
        and evidence.foundation_source_count >= 2
        and evidence.foundation_parent_count >= 2
        and evidence.foundation_fingerprint_count >= 2
        and evidence.higher_question_count >= 1
        and evidence.achieved_level > evidence.foundation_level
        as mastered
    from evidence
  )
  insert into public.chem_student_skill_state (
    student_id,
    skill_id,
    verified_level,
    candidate_level,
    stability,
    consecutive_errors,
    next_review_at,
    review_interval_index,
    last_reviewed_at,
    teacher_intervention,
    updated_at
  )
  select
    p_student_id,
    mastery.skill_id,
    case when mastery.mastered then mastery.achieved_level else 0 end,
    case when mastery.mastered then mastery.achieved_level else null end,
    case when mastery.mastered then 'verified' else 'learning' end,
    mastery.error_or_uncertain_count,
    now() + case when mastery.mastered then interval '3 days' else interval '1 day' end,
    case when mastery.mastered then 1 else 0 end,
    now(),
    not mastery.mastered and mastery.error_or_uncertain_count >= 3,
    now()
  from mastery
  on conflict (student_id, skill_id) do update set
    verified_level = case
      when excluded.stability = 'verified'
        then greatest(public.chem_student_skill_state.verified_level, excluded.verified_level)
      else public.chem_student_skill_state.verified_level
    end,
    candidate_level = case
      when excluded.stability = 'verified' then excluded.candidate_level
      else null
    end,
    stability = case
      when excluded.stability = 'verified' then 'verified'
      when public.chem_student_skill_state.verified_level > 0
        and excluded.consecutive_errors > 0 then 'forgotten'
      else 'learning'
    end,
    consecutive_errors = case
      when excluded.stability = 'verified' then 0
      else greatest(
        public.chem_student_skill_state.consecutive_errors,
        excluded.consecutive_errors
      )
    end,
    next_review_at = excluded.next_review_at,
    review_interval_index = case
      when excluded.stability = 'verified'
        then least(4, public.chem_student_skill_state.review_interval_index + 1)
      else 0
    end,
    last_reviewed_at = now(),
    teacher_intervention = public.chem_student_skill_state.teacher_intervention
      or excluded.teacher_intervention,
    updated_at = now();

  update public.chem_junior_daily_sessions
  set status = 'completed',
      completed_at = v_completed_at,
      blocked_reason_code = null,
      blocked_reason_detail = null,
      blocked_at = null,
      updated_at = now()
  where id = p_session_id;

  return query select true, v_total, v_correct;
end;
$$;

revoke all on function public.chem_junior_record_step(uuid, uuid, uuid, smallint, boolean, integer, text)
  from public, anon, authenticated;
revoke all on function public.chem_junior_finalize_session(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.chem_junior_record_step(uuid, uuid, uuid, smallint, boolean, integer, text)
  to service_role;
grant execute on function public.chem_junior_finalize_session(uuid, uuid)
  to service_role;

-- The service role is intentionally powerful, so code convention alone is
-- not an atomic-entry guarantee.  Only chem_junior_issue_step opens this
-- transaction-local insert gate, and answer recording may never rewrite the
-- issued identity, route or immutable question snapshot.
create or replace function app_private.chem_guard_junior_session_step_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if pg_catalog.current_setting('app.chem_junior_step_issue', true) is distinct from 'on' then
      raise exception 'junior session steps may be inserted only by the atomic issue RPC';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if pg_catalog.current_setting('app.chem_junior_step_answer', true) is distinct from 'on' then
      raise exception 'junior session steps may be answered only by the atomic record-step RPC';
    end if;
    if new.id is distinct from old.id
      or new.session_id is distinct from old.session_id
      or new.sequence is distinct from old.sequence
      or new.question_id is distinct from old.question_id
      or new.mother_id is distinct from old.mother_id
      or new.skill_id is distinct from old.skill_id
      or new.knowledge_id is distinct from old.knowledge_id
      or new.same_type_key is distinct from old.same_type_key
      or new.source_item_key is distinct from old.source_item_key
      or new.parent_source_item_key is distinct from old.parent_source_item_key
      or new.content_fingerprint is distinct from old.content_fingerprint
      or new.level is distinct from old.level
      or new.route_kind is distinct from old.route_kind
      or new.route_reason is distinct from old.route_reason
      or new.question_snapshot is distinct from old.question_snapshot
      or new.created_at is distinct from old.created_at
    then
      raise exception 'junior issued identity, route and snapshot are immutable';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists chem_junior_session_steps_guard_mutation
  on public.chem_junior_session_steps;
create trigger chem_junior_session_steps_guard_mutation
before insert or update on public.chem_junior_session_steps
for each row execute function app_private.chem_guard_junior_session_step_mutation();

revoke all on function app_private.chem_guard_junior_session_step_mutation()
  from public, anon, authenticated, service_role;

-- Issue one native junior original only after re-locking every mutable row
-- that authorizes it.  The RPC returns identifiers only: question content is
-- never part of an error or database response, and the Edge function may
-- shape its already selected row only after this transaction succeeds.
create or replace function public.chem_junior_issue_step(
  p_session_id uuid,
  p_student_id uuid,
  p_question_id text,
  p_sequence smallint,
  p_route_kind text,
  p_route_reason text,
  p_question_snapshot jsonb
)
returns table (
  step_id uuid,
  question_id text,
  sequence smallint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_step_id uuid;
  v_existing_count integer;
  v_max_sequence integer;
  v_unanswered_count integer;
  v_profile_id uuid;
  v_required_knowledge_count integer;
  v_required_card_count integer;
begin
  if p_session_id is null
    or p_student_id is null
    or length(pg_catalog.btrim(coalesce(p_question_id, ''))) = 0
    or p_sequence is null
    or p_sequence not between 1 and 15
    or p_route_kind is null
    or p_route_kind not in (
      'new_learning',
      'advance',
      'stability_validation',
      'foundation_repair',
      'prior_error_recovery'
    )
    or length(pg_catalog.btrim(coalesce(p_route_reason, ''))) not between 1 and 1000
    or pg_catalog.jsonb_typeof(p_question_snapshot) is distinct from 'object'
  then
    raise exception 'invalid junior step issue request';
  end if;

  -- Use the exact lifecycle lock order before touching a session or source
  -- row. Activation holds these transaction locks while retiring/enabling a
  -- batch, so issue cannot observe or persist a half-swapped release.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  -- The session row is the serialization point for issue, resume, answer and
  -- finalization.  A blocked/completed/future session therefore fails before
  -- any source payload could be returned.
  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and session.study_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  for update;

  if not found
    or length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable for question issue';
  end if;

  -- A session is only an execution snapshot of its immutable daily plan. Lock
  -- and reassert every authorization-bearing plan field before consulting the
  -- profile, curriculum, step history or any question-bearing table.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1
  for share;

  if not found then
    raise exception 'junior session plan contract changed before question issue';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  -- Lock every existing step after the session serialization lock.  The
  -- count/max/unanswered assertions make a stale concurrent selector retry
  -- through the independently validated resume path.
  perform existing.id
  from public.chem_junior_session_steps as existing
  where existing.session_id = p_session_id
  order by existing.sequence
  for share;

  select
    count(*)::integer,
    coalesce(max(existing.sequence), 0)::integer,
    (count(*) filter (where existing.answered_at is null))::integer
  into v_existing_count, v_max_sequence, v_unanswered_count
  from public.chem_junior_session_steps as existing
  where existing.session_id = p_session_id;

  if v_unanswered_count <> 0
    or p_sequence <> v_existing_count + 1
    or p_sequence <> v_max_sequence + 1
  then
    raise exception using
      errcode = '40001',
      message = 'junior issue sequence is stale';
  end if;
  if p_sequence > v_session.hard_question_cap then
    raise exception 'junior session hard question cap reached';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = p_question_id
  for share;

  if not found then
    raise exception 'junior question is unavailable for issue';
  end if;

  if v_question.grade_band <> '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.source_kind <> 'licensed_local'
    or v_question.review_status <> 'approved'
    or v_question.scope_status <> 'IN'
    or not v_question.usable_for_review
    or v_question.render_mode <> 'native'
    or v_question.image_url is not null
    or v_question.asset_refs <> '[]'::jsonb
    or v_question.skill_id is null
    or v_question.knowledge_id is null
    or v_question.skill_id <> v_question.knowledge_id
    or length(pg_catalog.btrim(coalesce(v_question.mother_id, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.same_type_key, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.source_item_key, ''))) < 16
    or length(pg_catalog.btrim(coalesce(v_question.parent_source_item_key, ''))) < 16
    or coalesce(v_question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or coalesce(v_question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
    or v_question.source_release_id is null
    or length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option < 0
    or v_question.correct_option > 3
  then
    raise exception 'junior question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior question contains duplicated options';
  end if;

  -- Recompute both native-content digests while the question row is locked.
  -- A matching snapshot is insufficient if a privileged writer corrupted a
  -- revision token together with the content it is meant to bind.
  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      app_private.chem_junior_native_revision_sha256(v_question)
  then
    raise exception 'junior question content digest is stale';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  where release.id = v_question.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share;

  if not found then
    raise exception 'junior source release is not active and fully verified';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_question.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior textbook knowledge provenance is not verified';
  end if;

  -- Every non-recovery route must stay inside the three locked curriculum
  -- skills. A recovery route, including one for a current-day skill, needs a
  -- real earlier completed error/uncertain answer of the same type and a new
  -- value for all five source identities.
  if p_route_kind = 'prior_error_recovery' then
    perform prior_step.id
    from public.chem_junior_daily_sessions as prior_session
    join public.chem_junior_session_steps as prior_step
      on prior_step.session_id = prior_session.id
    where prior_session.student_id = p_student_id
      and prior_session.id <> p_session_id
      and prior_session.status = 'completed'
      and prior_session.textbook_version = v_session.textbook_version
      and prior_session.completed_at is not null
      and prior_session.completed_at < v_session.started_at
      and prior_step.answered_at is not null
      and (not prior_step.correct or prior_step.uncertain)
      and prior_step.knowledge_id = v_question.knowledge_id
      and prior_step.same_type_key = v_question.same_type_key
      and prior_step.question_id is distinct from v_question.id
      and prior_step.mother_id is distinct from v_question.mother_id
      and prior_step.source_item_key is distinct from v_question.source_item_key
      and prior_step.parent_source_item_key is distinct from v_question.parent_source_item_key
      and prior_step.content_fingerprint is distinct from v_question.content_fingerprint
    order by prior_session.completed_at desc, prior_step.sequence desc
    limit 1
    for share of prior_session, prior_step;

    if not found then
      raise exception 'junior recovery route has no matching prior error evidence';
    end if;
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior non-recovery question is outside the locked curriculum skills';
  end if;

  -- Lock and require exactly one approved knowledge card for every current
  -- curriculum skill and for the selected recovery skill, if it is outside
  -- the current three. This closes the Edge card-read/change race.
  perform card.id
  from public.chem_knowledge_cards as card
  where card.review_status = 'approved'
    and card.skill_id = any(v_session.knowledge_skill_ids || array[v_question.knowledge_id])
  order by card.id
  for share;

  select count(*)::integer
  into v_required_knowledge_count
  from (
    select distinct requested.skill_id
    from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
  ) as required;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct requested.skill_id
      from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before issue';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', p_route_kind,
    'routeReason', p_route_reason
  );

  if p_question_snapshot is distinct from v_snapshot then
    raise exception 'junior issue snapshot does not match the locked source question';
  end if;

  if exists (
    select 1
    from public.chem_junior_session_steps as existing
    where existing.session_id = p_session_id
      and (
        existing.question_id = v_question.id
        or existing.mother_id = v_question.mother_id
        or existing.source_item_key = v_question.source_item_key
        or existing.parent_source_item_key = v_question.parent_source_item_key
        or existing.content_fingerprint = v_question.content_fingerprint
      )
  ) then
    raise exception 'junior source identity was already issued in this session';
  end if;

  perform pg_catalog.set_config('app.chem_junior_step_issue', 'on', true);
  insert into public.chem_junior_session_steps (
    session_id,
    sequence,
    question_id,
    mother_id,
    skill_id,
    knowledge_id,
    same_type_key,
    source_item_key,
    parent_source_item_key,
    content_fingerprint,
    level,
    route_kind,
    route_reason,
    question_snapshot
  ) values (
    p_session_id,
    p_sequence,
    v_question.id,
    v_question.mother_id,
    v_question.skill_id,
    v_question.knowledge_id,
    v_question.same_type_key,
    v_question.source_item_key,
    v_question.parent_source_item_key,
    v_question.content_fingerprint,
    v_question.level,
    p_route_kind,
    p_route_reason,
    v_snapshot
  )
  returning id
  into v_step_id;
  perform pg_catalog.set_config('app.chem_junior_step_issue', 'off', true);

  return query select v_step_id, v_question.id, p_sequence;
end;
$$;

-- Revalidate an unanswered step before Edge resumes it.  Like issuance, this
-- returns only identifiers after locking the full current authorization chain;
-- retirement, provenance withdrawal, blocking or content drift therefore
-- produces no question-bearing database response.
create or replace function public.chem_junior_validate_issued_step(
  p_session_id uuid,
  p_student_id uuid,
  p_step_id uuid
)
returns table (
  step_id uuid,
  question_id text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chem_junior_daily_sessions%rowtype;
  v_plan public.chem_learning_plans%rowtype;
  v_curriculum public.chem_junior_curriculum_days%rowtype;
  v_step public.chem_junior_session_steps%rowtype;
  v_question public.chem_questions%rowtype;
  v_provenance app_private.chem_junior_knowledge_provenance%rowtype;
  v_release app_private.chem_question_source_releases%rowtype;
  v_snapshot jsonb;
  v_profile_id uuid;
  v_unanswered_count integer;
  v_required_knowledge_count integer;
  v_required_card_count integer;
begin
  if p_session_id is null or p_student_id is null or p_step_id is null then
    raise exception 'invalid junior issued-step validation request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release', 0)
  );

  select session.*
  into v_session
  from public.chem_junior_daily_sessions as session
  where session.id = p_session_id
    and session.student_id = p_student_id
    and session.status = 'active'
    and session.study_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
  for update;

  if not found
    or length(pg_catalog.btrim(coalesce(v_session.textbook_version, ''))) = 0
    or v_session.textbook_version = '待确认'
  then
    raise exception 'junior session is unavailable for resume';
  end if;

  -- Resume is a disclosure path too. A previously issued payload remains
  -- unavailable unless the locked plan is still the exact parent snapshot of
  -- the active session.
  select plan.*
  into v_plan
  from public.chem_learning_plans as plan
  where plan.id = v_session.plan_day_id
    and plan.student_id = v_session.student_id
    and plan.student_id = p_student_id
    and plan.delivery_mode = 'junior_adaptive'
    and plan.plan_date = v_session.study_date
    and plan.plan_date <= (pg_catalog.now() at time zone 'Asia/Shanghai')::date
    and plan.junior_curriculum_day_id = v_session.curriculum_day_id
    and plan.skill_ids = v_session.knowledge_skill_ids
    and plan.mode = 'REVIEW'
    and plan.question_count = v_session.initial_question_target
    and plan.round_limit = 1
  for share;

  if not found then
    raise exception 'junior session plan contract changed before resume';
  end if;

  select student.id
  into v_profile_id
  from public.chem_students_v2 as student
  where student.id = p_student_id
    and student.grade_band = '初三'
    and student.record_status = 'active'
    and student.textbook_version = v_session.textbook_version
  for share;

  if not found or v_profile_id is null then
    raise exception 'junior student textbook no longer matches the active session';
  end if;

  select curriculum.*
  into v_curriculum
  from public.chem_junior_curriculum_days as curriculum
  where curriculum.id = v_session.curriculum_day_id
    and curriculum.textbook_version = v_session.textbook_version
    and curriculum.release_status = 'ready'
    and curriculum.knowledge_skill_ids = v_session.knowledge_skill_ids
  for share;

  if not found
    or cardinality(v_session.knowledge_skill_ids) <> 3
    or (
      select count(distinct requested.skill_id)
      from unnest(v_session.knowledge_skill_ids) as requested(skill_id)
    ) <> 3
  then
    raise exception 'junior curriculum day is no longer ready or does not match the session';
  end if;

  select step.*
  into v_step
  from public.chem_junior_session_steps as step
  where step.id = p_step_id
    and step.session_id = p_session_id
  for share;

  if not found
    or v_step.answered_at is not null
    or v_step.selected_option is not null
    or v_step.uncertain is not null
    or v_step.duration_sec is not null
    or v_step.correct is not null
    or v_step.sequence not between 1 and v_session.hard_question_cap
  then
    raise exception 'junior issued step is unavailable for resume';
  end if;

  select (count(*) filter (where step.answered_at is null))::integer
  into v_unanswered_count
  from public.chem_junior_session_steps as step
  where step.session_id = p_session_id;

  if v_unanswered_count <> 1 then
    raise exception 'junior session does not have exactly one resumable step';
  end if;

  select question.*
  into v_question
  from public.chem_questions as question
  where question.id = v_step.question_id
  for share;

  if not found then
    raise exception 'junior issued question is unavailable';
  end if;

  if v_question.grade_band <> '初三'
    or v_question.textbook_version is distinct from v_session.textbook_version
    or v_question.source_kind <> 'licensed_local'
    or v_question.review_status <> 'approved'
    or v_question.scope_status <> 'IN'
    or not v_question.usable_for_review
    or v_question.render_mode <> 'native'
    or v_question.image_url is not null
    or v_question.asset_refs <> '[]'::jsonb
    or v_question.skill_id is null
    or v_question.knowledge_id is null
    or v_question.skill_id <> v_question.knowledge_id
    or length(pg_catalog.btrim(coalesce(v_question.mother_id, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.same_type_key, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.source_item_key, ''))) < 16
    or length(pg_catalog.btrim(coalesce(v_question.parent_source_item_key, ''))) < 16
    or coalesce(v_question.content_fingerprint, '') !~ '^[0-9a-f]{64}$'
    or coalesce(v_question.question_revision_token, '') !~ '^[0-9a-f]{64}$'
    or v_question.source_release_id is null
    or length(pg_catalog.btrim(coalesce(v_question.stem, ''))) = 0
    or length(pg_catalog.btrim(coalesce(v_question.explanation, ''))) = 0
  then
    raise exception 'junior issued question no longer satisfies the native source contract';
  end if;

  if pg_catalog.jsonb_typeof(v_question.options) is distinct from 'array' then
    raise exception 'junior issued question options are not an array';
  end if;
  if pg_catalog.jsonb_array_length(v_question.options) <> 4
    or v_question.correct_option < 0
    or v_question.correct_option > 3
  then
    raise exception 'junior issued question option contract is invalid';
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
    where pg_catalog.jsonb_typeof(option_value.value) is distinct from 'string'
      or length(pg_catalog.btrim(option_value.value #>> '{}')) = 0
  ) then
    raise exception 'junior issued question contains a non-text or empty option';
  end if;
  if (
    select count(distinct pg_catalog.btrim(option_value.value #>> '{}'))
    from pg_catalog.jsonb_array_elements(v_question.options) as option_value(value)
  ) <> 4 then
    raise exception 'junior issued question contains duplicated options';
  end if;

  if v_question.content_fingerprint is distinct from
      app_private.chem_h3_content_fingerprint(v_question.stem, v_question.options)
    or v_question.question_revision_token is distinct from
      app_private.chem_junior_native_revision_sha256(v_question)
  then
    raise exception 'junior issued question content digest is stale';
  end if;

  select release.*
  into v_release
  from app_private.chem_question_source_releases as release
  where release.id = v_question.source_release_id
    and release.grade_band = '初三'
    and release.textbook_version = v_session.textbook_version
    and release.status = 'active'
    and release.verification_status = 'full_visual_verified'
    and release.verification_manifest_sha256 = release.manifest_sha256
    and release.revision_contract = 'v3_junior_native_text'
    and release.verified_at is not null
    and length(pg_catalog.btrim(coalesce(release.verification_actor, ''))) > 0
    and release.activated_at is not null
  for share;

  if not found then
    raise exception 'junior issued source release is no longer active and verified';
  end if;

  select provenance.*
  into v_provenance
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.textbook_version = v_session.textbook_version
    and provenance.knowledge_id = v_question.knowledge_id
    and provenance.source_release_id = v_question.source_release_id
    and provenance.verification_status = 'verified'
    and provenance.reviewed_at is not null
  for share;

  if not found then
    raise exception 'junior issued textbook provenance is no longer verified';
  end if;

  if v_step.route_kind = 'prior_error_recovery' then
    perform prior_step.id
    from public.chem_junior_daily_sessions as prior_session
    join public.chem_junior_session_steps as prior_step
      on prior_step.session_id = prior_session.id
    where prior_session.student_id = p_student_id
      and prior_session.id <> p_session_id
      and prior_session.status = 'completed'
      and prior_session.textbook_version = v_session.textbook_version
      and prior_session.completed_at is not null
      and prior_session.completed_at < v_session.started_at
      and prior_step.answered_at is not null
      and (not prior_step.correct or prior_step.uncertain)
      and prior_step.knowledge_id = v_question.knowledge_id
      and prior_step.same_type_key = v_question.same_type_key
      and prior_step.question_id is distinct from v_question.id
      and prior_step.mother_id is distinct from v_question.mother_id
      and prior_step.source_item_key is distinct from v_question.source_item_key
      and prior_step.parent_source_item_key is distinct from v_question.parent_source_item_key
      and prior_step.content_fingerprint is distinct from v_question.content_fingerprint
    order by prior_session.completed_at desc, prior_step.sequence desc
    limit 1
    for share of prior_session, prior_step;

    if not found then
      raise exception 'junior issued recovery step no longer has prior error evidence';
    end if;
  elsif not (v_question.knowledge_id = any(v_session.knowledge_skill_ids)) then
    raise exception 'junior issued non-recovery step is outside the locked curriculum skills';
  end if;

  perform card.id
  from public.chem_knowledge_cards as card
  where card.review_status = 'approved'
    and card.skill_id = any(v_session.knowledge_skill_ids || array[v_question.knowledge_id])
  order by card.id
  for share;

  select count(*)::integer
  into v_required_knowledge_count
  from (
    select distinct requested.skill_id
    from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
  ) as required;

  select count(*)::integer
  into v_required_card_count
  from (
    select required.skill_id
    from (
      select distinct requested.skill_id
      from unnest(v_session.knowledge_skill_ids || array[v_question.knowledge_id]) as requested(skill_id)
    ) as required
    join public.chem_knowledge_cards as card
      on card.skill_id = required.skill_id
     and card.review_status = 'approved'
    group by required.skill_id
    having count(card.id) = 1
  ) as exactly_one_card;

  if v_required_card_count <> v_required_knowledge_count then
    raise exception 'junior knowledge-card approval contract changed before resume';
  end if;

  v_snapshot := pg_catalog.jsonb_build_object(
    'questionId', v_question.id,
    'motherId', v_question.mother_id,
    'skillId', v_question.skill_id,
    'knowledgeId', v_question.knowledge_id,
    'conceptKey', v_question.concept_key,
    'level', v_question.level,
    'gradeBand', v_question.grade_band,
    'textbookVersion', v_question.textbook_version,
    'stem', v_question.stem,
    'options', v_question.options,
    'correctOption', v_question.correct_option,
    'explanation', v_question.explanation,
    'scaffold', v_question.scaffold,
    'reviewStatus', v_question.review_status,
    'scopeStatus', v_question.scope_status,
    'sourceKind', v_question.source_kind,
    'renderMode', v_question.render_mode,
    'imageUrl', v_question.image_url,
    'assetRefs', v_question.asset_refs,
    'sourceReleaseId', v_question.source_release_id,
    'sourceItemKey', v_question.source_item_key,
    'parentSourceItemKey', v_question.parent_source_item_key,
    'sameTypeKey', v_question.same_type_key,
    'contentFingerprint', v_question.content_fingerprint,
    'revisionToken', v_question.question_revision_token,
    'routeKind', v_step.route_kind,
    'routeReason', v_step.route_reason
  );

  if v_step.question_id is distinct from v_question.id
    or v_step.mother_id is distinct from v_question.mother_id
    or v_step.skill_id is distinct from v_question.skill_id
    or v_step.knowledge_id is distinct from v_question.knowledge_id
    or v_step.same_type_key is distinct from v_question.same_type_key
    or v_step.source_item_key is distinct from v_question.source_item_key
    or v_step.parent_source_item_key is distinct from v_question.parent_source_item_key
    or v_step.content_fingerprint is distinct from v_question.content_fingerprint
    or v_step.level is distinct from v_question.level
    or v_step.question_snapshot is distinct from v_snapshot
  then
    raise exception 'junior issued step no longer matches its locked source snapshot';
  end if;

  return query select v_step.id, v_question.id;
end;
$$;

revoke all on function public.chem_junior_issue_step(uuid, uuid, text, smallint, text, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.chem_junior_validate_issued_step(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.chem_junior_issue_step(uuid, uuid, text, smallint, text, text, jsonb)
  to service_role;
grant execute on function public.chem_junior_validate_issued_step(uuid, uuid, uuid)
  to service_role;

comment on function public.chem_junior_issue_step(uuid, uuid, text, smallint, text, text, jsonb) is
  'Server-only atomic junior issue gate; returns identifiers only after locking and validating session, current native question, textbook provenance and active source release.';
comment on function public.chem_junior_validate_issued_step(uuid, uuid, uuid) is
  'Server-only atomic resume gate; returns identifiers only and fails closed when a session, source release, provenance row, question digest or immutable snapshot changed.';

commit;
