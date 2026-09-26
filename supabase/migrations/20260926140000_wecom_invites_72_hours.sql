-- Extend only active, unused WeCom invitations that were issued under the
-- former 24-hour rule. Never revive an expired or revoked invitation.
update app_private.chem_registration_invites
set expires_at = greatest(expires_at, created_at + interval '72 hours')
where source = 'wecom'
  and consumed_at is null
  and revoked_at is null
  and expires_at > now()
  and expires_at < created_at + interval '72 hours';

-- Teacher-issued invitations keep their existing seven-day lifetime and
-- role/phone binding. Only the WeCom issuance function changes.
create or replace function public.chem_create_wecom_registration_invite(
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

  -- Half-contact and full-contact events for one add reuse the first active
  -- code, even if the welcome-send acknowledgement was interrupted.
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

  -- The open-invite index includes expired rows. Revoke those before issuing
  -- a new code, without invalidating a still-active link.
  update app_private.chem_registration_invites
    set revoked_at=now(),revoked_by='system:wecom_expired'
    where source='wecom' and external_user_hash=p_external_hash
      and consumed_at is null and revoked_at is null and expires_at<=now();
  insert into app_private.chem_registration_invites
    (code_hash,source,external_user_hash,event_hash,issued_by,issued_by_hash,expires_at)
  values(p_code_hash,'wecom',p_external_hash,p_event_hash,
    '企业微信自动',p_external_hash,now()+interval '72 hours')
  returning id,expires_at into v_id,v_expires_at;
  return jsonb_build_object('id',v_id,'shouldSend',true,
    'eventHash',p_event_hash,'expiresAt',v_expires_at);
end $$;
