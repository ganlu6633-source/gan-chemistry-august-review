-- The provenance table contains canonical source locators and hashes.  It is
-- never a browser data source: only the Edge Function's service role needs it.
-- RLS is therefore a defense-in-depth boundary with no public policies.
alter table app_private.chem_junior_knowledge_provenance
  enable row level security;

revoke all on table app_private.chem_junior_knowledge_provenance
  from anon, authenticated;
