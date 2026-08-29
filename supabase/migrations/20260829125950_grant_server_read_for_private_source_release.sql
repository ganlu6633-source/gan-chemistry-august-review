-- Edge Functions use the service_role key after custom application-session
-- authentication.  Give that server-only role the minimum read access needed
-- to verify active source releases and junior knowledge provenance.  No
-- browser-accessible role receives either schema or table permission.
grant usage on schema app_private to service_role;
grant select on table app_private.chem_question_source_releases to service_role;
grant select on table app_private.chem_junior_knowledge_provenance to service_role;

revoke all on table app_private.chem_question_source_releases
  from anon, authenticated;
revoke all on table app_private.chem_junior_knowledge_provenance
  from anon, authenticated;
