-- Holds propagate to exact duplicate fingerprints, including retired and
-- pending questions. The previous partial unique index covers only approved
-- questions and forced a full scan for each hold when listing a student pool.
create index if not exists chem_questions_all_fingerprint_idx
  on public.chem_questions(content_fingerprint)
  where content_fingerprint is not null;
