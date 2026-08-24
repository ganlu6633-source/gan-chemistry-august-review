-- Production contract for cumulative High-1 source-backed REVIEW releases.
-- Content payloads remain in the private deployment package.
begin;

alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_expected_question_count_check;
alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_expected_question_count_check check (
    (grade_band='高一' and (
      expected_question_count in (125,175)
      or expected_question_count between 211 and 275
    ))
    or (grade_band='高二' and expected_question_count between 200 and 2000)
    or (grade_band='高三' and expected_question_count between 275 and 2000)
  );

create table if not exists app_private.chem_question_source_release_extensions (
  release_id uuid primary key
    references app_private.chem_question_source_releases(id) on delete restrict,
  base_release_id uuid not null
    references app_private.chem_question_source_releases(id) on delete restrict,
  retained_question_count integer not null check (retained_question_count = 175),
  added_question_count integer not null check (added_question_count between 36 and 100),
  created_at timestamptz not null default now(),
  check (release_id <> base_release_id)
);
alter table app_private.chem_question_source_release_extensions enable row level security;
revoke all on table app_private.chem_question_source_release_extensions
  from public, anon, authenticated, service_role;

create table if not exists app_private.chem_question_source_release_lineage (
  release_id uuid not null
    references app_private.chem_question_source_releases(id) on delete restrict,
  question_id text not null
    references public.chem_questions(id) on delete restrict,
  previous_release_id uuid not null
    references app_private.chem_question_source_releases(id) on delete restrict,
  previous_question_id text not null
    references public.chem_questions(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (release_id, question_id),
  unique (release_id, previous_question_id),
  check (release_id <> previous_release_id),
  check (question_id <> previous_question_id)
);
create index if not exists chem_question_source_release_lineage_previous_question_idx
  on app_private.chem_question_source_release_lineage(previous_question_id);
alter table app_private.chem_question_source_release_lineage enable row level security;
revoke all on table app_private.chem_question_source_release_lineage
  from public, anon, authenticated, service_role;

create or replace function app_private.chem_guard_h1_source_release_extension_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_release_id uuid := case when tg_op='DELETE' then old.release_id else new.release_id end;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release',0)
  );
  if tg_op='UPDATE' and (
    new.release_id is distinct from old.release_id
    or new.base_release_id is distinct from old.base_release_id
  ) then
    raise exception 'expanded source-release lineage identity is immutable';
  end if;
  if not exists (
    select 1 from app_private.chem_question_source_releases release
    where release.id=v_release_id and release.status='staged'
  ) then
    raise exception 'expanded source-release lineage may change only while staged';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function app_private.chem_guard_h1_source_release_extension_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists chem_guard_h1_source_release_extension_mutation
  on app_private.chem_question_source_release_extensions;
create trigger chem_guard_h1_source_release_extension_mutation
before insert or update or delete on app_private.chem_question_source_release_extensions
for each row execute function app_private.chem_guard_h1_source_release_extension_mutation();

create or replace function app_private.chem_guard_h1_source_release_lineage_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_release_id uuid := case when tg_op='DELETE' then old.release_id else new.release_id end;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release',0)
  );
  if tg_op='UPDATE' and (
    new.release_id is distinct from old.release_id
    or new.question_id is distinct from old.question_id
    or new.previous_release_id is distinct from old.previous_release_id
    or new.previous_question_id is distinct from old.previous_question_id
  ) then
    raise exception 'question lineage identity is immutable';
  end if;
  if not exists (
    select 1 from app_private.chem_question_source_releases release
    where release.id=v_release_id and release.status='staged'
  ) then
    raise exception 'question lineage may change only while the target release is staged';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function app_private.chem_guard_h1_source_release_lineage_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists chem_guard_h1_source_release_lineage_mutation
  on app_private.chem_question_source_release_lineage;
create trigger chem_guard_h1_source_release_lineage_mutation
before insert or update or delete on app_private.chem_question_source_release_lineage
for each row execute function app_private.chem_guard_h1_source_release_lineage_mutation();

