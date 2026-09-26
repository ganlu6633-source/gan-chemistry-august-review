create or replace function public.chem_set_knowledge_rating(
  p_attempt_id uuid,
  p_student_id uuid,
  p_plan_day_id uuid,
  p_point_id text,
  p_rating text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_point_id !~ '^[A-Za-z0-9_-]{1,90}:(s[0-9]{1,3}:i[0-9]{1,3}:p[0-9]{1,2}|core)$'
    or p_rating not in ('unknown', 'familiar', 'fluent') then
    return false;
  end if;

  update public.chem_learning_attempts attempt
  set knowledge_ratings = (
    select coalesce(jsonb_agg(entry), '[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('pointId', p_point_id, 'rating', p_rating))
    from jsonb_array_elements(attempt.knowledge_ratings) entry
    where entry->>'pointId' is distinct from p_point_id
  )
  where attempt.id = p_attempt_id and attempt.student_id = p_student_id
    and attempt.plan_day_id = p_plan_day_id;

  return found;
end;
$$;

revoke all on function public.chem_set_knowledge_rating(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.chem_set_knowledge_rating(uuid,uuid,uuid,text,text) to service_role;
