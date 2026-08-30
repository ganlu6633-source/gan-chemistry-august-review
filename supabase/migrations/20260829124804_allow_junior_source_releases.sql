-- The source-release registry predates the junior-high path.  A junior
-- release is a deliberately smaller, independently verified content batch
-- (for example, the 21-source pool behind one three-point learning day).
-- Keep all existing high-school constraints intact while admitting 初三.
alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_grade_band_check;

alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_grade_band_check
  check (grade_band in ('初三', '高一', '高二', '高三'));

alter table app_private.chem_question_source_releases
  drop constraint if exists chem_question_source_releases_expected_question_count_check;

alter table app_private.chem_question_source_releases
  add constraint chem_question_source_releases_expected_question_count_check
  check (
    (grade_band = '初三' and expected_question_count between 1 and 2000)
    or (grade_band = '高一' and (expected_question_count in (125, 175) or expected_question_count between 211 and 275))
    or (grade_band = '高二' and expected_question_count between 200 and 2000)
    or (grade_band = '高三' and expected_question_count between 275 and 2000)
  );
