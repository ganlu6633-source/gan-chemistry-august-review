-- A matching SHA string in the source ledger is not enough if the stored
-- image bytes can later be replaced independently. Validate new/changed
-- payloads at the database boundary, before they can enter a review release.
begin;

create function app_private.chem_validate_question_asset_payload()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  image_bytes bytea;
begin
  if new.mime_type <> 'image/webp' or new.width < 1 or new.height < 1
     or new.width > 6000 or new.height > 12000 then
    raise exception 'Question image type or dimensions are invalid';
  end if;

  image_bytes := decode(new.payload_base64, 'base64');
  if octet_length(image_bytes) < 20
     or substring(image_bytes from 1 for 4) <> '\x52494646'::bytea
     or substring(image_bytes from 9 for 4) <> '\x57454250'::bytea then
    raise exception 'Question image is not a WebP payload';
  end if;
  if new.sha256 is distinct from encode(extensions.digest(image_bytes,'sha256'),'hex') then
    raise exception 'Question image payload SHA-256 does not match its manifest';
  end if;
  return new;
end;
$$;

revoke all on function app_private.chem_validate_question_asset_payload()
  from public, anon, authenticated, service_role;

create trigger chem_validate_question_asset_payload
before insert or update of payload_base64,sha256,mime_type,width,height
on app_private.chem_question_assets
for each row execute function app_private.chem_validate_question_asset_payload();

commit;
