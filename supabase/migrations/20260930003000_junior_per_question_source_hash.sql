-- The junior review previously copied one document hash per knowledge_id.
-- A knowledge_id may contain questions from several books, so this could
-- certify a question against the wrong source. Bind the exact document to
-- the exact question revision and immutable source item instead.
begin;

create table app_private.chem_junior_question_source_documents (
  question_id text primary key references public.chem_questions(id) on delete restrict,
  source_release_id uuid not null references app_private.chem_question_source_releases(id) on delete restrict,
  revision_token text not null check (revision_token ~ '^[0-9a-f]{64}$'),
  source_item_sha256 text not null check (source_item_sha256 ~ '^[0-9a-f]{64}$'),
  source_document_sha256 text not null check (source_document_sha256 ~ '^[0-9a-f]{64}$'),
  source_locator text not null check (length(btrim(source_locator)) >= 3),
  source_reference text not null check (length(btrim(source_reference)) >= 3),
  verification_note text not null check (length(btrim(verification_note)) >= 12),
  verification_actor text not null check (length(btrim(verification_actor)) >= 3),
  verified_at timestamptz not null default now()
);
create index chem_junior_question_source_documents_release_idx
  on app_private.chem_junior_question_source_documents(source_release_id);
alter table app_private.chem_junior_question_source_documents enable row level security;
revoke all on table app_private.chem_junior_question_source_documents from public,anon,authenticated,service_role;

-- All 25 distinct files were hashed again from their physical originals
-- (including the three members of the 5·3 archive) before this backfill.
-- LOCAL-* identities carry the full source-document hash. The six LP
-- questions come from one verified .ppt, while the SRC/ARCM IDs below map
-- to the specific local file recorded in the private materials registry.
with current_junior as (
  select q.id,q.source_release_id,q.question_revision_token,
    q.source_info->>'locator' as locator,q.source_info->>'title' as title,
    item.item_sha256,item.canonical_source_id,
    case
      when item.canonical_source_id ~ '^LOCAL-(DOCX|PDF)-[0-9a-f]{64}'
        then substring(item.canonical_source_id from '^LOCAL-(?:DOCX|PDF)-([0-9a-f]{64})')
      when item.canonical_source_id ~ '^LOCAL-(DOCX|PDF)-[0-9a-f]{16}:'
        then substring(q.source_info->>'locator' from '([0-9a-f]{64})')
      when item.canonical_source_id like 'SRC-F021F315B1883169:%'
        then '2b7cd0573d9f5c472e71d655c8a9241f475df51734ab49cf7ba6b00adddc68d7'
      when item.canonical_source_id like 'SRC-45BB8FB5DF1DB67B:%'
        then 'df8f9d5a30797172ebf38f8a145b7ab8bf4825bbd54e7ea1dd00c15642a5ac2e'
      when item.canonical_source_id like 'SRC-383CD86AB9D081C8:%'
        then '661d74b1ff5e7d0b76dbdf9b56fd2e5187fc0e6719aa1f06db06a484b732f76b'
      when item.canonical_source_id like 'ARCM-9065CD3D54F4FCCC:%'
        then '4e4f9fd514beec3f0f09f543198dcce2c77fa62df87ae95fe392b3441c746a28'
      when item.canonical_source_id like 'ARCM-669768177CABE934:%'
        then '7f072cc04caa34dff7fa836615b9b61263aef57850e2263318310b4149657004'
      when item.canonical_source_id like 'ARCM-AD6844DF09E0CB19:%'
        then 'ca9e2f9dd915701ebf1ab935e40391e3709fd944ef33f83b2bfe20c5e8170d8c'
    end as document_sha256
  from app_private.chem_teaching_ready_questions q
  join app_private.chem_question_source_release_items item
    on item.release_id=q.source_release_id and item.question_id=q.id
  where q.grade_band='初三'
)
insert into app_private.chem_junior_question_source_documents(
  question_id,source_release_id,revision_token,source_item_sha256,
  source_document_sha256,source_locator,source_reference,
  verification_note,verification_actor
)
select id,source_release_id,question_revision_token,item_sha256,
  document_sha256,locator,
  coalesce(title,'原始材料') || ' | ' || canonical_source_id,
  '2026-09-30 按逐题来源核对本地原件；25 份来源文件均重新计算 SHA-256，含压缩包内原始文件',
  'codex-junior-source-audit'
