-- A phone registration must follow a teacher-issued invitation for that exact role and phone.
-- Codes are generated in the Edge Function. Only a keyed digest reaches the database.
create table app_private.chem_registration_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  role text not null check (role in ('student','guardian')),
  phone text not null check (phone ~ '^1[3-9][0-9]{9}$'),
  note text check (note is null or char_length(note) between 1 and 120),
  issued_by text not null,
  issued_by_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz,
  revoked_by text,
  check (expires_at > created_at),
  check (consumed_at is null or revoked_at is null)
);
create index chem_registration_invites_phone on app_private.chem_registration_invites(role,phone,created_at desc);
create index chem_registration_invites_issued_by on app_private.chem_registration_invites(issued_by_hash,created_at desc);
create unique index chem_registration_one_open_invite
  on app_private.chem_registration_invites(role,phone)
  where consumed_at is null and revoked_at is null;
alter table app_private.chem_registration_invites enable row level security;
revoke all on app_private.chem_registration_invites from public,anon,authenticated;

alter table app_private.chem_registration_requests
  add column invite_id uuid unique references app_private.chem_registration_invites(id);
-- The old pending requests were submitted before a teacher checked the WeChat identity.
-- Historical approved accounts remain untouched.
update app_private.chem_registration_requests
set status='rejected',reviewed_at=now(),reviewed_by='system:invitation_required'
where status='pending' and invite_id is null;
alter table app_private.chem_registration_requests
  add constraint chem_registration_pending_requires_invite
  check (status <> 'pending' or invite_id is not null);

alter table app_private.chem_registration_attempts add column phone text;
create index chem_registration_attempts_phone on app_private.chem_registration_attempts(phone,attempted_at desc)
  where phone is not null;

create function public.chem_create_registration_invite(
  p_role text,p_phone text,p_code_hash text,p_actor_hash text,p_actor_name text,p_note text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_expires_at timestamptz;
begin
  if not exists(select 1 from app_private.chem_app_sessions
    where token_hash=p_actor_hash and role='teacher' and revoked_at is null
      and expires_at>now() and access_scope='unified') then
    raise exception '教师身份已失效';
  end if;
  if p_role is null or p_role not in ('student','guardian')
    or p_phone is null or p_phone !~ '^1[3-9][0-9]{9}$'
    or p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$'
    or p_actor_name is null or char_length(btrim(p_actor_name)) not between 1 and 60
    or (p_note is not null and char_length(btrim(p_note)) not between 1 and 120) then
    raise exception '邀请信息无效';
  end if;
  perform pg_advisory_xact_lock(hashtext('registration-phone:'||p_phone));
  if exists(select 1 from app_private.chem_phone_accounts
    where role=p_role and phone=p_phone) then
    raise exception '该手机号已有账号';
  end if;
  if exists(select 1 from app_private.chem_registration_requests
    where role=p_role and phone=p_phone and status='pending') then
    raise exception '该手机号已有待审核申请';
  end if;
  -- A replacement invite makes an earlier shared code unusable immediately.
  update app_private.chem_registration_invites
  set revoked_at=now(),revoked_by=p_actor_name
  where role=p_role and phone=p_phone and consumed_at is null and revoked_at is null;
  insert into app_private.chem_registration_invites
    (code_hash,role,phone,note,issued_by,issued_by_hash,expires_at)
  values(p_code_hash,p_role,p_phone,nullif(btrim(p_note),''),p_actor_name,p_actor_hash,now()+interval '7 days')
  returning id,expires_at into v_id,v_expires_at;
  return jsonb_build_object('id',v_id,'role',p_role,'phone',p_phone,
    'note',nullif(btrim(p_note),''),'expiresAt',v_expires_at);
end $$;

create function public.chem_list_registration_invites(p_actor_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from app_private.chem_app_sessions
    where token_hash=p_actor_hash and role='teacher' and revoked_at is null
      and expires_at>now() and access_scope='unified') then
    raise exception '教师身份已失效';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'role',i.role,'phone',i.phone,'note',i.note,
    'issuedBy',i.issued_by,'createdAt',i.created_at,'expiresAt',i.expires_at,
    'consumedAt',i.consumed_at,'revokedAt',i.revoked_at,
    'status',case when i.consumed_at is not null then 'used'
      when i.revoked_at is not null then 'revoked'
      when i.expires_at<=now() then 'expired' else 'active' end)
    order by i.created_at desc)
    from (select * from app_private.chem_registration_invites order by created_at desc limit 100) i),'[]'::jsonb);
end $$;

