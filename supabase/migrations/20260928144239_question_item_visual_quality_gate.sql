-- A release-wide hash proves that bytes did not change. It does not prove that
-- each crop contains every formula, charge, option and explanation. New source
-- questions therefore start pending a per-item comparison with the original.
-- Existing active releases are intentionally not backfilled here: that would
-- hide the whole live bank before the original PDFs have been rechecked.
begin;

create table app_private.chem_question_item_visual_reviews (
  question_id text primary key references public.chem_questions(id) on delete restrict,
  source_release_id uuid not null references app_private.chem_question_source_releases(id) on delete restrict,
  review_state text not null default 'pending' check (review_state in ('pending','verified','rejected')),
  revision_token text check (revision_token is null or revision_token ~ '^[0-9a-f]{64}$'),
  source_item_sha256 text check (source_item_sha256 is null or source_item_sha256 ~ '^[0-9a-f]{64}$'),
  question_image_sha256 text check (question_image_sha256 is null or question_image_sha256 ~ '^[0-9a-f]{64}$'),
  analysis_image_sha256 text check (analysis_image_sha256 is null or analysis_image_sha256 ~ '^[0-9a-f]{64}$'),
  source_document_sha256 text check (source_document_sha256 is null or source_document_sha256 ~ '^[0-9a-f]{64}$'),
  source_locator text,
  review_checks jsonb not null default '{}'::jsonb check (jsonb_typeof(review_checks)='object'),
  review_note text,
  review_actor text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chem_question_item_visual_verified_evidence check (
    review_state <> 'verified' or (
      revision_token is not null and source_item_sha256 is not null
      and length(btrim(coalesce(source_locator,''))) >= 3
      and length(btrim(coalesce(review_note,''))) >= 12
      and length(btrim(coalesce(review_actor,''))) >= 3
      and reviewed_at is not null
      and review_checks->'stem_options_and_formula' is not distinct from 'true'::jsonb
      and review_checks->'answer_and_explanation' is not distinct from 'true'::jsonb
      and review_checks->'source_image_complete' is not distinct from 'true'::jsonb
      and review_checks->'source_locator_matches' is not distinct from 'true'::jsonb
      and ((question_image_sha256 is not null and analysis_image_sha256 is not null)
        or source_document_sha256 is not null)
    )
  )
);
create index chem_question_item_visual_reviews_pending_idx
  on app_private.chem_question_item_visual_reviews(source_release_id, review_state)
  where review_state <> 'verified';
alter table app_private.chem_question_item_visual_reviews enable row level security;
revoke all on table app_private.chem_question_item_visual_reviews from public, anon, authenticated, service_role;

create table app_private.chem_question_item_visual_review_events (
  event_id bigint generated always as identity primary key,
  question_id text not null references public.chem_questions(id) on delete restrict,
  review_state text not null,
  revision_token text,
  source_item_sha256 text,
  review_actor text,
  review_note text,
  recorded_at timestamptz not null default now()
);
create index chem_question_item_visual_review_events_question_idx
  on app_private.chem_question_item_visual_review_events(question_id,event_id);
alter table app_private.chem_question_item_visual_review_events enable row level security;
revoke all on table app_private.chem_question_item_visual_review_events from public,anon,authenticated,service_role;

create function app_private.chem_log_question_item_visual_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into app_private.chem_question_item_visual_review_events(
    question_id,review_state,revision_token,source_item_sha256,review_actor,review_note
  ) values (
    new.question_id,new.review_state,new.revision_token,new.source_item_sha256,
    new.review_actor,new.review_note
  );
  return new;
end;
$$;
revoke all on function app_private.chem_log_question_item_visual_review()
  from public,anon,authenticated,service_role;
create trigger chem_log_question_item_visual_review
after insert or update on app_private.chem_question_item_visual_reviews
for each row execute function app_private.chem_log_question_item_visual_review();