create or replace function public.chem_prepare_h1_expanded_source_release(
  p_release_id uuid,
  p_manifest_sha256 text,
  p_expected_question_count integer,
  p_base_release_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_release_id is null
    or p_base_release_id is null
    or p_release_id=p_base_release_id
    or coalesce(p_manifest_sha256,'') !~ '^[0-9a-f]{64}$'
    or p_expected_question_count not between 211 and 275
  then
    raise exception 'invalid expanded High-1 release specification';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release',0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release',0)
  );
  if not exists (
    select 1
    from app_private.chem_question_source_releases base
    where base.id=p_base_release_id
      and base.grade_band='高一'
      and base.status='active'
      and base.expected_question_count=175
      and base.verification_status='full_visual_verified'
      and base.verification_manifest_sha256=base.manifest_sha256
      and base.revision_contract='v2_explanation_assets'
      and (select count(*) from public.chem_questions q where q.source_release_id=base.id)=175
      and (
        select count(*) from app_private.chem_question_assets asset
        join public.chem_questions q on q.id=asset.question_id
        where q.source_release_id=base.id
      )=350
      and (
        select count(*) from app_private.chem_question_source_release_items item
        where item.release_id=base.id
      )=175
  ) then
    raise exception 'the declared High-1 baseline is not the complete active 175-question verified release';
  end if;
  if exists (
    select 1 from app_private.chem_question_source_releases release
    where release.id=p_release_id or release.manifest_sha256=p_manifest_sha256
  ) then
    raise exception 'expanded release id or manifest already exists';
  end if;
  insert into app_private.chem_question_source_releases(
    id,manifest_sha256,grade_band,status,expected_question_count,
    verification_status,revision_contract
  ) values (
    p_release_id,p_manifest_sha256,'高一','staged',p_expected_question_count,
    'pending','v2_explanation_assets'
  );
  insert into app_private.chem_question_source_release_extensions(
    release_id,base_release_id,retained_question_count,added_question_count
  ) values (
    p_release_id,p_base_release_id,175,p_expected_question_count-175
  );
end;
$$;
revoke all on function public.chem_prepare_h1_expanded_source_release(uuid,text,integer,uuid)
  from public, anon, authenticated;
grant execute on function public.chem_prepare_h1_expanded_source_release(uuid,text,integer,uuid)
  to service_role;

create or replace function public.chem_stage_h1_expanded_release_lineage(
  p_release_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release',0)
  );
  if not exists (
    select 1
    from app_private.chem_question_source_release_extensions extension_row
    join app_private.chem_question_source_releases target
      on target.id=extension_row.release_id
    join app_private.chem_question_source_releases base
      on base.id=extension_row.base_release_id
    where extension_row.release_id=p_release_id
      and target.grade_band='高一'
      and target.status='staged'
      and target.verification_status='pending'
      and target.expected_question_count
        =extension_row.retained_question_count+extension_row.added_question_count
      and base.grade_band='高一'
      and base.status='active'
      and base.expected_question_count=175
      and base.verification_status='full_visual_verified'
  ) then
    raise exception 'expanded High-1 release is not ready for lineage staging';
  end if;
  delete from app_private.chem_question_source_release_lineage lineage
  where lineage.release_id=p_release_id;
  insert into app_private.chem_question_source_release_lineage(
    release_id,question_id,previous_release_id,previous_question_id
  )
  select extension_row.release_id,new_q.id,extension_row.base_release_id,old_q.id
  from app_private.chem_question_source_release_extensions extension_row
  join public.chem_questions old_q
    on old_q.source_release_id=extension_row.base_release_id
  join public.chem_questions new_q
    on new_q.source_release_id=extension_row.release_id
   and new_q.mother_id=old_q.mother_id
   and new_q.source_item_key=old_q.source_item_key
   and new_q.content_fingerprint=old_q.content_fingerprint
  join app_private.chem_question_source_release_items old_item
    on old_item.release_id=extension_row.base_release_id
   and old_item.question_id=old_q.id
  join app_private.chem_question_source_release_items new_item
    on new_item.release_id=extension_row.release_id
   and new_item.question_id=new_q.id
   and new_item.canonical_source_id=old_item.canonical_source_id
   and new_item.question_asset_sha256=old_item.question_asset_sha256
   and new_item.analysis_asset_sha256=old_item.analysis_asset_sha256
  where extension_row.release_id=p_release_id
    and new_q.id<>old_q.id
    and new_q.skill_id is not distinct from old_q.skill_id
    and new_q.concept_key is not distinct from old_q.concept_key
    and new_q.level is not distinct from old_q.level
    and new_q.grade_band is not distinct from old_q.grade_band
    and new_q.stem is not distinct from old_q.stem
    and new_q.options is not distinct from old_q.options
    and new_q.correct_option is not distinct from old_q.correct_option
    and new_q.explanation is not distinct from old_q.explanation
    and new_q.scaffold is not distinct from old_q.scaffold
    and new_q.source_kind is not distinct from old_q.source_kind
    and new_q.source_info is not distinct from old_q.source_info
    and new_q.render_mode is not distinct from old_q.render_mode
    and new_q.image_url is not distinct from old_q.image_url
    and (
      select jsonb_agg(ref-'path' order by ref->>'kind')
      from jsonb_array_elements(new_q.asset_refs) ref
    ) is not distinct from (
      select jsonb_agg(ref-'path' order by ref->>'kind')
      from jsonb_array_elements(old_q.asset_refs) ref
    )
    and new_q.review_status='approved'
    and new_q.scope_status='IN'
    and not new_q.usable_for_review
    and not new_q.usable_for_class_quiz
    and not new_q.usable_for_exam_sprint
    and not new_q.usable_for_demo;
  get diagnostics v_inserted=row_count;
  if v_inserted<>175 then
    raise exception 'expanded release preserves % of 175 baseline questions',v_inserted;
  end if;
  return v_inserted;