create function public.chem_revoke_registration_invite(p_invite_id uuid,p_actor_hash text,p_actor_name text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from app_private.chem_app_sessions
    where token_hash=p_actor_hash and role='teacher' and revoked_at is null
      and expires_at>now() and access_scope='unified') then
    raise exception '教师身份已失效';
  end if;
  update app_private.chem_registration_invites
  set revoked_at=now(),revoked_by=p_actor_name
  where id=p_invite_id and consumed_at is null and revoked_at is null;
  return found;
end $$;

-- Remove the two-argument route: no service-role caller can use the previous
-- invitation-free signature after this migration.
drop function public.chem_submit_registration(jsonb,text);
create function public.chem_submit_registration(p_data jsonb,p_fingerprint_hash text,p_invite_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_role text=p_data->>'role'; v_name text=btrim(p_data->>'displayName'); v_phone text=p_data->>'phone';
  v_password text=p_data->>'password'; v_grade text=p_data->>'gradeBand'; v_child_name text=btrim(p_data->>'childName');
  v_child_phone text=p_data->>'childPhone'; v_invite_id uuid; v_request_id uuid;
begin
  if p_fingerprint_hash is null or p_fingerprint_hash !~ '^[0-9a-f]{64}$' then return false; end if;
  perform pg_advisory_xact_lock(hashtext(p_fingerprint_hash));
  if (select count(*) from app_private.chem_registration_attempts
      where fingerprint_hash=p_fingerprint_hash and attempted_at>now()-interval '1 hour')>=5 then return false; end if;
  -- A second, phone-based limit prevents an easily rotated client fingerprint
  -- from testing many codes against a single invited number.
  if v_phone is not null and v_phone ~ '^1[3-9][0-9]{9}$' then
    perform pg_advisory_xact_lock(hashtext('registration-phone:'||v_phone));
    if (select count(*) from app_private.chem_registration_attempts
      where phone=v_phone and attempted_at>now()-interval '1 hour')>=10 then return false; end if;
  end if;
  insert into app_private.chem_registration_attempts(fingerprint_hash,phone)
  values(p_fingerprint_hash,case when v_phone ~ '^1[3-9][0-9]{9}$' then v_phone else null end);
  if v_role is null or v_role not in ('student','guardian') or v_name is null or char_length(v_name) not between 1 and 30 or
     v_phone is null or v_phone !~ '^1[3-9][0-9]{9}$' or v_password is null or char_length(v_password) not between 6 and 12 or
     v_password ~ '[[:cntrl:]]' or v_password <> btrim(v_password) or
     (v_role='student' and (v_grade not in ('初三','高一','高二','高三') or v_grade is null)) or
     (v_role='guardian' and (v_child_name is null or char_length(v_child_name) not between 1 and 40 or v_child_phone is null or v_child_phone !~ '^1[3-9][0-9]{9}$')) or
     p_invite_hash is null or p_invite_hash !~ '^[0-9a-f]{64}$' then return false; end if;
  select i.id into v_invite_id from app_private.chem_registration_invites i
  where i.code_hash=p_invite_hash and i.role=v_role and i.phone=v_phone
    and i.consumed_at is null and i.revoked_at is null and i.expires_at>now()
  for update;
  if not found then return false; end if;
  -- Keep the response generic for an existing account or already-pending request.
  if exists(select 1 from app_private.chem_phone_accounts where role=v_role and phone=v_phone) then return true; end if;
  insert into app_private.chem_registration_requests
    (role,display_name,phone,password_hash,grade_band,child_name,child_phone,invite_id)
  values(v_role,v_name,v_phone,extensions.crypt(v_password,extensions.gen_salt('bf',10)),
    case when v_role='student' then v_grade else null end,
    case when v_role='guardian' then v_child_name else null end,
    case when v_role='guardian' then v_child_phone else null end,v_invite_id)
  on conflict (role,phone) where status='pending' do nothing
  returning id into v_request_id;
  if v_request_id is null then return true; end if;
  update app_private.chem_registration_invites set consumed_at=now() where id=v_invite_id;
  return true;
end $$;

revoke all on function public.chem_create_registration_invite(text,text,text,text,text,text),
  public.chem_list_registration_invites(text),
  public.chem_revoke_registration_invite(uuid,text,text),
  public.chem_submit_registration(jsonb,text,text) from public,anon,authenticated;
grant execute on function public.chem_create_registration_invite(text,text,text,text,text,text),
  public.chem_list_registration_invites(text),
  public.chem_revoke_registration_invite(uuid,text,text),
  public.chem_submit_registration(jsonb,text,text) to service_role;
