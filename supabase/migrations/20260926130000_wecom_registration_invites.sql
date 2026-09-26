-- Verified WeCom customer-contact callbacks may issue one-time registration
-- invitations before the contact has supplied a role or a phone number.
-- The existing teacher-issued invitations remain bound to both fields.
alter table app_private.chem_registration_invites
  add column source text not null default 'teacher'
    check (source in ('teacher','wecom')),
  add column external_user_hash text
    check (external_user_hash is null or external_user_hash ~ '^[0-9a-f]{64}$'),
  add column event_hash text unique
    check (event_hash is null or event_hash ~ '^[0-9a-f]{64}$'),
  add column welcome_sent_at timestamptz;

alter table app_private.chem_registration_invites
  alter column role drop not null,
  alter column phone drop not null;

alter table app_private.chem_registration_invites
  add constraint chem_registration_invite_source_fields check (
    (source='teacher' and role is not null and role in ('student','guardian')
      and phone is not null and phone ~ '^1[3-9][0-9]{9}$'
      and external_user_hash is null and event_hash is null
      and welcome_sent_at is null)
    or
    (source='wecom' and external_user_hash is not null and event_hash is not null
      and ((role is null and phone is null)
        or (role is not null and role in ('student','guardian')
          and phone is not null and phone ~ '^1[3-9][0-9]{9}$')))
  );

create unique index chem_registration_one_open_wecom_contact
  on app_private.chem_registration_invites(external_user_hash)
  where source='wecom' and consumed_at is null and revoked_at is null;

-- Call only after the Edge webhook has verified and decrypted the WeCom event.
-- The Edge function derives a deterministic code for the signed event, allowing
-- a callback retry to deliver the same code without storing it in plaintext.
create function public.chem_create_wecom_registration_invite(
  p_code_hash text,p_external_hash text,p_event_hash text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_existing app_private.chem_registration_invites%rowtype;
  v_id uuid; v_expires_at timestamptz;
begin
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$'
    or p_external_hash is null or p_external_hash !~ '^[0-9a-f]{64}$'
    or p_event_hash is null or p_event_hash !~ '^[0-9a-f]{64}$' then
    raise exception '企业微信邀请信息无效';
  end if;
  perform pg_advisory_xact_lock(hashtext('wecom-contact:'||p_external_hash));
  select * into v_existing from app_private.chem_registration_invites
    where event_hash=p_event_hash for update;
  if found then
    if v_existing.source<>'wecom' or v_existing.external_user_hash<>p_external_hash
      or v_existing.code_hash<>p_code_hash then
      raise exception '企业微信事件与邀请码不一致';
    end if;
    return jsonb_build_object('id',v_existing.id,
      'shouldSend',v_existing.welcome_sent_at is null
        and v_existing.consumed_at is null and v_existing.revoked_at is null
        and v_existing.expires_at>now(),
      'eventHash',v_existing.event_hash,
      'expiresAt',v_existing.expires_at);
  end if;

  -- WeCom can emit half-contact and full-contact events for one add. Keep the
  -- first active code even when its welcome mark failed after a successful
  -- send; the caller derives that same code from the returned eventHash.
  select * into v_existing from app_private.chem_registration_invites
    where source='wecom' and external_user_hash=p_external_hash
      and consumed_at is null and revoked_at is null and expires_at>now()
    for update;
  if found then
    return jsonb_build_object('id',v_existing.id,
      'shouldSend',v_existing.welcome_sent_at is null,
      'eventHash',v_existing.event_hash,
      'expiresAt',v_existing.expires_at);
  end if;

  -- The open-invite index includes expired rows. Revoke only those stale rows
  -- before issuing a new code; a current link must never be invalidated.
  update app_private.chem_registration_invites
    set revoked_at=now(),revoked_by='system:wecom_expired'
    where source='wecom' and external_user_hash=p_external_hash
      and consumed_at is null and revoked_at is null and expires_at<=now();
  insert into app_private.chem_registration_invites
    (code_hash,source,external_user_hash,event_hash,issued_by,issued_by_hash,expires_at)
  values(p_code_hash,'wecom',p_external_hash,p_event_hash,
    '企业微信自动',p_external_hash,now()+interval '24 hours')
  returning id,expires_at into v_id,v_expires_at;
  return jsonb_build_object('id',v_id,'shouldSend',true,
    'eventHash',p_event_hash,'expiresAt',v_expires_at);
end $$;

create function public.chem_mark_wecom_welcome_sent(p_invite_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  update app_private.chem_registration_invites
    set welcome_sent_at=now()
    where id=p_invite_id and source='wecom'
      and welcome_sent_at is null and consumed_at is null and revoked_at is null
      and expires_at>now();
  return found;
end $$;

-- Keep the teacher's manual-invite list unchanged when automatic WeCom
-- invitations have not yet collected an identity or phone number.
create or replace function public.chem_list_registration_invites(p_actor_hash text)
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
    from (select * from app_private.chem_registration_invites
      where source='teacher' order by created_at desc limit 100) i),'[]'::jsonb);
