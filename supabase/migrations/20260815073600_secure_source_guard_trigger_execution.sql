-- Source-backed rows are staged through the server-only Edge import bridge.
-- The guard triggers must still be able to inspect app_private release state
-- when the insert originates from PostgREST's service_role connection.  Keep
-- their empty search_path and run only the guard lookup with the function
-- owner's privileges; browser roles cannot execute these functions directly.

alter function app_private.chem_guard_source_asset_mutation() security definer;
alter function app_private.chem_guard_source_question_content_mutation() security definer;
alter function app_private.chem_guard_release_item_mutation() security definer;
alter function app_private.chem_guard_active_source_question_eligibility() security definer;

revoke all on function app_private.chem_guard_source_asset_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_source_question_content_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_release_item_mutation()
  from public, anon, authenticated, service_role;
revoke all on function app_private.chem_guard_active_source_question_eligibility()
  from public, anon, authenticated, service_role;
