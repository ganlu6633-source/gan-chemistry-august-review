alter table public.chem_learning_attempts
  add column if not exists knowledge_ratings jsonb not null default '[]'::jsonb;

alter table public.chem_learning_attempts
  drop constraint if exists chem_learning_attempts_knowledge_ratings_array;

alter table public.chem_learning_attempts
  add constraint chem_learning_attempts_knowledge_ratings_array
  check (jsonb_typeof(knowledge_ratings) = 'array');