from current_junior;

-- Correct only the 66 incorrectly attributed hashes. Original content
-- attestations remain in place; this update records a metadata correction.
update app_private.chem_question_item_visual_reviews review
set source_document_sha256=binding.source_document_sha256,
    review_note=review.review_note ||
      '；2026-09-30 来源记录校正：按该题的本地原文件重新核对文件摘要。',
    updated_at=now()
from app_private.chem_junior_question_source_documents binding
where binding.question_id=review.question_id
  and review.review_state='verified'
  and review.source_document_sha256 is distinct from binding.source_document_sha256;

create or replace function app_private.chem_question_item_visual_reviewed(p_question_id text)
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
        or (q.grade_band='初三' and exists (
          select 1
          from app_private.chem_junior_question_source_documents source_doc
          where source_doc.question_id=q.id
            and source_doc.source_release_id=q.source_release_id
            and source_doc.revision_token=q.question_revision_token
            and source_doc.source_item_sha256=item.item_sha256
            and source_doc.source_locator=q.source_info->>'locator'
            and source_doc.source_document_sha256=review.source_document_sha256
        ))
      )
  );
$$;
revoke all on function app_private.chem_question_item_visual_reviewed(text)
  from public,anon,authenticated,service_role;

create or replace function public.chem_record_question_item_visual_review(
  p_question_id text,p_revision_token text,p_source_locator text,
  p_review_actor text,p_review_note text,p_checks jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_question public.chem_questions%rowtype;
  v_item app_private.chem_question_source_release_items%rowtype;
  v_document app_private.chem_junior_question_source_documents%rowtype;
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
    select * into v_document
    from app_private.chem_junior_question_source_documents source_doc
    where source_doc.question_id=v_question.id
      and source_doc.source_release_id=v_question.source_release_id
      and source_doc.revision_token=v_question.question_revision_token
      and source_doc.source_item_sha256=v_item.item_sha256
      and source_doc.source_locator=v_question.source_info->>'locator'
    for update;
    if not found then
      raise exception '这道初三题还没有单独核对原始材料，请先登记该题的原文件';
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
    case when v_question.grade_band='初三' then v_document.source_document_sha256 end,
    p_source_locator,p_checks,btrim(p_review_note),btrim(p_review_actor),now(),now()
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

-- Future junior imports must register an actual document for each item
-- before visual review. Known material identities cannot be bound to a
-- different hash. Changing an existing binding queues a fresh review.
create function public.chem_bind_junior_question_source_document(
  p_question_id text,p_revision_token text,p_source_document_sha256 text,
  p_source_reference text,p_review_actor text,p_review_note text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_question public.chem_questions%rowtype;
  v_item app_private.chem_question_source_release_items%rowtype;
  v_identity_hash text;
  v_registry_hash text;
  v_registry_count integer;
  v_old_hash text;
begin
  if coalesce(p_revision_token,'') !~ '^[0-9a-f]{64}$'
    or coalesce(p_source_document_sha256,'') !~ '^[0-9a-f]{64}$'
    or length(btrim(coalesce(p_source_reference,''))) < 3
    or length(btrim(coalesce(p_review_actor,''))) < 3
    or length(btrim(coalesce(p_review_note,''))) < 12
  then raise exception '请逐题填写原文件摘要、文件定位和核对记录'; end if;

  select * into v_question from public.chem_questions
  where id=p_question_id and grade_band='初三' and source_release_id is not null for update;
  if not found or v_question.question_revision_token is distinct from p_revision_token
    or length(btrim(coalesce(v_question.source_info->>'locator',''))) < 3
  then raise exception '初三原题不存在或已修订，请重新定位原文件'; end if;
  select * into v_item from app_private.chem_question_source_release_items
  where release_id=v_question.source_release_id and question_id=v_question.id;
  if not found then raise exception '这道题缺少原题清单'; end if;

  v_identity_hash := coalesce(
    substring(v_item.canonical_source_id from '^LOCAL-(?:DOCX|PDF)-([0-9a-f]{64})'),
    case when v_item.canonical_source_id ~ '^LOCAL-(DOCX|PDF)-[0-9a-f]{16}:'
      then substring(v_question.source_info->>'locator' from '([0-9a-f]{64})')
    end
  );
  if v_identity_hash is not null and v_identity_hash <> p_source_document_sha256 then
    raise exception '原文件摘要与该题已登记的原件身份不一致';
  end if;

  select count(distinct lower(material.metadata->>'sha256')),
         min(lower(material.metadata->>'sha256'))
    into v_registry_count,v_registry_hash
  from app_private.chem_teaching_materials material
  where material.metadata->'mainSourceIds' ? split_part(v_item.canonical_source_id,':',1)
    and coalesce(material.metadata->>'sha256','') ~ '^[0-9a-fA-F]{64}$';
  if v_registry_count > 1 then
    raise exception '同一原件编号在资料库中指向多个文件，须先排查';
  end if;
  if v_registry_count=1 and v_registry_hash <> p_source_document_sha256 then
    raise exception '原文件摘要与资料库中的原件不一致';
  end if;

  select source_document_sha256 into v_old_hash
  from app_private.chem_junior_question_source_documents
  where question_id=p_question_id for update;
  insert into app_private.chem_junior_question_source_documents(
    question_id,source_release_id,revision_token,source_item_sha256,
    source_document_sha256,source_locator,source_reference,
    verification_note,verification_actor,verified_at
  ) values (
    v_question.id,v_question.source_release_id,v_question.question_revision_token,
    v_item.item_sha256,p_source_document_sha256,v_question.source_info->>'locator',
    btrim(p_source_reference),btrim(p_review_note),btrim(p_review_actor),now()
  ) on conflict(question_id) do update set
    source_release_id=excluded.source_release_id,
    revision_token=excluded.revision_token,
    source_item_sha256=excluded.source_item_sha256,
    source_document_sha256=excluded.source_document_sha256,
    source_locator=excluded.source_locator,
    source_reference=excluded.source_reference,
    verification_note=excluded.verification_note,
    verification_actor=excluded.verification_actor,
    verified_at=excluded.verified_at;
  if v_old_hash is distinct from p_source_document_sha256 and exists (
    select 1 from app_private.chem_question_item_visual_reviews review
    where review.question_id=p_question_id and review.review_state='verified'
  ) then
    perform public.chem_queue_question_item_visual_recheck(
      p_question_id,'该题原文件绑定发生变化，必须重新核对题干、选项和解析',p_review_actor
    );
  end if;
  return jsonb_build_object('questionId',p_question_id,
    'sourceDocumentSha256',p_source_document_sha256,'needsVisualReview',true);
end;
$$;
revoke all on function public.chem_bind_junior_question_source_document(
  text,text,text,text,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.chem_bind_junior_question_source_document(
  text,text,text,text,text,text
) to service_role;

do $$
declare v_ready integer; v_bound integer; v_bad integer;
begin
  select count(*) into v_ready from app_private.chem_teaching_ready_questions
  where grade_band='初三';
  select count(*) into v_bound from app_private.chem_junior_question_source_documents;
  select count(*) into v_bad
  from app_private.chem_junior_question_source_documents source_doc
  join app_private.chem_question_item_visual_reviews review
    on review.question_id=source_doc.question_id
  where review.source_document_sha256 is distinct from source_doc.source_document_sha256;
  if v_ready<>289 or v_bound<>289 or v_bad<>0 then
    raise exception '逐题原件绑定回填未通过：ready=%, bound=%, bad=%',
      v_ready,v_bound,v_bad;
  end if;
end;
$$;
commit;
