-- Add genuinely new 初三 knowledge routes without retiring originals that
-- learners have already received. A cumulative staged batch carries exact
-- copies of live questions for preflight, but only its new routes go live.
begin;

create table if not exists app_private.chem_junior_active_release_routes (
  textbook_version text not null,
  knowledge_id text not null,
  source_release_id uuid not null
    references app_private.chem_question_source_releases(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (textbook_version, knowledge_id)
);
create index if not exists chem_junior_active_release_routes_release_idx
  on app_private.chem_junior_active_release_routes(source_release_id);
alter table app_private.chem_junior_active_release_routes enable row level security;
revoke all on table app_private.chem_junior_active_release_routes
  from public, anon, authenticated, service_role;

-- Seed only genuinely live, verified routes. The table's primary key is the
-- permanent one-release-per-knowledge-point constraint.
insert into app_private.chem_junior_active_release_routes (
  textbook_version, knowledge_id, source_release_id
)
select distinct p.textbook_version,p.knowledge_id,p.source_release_id
from app_private.chem_junior_knowledge_provenance p
join app_private.chem_question_source_releases r
  on r.id=p.source_release_id
join public.chem_questions q
  on q.source_release_id=r.id and q.knowledge_id=p.knowledge_id
where p.textbook_version='科粤版'
  and p.verification_status='verified'
  and r.grade_band='初三' and r.textbook_version='科粤版'
  and r.status='active' and r.verification_status='full_visual_verified'
  and q.usable_for_review
on conflict (textbook_version,knowledge_id) do nothing;

create or replace function app_private.chem_track_junior_active_release_routes()
returns trigger
language plpgsql security definer set search_path=''
as $function$
declare
  v_routes integer;
begin
  if tg_op='UPDATE' and old.grade_band='初三'
    and old.status='active' and new.status is distinct from 'active'
  then
    delete from app_private.chem_junior_active_release_routes route
    where route.source_release_id=old.id;
  end if;

  if new.grade_band='初三' and new.status='active'
    and (tg_op='INSERT' or old.status is distinct from 'active')
  then
    if new.textbook_version is distinct from '科粤版'
      or exists (
        select 1 from public.chem_questions q
        where q.source_release_id=new.id and q.usable_for_review
          and not exists (
            select 1 from app_private.chem_junior_knowledge_provenance p
            where p.textbook_version='科粤版'
              and p.knowledge_id=q.knowledge_id
              and p.source_release_id=new.id
              and p.verification_status='verified'
          )
      )
    then
      raise exception 'active junior questions need exact verified route ownership';
    end if;

    insert into app_private.chem_junior_active_release_routes (
      textbook_version,knowledge_id,source_release_id
    )
    select distinct p.textbook_version,p.knowledge_id,p.source_release_id
    from app_private.chem_junior_knowledge_provenance p
    join public.chem_questions q
      on q.source_release_id=new.id and q.knowledge_id=p.knowledge_id
    where p.textbook_version='科粤版'
      and p.source_release_id=new.id
      and p.verification_status='verified'
      and q.usable_for_review;
    get diagnostics v_routes = row_count;
    if v_routes < 1 then
      raise exception 'active junior release has no owned knowledge route';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function app_private.chem_track_junior_active_release_routes()
  from public, anon, authenticated, service_role;
drop trigger if exists chem_track_junior_active_release_routes
  on app_private.chem_question_source_releases;
create trigger chem_track_junior_active_release_routes
after insert or update of status on app_private.chem_question_source_releases
for each row execute function app_private.chem_track_junior_active_release_routes();

-- A published route cannot quietly be rebound by editing its source proof.
-- Ordinary full replacement first retires its old releases (and the status
-- trigger removes their route ownership), then changes provenance.
create or replace function app_private.chem_guard_junior_active_route_provenance()
returns trigger
language plpgsql security definer set search_path=''
as $function$
begin
  if old.textbook_version='科粤版'
    and exists (
      select 1 from app_private.chem_junior_active_release_routes route
      where route.textbook_version=old.textbook_version
        and route.knowledge_id=old.knowledge_id
        and route.source_release_id=old.source_release_id
    )
    and (tg_op='DELETE' or new is distinct from old)
  then
    raise exception 'active junior route provenance is immutable until its release retires';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$function$;
revoke all on function app_private.chem_guard_junior_active_route_provenance()
  from public,anon,authenticated,service_role;
drop trigger if exists chem_guard_junior_active_route_provenance
  on app_private.chem_junior_knowledge_provenance;
create trigger chem_guard_junior_active_route_provenance
before update or delete on app_private.chem_junior_knowledge_provenance
for each row execute function app_private.chem_guard_junior_active_route_provenance();

-- Existing one-active-per-book index is replaced by the route key above.
drop index if exists app_private.chem_question_source_releases_one_active_junior_textbook_uidx;

create or replace function public.chem_activate_junior_additive_source_release(
  p_release_id uuid,
  p_manifest_sha256 text
)
returns table (
  activated_release_id uuid,
  added_questions integer,
  total_usable_questions integer,
  added_knowledge_routes integer
)
language plpgsql security definer set search_path=''
as $function$
declare
  v_target app_private.chem_question_source_releases%rowtype;
  v_target_ids text[];
  v_current_ids text[];
  v_added_ids text[];
  v_existing_count integer;
  v_added_count integer;
  v_total_count integer;
  v_matched_count integer;
  v_count integer;
begin
  if p_release_id is null
    or coalesce(p_manifest_sha256,'') !~ '^[0-9a-f]{64}$'
  then raise exception 'invalid junior additive release identity'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-source-original-release',0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chem-h3-original-release',0));

  select * into v_target
  from app_private.chem_question_source_releases r
  where r.id=p_release_id for update;
  if not found or v_target.grade_band is distinct from '初三'
    or v_target.textbook_version is distinct from '科粤版'
    or v_target.manifest_sha256 is distinct from p_manifest_sha256
    or v_target.verification_status is distinct from 'full_visual_verified'
    or v_target.verification_manifest_sha256 is distinct from p_manifest_sha256
  then raise exception 'junior additive release changed or is unverified'; end if;

  -- Safe to rerun after a successful prior transaction. No state changes.
  if v_target.status='active' then
    select count(*) into v_added_count from public.chem_questions q
    where q.source_release_id=p_release_id and q.usable_for_review;
    select count(*) into v_count
    from app_private.chem_junior_active_release_routes route
    where route.source_release_id=p_release_id;
    if v_added_count < 1 or v_count < 1
      or exists (
        select 1 from public.chem_questions q
        where q.source_release_id=p_release_id and q.usable_for_review
          and not exists (
            select 1 from app_private.chem_junior_active_release_routes route
            where route.textbook_version='科粤版'
              and route.knowledge_id=q.knowledge_id
              and route.source_release_id=p_release_id
          )
      )
    then raise exception 'previous junior additive activation is incomplete'; end if;
    select count(*) into v_total_count from public.chem_questions q
    join app_private.chem_junior_active_release_routes route
      on route.textbook_version='科粤版'
     and route.knowledge_id=q.knowledge_id
     and route.source_release_id=q.source_release_id
    where q.grade_band='初三' and q.usable_for_review;
    return query select p_release_id,v_added_count,v_total_count,v_count;
    return;
  end if;
  if v_target.status is distinct from 'staged' then
    raise exception 'junior additive release must be staged';
  end if;

  -- The canonical full-batch preflight locks every question, source proof,
  -- card and curriculum row and checks formula/visual/answer integrity.
  perform app_private.chem_assert_junior_source_release(
    p_release_id,p_manifest_sha256,true);
  select spec.knowledge_ids into v_target_ids
  from app_private.chem_junior_source_release_specs spec
  where spec.release_id=p_release_id and spec.textbook_version='科粤版'
  for update;
  select pg_catalog.array_agg(route.knowledge_id order by route.knowledge_id)
    into v_current_ids
  from app_private.chem_junior_active_release_routes route
  where route.textbook_version='科粤版';
  select pg_catalog.array_agg(route.id order by route.id)
    into v_added_ids
  from pg_catalog.unnest(v_target_ids) route(id)
  where not route.id=any(v_current_ids);
  if cardinality(v_current_ids) < 1
    or cardinality(v_added_ids) < 1
    or exists (select 1 from pg_catalog.unnest(v_current_ids) route(id)
               where not route.id=any(v_target_ids))
    or exists (
      select 1 from app_private.chem_junior_active_release_routes route
      left join app_private.chem_question_source_releases r
        on r.id=route.source_release_id
      left join app_private.chem_junior_knowledge_provenance p
        on p.textbook_version=route.textbook_version
       and p.knowledge_id=route.knowledge_id
       and p.source_release_id=route.source_release_id
       and p.verification_status='verified'
      where route.textbook_version='科粤版'
        and (r.status is distinct from 'active' or p.knowledge_id is null)
    )
  then raise exception 'junior additive routes overlap or current route ownership is stale'; end if;

  perform r.id
  from app_private.chem_question_source_releases r
  where r.id in (
    select distinct route.source_release_id
    from app_private.chem_junior_active_release_routes route
    where route.textbook_version='科粤版'
  )
  order by r.id for update;

  if exists (
    select 1 from public.chem_questions q
    join app_private.chem_question_source_releases r
      on r.id=q.source_release_id
    where r.grade_band='初三' and r.textbook_version='科粤版'
      and r.status='active' and q.usable_for_review
      and not exists (
        select 1 from app_private.chem_junior_active_release_routes route
        where route.textbook_version='科粤版'
          and route.knowledge_id=q.knowledge_id
          and route.source_release_id=q.source_release_id
      )
  ) then raise exception 'current junior questions are not uniquely route-owned'; end if;

  select count(*) into v_existing_count
  from public.chem_questions q
  join app_private.chem_junior_active_release_routes route
    on route.textbook_version='科粤版'
   and route.knowledge_id=q.knowledge_id
   and route.source_release_id=q.source_release_id
  where q.grade_band='初三' and q.usable_for_review;
  select count(*) into v_added_count from public.chem_questions q
  where q.source_release_id=p_release_id and q.knowledge_id=any(v_added_ids);
  if v_existing_count < 1
    or v_added_count < 7*cardinality(v_added_ids)
    or v_existing_count+v_added_count<>v_target.expected_question_count
    or (select count(*) from public.chem_questions q
        where q.source_release_id=p_release_id
          and q.knowledge_id=any(v_current_ids)) <> v_existing_count
    or exists (select 1 from public.chem_questions q
               where q.source_release_id=p_release_id and q.usable_for_review)
  then raise exception 'junior additive batch does not equal exact live copies plus new routes'; end if;

  select count(*) into v_matched_count
  from public.chem_questions current_q
  join app_private.chem_junior_active_release_routes route
    on route.textbook_version='科粤版'
   and route.knowledge_id=current_q.knowledge_id
   and route.source_release_id=current_q.source_release_id
  join public.chem_questions copy_q
    on copy_q.source_release_id=p_release_id
   and copy_q.knowledge_id=current_q.knowledge_id
   and copy_q.source_item_key=current_q.source_item_key
   and copy_q.content_fingerprint=current_q.content_fingerprint
   and copy_q.mother_id=current_q.mother_id
   and copy_q.parent_source_item_key=current_q.parent_source_item_key
   and copy_q.correct_option=current_q.correct_option
   and copy_q.options=current_q.options
   and copy_q.explanation=current_q.explanation
  where current_q.grade_band='初三' and current_q.usable_for_review;
  if v_matched_count<>v_existing_count
    or exists (
      select 1 from app_private.chem_junior_knowledge_provenance p
      where p.textbook_version='科粤版' and p.knowledge_id=any(v_added_ids)
    )
    or (select count(*) from app_private.chem_junior_source_release_provenance p
        where p.release_id=p_release_id
          and p.knowledge_id=any(v_added_ids)
          and p.verification_status='verified')<>cardinality(v_added_ids)
  then raise exception 'junior additive copies or new provenance are not exact'; end if;

  perform pg_catalog.set_config('app.chem_junior_release_lifecycle','on',true);
  perform pg_catalog.set_config('app.chem_release_activation','on',true);
  insert into app_private.chem_junior_knowledge_provenance (
    textbook_version,knowledge_id,source_release_id,source_id,
    source_locator,source_sha256,verification_status,reviewed_at
  )
  select p.textbook_version,p.knowledge_id,p.release_id,p.source_id,
         p.source_locator,p.source_sha256,'verified',p.reviewed_at
  from app_private.chem_junior_source_release_provenance p
  where p.release_id=p_release_id and p.knowledge_id=any(v_added_ids);
  get diagnostics v_count = row_count;
  if v_count<>cardinality(v_added_ids) then
    raise exception 'junior additive provenance insertion count changed';
  end if;

  update public.chem_questions q
  set usable_for_review=true,updated_at=now()
  where q.source_release_id=p_release_id
    and q.knowledge_id=any(v_added_ids);
  get diagnostics v_count = row_count;
  if v_count<>v_added_count then
    raise exception 'junior additive enabled question count changed';
  end if;
  update app_private.chem_question_source_releases r
  set status='active',activated_at=now(),retired_at=null
  where r.id=p_release_id and r.status='staged'
    and r.verification_status='full_visual_verified'
    and r.verification_manifest_sha256=p_manifest_sha256;
  get diagnostics v_count = row_count;
  if v_count<>1 then raise exception 'junior additive status update failed'; end if;

  select count(*) into v_total_count
  from public.chem_questions q
  join app_private.chem_junior_active_release_routes route
    on route.textbook_version='科粤版'
   and route.knowledge_id=q.knowledge_id
   and route.source_release_id=q.source_release_id
  where q.grade_band='初三' and q.usable_for_review;
  if v_total_count<>v_existing_count+v_added_count
    or (select count(*) from app_private.chem_teaching_ready_questions ready
        where ready.grade_band='初三'
          and ready.source_release_id in (
            select distinct route.source_release_id
            from app_private.chem_junior_active_release_routes route
            where route.textbook_version='科粤版'
          ))<>v_total_count
    or (select count(*) from app_private.chem_junior_active_release_routes route
        where route.textbook_version='科粤版'
          and route.knowledge_id=any(v_added_ids)
          and route.source_release_id=p_release_id)<>cardinality(v_added_ids)
    or exists (
      select 1 from pg_catalog.unnest(v_added_ids) route(id)
      cross join lateral public.chem_junior_verified_provenance_rows(
        '科粤版',array[route.id]) verified
      where verified.source_release_id is distinct from p_release_id
        or not verified.source_release_ready
    )
  then raise exception 'junior additive delivery postcondition failed'; end if;
  perform pg_catalog.set_config('app.chem_release_activation','off',true);
  perform pg_catalog.set_config('app.chem_junior_release_lifecycle','off',true);
  return query select p_release_id,v_added_count,v_total_count,
    cardinality(v_added_ids);
