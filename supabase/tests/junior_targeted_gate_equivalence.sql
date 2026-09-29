begin;
do $test$
declare expected jsonb; actual jsonb; allids text[];
begin
 select array_agg(id) into allids from public.chem_questions;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.question_id,x.reason),'[]') into expected from public.chem_question_delivery_holds() x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.question_id,x.reason),'[]') into actual from public.chem_question_delivery_holds_for(allids) x;
 if actual is distinct from expected then raise exception 'scoped full-ID holds differ from legacy gate';end if;
 if exists(select 1 from public.chem_question_delivery_holds_for(array[]::text[]))
   or exists(select 1 from public.chem_question_delivery_holds_for(null))
 then raise exception 'empty scoped holds expose unrelated data';end if;
 if exists(select 1 from public.chem_question_delivery_holds_for(array[allids[1]]) x where x.question_id<>allids[1])
 then raise exception 'scoped hold did not restrict target';end if;
 select coalesce(jsonb_agg(id order by id),'[]') into expected from app_private.chem_teaching_ready_questions where grade_band='初三';
 select coalesce(jsonb_agg(q.id order by q.id),'[]') into actual from public.chem_questions q
   where q.grade_band='初三' and app_private.chem_junior_question_delivery_ready(q.id);
 if actual is distinct from expected then raise exception 'targeted junior source gate differs from existing teaching-ready view';end if;
 if has_function_privilege('anon','public.chem_junior_submit_answer(uuid,uuid,uuid,smallint,boolean,integer,text)','EXECUTE')
   or has_function_privilege('authenticated','public.chem_junior_practice_context(uuid,uuid,uuid)','EXECUTE')
   or has_function_privilege('anon','public.chem_question_delivery_holds_for(text[])','EXECUTE')
 then raise exception 'internal answer/source RPC is exposed to browser roles';end if;
end;
$test$;
rollback;
select 'source/hold equivalence and service-only access passed' as result;