end;
$$;
revoke all on function public.chem_stage_h1_expanded_release_lineage(uuid)
  from public, anon, authenticated;
grant execute on function public.chem_stage_h1_expanded_release_lineage(uuid)
  to service_role;

create or replace function app_private.chem_assert_h1_expanded_release(
  p_release_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_base_release_id uuid;
  v_expected integer;
begin
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
$$;
revoke all on function app_private.chem_assert_h1_expanded_release(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.chem_activate_source_original_release(
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
  v_expected_skill_ids text[];
  v_grade_band text;
  v_expected_concept_count integer;
begin
  if p_release_id is null or coalesce(p_manifest_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid release identity';
  end if;

  -- Serialize release switches.  Every assertion and both the old/new pool
  -- updates run in this function's transaction, so a failed assertion leaves
  -- the currently active REVIEW pool unchanged.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release', 0));

  select r.manifest_sha256, r.status, r.expected_question_count,
    r.verification_status, r.verification_manifest_sha256,
    r.verification_actor, r.verified_at, r.grade_band
  into v_release_manifest, v_release_status, v_release_expected,
    v_verification_status, v_verification_manifest,
    v_verification_actor, v_verified_at, v_grade_band
  from app_private.chem_question_source_releases r
  where r.id = p_release_id
    and r.grade_band in ('高一','高二','高三')
  for update;

  if not found
    or v_release_manifest <> p_manifest_sha256
    or v_release_status <> 'staged'
    or (v_grade_band = '高一' and v_release_expected not in (125,175) and v_release_expected not between 211 and 275)
    or (v_grade_band = '高二' and v_release_expected not between 200 and 2000)
    or (v_grade_band = '高三' and v_release_expected not between 275 and 2000)
    or v_verification_status <> 'full_visual_verified'
    or v_verification_manifest is distinct from p_manifest_sha256
    or length(btrim(coalesce(v_verification_actor, ''))) < 8
    or v_verified_at is null
  then
    raise exception 'release is missing, unverified, already activated, or manifest hash does not match';
  end if;

  v_expected_skill_ids := case v_grade_band
    when '高一' then case
      when v_release_expected >= 175 then array[
        'H1_CLASSIFY','H1_GAS_MOLAR_VOLUME','H1_MOLE_INTRO','H1_PERIODIC',
        'H1_REACTION_CLASSIFICATION','H1_REDOX','H1_SOLUTION_CONCENTRATION'
      ]::text[]
      else array['H1_CLASSIFY','H1_GAS_MOLAR_VOLUME','H1_MOLE_INTRO','H1_PERIODIC','H1_REDOX']::text[]
    end
    when '高二' then array['H2_ELECTRO','H2_EQUIL','H2_K','H2_KSP','H2_PH_HYDRO','H2_RATE','H2_THERMO','H2_WEAK']::text[]
    else array['H3_AQ','H3_ELECTRO','H3_EQUILIBRIUM','H3_EXPERIMENT','H3_INORGANIC','H3_ION_REDOX','H3_ORGANIC','H3_PROCESS','H3_STOICH','H3_STRUCTURE','H3_THERMO_RATE']::text[]
  end;
  v_expected_concept_count := pg_catalog.array_length(v_expected_skill_ids, 1) * 5;

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

  if v_grade_band = '高一' and v_release_expected between 211 and 275 then
    perform app_private.chem_assert_h1_expanded_release(p_release_id);
  elsif exists (
    select 1
    from app_private.chem_question_source_release_extensions extension_row
    where extension_row.release_id = p_release_id
  ) then
    raise exception 'only an expanded High-1 release may declare source-release lineage';
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release must contain exactly % questions, found %', v_release_expected, v_question_count;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
      and (
        q.grade_band <> v_grade_band
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
    raise exception 'release does not contain the exact REVIEW skills for the release grade';
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.source_release_id = p_release_id
    group by q.skill_id
    having count(distinct q.concept_key) <> 5
      or (v_grade_band = '高一' and v_release_expected in (125,175) and count(*) <> 25)
      or (v_grade_band = '高一' and v_release_expected between 211 and 275 and count(*) < 25)
      or (v_grade_band in ('高二','高三') and count(*) < 25)
  ) then
    raise exception 'every release skill must use exactly five concepts; legacy High-1 requires exactly 25 questions per skill and expanded releases require at least 25';
  end if;

  if (
    select count(*)
    from (
      select q.skill_id, q.concept_key
      from public.chem_questions q
      where q.source_release_id = p_release_id
      group by q.skill_id, q.concept_key
      having (v_grade_band = '高一' and v_release_expected in (125,175) and count(*) = 5)
        or (v_grade_band = '高一' and v_release_expected between 211 and 275 and count(*) >= 5)
        or (v_grade_band in ('高二','高三') and count(*) >= 5)
    ) concept_groups
  ) <> v_expected_concept_count then
    raise exception 'legacy High-1 requires exactly five questions per fine concept; expanded releases and High-2/High-3 require at least five';
  end if;

  select count(distinct q.id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question ids are not unique inside release'; end if;
  select count(distinct q.mother_id) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'mother ids are not unique inside release'; end if;
  select count(distinct q.source_item_key) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'source item identities are not unique inside release'; end if;
  select count(distinct q.content_fingerprint) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'content fingerprints are not unique inside release'; end if;
  select count(distinct q.question_revision_token) into v_distinct_count
  from public.chem_questions q where q.source_release_id = p_release_id;
  if v_distinct_count <> v_release_expected then raise exception 'question revision tokens are not unique inside release'; end if;

  select count(*) into v_question_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'release ledger must contain exactly % items, found %', v_release_expected, v_question_count;
  end if;

  select count(distinct ri.canonical_source_id) into v_distinct_count
  from app_private.chem_question_source_release_items ri
  where ri.release_id = p_release_id;
  if v_distinct_count <> v_release_expected then
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
        or coalesce(q.source_info->>'transcriptionPolicy', '') not in (
          'source_image_authoritative',
          'teacher_verified_exact_reflow_of_registered_source',
          'source_crop_sanitized'
        )
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
    raise exception 'release manifest does not match the staged source items';
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
  where grade_band = v_grade_band
    and usable_for_review
    and source_release_id is distinct from p_release_id;

  update public.chem_questions
  set usable_for_review = true,
      updated_at = now()
  where source_release_id = p_release_id;
  get diagnostics v_question_count = row_count;
  if v_question_count <> v_release_expected then
    raise exception 'activation updated %, expected %', v_question_count, v_release_expected;
  end if;

  update app_private.chem_question_source_releases
  set status = 'retired', retired_at = now()
  where grade_band = v_grade_band and status = 'active' and id <> p_release_id;

  update app_private.chem_question_source_releases
  set status = 'active', activated_at = now(), retired_at = null
  where id = p_release_id;
  get diagnostics v_distinct_count = row_count;
  if v_distinct_count <> 1 then
    raise exception 'release activation status update affected %, expected 1', v_distinct_count;
  end if;

  select count(*) into v_question_count
  from public.chem_questions q
  where q.grade_band = v_grade_band
    and q.usable_for_review
    and q.source_release_id = p_release_id;
  if v_question_count <> v_release_expected then
    raise exception 'postcondition failed: active release exposes %, expected %', v_question_count, v_release_expected;
  end if;

  if exists (
    select 1
    from public.chem_questions q
    where q.grade_band = v_grade_band
      and q.usable_for_review
      and q.source_release_id is distinct from p_release_id
  ) then
    raise exception 'postcondition failed: an older same-grade REVIEW question remains enabled';
  end if;

  select count(*) into v_distinct_count
  from app_private.chem_question_source_releases r
  where r.grade_band = v_grade_band and r.status = 'active';
  if v_distinct_count <> 1 then
    raise exception 'postcondition failed: the grade must have exactly one active source release';
  end if;

  -- Do not leave the narrowly scoped activation bypass enabled for any later
  -- statements when a caller invokes this function inside a larger transaction.
  perform pg_catalog.set_config('app.chem_release_activation', 'off', true);

  return query select p_release_id, v_question_count;
end;
$$;
revoke all on function public.chem_activate_source_original_release(uuid,text) from public, anon, authenticated;
grant execute on function public.chem_activate_source_original_release(uuid,text) to service_role;

commit;
