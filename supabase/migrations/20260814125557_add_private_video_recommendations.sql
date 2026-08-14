-- Teacher-reviewed explainer videos are server-only records.  The browser never
-- receives direct table privileges; Edge Functions mediate every read/write.

create table if not exists app_private.chem_video_recommendations (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.chem_students_v2(id) on delete cascade,
  skill_id text not null references public.chem_skills(id) on delete restrict,
  unresolved_on date not null default ((now() at time zone 'Asia/Shanghai')::date),
  source_attempt_id uuid references public.chem_learning_attempts(id) on delete set null,
  source_alert_id uuid references public.chem_teacher_alerts(id) on delete set null,
  title text not null check (length(btrim(title)) between 1 and 160),
  provider text not null check (length(btrim(provider)) between 1 and 60),
  external_url text not null check (length(external_url) <= 2048 and external_url ~ '^https://[^[:space:]]+$'),
  teacher_reason text not null check (length(btrim(teacher_reason)) between 1 and 1000),
  tracking_capability text not null default 'self_reported'
    check (tracking_capability in ('link_open_only','self_reported','player_tracked')),
  status text not null default 'draft'
    check (status in ('draft','published','withdrawn')),
  created_by text not null check (length(btrim(created_by)) between 1 and 80),
  reviewed_by text,
  reviewed_at timestamptz,
  published_by text,
  published_at timestamptz,
  withdrawn_by text,
  withdrawn_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, student_id),
  unique (student_id, skill_id, external_url, unresolved_on)
);

create table if not exists app_private.chem_video_engagements (
  recommendation_id uuid primary key,
  student_id uuid not null,
  opened_at timestamptz,
  last_engaged_at timestamptz not null default now(),
  progress_position_seconds integer not null default 0
    check (progress_position_seconds between 0 and 86400),
  duration_seconds integer check (duration_seconds between 1 and 86400),
  tracking_method text not null default 'link_open_only'
    check (tracking_method in ('link_open_only','self_reported','player_tracked')),
  completed_at timestamptz,
  last_event text not null check (last_event in ('open','progress','complete')),
  event_count integer not null default 1 check (event_count >= 1),
  updated_at timestamptz not null default now(),
  foreign key (recommendation_id, student_id)
    references app_private.chem_video_recommendations(id, student_id) on delete cascade,
  check (duration_seconds is null or progress_position_seconds <= duration_seconds),
  check (tracking_method <> 'link_open_only' or progress_position_seconds = 0)
);

create table if not exists app_private.chem_video_engagement_events (
  id bigint generated always as identity primary key,
  recommendation_id uuid not null,
  student_id uuid not null,
  event_type text not null check (event_type in ('open','progress','complete')),
  position_seconds integer check (position_seconds between 0 and 86400),
  duration_seconds integer check (duration_seconds between 1 and 86400),
  tracking_method text not null
    check (tracking_method in ('link_open_only','self_reported','player_tracked')),
  occurred_at timestamptz not null default now(),
  foreign key (recommendation_id, student_id)
    references app_private.chem_video_recommendations(id, student_id) on delete cascade,
  check (duration_seconds is null or position_seconds is null or position_seconds <= duration_seconds),
  check (
    (event_type = 'open' and tracking_method = 'link_open_only' and position_seconds is null and duration_seconds is null)
    or
    (event_type = 'progress' and tracking_method in ('self_reported','player_tracked') and position_seconds is not null)
    or
    (
      event_type = 'complete'
      and tracking_method in ('self_reported','player_tracked')
      and (
        (position_seconds is null and duration_seconds is null)
        or (position_seconds is not null and duration_seconds is not null)
      )
    )
  )
);

create index if not exists chem_video_recommendations_student_status_idx
  on app_private.chem_video_recommendations(student_id, status, unresolved_on desc);
create index if not exists chem_video_recommendations_review_queue_idx
  on app_private.chem_video_recommendations(status, created_at desc)
  where status = 'draft';
create index if not exists chem_video_engagement_events_student_idx
  on app_private.chem_video_engagement_events(student_id, occurred_at desc);

