begin;
do $qa$ declare g text; ids text[]; delta int; begin
 foreach g in array array['初三','高一','高二','高三'] loop
  for ids in select array_agg(id order by id) from (select id,(row_number() over(order by id)-1)/900 batch from public.chem_questions where grade_band=g) q group by batch loop
   select count(*) into delta from (
    (select id,source_release_id from app_private.chem_teaching_ready_questions where grade_band=g and id=any(ids) except select * from public.chem_teaching_ready_question_ids(g,ids))
    union all
    (select * from public.chem_teaching_ready_question_ids(g,ids) except select id,source_release_id from app_private.chem_teaching_ready_questions where grade_band=g and id=any(ids))
   ) d;
   if delta<>0 then raise exception 'readiness mismatch %, %',g,delta;end if;
  end loop;
 end loop; end $qa$;
rollback;
