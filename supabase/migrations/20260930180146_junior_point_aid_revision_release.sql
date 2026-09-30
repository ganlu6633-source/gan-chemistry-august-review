-- Independently reviewed knowledge aids; question releases and immutable source cards remain unchanged.
-- A revision has separate storage identity. Student-facing card.id always remains the original logical ID.

create table app_private.chem_junior_point_aid_releases (
  id uuid primary key,
  revision_seq bigint generated always as identity unique,
  status text not null default 'staged' check (status in ('staged','attested','active')),
  reviewed_artifact_sha256 text not null check (reviewed_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  reviewed_payload jsonb not null check (jsonb_typeof(reviewed_payload)='array' and jsonb_array_length(reviewed_payload)>0),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  manifest_sha256 text check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  verification_actor text not null check (verification_actor='codex-knowledge-card-source-qa'),
  attestation_actor text,
  rights_status text not null default 'user_provided_private_use_unverified_for_redistribution'
    check (rights_status='user_provided_private_use_unverified_for_redistribution'),
  redistribution_allowed boolean not null default false check (redistribution_allowed=false),
  created_at timestamptz not null default now(),
  attested_at timestamptz,
  activated_at timestamptz,
  check ((status='staged' and attested_at is null and activated_at is null)
    or (status='attested' and attested_at is not null and activated_at is null and manifest_sha256 is not null and length(btrim(attestation_actor))>0)
    or (status='active' and attested_at is not null and activated_at is not null and manifest_sha256 is not null and length(btrim(attestation_actor))>0))
);

create table app_private.chem_junior_point_aid_bindings (
  revision_id uuid not null references app_private.chem_junior_point_aid_releases(id),
  textbook_version text not null default '科粤版' check (textbook_version='科粤版'),
  knowledge_id text not null,
  logical_card_id text not null references public.chem_knowledge_cards(id),
  original_card_sha256 text not null check (original_card_sha256 ~ '^[0-9a-f]{64}$'),
  parent_release_id uuid not null references app_private.chem_question_source_releases(id),
  parent_question_manifest_sha256 text not null check (parent_question_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  parent_card_manifest_sha256 text not null check (parent_card_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  canonical_source_id text not null,
  canonical_source_sha256 text not null check (canonical_source_sha256 ~ '^[0-9a-f]{64}$'),
  previous_revision_id uuid references app_private.chem_junior_point_aid_releases(id),
  prior_storage_card_id text not null references public.chem_knowledge_cards(id),
  prior_card_sha256 text not null check (prior_card_sha256 ~ '^[0-9a-f]{64}$'),
  storage_card_id text not null unique references public.chem_knowledge_cards(id),
  storage_card_sha256 text not null check (storage_card_sha256 ~ '^[0-9a-f]{64}$'),
  reviewed_patches jsonb not null check (jsonb_typeof(reviewed_patches)='array' and jsonb_array_length(reviewed_patches)>0),
  primary key (revision_id,knowledge_id),
  unique (revision_id,logical_card_id),
  check (storage_card_id<>logical_card_id and storage_card_id<>prior_storage_card_id)
);
create index chem_junior_point_aid_bindings_lookup on app_private.chem_junior_point_aid_bindings(logical_card_id,parent_release_id,revision_id);
create index chem_junior_point_aid_bindings_presented_lookup on app_private.chem_junior_point_aid_bindings(textbook_version,knowledge_id,parent_release_id,logical_card_id) include(revision_id,storage_card_id);
alter table app_private.chem_junior_point_aid_releases enable row level security;
alter table app_private.chem_junior_point_aid_bindings enable row level security;
revoke all on app_private.chem_junior_point_aid_releases, app_private.chem_junior_point_aid_bindings from public,anon,authenticated,service_role;
grant select on app_private.chem_junior_point_aid_releases,app_private.chem_junior_point_aid_bindings to service_role;
revoke all on sequence app_private.chem_junior_point_aid_releases_revision_seq_seq from public,anon,authenticated,service_role;

create function app_private.chem_apply_reviewed_point_aid_patches(p_content jsonb,p_patches jsonb)
returns jsonb language plpgsql immutable set search_path='' as $fn$
declare
  v_patch jsonb; v_path text[]; v_seen text[]:=array[]::text[]; v_content jsonb:=p_content;
  v_idx integer; v_n integer; v_key text; v_field text; v_array jsonb; v_element jsonb;
begin
  if jsonb_typeof(p_content) is distinct from 'object' or jsonb_typeof(p_patches) is distinct from 'array'
    or jsonb_array_length(p_patches) not between 1 and 1000 then raise exception 'invalid reviewed point aid payload'; end if;
  for v_patch in select value from jsonb_array_elements(p_patches) loop
    if jsonb_typeof(v_patch) is distinct from 'object' or exists(
      select 1 from jsonb_object_keys(v_patch) as key where key not in ('path','expectedLabel','expectedRule','examples','visualSteps','nextRule')
    ) or not(v_patch ?& array['path','expectedLabel','expectedRule','examples','visualSteps'])
      or jsonb_typeof(v_patch->'path') is distinct from 'array'
      or jsonb_typeof(v_patch->'expectedLabel') is distinct from 'string'
      or jsonb_typeof(v_patch->'expectedRule') is distinct from 'string' then raise exception 'reviewed point aid patch has unapproved fields'; end if;
    if exists(select 1 from jsonb_array_elements(v_patch->'path') value where jsonb_typeof(value)<>'string') then raise exception 'path must be string segments'; end if;
    select array_agg(value order by ordinality) into v_path from jsonb_array_elements_text(v_patch->'path') with ordinality;
    v_n:=cardinality(v_path);
    if v_path[1]='sections' then
      if v_n<4 or v_path[2]!~'^(0|[1-9][0-9]*)$' or v_path[3]<>'items' or v_path[4]!~'^(0|[1-9][0-9]*)$' or mod(v_n-4,2)<>0 then raise exception 'invalid section node path'; end if;
      v_idx:=5;
    elsif v_path[1]='rootTree' then
      if mod(v_n-1,2)<>0 then raise exception 'invalid root tree node path'; end if;
      v_idx:=2;
    else raise exception 'only sections/items or rootTree nodes may be revised'; end if;
    while v_idx<=v_n loop
      if v_path[v_idx]<>'children' or v_path[v_idx+1]!~'^(0|[1-9][0-9]*)$' then raise exception 'invalid child node path'; end if;
      v_idx:=v_idx+2;
    end loop;
    v_key:=v_path::text;
    if v_key=any(v_seen) then raise exception 'duplicate reviewed path: %',v_key; end if;
    v_seen:=array_append(v_seen,v_key);
    if jsonb_typeof(v_content#>v_path) is distinct from 'object'
      or (v_content#>>(v_path||array['label'])) is distinct from v_patch->>'expectedLabel'
      or (v_content#>>(v_path||array['rule'])) is distinct from v_patch->>'expectedRule' then raise exception 'stale reviewed node at %',v_key; end if;
    foreach v_field in array array['examples','visualSteps'] loop
      v_array:=v_patch->v_field;
      if jsonb_typeof(v_array) is distinct from 'array' or jsonb_array_length(v_array) not between 1 and 12 then raise exception 'invalid % at %',v_field,v_key; end if;
      for v_element in select value from jsonb_array_elements(v_array) loop
        if jsonb_typeof(v_element) is distinct from 'string' or length(btrim(v_element#>>'{}')) not between 1 and 4000 then raise exception 'invalid point aid text'; end if;
      end loop;
      v_content:=jsonb_set(v_content,v_path||array[v_field],v_array,true);
    end loop;
    if v_patch ? 'nextRule' then
      if jsonb_typeof(v_patch->'nextRule') is distinct from 'string' or length(btrim(v_patch->>'nextRule')) not between 1 and 4000 then raise exception 'invalid reviewed rule'; end if;
      v_content:=jsonb_set(v_content,v_path||array['rule'],v_patch->'nextRule',false);
    end if;
  end loop;
  return v_content;
end;
$fn$;

create function app_private.chem_junior_point_aid_manifest_sha256(p_revision_id uuid)
returns text language sql stable set search_path='' as $fn$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'contract','junior_reviewed_point_aids_v1',
    'id',r.id,'reviewed_artifact_sha256',r.reviewed_artifact_sha256,'payload_sha256',r.payload_sha256,
    'bindings',coalesce((select jsonb_agg(to_jsonb(b) order by b.knowledge_id) from app_private.chem_junior_point_aid_bindings b where b.revision_id=r.id),'[]'::jsonb)
  )::text,'UTF8'),'sha256'),'hex') from app_private.chem_junior_point_aid_releases r where r.id=p_revision_id;
$fn$;

create function app_private.chem_assert_junior_point_aid_revision(p_revision_id uuid)
returns void language plpgsql stable set search_path='' as $fn$
declare
  v_release app_private.chem_junior_point_aid_releases%rowtype;
  v_binding app_private.chem_junior_point_aid_bindings%rowtype;
  v_original public.chem_knowledge_cards%rowtype; v_prior public.chem_knowledge_cards%rowtype; v_next public.chem_knowledge_cards%rowtype;
  v_group jsonb; v_count integer;
begin
  select * into strict v_release from app_private.chem_junior_point_aid_releases where id=p_revision_id;
  if v_release.payload_sha256<>encode(extensions.digest(convert_to(v_release.reviewed_payload::text,'UTF8'),'sha256'),'hex') then raise exception 'reviewed payload digest mismatch'; end if;
  select count(*) into v_count from app_private.chem_junior_point_aid_bindings where revision_id=p_revision_id;
  if v_count<>jsonb_array_length(v_release.reviewed_payload) then raise exception 'revision binding coverage mismatch'; end if;
  for v_binding in select * from app_private.chem_junior_point_aid_bindings where revision_id=p_revision_id order by knowledge_id loop
    select * into strict v_original from public.chem_knowledge_cards where id=v_binding.logical_card_id;
    select * into strict v_prior from public.chem_knowledge_cards where id=v_binding.prior_storage_card_id;
    select * into strict v_next from public.chem_knowledge_cards where id=v_binding.storage_card_id;
    select value into strict v_group from jsonb_array_elements(v_release.reviewed_payload) where value->>'logicalCardId'=v_binding.logical_card_id;
    if v_group->'patches' is distinct from v_binding.reviewed_patches
      or v_group->>'storageCardId' is distinct from v_binding.storage_card_id
      or v_group->>'knowledgeId' is distinct from v_binding.knowledge_id
      or v_original.skill_id<>v_binding.knowledge_id or v_next.skill_id<>v_binding.knowledge_id
      or v_next.review_status<>'draft'
      or app_private.chem_junior_knowledge_card_sha256(v_original)<>v_binding.original_card_sha256
      or app_private.chem_junior_knowledge_card_sha256(v_prior)<>v_binding.prior_card_sha256
      or app_private.chem_junior_knowledge_card_sha256(v_next)<>v_binding.storage_card_sha256
      or (to_jsonb(v_next)-array['id','created_at','updated_at','structured_content','review_status']) is distinct from (to_jsonb(v_prior)-array['id','created_at','updated_at','structured_content','review_status'])
      or v_next.structured_content is distinct from app_private.chem_apply_reviewed_point_aid_patches(v_prior.structured_content,v_binding.reviewed_patches)
      then raise exception 'revision changes unreviewed fields or digest: %',v_binding.logical_card_id; end if;
    if v_binding.previous_revision_id is null then
      if v_binding.prior_storage_card_id<>v_binding.logical_card_id or v_binding.prior_card_sha256<>v_binding.original_card_sha256 then raise exception 'invalid initial revision ancestry'; end if;
    elsif not exists(select 1 from app_private.chem_junior_point_aid_bindings prior join app_private.chem_junior_point_aid_releases prior_release on prior_release.id=prior.revision_id
      where prior.revision_id=v_binding.previous_revision_id and prior_release.status='active' and prior_release.revision_seq<v_release.revision_seq
        and prior.logical_card_id=v_binding.logical_card_id and prior.parent_release_id=v_binding.parent_release_id
        and prior.storage_card_id=v_binding.prior_storage_card_id and prior.storage_card_sha256=v_binding.prior_card_sha256
    ) then raise exception 'invalid revision ancestry'; end if;
    if not app_private.chem_junior_knowledge_card_binding_matches(v_binding.parent_release_id,'科粤版',v_binding.knowledge_id)
      or not exists(select 1 from app_private.chem_junior_knowledge_card_bindings original_binding
        join app_private.chem_question_source_releases source_release on source_release.id=original_binding.release_id
        join app_private.chem_junior_source_release_rights rights on rights.release_id=source_release.id
        where original_binding.release_id=v_binding.parent_release_id and original_binding.knowledge_id=v_binding.knowledge_id
          and original_binding.card_id=v_binding.logical_card_id and original_binding.card_sha256=v_binding.original_card_sha256
          and original_binding.canonical_source_id=v_binding.canonical_source_id and original_binding.canonical_source_sha256=v_binding.canonical_source_sha256
          and source_release.manifest_sha256=v_binding.parent_question_manifest_sha256
          and rights.attested_manifest_sha256=source_release.manifest_sha256
          and rights.attested_card_manifest_sha256=v_binding.parent_card_manifest_sha256
          and rights.attested_card_manifest_sha256=app_private.chem_junior_knowledge_card_manifest_sha256(source_release.id)
          and rights.rights_status=v_release.rights_status and rights.redistribution_allowed=false and rights.attested_at is not null
      ) then raise exception 'original question/source/card attestation mismatch'; end if;
  end loop;
  if v_release.status<>'staged' and v_release.manifest_sha256 is distinct from app_private.chem_junior_point_aid_manifest_sha256(p_revision_id) then raise exception 'revision manifest mismatch'; end if;
end;
$fn$;

create function app_private.chem_guard_junior_point_aid_release()
returns trigger language plpgsql set search_path='' as $fn$
begin
  if tg_op='DELETE' then raise exception 'point aid release audit ledger is append-only'; end if;
  if not ((old.status='staged' and new.status='attested'
      and (to_jsonb(new)-array['status','manifest_sha256','attestation_actor','attested_at'])=(to_jsonb(old)-array['status','manifest_sha256','attestation_actor','attested_at']))
    or (old.status='attested' and new.status='active'
      and (to_jsonb(new)-array['status','activated_at'])=(to_jsonb(old)-array['status','activated_at']))) then raise exception 'point aid release is immutable except attestation and activation'; end if;
  return new;
end;
$fn$;
create trigger chem_guard_junior_point_aid_release before update or delete on app_private.chem_junior_point_aid_releases
for each row execute function app_private.chem_guard_junior_point_aid_release();

create function app_private.chem_guard_junior_point_aid_binding()
returns trigger language plpgsql set search_path='' as $fn$
begin
  if tg_op<>'INSERT' then raise exception 'point aid revision binding is append-only'; end if;
  perform id from app_private.chem_junior_point_aid_releases where id=new.revision_id and status='staged' for update;
  if not found then raise exception 'only staged point aid release accepts bindings'; end if;
  return new;
end;
$fn$;
create trigger chem_guard_junior_point_aid_binding before insert or update or delete on app_private.chem_junior_point_aid_bindings
for each row execute function app_private.chem_guard_junior_point_aid_binding();

create function app_private.chem_guard_revision_storage_junior_card()
returns trigger language plpgsql set search_path='' as $fn$
begin
  if exists(select 1 from app_private.chem_junior_point_aid_bindings where storage_card_id=old.id) then raise exception 'bound point aid revision storage card is immutable; publish a further revision'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$fn$;
create trigger chem_guard_revision_storage_junior_card before update or delete on public.chem_knowledge_cards
for each row execute function app_private.chem_guard_revision_storage_junior_card();

create function app_private.chem_stage_junior_point_aid_revision(p_revision_id uuid,p_reviewed_artifact_sha256 text,p_reviewed_payload jsonb,p_verification_actor text)
returns text language plpgsql set search_path='' as $fn$
declare
  v_group jsonb; v_release app_private.chem_junior_point_aid_releases%rowtype;
  v_original public.chem_knowledge_cards%rowtype; v_prior public.chem_knowledge_cards%rowtype; v_next public.chem_knowledge_cards%rowtype;
  v_previous app_private.chem_junior_point_aid_bindings%rowtype;
  v_parent app_private.chem_junior_knowledge_card_bindings%rowtype; v_content jsonb; v_payload_sha text;
  v_parent_manifest text; v_parent_card_manifest text; v_prev_id uuid; v_storage_id text; v_manifest text;
begin
  if p_revision_id is null or p_reviewed_artifact_sha256!~'^[0-9a-f]{64}$'
    or p_verification_actor is distinct from 'codex-knowledge-card-source-qa'
    or jsonb_typeof(p_reviewed_payload) is distinct from 'array' or jsonb_array_length(p_reviewed_payload) not between 1 and 100 then raise exception 'invalid staged point aid release'; end if;
  perform pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
  perform pg_advisory_xact_lock(hashtextextended('chem-h3-original-release',0));
  v_payload_sha:=encode(extensions.digest(convert_to(p_reviewed_payload::text,'UTF8'),'sha256'),'hex');
  select * into v_release from app_private.chem_junior_point_aid_releases where id=p_revision_id for update;
  if found then
    if v_release.payload_sha256<>v_payload_sha or v_release.reviewed_artifact_sha256<>p_reviewed_artifact_sha256 then raise exception 'revision idempotency key used for a different reviewed payload'; end if;
    perform app_private.chem_assert_junior_point_aid_revision(p_revision_id);
    return app_private.chem_junior_point_aid_manifest_sha256(p_revision_id);
  end if;
  insert into app_private.chem_junior_point_aid_releases(id,reviewed_artifact_sha256,reviewed_payload,payload_sha256,verification_actor)
    values(p_revision_id,p_reviewed_artifact_sha256,p_reviewed_payload,v_payload_sha,p_verification_actor);
  for v_group in select value from jsonb_array_elements(p_reviewed_payload) order by value->>'knowledgeId' loop
    if jsonb_typeof(v_group) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v_group) as key where key not in(
      'knowledgeId','logicalCardId','storageCardId','expectedOriginalCardSha256','expectedParentReleaseId','expectedParentQuestionManifestSha256','expectedParentCardManifestSha256',
      'expectedCanonicalSourceId','expectedCanonicalSourceSha256','expectedPreviousRevisionId','expectedPriorStorageCardId','expectedPriorCardSha256','patches'))
      or not(v_group ?& array['knowledgeId','logicalCardId','storageCardId','expectedOriginalCardSha256','expectedParentReleaseId','expectedParentQuestionManifestSha256','expectedParentCardManifestSha256',
      'expectedCanonicalSourceId','expectedCanonicalSourceSha256','expectedPreviousRevisionId','expectedPriorStorageCardId','expectedPriorCardSha256','patches']) then raise exception 'invalid reviewed card group fields'; end if;
    if app_private.chem_junior_ready_card_id('科粤版',v_group->>'knowledgeId') is distinct from v_group->>'logicalCardId' then raise exception 'original logical card is not the current sealed ready card'; end if;
    select card.* into strict v_original from public.chem_knowledge_cards card where card.id=v_group->>'logicalCardId' for share;
    select original_binding.* into strict v_parent from app_private.chem_junior_knowledge_card_bindings original_binding
      join app_private.chem_junior_knowledge_provenance provenance on provenance.source_release_id=original_binding.release_id and provenance.knowledge_id=original_binding.knowledge_id and provenance.textbook_version=original_binding.textbook_version
      where provenance.textbook_version='科粤版' and provenance.knowledge_id=v_group->>'knowledgeId' and original_binding.card_id=v_original.id for share of original_binding,provenance;
    select manifest_sha256 into strict v_parent_manifest from app_private.chem_question_source_releases where id=v_parent.release_id for share;
    select attested_card_manifest_sha256 into strict v_parent_card_manifest from app_private.chem_junior_source_release_rights where release_id=v_parent.release_id for share;
    if v_group->>'expectedOriginalCardSha256' is distinct from v_parent.card_sha256
      or app_private.chem_junior_knowledge_card_sha256(v_original)<>v_parent.card_sha256
      or v_group->>'expectedParentReleaseId' is distinct from v_parent.release_id::text
      or v_group->>'expectedParentQuestionManifestSha256' is distinct from v_parent_manifest
      or v_group->>'expectedParentCardManifestSha256' is distinct from v_parent_card_manifest
      or v_group->>'expectedCanonicalSourceId' is distinct from v_parent.canonical_source_id
      or v_group->>'expectedCanonicalSourceSha256' is distinct from v_parent.canonical_source_sha256 then raise exception 'stale original card/source/release proof'; end if;
    select binding.* into v_previous from app_private.chem_junior_point_aid_bindings binding join app_private.chem_junior_point_aid_releases release_row on release_row.id=binding.revision_id
      where binding.logical_card_id=v_original.id and binding.parent_release_id=v_parent.release_id and release_row.status='active' order by release_row.revision_seq desc limit 1;
    v_prev_id:=v_previous.revision_id;
    if v_prev_id::text is distinct from v_group->>'expectedPreviousRevisionId' then raise exception 'concurrent point aid revision'; end if;
    select * into strict v_prior from public.chem_knowledge_cards where id=coalesce(v_previous.storage_card_id,v_original.id) for share;
    if v_group->>'expectedPriorStorageCardId' is distinct from v_prior.id or v_group->>'expectedPriorCardSha256' is distinct from app_private.chem_junior_knowledge_card_sha256(v_prior) then raise exception 'stale prior point aid payload'; end if;
    if v_prev_id is not null then perform app_private.chem_assert_junior_point_aid_revision(v_prev_id); end if;
    v_content:=app_private.chem_apply_reviewed_point_aid_patches(v_prior.structured_content,v_group->'patches');
    v_storage_id:=v_group->>'storageCardId';
    if v_storage_id is distinct from (v_original.id||'__AIDREV_'||replace(p_revision_id::text,'-','')) then raise exception 'storage identity must be namespaced by exact release id'; end if;
    insert into public.chem_knowledge_cards(id,skill_id,title,core,detail,steps,common_mistakes,micro_example,asset,review_status,structured_content)
      values(v_storage_id,v_prior.skill_id,v_prior.title,v_prior.core,v_prior.detail,v_prior.steps,v_prior.common_mistakes,v_prior.micro_example,v_prior.asset,'draft',v_content)
      returning * into v_next;
    insert into app_private.chem_junior_point_aid_bindings(revision_id,knowledge_id,logical_card_id,original_card_sha256,parent_release_id,parent_question_manifest_sha256,parent_card_manifest_sha256,
      canonical_source_id,canonical_source_sha256,previous_revision_id,prior_storage_card_id,prior_card_sha256,storage_card_id,storage_card_sha256,reviewed_patches)
      values(p_revision_id,v_parent.knowledge_id,v_original.id,v_parent.card_sha256,v_parent.release_id,v_parent_manifest,v_parent_card_manifest,v_parent.canonical_source_id,v_parent.canonical_source_sha256,
      v_prev_id,v_prior.id,app_private.chem_junior_knowledge_card_sha256(v_prior),v_next.id,app_private.chem_junior_knowledge_card_sha256(v_next),v_group->'patches');
  end loop;
  perform app_private.chem_assert_junior_point_aid_revision(p_revision_id);
  v_manifest:=app_private.chem_junior_point_aid_manifest_sha256(p_revision_id);
  return v_manifest;
end;
$fn$;

create function app_private.chem_attest_junior_point_aid_revision(p_revision_id uuid,p_expected_manifest_sha256 text,p_attestation_actor text)
returns void language plpgsql set search_path='' as $fn$
declare v_release app_private.chem_junior_point_aid_releases%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
  perform pg_advisory_xact_lock(hashtextextended('chem-h3-original-release',0));
  select * into strict v_release from app_private.chem_junior_point_aid_releases where id=p_revision_id for update;
  if length(btrim(coalesce(p_attestation_actor,''))) not between 3 and 160 then raise exception 'named review attestation required'; end if;
  perform app_private.chem_assert_junior_point_aid_revision(p_revision_id);
  if p_expected_manifest_sha256 is distinct from app_private.chem_junior_point_aid_manifest_sha256(p_revision_id) then raise exception 'attestation manifest mismatch'; end if;
  if v_release.status='staged' then
    update app_private.chem_junior_point_aid_releases set status='attested',manifest_sha256=p_expected_manifest_sha256,attestation_actor=btrim(p_attestation_actor),attested_at=now() where id=p_revision_id;
  elsif v_release.attestation_actor is distinct from btrim(p_attestation_actor) then raise exception 'existing attestation belongs to different reviewer'; end if;
end;
$fn$;

create function app_private.chem_activate_junior_point_aid_revision(p_revision_id uuid,p_expected_manifest_sha256 text)
returns void language plpgsql set search_path='' as $fn$
declare v_release app_private.chem_junior_point_aid_releases%rowtype; v_binding app_private.chem_junior_point_aid_bindings%rowtype; v_latest uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
  perform pg_advisory_xact_lock(hashtextextended('chem-h3-original-release',0));
  select * into strict v_release from app_private.chem_junior_point_aid_releases where id=p_revision_id for update;
  if v_release.status not in ('attested','active') or v_release.manifest_sha256 is distinct from p_expected_manifest_sha256 then raise exception 'activation requires exact attested revision'; end if;
  perform app_private.chem_assert_junior_point_aid_revision(p_revision_id);
  if v_release.status='active' then return; end if;
  for v_binding in select * from app_private.chem_junior_point_aid_bindings where revision_id=p_revision_id loop
    if app_private.chem_junior_ready_card_id('科粤版',v_binding.knowledge_id) is distinct from v_binding.logical_card_id
      or not exists(select 1 from app_private.chem_junior_knowledge_provenance where textbook_version='科粤版' and knowledge_id=v_binding.knowledge_id and source_release_id=v_binding.parent_release_id) then raise exception 'activation source route changed'; end if;
    select b.revision_id into v_latest from app_private.chem_junior_point_aid_bindings b join app_private.chem_junior_point_aid_releases r on r.id=b.revision_id
      where b.logical_card_id=v_binding.logical_card_id and b.parent_release_id=v_binding.parent_release_id and r.status='active' order by r.revision_seq desc limit 1;
    if v_latest is distinct from v_binding.previous_revision_id then raise exception 'activation would overwrite newer published point aids'; end if;
  end loop;
  update app_private.chem_junior_point_aid_releases set status='active',activated_at=now() where id=p_revision_id;
end;
$fn$;

create function app_private.chem_junior_point_aid_card(p_textbook_version text,p_knowledge_id text)
returns public.chem_knowledge_cards language plpgsql stable set search_path='' as $fn$
declare
  v_logical_id text; v_parent_id uuid; v_revision_id uuid; v_storage_id text; v_card public.chem_knowledge_cards%rowtype;
begin
  v_logical_id:=app_private.chem_junior_ready_card_id(p_textbook_version,p_knowledge_id);
  if v_logical_id is null then return null; end if;
  select source_release_id into strict v_parent_id from app_private.chem_junior_knowledge_provenance where textbook_version=p_textbook_version and knowledge_id=p_knowledge_id;
  select b.revision_id,b.storage_card_id into v_revision_id,v_storage_id from app_private.chem_junior_point_aid_bindings b join app_private.chem_junior_point_aid_releases r on r.id=b.revision_id
    where b.textbook_version=p_textbook_version and b.knowledge_id=p_knowledge_id and b.logical_card_id=v_logical_id and b.parent_release_id=v_parent_id and r.status='active'
    order by r.revision_seq desc limit 1;
  -- Called only by the server-only batch RPC after each distinct revision has been checked once.
  select * into strict v_card from public.chem_knowledge_cards where id=coalesce(v_storage_id,v_logical_id);
  v_card.id:=v_logical_id;
  if v_revision_id is not null then v_card.review_status:='approved'; end if;
  return v_card;
end;
$fn$;

create or replace function public.chem_junior_bound_knowledge_cards(p_textbook_version text,p_knowledge_ids text[] default null)
returns setof public.chem_knowledge_cards language plpgsql stable security definer set search_path='' as $fn$
declare v_revision_id uuid;
begin
  -- Validate a release once for a requested batch, never once per card. No stale fallback on verification failure.
  for v_revision_id in
    select distinct latest.revision_id from app_private.chem_junior_knowledge_provenance provenance
    cross join lateral (
      select b.revision_id from app_private.chem_junior_point_aid_bindings b join app_private.chem_junior_point_aid_releases r on r.id=b.revision_id
      where b.textbook_version=provenance.textbook_version and b.knowledge_id=provenance.knowledge_id and b.parent_release_id=provenance.source_release_id
        and b.logical_card_id=app_private.chem_junior_ready_card_id(p_textbook_version,provenance.knowledge_id) and r.status='active'
      order by r.revision_seq desc limit 1
    ) latest
    where provenance.textbook_version=p_textbook_version and (p_knowledge_ids is null or provenance.knowledge_id=any(p_knowledge_ids))
  loop
    perform app_private.chem_assert_junior_point_aid_revision(v_revision_id);
  end loop;
  return query select card.* from app_private.chem_junior_knowledge_provenance provenance
  cross join lateral app_private.chem_junior_point_aid_card(p_textbook_version,provenance.knowledge_id) card
  where provenance.textbook_version=p_textbook_version
    and (p_knowledge_ids is null or provenance.knowledge_id=any(p_knowledge_ids))
    and card.id is not null order by card.skill_id,card.id;
end;
$fn$;

revoke all on function app_private.chem_apply_reviewed_point_aid_patches(jsonb,jsonb),
  app_private.chem_junior_point_aid_manifest_sha256(uuid),app_private.chem_assert_junior_point_aid_revision(uuid),
  app_private.chem_guard_junior_point_aid_release(),app_private.chem_guard_junior_point_aid_binding(),app_private.chem_guard_revision_storage_junior_card(),
  app_private.chem_stage_junior_point_aid_revision(uuid,text,jsonb,text),app_private.chem_attest_junior_point_aid_revision(uuid,text,text),
  app_private.chem_activate_junior_point_aid_revision(uuid,text),app_private.chem_junior_point_aid_card(text,text)
from public,anon,authenticated,service_role;
-- Trigger executes with its caller; existing service-role card writes may read only the immutable ledger.
grant execute on function app_private.chem_guard_revision_storage_junior_card() to service_role;
revoke all on function public.chem_junior_bound_knowledge_cards(text,text[]) from public,anon,authenticated,service_role;
grant execute on function public.chem_junior_bound_knowledge_cards(text,text[]) to service_role;
comment on function public.chem_junior_bound_knowledge_cards(text,text[]) is
  'Server-only version resolver: preserves original logical card and point IDs; independently attested revisions alter only reviewed node examples/visualSteps/rule. Question source release and provenance remain intact.';