alter table app_private.chem_video_recommendations enable row level security;
alter table app_private.chem_video_engagements enable row level security;
alter table app_private.chem_video_engagement_events enable row level security;

revoke all on table app_private.chem_video_recommendations from public, anon, authenticated, service_role;
revoke all on table app_private.chem_video_engagements from public, anon, authenticated, service_role;
revoke all on table app_private.chem_video_engagement_events from public, anon, authenticated, service_role;
revoke all on sequence app_private.chem_video_engagement_events_id_seq from public, anon, authenticated, service_role;

create or replace function public.chem_video_create_recommendation(
  p_student_id uuid,
  p_skill_id text,
  p_title text,
  p_provider text,
  p_external_url text,
  p_teacher_reason text,
  p_tracking_capability text,
  p_unresolved_on date,
  p_source_attempt_id uuid,
  p_source_alert_id uuid,
  p_actor_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_unresolved_on date := coalesce(p_unresolved_on, (now() at time zone 'Asia/Shanghai')::date);
begin
  if length(btrim(coalesce(p_title, ''))) not between 1 and 160
    or length(btrim(coalesce(p_teacher_reason, ''))) not between 1 and 1000
    or length(btrim(coalesce(p_actor_name, ''))) not between 1 and 80
    or length(btrim(coalesce(p_provider, ''))) not between 1 and 60
    or p_tracking_capability not in ('link_open_only','self_reported','player_tracked')
    or coalesce(p_external_url, '') !~ '^https://[^[:space:]]+$'
  then
    raise exception 'invalid video recommendation';
  end if;

  if not exists (
    select 1
    from public.chem_students_v2 s
    join public.chem_skills k
      on k.id = p_skill_id
     and k.grade_band = s.grade_band
     and k.active
    where s.id = p_student_id
      and s.record_status = 'active'
  ) then
    raise exception 'student or skill is not eligible';
  end if;

  if p_source_attempt_id is not null and not exists (
    select 1
    from public.chem_learning_attempts a
    join public.chem_attempt_answers aa on aa.attempt_id = a.id
    where a.id = p_source_attempt_id
      and a.student_id = p_student_id
      and aa.skill_id = p_skill_id
      and (not aa.correct or aa.uncertain)
  ) then
    raise exception 'source attempt does not contain unresolved evidence';
  end if;

  if p_source_alert_id is not null and not exists (
    select 1
    from public.chem_teacher_alerts a
    where a.id = p_source_alert_id
      and a.student_id = p_student_id
  ) then
    raise exception 'source alert does not belong to student';
  end if;

  select r.id into v_id
  from app_private.chem_video_recommendations r
  where r.student_id = p_student_id
    and r.skill_id = p_skill_id
    and r.external_url = p_external_url
    and r.unresolved_on = v_unresolved_on;

  if v_id is not null then
    return v_id;
  end if;

  insert into app_private.chem_video_recommendations (
    student_id, skill_id, unresolved_on, source_attempt_id, source_alert_id,
    title, provider, external_url, teacher_reason, tracking_capability, created_by
  ) values (
    p_student_id, p_skill_id, v_unresolved_on, p_source_attempt_id, p_source_alert_id,
    btrim(p_title), btrim(p_provider), p_external_url, btrim(p_teacher_reason),
    p_tracking_capability, btrim(p_actor_name)
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.chem_video_set_recommendation_status(
  p_recommendation_id uuid,
  p_target_status text,
  p_actor_name text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_status text;
begin
  if p_target_status not in ('published','withdrawn')
    or length(btrim(coalesce(p_actor_name, ''))) not between 1 and 80
  then
    raise exception 'invalid recommendation status change';
  end if;

  select status into v_current_status
  from app_private.chem_video_recommendations
  where id = p_recommendation_id
  for update;

  if v_current_status is null then
    return false;
  end if;
  if v_current_status = p_target_status then
    return true;
  end if;
  if not (
    (p_target_status = 'published' and v_current_status in ('draft','withdrawn'))
    or (p_target_status = 'withdrawn' and v_current_status in ('draft','published'))
  ) then
    raise exception 'invalid recommendation status transition';
  end if;

  update app_private.chem_video_recommendations
  set status = p_target_status,
      reviewed_by = case when p_target_status = 'published' then btrim(p_actor_name) else reviewed_by end,
      reviewed_at = case when p_target_status = 'published' then now() else reviewed_at end,
      published_by = case when p_target_status = 'published' then btrim(p_actor_name) else published_by end,
      published_at = case when p_target_status = 'published' then now() else published_at end,
      withdrawn_by = case when p_target_status = 'withdrawn' then btrim(p_actor_name) else null end,
      withdrawn_at = case when p_target_status = 'withdrawn' then now() else null end,
      updated_at = now()
  where id = p_recommendation_id;

  return true;
end;
$$;

create or replace function public.chem_video_record_engagement(
  p_recommendation_id uuid,
  p_student_id uuid,
  p_event_type text,
  p_progress_position_seconds integer,
  p_duration_seconds integer,
  p_tracking_method text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capability text;
  v_method text;
  v_position integer;
  v_duration integer;
begin
  select tracking_capability into v_capability
  from app_private.chem_video_recommendations
  where id = p_recommendation_id
    and student_id = p_student_id
    and status = 'published';

  if v_capability is null then
    return false;
  end if;

  if p_event_type = 'open' then
    v_method := 'link_open_only';
    v_position := null;
    v_duration := null;
  elsif p_event_type = 'progress' then
    if v_capability = 'link_open_only'
      or p_tracking_method not in ('self_reported','player_tracked')
      or p_tracking_method <> v_capability
      or p_progress_position_seconds is null
      or p_progress_position_seconds not between 0 and 86400
      or (p_duration_seconds is not null and p_duration_seconds not between 1 and 86400)
      or (p_duration_seconds is not null and p_progress_position_seconds > p_duration_seconds)
    then
      raise exception 'invalid or unverifiable video progress';
    end if;
    v_method := p_tracking_method;
    v_position := p_progress_position_seconds;
    v_duration := p_duration_seconds;
  elsif p_event_type = 'complete' then
    if v_capability = 'link_open_only'
      or p_tracking_method not in ('self_reported','player_tracked')
      or p_tracking_method <> v_capability
      or ((p_progress_position_seconds is null) <> (p_duration_seconds is null))
      or (p_progress_position_seconds is not null and p_progress_position_seconds not between 0 and 86400)
      or (p_duration_seconds is not null and p_duration_seconds not between 1 and 86400)
      or (p_progress_position_seconds is not null and p_progress_position_seconds > p_duration_seconds)
      or (
        p_progress_position_seconds is not null
        and p_progress_position_seconds * 10 < p_duration_seconds * 9
      )
    then
      raise exception 'invalid or unverifiable video completion';
    end if;
    v_method := p_tracking_method;
    v_position := p_progress_position_seconds;
    v_duration := p_duration_seconds;
  else
    raise exception 'invalid video engagement event';
  end if;

  insert into app_private.chem_video_engagement_events (
    recommendation_id, student_id, event_type, position_seconds, duration_seconds, tracking_method
  ) values (
    p_recommendation_id, p_student_id, p_event_type, v_position, v_duration, v_method
  );

  insert into app_private.chem_video_engagements (
    recommendation_id, student_id, opened_at, last_engaged_at,
    progress_position_seconds, duration_seconds, tracking_method,
    completed_at, last_event, event_count, updated_at
  ) values (
    p_recommendation_id,
    p_student_id,
    now(),
    now(),
    coalesce(v_position, 0),
    v_duration,
    v_method,
    case when p_event_type = 'complete' then now() else null end,
    p_event_type,
    1,
    now()
  )
  on conflict (recommendation_id) do update
  set opened_at = coalesce(app_private.chem_video_engagements.opened_at, excluded.opened_at),
      last_engaged_at = excluded.last_engaged_at,
      progress_position_seconds = greatest(
        app_private.chem_video_engagements.progress_position_seconds,
        excluded.progress_position_seconds
      ),
      duration_seconds = coalesce(
        greatest(app_private.chem_video_engagements.duration_seconds, excluded.duration_seconds),
        app_private.chem_video_engagements.duration_seconds,
        excluded.duration_seconds
      ),
      tracking_method = case
        when excluded.last_event = 'open' then app_private.chem_video_engagements.tracking_method
        else excluded.tracking_method
      end,
      completed_at = coalesce(app_private.chem_video_engagements.completed_at, excluded.completed_at),
      last_event = excluded.last_event,
      event_count = app_private.chem_video_engagements.event_count + 1,
      updated_at = now();

  return true;
end;
$$;

create or replace function public.chem_video_list_recommendations(
  p_student_id uuid,
  p_include_unpublished boolean
)
returns table (
  id uuid,
  student_id uuid,
  student_name text,
  skill_id text,
  skill_title text,
  unresolved_on date,
  source_attempt_id uuid,
  source_alert_id uuid,
  title text,
  provider text,
  external_url text,
  teacher_reason text,
  tracking_capability text,
  status text,
  created_by text,
  reviewed_by text,
  reviewed_at timestamptz,
  published_by text,
  published_at timestamptz,
  withdrawn_by text,
  withdrawn_at timestamptz,
  created_at timestamptz,
  opened_at timestamptz,
  last_engaged_at timestamptz,
  progress_position_seconds integer,
  duration_seconds integer,
  completion_percent numeric,
  tracking_method text,
  completed_at timestamptz,
  event_count integer
)
language sql
security definer
set search_path = ''
as $$
  select
    r.id,
    r.student_id,
    s.display_name,
    r.skill_id,
    k.title,
    r.unresolved_on,
    r.source_attempt_id,
    r.source_alert_id,
    r.title,
    r.provider,
    r.external_url,
    r.teacher_reason,
    r.tracking_capability,
    r.status,
    r.created_by,
    r.reviewed_by,
    r.reviewed_at,
    r.published_by,
    r.published_at,
    r.withdrawn_by,
    r.withdrawn_at,
    r.created_at,
    e.opened_at,
    e.last_engaged_at,
    coalesce(e.progress_position_seconds, 0),
    e.duration_seconds,
    case
      when e.completed_at is not null then 100::numeric
      when e.duration_seconds is not null and e.duration_seconds > 0
        then round(least(100::numeric, e.progress_position_seconds * 100.0 / e.duration_seconds), 1)
      else null
    end,
    coalesce(e.tracking_method, 'link_open_only'),
    e.completed_at,
    coalesce(e.event_count, 0)
  from app_private.chem_video_recommendations r
  join public.chem_students_v2 s on s.id = r.student_id
  join public.chem_skills k on k.id = r.skill_id
  left join app_private.chem_video_engagements e on e.recommendation_id = r.id
  where (p_student_id is null or r.student_id = p_student_id)
    and (p_include_unpublished or r.status = 'published')
  order by coalesce(r.published_at, r.created_at) desc, r.id;
$$;

revoke all on function public.chem_video_create_recommendation(uuid,text,text,text,text,text,text,date,uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function public.chem_video_set_recommendation_status(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.chem_video_record_engagement(uuid,uuid,text,integer,integer,text)
  from public, anon, authenticated;
revoke all on function public.chem_video_list_recommendations(uuid,boolean)
  from public, anon, authenticated;

grant execute on function public.chem_video_create_recommendation(uuid,text,text,text,text,text,text,date,uuid,uuid,text)
  to service_role;
grant execute on function public.chem_video_set_recommendation_status(uuid,text,text)
  to service_role;
grant execute on function public.chem_video_record_engagement(uuid,uuid,text,integer,integer,text)
  to service_role;
grant execute on function public.chem_video_list_recommendations(uuid,boolean)
  to service_role;

comment on table app_private.chem_video_recommendations is
  'Private teacher-reviewed explainer video queue tied to a student unresolved skill.';
comment on column app_private.chem_video_recommendations.tracking_capability is
  'link_open_only means exact viewing progress is unavailable; self_reported and player_tracked preserve provenance.';
comment on table app_private.chem_video_engagement_events is
  'Append-only audit of opens and progress reports; tracking_method states whether progress was self-reported or player-verified.';