-- This trigger covers future imports and any change to the student-facing
-- question, answer, explanation, image link, or source identity. Merely
-- switching an already-reviewed release to usable_for_review does not erase
-- its approval.
create function app_private.chem_queue_question_item_visual_review()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.source_release_id is null then return new; end if;
  if tg_op = 'UPDATE' then
    if not (
      new.source_release_id is distinct from old.source_release_id or
      new.stem is distinct from old.stem or
      new.options is distinct from old.options or
      new.correct_option is distinct from old.correct_option or
      new.explanation is distinct from old.explanation or
      new.render_mode is distinct from old.render_mode or
      new.asset_refs is distinct from old.asset_refs or
      new.image_url is distinct from old.image_url or
      new.source_info is distinct from old.source_info or
      new.source_item_key is distinct from old.source_item_key or
      new.content_fingerprint is distinct from old.content_fingerprint or
      new.question_revision_token is distinct from old.question_revision_token
    ) then return new; end if;
  end if;

  insert into app_private.chem_question_item_visual_reviews(
    question_id,source_release_id,review_state,revision_token,updated_at
  ) values (new.id,new.source_release_id,'pending',new.question_revision_token,now())
  on conflict(question_id) do update set
    source_release_id=excluded.source_release_id,
    review_state='pending',
    revision_token=excluded.revision_token,
    source_item_sha256=null,
    question_image_sha256=null,
    analysis_image_sha256=null,
    source_document_sha256=null,
    source_locator=null,
    review_checks='{}'::jsonb,
    review_note=null,
    review_actor=null,
    reviewed_at=null,
    updated_at=now();
  return new;
end;
$$;
revoke all on function app_private.chem_queue_question_item_visual_review() from public,anon,authenticated,service_role;
create trigger chem_queue_question_item_visual_review
after insert or update on public.chem_questions
for each row execute function app_private.chem_queue_question_item_visual_review();

-- Readiness is tied to the exact revision AND the immutable source-item
-- ledger. A release-level full_visual_verified flag alone never satisfies it.
create function app_private.chem_question_item_visual_reviewed(p_question_id text)
returns boolean language sql stable set search_path='' as $$
  select exists(
    select 1 from public.chem_questions q
    join app_private.chem_question_item_visual_reviews review
      on review.question_id=q.id and review.source_release_id=q.source_release_id
    join app_private.chem_question_source_release_items item
      on item.question_id=q.id and item.release_id=q.source_release_id
    where q.id=p_question_id
      and review.review_state='verified'
      and review.revision_token=q.question_revision_token
      and review.source_locator=q.source_info->>'locator'
      and review.source_item_sha256=item.item_sha256
      and (
        (q.grade_band in ('高一','高二','高三')
          and review.question_image_sha256=item.question_asset_sha256
          and review.analysis_image_sha256=item.analysis_asset_sha256)
        or (q.grade_band='初三' and review.source_document_sha256 is not null
          and exists (
            select 1 from app_private.chem_junior_source_release_provenance provenance
            where provenance.release_id=q.source_release_id
              and provenance.knowledge_id=q.knowledge_id
              and provenance.source_sha256=review.source_document_sha256
              and provenance.verification_status='verified'
          ))
      )
  );
$$;
revoke all on function app_private.chem_question_item_visual_reviewed(text) from public,anon,authenticated,service_role;

-- Private audit inventory for systematically reviewing the already-active
-- legacy pool. Candidate flags are triage hints, never automatic chemistry
-- corrections or blanket holds; every item still needs its source compared.
create view app_private.chem_question_item_visual_audit_queue as
select q.id as question_id,q.grade_band,q.source_release_id,
  q.source_info->>'locator' as source_locator,q.question_revision_token,
  coalesce(review.review_state,'legacy_unreviewed') as review_state,
  array_remove(array[
    case when q.question_revision_token is null then 'missing_revision_token' end,
    case when item.question_id is null then 'missing_source_item' end,
    case when (q.stem || q.options::text || q.explanation)
      ~ ('[' || U&'\FFFD' || U&'\E000' || '-' || U&'\F8FF' || ']')
      then 'ocr_replacement_or_private_use_character' end,
    case when q.grade_band in ('高一','高二','高三') and not exists (
      select 1 from app_private.chem_question_assets asset
      where asset.question_id=q.id and asset.asset_kind='question_image'
        and asset.sha256=item.question_asset_sha256
    ) then 'question_image_missing_or_mismatched' end,
    case when q.grade_band in ('高一','高二','高三') and not exists (
      select 1 from app_private.chem_question_assets asset
      where asset.question_id=q.id and asset.asset_kind='analysis_image'
        and asset.sha256=item.analysis_asset_sha256
    ) then 'analysis_image_missing_or_mismatched' end
  ],null)::text[] as candidate_flags