end $$;

create or replace function public.chem_submit_registration(p_data jsonb,p_fingerprint_hash text,p_invite_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_role text=p_data->>'role'; v_name text=btrim(p_data->>'displayName'); v_phone text=p_data->>'phone';
  v_password text=p_data->>'password'; v_grade text=p_data->>'gradeBand'; v_child_name text=btrim(p_data->>'childName');
  v_child_phone text=p_data->>'childPhone'; v_invite_id uuid; v_request_id uuid; v_source text;
begin
  if p_fingerprint_hash is null or p_fingerprint_hash !~ '^[0-9a-f]{64}$' then return false; end if;
  perform pg_advisory_xact_lock(hashtext(p_fingerprint_hash));
  if (select count(*) from app_private.chem_registration_attempts
      where fingerprint_hash=p_fingerprint_hash and attempted_at>now()-interval '1 hour')>=5 then return false; end if;
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
  select i.id,i.source into v_invite_id,v_source from app_private.chem_registration_invites i
  where i.code_hash=p_invite_hash
    and ((i.source='teacher' and i.role=v_role and i.phone=v_phone)
      or (i.source='wecom' and i.role is null and i.phone is null))
    and i.consumed_at is null and i.revoked_at is null and i.expires_at>now()
  for update;
  if not found then return false; end if;
  -- An already-registered or pending phone gets a generic response, but an
  -- unbound WeCom code must still be consumed so it cannot be forwarded.
  if exists(select 1 from app_private.chem_phone_accounts where role=v_role and phone=v_phone) then
    if v_source='wecom' then
      update app_private.chem_registration_invites
        set role=v_role,phone=v_phone,consumed_at=now() where id=v_invite_id;
    end if;
    return true;
  end if;
  insert into app_private.chem_registration_requests
    (role,display_name,phone,password_hash,grade_band,child_name,child_phone,invite_id)
  values(v_role,v_name,v_phone,extensions.crypt(v_password,extensions.gen_salt('bf',10)),
    case when v_role='student' then v_grade else null end,
    case when v_role='guardian' then v_child_name else null end,
    case when v_role='guardian' then v_child_phone else null end,v_invite_id)
  on conflict (role,phone) where status='pending' do nothing
  returning id into v_request_id;
  if v_request_id is null then
    if v_source='wecom' then
      update app_private.chem_registration_invites
        set role=v_role,phone=v_phone,consumed_at=now() where id=v_invite_id;
    end if;
    return true;
  end if;
  update app_private.chem_registration_invites
    set role=case when v_source='wecom' then v_role else role end,
        phone=case when v_source='wecom' then v_phone else phone end,
        consumed_at=now()
    where id=v_invite_id;
  return true;
end $$;

revoke all on function public.chem_create_wecom_registration_invite(text,text,text),
  public.chem_mark_wecom_welcome_sent(uuid) from public,anon,authenticated;
grant execute on function public.chem_create_wecom_registration_invite(text,text,text),
  public.chem_mark_wecom_welcome_sent(uuid) to service_role;