end;
$function$;
revoke all on function public.chem_activate_junior_additive_source_release(uuid,text)
  from public,anon,authenticated;
grant execute on function public.chem_activate_junior_additive_source_release(uuid,text)
  to service_role;

do $seed_check$
declare
  v_target_status text;
  v_total_routes integer;
begin
  select r.status into v_target_status
  from app_private.chem_question_source_releases r
  where r.id='3d73e998-e8b4-521b-a201-7ffd9444cd0d';
  select count(*) into v_total_routes
  from app_private.chem_junior_active_release_routes route
  where route.textbook_version='科粤版';
  if (select count(*) from app_private.chem_junior_active_release_routes
        where textbook_version='科粤版'
          and source_release_id='2d5adf4e-d2d1-5006-bb48-df97e4f1d1be')<>17
    or not (
      (v_target_status='staged' and v_total_routes=17)
      or (v_target_status='active' and v_total_routes=20
        and (select count(*) from app_private.chem_junior_active_release_routes
             where textbook_version='科粤版'
               and source_release_id='3d73e998-e8b4-521b-a201-7ffd9444cd0d')=3)
    )
  then raise exception 'junior route seed does not match the 17 live baseline routes'; end if;
end;
$seed_check$;

do $first_extension$
declare
  v_result record;
  v_manifest text;
begin
  select r.manifest_sha256 into v_manifest
  from app_private.chem_question_source_releases r
  where r.id='3d73e998-e8b4-521b-a201-7ffd9444cd0d'
    and r.expected_question_count=310
    and r.verification_status='full_visual_verified'
    and r.verification_manifest_sha256=r.manifest_sha256;
  if not found then raise exception 'reviewed 310-question junior batch is missing'; end if;
  select * into v_result
  from public.chem_activate_junior_additive_source_release(
    '3d73e998-e8b4-521b-a201-7ffd9444cd0d',v_manifest);
  if v_result.added_questions<>21
    or v_result.total_usable_questions<>310
    or v_result.added_knowledge_routes<>3
  then raise exception 'junior first extension expected 21 new originals and 310 usable total'; end if;
end;
$first_extension$;

commit;