from public.chem_questions q
join app_private.chem_question_source_releases release on release.id=q.source_release_id
left join app_private.chem_question_source_release_items item
  on item.release_id=q.source_release_id and item.question_id=q.id
left join app_private.chem_question_item_visual_reviews review on review.question_id=q.id
where release.status='active' and q.usable_for_review;
revoke all on app_private.chem_question_item_visual_audit_queue from public,anon,authenticated,service_role;

-- A service-only reviewer must inspect the source crop/PDF, transcribed
-- stem and options (including all subscripts/charges), answer and explanation.
-- These explicit attestations make the human decision auditable; the function
-- independently checks that the cited asset/source hashes still match.
create function public.chem_record_question_item_visual_review(
  p_question_id text,
  p_revision_token text,
  p_source_locator text,
  p_review_actor text,
  p_review_note text,
  p_checks jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_question public.chem_questions%rowtype;
  v_item app_private.chem_question_source_release_items%rowtype;
  v_source_document_sha256 text;
begin
  if p_revision_token !~ '^[0-9a-f]{64}$'
    or length(btrim(coalesce(p_source_locator,''))) < 3
    or length(btrim(coalesce(p_review_actor,''))) < 3
    or length(btrim(coalesce(p_review_note,''))) < 12
    or jsonb_typeof(p_checks) is distinct from 'object'
    or p_checks->'stem_options_and_formula' is distinct from 'true'::jsonb
    or p_checks->'answer_and_explanation' is distinct from 'true'::jsonb
    or p_checks->'source_image_complete' is distinct from 'true'::jsonb
    or p_checks->'source_locator_matches' is distinct from 'true'::jsonb
  then raise exception '逐题核验须包含原图、公式上下标及电荷、四个选项、答案解析和来源定位'; end if;

  select * into v_question from public.chem_questions
  where id=p_question_id and source_release_id is not null for update;
  if not found or v_question.question_revision_token is distinct from p_revision_token
    or v_question.source_info->>'locator' is distinct from p_source_locator
  then raise exception '题目修订或来源定位已变化，请重新核验'; end if;

  select * into v_item from app_private.chem_question_source_release_items
  where release_id=v_question.source_release_id and question_id=v_question.id for update;
  if not found then raise exception '原题缺少对应的来源清单'; end if;

  if v_question.grade_band in ('高一','高二','高三') then
    if v_question.render_mode <> 'image_primary'
      or not exists (
        select 1 from app_private.chem_question_assets asset
        where asset.question_id=v_question.id and asset.asset_kind='question_image'
          and asset.sha256=v_item.question_asset_sha256
          and exists (
            select 1 from jsonb_array_elements(v_question.asset_refs) ref
            where ref->>'kind'='question_image' and ref->>'path'=asset.asset_path
              and ref->>'sha256'=asset.sha256
          )
      )
      or not exists (
        select 1 from app_private.chem_question_assets asset
        where asset.question_id=v_question.id and asset.asset_kind='analysis_image'
          and asset.sha256=v_item.analysis_asset_sha256
          and exists (
            select 1 from jsonb_array_elements(v_question.asset_refs) ref
            where ref->>'kind'='analysis_image' and ref->>'path'=asset.asset_path
              and ref->>'sha256'=asset.sha256
          )
      )
    then raise exception '原题图或答案图未与来源清单及页面引用一致'; end if;
  elsif v_question.grade_band='初三' then
    select provenance.source_sha256 into v_source_document_sha256
    from app_private.chem_junior_source_release_provenance provenance
    where provenance.release_id=v_question.source_release_id
      and provenance.knowledge_id=v_question.knowledge_id
      and provenance.verification_status='verified';
    if v_source_document_sha256 is null then
      raise exception '初三原始材料的定位或源文件摘要尚未核验';
    end if;
  else raise exception '未支持的年级'; end if;

  insert into app_private.chem_question_item_visual_reviews(
    question_id,source_release_id,review_state,revision_token,
    source_item_sha256,question_image_sha256,analysis_image_sha256,
    source_document_sha256,source_locator,review_checks,review_note,
    review_actor,reviewed_at,updated_at
  ) values (
    v_question.id,v_question.source_release_id,'verified',p_revision_token,
    v_item.item_sha256,
    case when v_question.grade_band<>'初三' then v_item.question_asset_sha256 end,
    case when v_question.grade_band<>'初三' then v_item.analysis_asset_sha256 end,
    v_source_document_sha256,p_source_locator,p_checks,btrim(p_review_note),
    btrim(p_review_actor),now(),now()
  ) on conflict(question_id) do update set
    source_release_id=excluded.source_release_id,
    review_state=excluded.review_state,
    revision_token=excluded.revision_token,
    source_item_sha256=excluded.source_item_sha256,
    question_image_sha256=excluded.question_image_sha256,
    analysis_image_sha256=excluded.analysis_image_sha256,
    source_document_sha256=excluded.source_document_sha256,
    source_locator=excluded.source_locator,
    review_checks=excluded.review_checks,
    review_note=excluded.review_note,
    review_actor=excluded.review_actor,
    reviewed_at=excluded.reviewed_at,
    updated_at=excluded.updated_at;
  return jsonb_build_object('questionId',v_question.id,'reviewState','verified',
    'sourceItemSha256',v_item.item_sha256,'revisionToken',p_revision_token);
end;
$$;
revoke all on function public.chem_record_question_item_visual_review(text,text,text,text,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.chem_record_question_item_visual_review(text,text,text,text,text,jsonb)
  to service_role;

-- Reviewers can quarantine an existing active item without suppressing the
-- other questions in its release. This also queues possible OCR damage for
-- a source-image comparison rather than silently rewriting chemistry.
create function public.chem_queue_question_item_visual_recheck(
  p_question_id text,p_reason text,p_review_actor text
) returns void language plpgsql security definer set search_path='' as $$
declare v_question public.chem_questions%rowtype;
begin
  if length(btrim(coalesce(p_reason,''))) < 12 or length(btrim(coalesce(p_review_actor,''))) < 3 then
    raise exception '请说明疑似缺失或错字以及复核人';
  end if;
  select * into v_question from public.chem_questions
  where id=p_question_id and source_release_id is not null for update;
  if not found then raise exception '原题不存在'; end if;
  insert into app_private.chem_question_item_visual_reviews(
    question_id,source_release_id,review_state,revision_token,review_note,review_actor,updated_at
  ) values (
    v_question.id,v_question.source_release_id,'pending',v_question.question_revision_token,
    btrim(p_reason),btrim(p_review_actor),now()
  ) on conflict(question_id) do update set
    review_state='pending',revision_token=excluded.revision_token,
    source_item_sha256=null,question_image_sha256=null,analysis_image_sha256=null,
    source_document_sha256=null,source_locator=null,review_checks='{}'::jsonb,
    review_note=excluded.review_note,review_actor=excluded.review_actor,
    reviewed_at=null,updated_at=now();
end;
$$;
revoke all on function public.chem_queue_question_item_visual_recheck(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.chem_queue_question_item_visual_recheck(text,text,text)
  to service_role;

-- Central hold RPC is consulted by adaptive, review, and self-study issue
-- paths. A pending or stale visual review blocks only that exact question ID.
-- Explicit legacy holds still follow a byte-identical stem/options fingerprint,
-- but no longer follow source_item_key: a repaired revision intentionally keeps
-- its source identity and must not inherit the old damaged transcript's hold.
create or replace function public.chem_question_delivery_holds()
returns table(question_id text,reason text)
language sql stable security definer set search_path=''
as $$
  select distinct q.id,h.reason
  from app_private.chem_question_delivery_holds h
  join public.chem_questions anchor on anchor.id=h.anchor_question_id
  join public.chem_questions q on q.id=anchor.id
    or q.content_fingerprint=anchor.content_fingerprint
  where h.resolved_at is null
  union
  select review.question_id,'逐题原题图像、公式和解析待复核'::text
  from app_private.chem_question_item_visual_reviews review
  join public.chem_questions reviewed_question on reviewed_question.id=review.question_id
  join app_private.chem_question_source_releases reviewed_release
    on reviewed_release.id=reviewed_question.source_release_id
  where reviewed_question.usable_for_review and reviewed_release.status='active'
    and (review.review_state <> 'verified'
      or not app_private.chem_question_item_visual_reviewed(review.question_id));
$$;
revoke all on function public.chem_question_delivery_holds() from public,anon,authenticated;
grant execute on function public.chem_question_delivery_holds() to service_role;

-- The teacher catalog gets the same per-item gate. Legacy active questions
-- with no review row remain visible until a targeted audit queues them.
create or replace view app_private.chem_teaching_ready_questions as
 select q.* from public.chem_questions q
 join app_private.chem_question_source_releases r on r.id=q.source_release_id
 where q.review_status='approved' and q.scope_status='IN' and q.usable_for_review
 and r.status='active' and r.verification_status='full_visual_verified' and r.manifest_sha256=r.verification_manifest_sha256
 and jsonb_typeof(q.options)='array' and jsonb_array_length(q.options)=4 and q.correct_option between 0 and 3
 and length(btrim(q.stem))>0 and length(btrim(q.explanation))>0 and q.content_fingerprint is not null and q.source_item_key is not null
 and not exists(select 1 from public.chem_question_delivery_holds() h where h.question_id=q.id)
 and (not exists(select 1 from app_private.chem_question_item_visual_reviews review where review.question_id=q.id)
   or app_private.chem_question_item_visual_reviewed(q.id))
 and ((q.grade_band in ('高一','高二','高三') and q.source_kind='licensed_local' and q.render_mode='image_primary'
 and (r.release_kind='teaching_material' or exists(select 1 from public.chem_active_verified_source_releases() a where a.source_release_id=q.source_release_id and a.grade_band=q.grade_band)))
 or (q.grade_band='初三' and q.source_kind='user_provided_local' and q.render_mode='native' and q.textbook_version='科粤版'
 and exists(select 1 from public.chem_junior_verified_provenance_rows('科粤版',array[q.knowledge_id]) a where a.source_release_id=q.source_release_id and a.source_release_ready and a.verification_status='verified')));

-- All releases activated after this migration (including a staged release
-- created earlier) must have a verified row for every individual question.
-- The existing active pool is not retroactively made unavailable.
create function app_private.chem_require_item_visual_reviews_before_activation()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_count integer; v_verified integer;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op='UPDATE' then
    if old.status='active' then return new; end if;
  end if;
  select count(*) into v_count from public.chem_questions q where q.source_release_id=new.id;
  select count(*) into v_verified from public.chem_questions q
  where q.source_release_id=new.id
    and app_private.chem_question_item_visual_reviewed(q.id);
  if v_count <> new.expected_question_count or v_verified <> v_count then
    raise exception '逐题原图、公式、选项和答案解析未核验：发布版 % 已核验 % / %',new.id,v_verified,v_count;
  end if;
  return new;
end;
$$;
revoke all on function app_private.chem_require_item_visual_reviews_before_activation()
  from public,anon,authenticated,service_role;
create trigger chem_require_item_visual_reviews_before_activation
before insert or update of status on app_private.chem_question_source_releases
for each row execute function app_private.chem_require_item_visual_reviews_before_activation();

commit;
