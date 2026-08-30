-- app_private is deliberately not exposed through PostgREST.  The Edge
-- Function therefore obtains only the minimum release/provenance state it
-- needs through server-only, fixed-shape RPCs; canonical locators, hashes,
-- files, answers, and source labels never cross this boundary.
create or replace function public.chem_source_release_states(
  p_release_ids uuid[]
)
returns table (
  id uuid,
  status text,
  verification_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select release.id, release.status, release.verification_status
  from app_private.chem_question_source_releases as release
  where release.id = any(p_release_ids);
$$;

create or replace function public.chem_junior_knowledge_provenance_states(
  p_knowledge_ids text[]
)
returns table (
  knowledge_id text,
  verification_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select provenance.knowledge_id, provenance.verification_status
  from app_private.chem_junior_knowledge_provenance as provenance
  where provenance.knowledge_id = any(p_knowledge_ids);
$$;

revoke all on function public.chem_source_release_states(uuid[]) from public, anon, authenticated;
revoke all on function public.chem_junior_knowledge_provenance_states(text[]) from public, anon, authenticated;
grant execute on function public.chem_source_release_states(uuid[]) to service_role;
grant execute on function public.chem_junior_knowledge_provenance_states(text[]) to service_role;
