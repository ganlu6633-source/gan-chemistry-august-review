-- Cover every REVIEW video foreign-key lookup reported by the database linter.
-- These server-only tables are small today, but the indexes prevent full scans
-- when recommendations or students are updated and as engagement history grows.
begin;

create index if not exists chem_video_engagement_events_recommendation_student_idx
  on app_private.chem_video_engagement_events (recommendation_id, student_id);

create index if not exists chem_video_engagements_recommendation_student_idx
  on app_private.chem_video_engagements (recommendation_id, student_id);

create index if not exists chem_video_recommendations_skill_idx
  on app_private.chem_video_recommendations (skill_id);

create index if not exists chem_video_recommendations_source_alert_idx
  on app_private.chem_video_recommendations (source_alert_id)
  where source_alert_id is not null;

create index if not exists chem_video_recommendations_source_attempt_idx
  on app_private.chem_video_recommendations (source_attempt_id)
  where source_attempt_id is not null;

commit;
