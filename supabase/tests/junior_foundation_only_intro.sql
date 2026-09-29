begin;
do $test$
declare k text; q public.chem_questions%rowtype; old_policy text;
begin
 foreach k in array array['J_KY_1_1_K01','J_KY_1_1_K02','J_KY_1_1_K03'] loop
   if not app_private.chem_junior_route_inventory_valid('科粤版',k,7,7,0,1::smallint)
     or app_private.chem_junior_route_inventory_valid('科粤版',k,6,6,0,1::smallint)
     or app_private.chem_junior_route_inventory_valid('科粤版',k,7,6,2,1::smallint)
     or app_private.chem_junior_route_inventory_valid('科粤版',k,7,7,0,2::smallint)
   then raise exception 'foundation inventory boundary failed: %',k; end if;
   if app_private.chem_junior_demonstrated_level('科粤版',k,'spaced_review',1::smallint,3,0,null::smallint)<>1
     or app_private.chem_junior_demonstrated_level('科粤版',k,'spaced_review',1::smallint,2,0,null::smallint)<>0
     or app_private.chem_junior_demonstrated_level('科粤版',k,'fresh_only',1::smallint,3,0,null::smallint)<>0
     or app_private.chem_junior_demonstrated_level('科粤版',k,'fresh_only',1::smallint,2,1,2::smallint)<>2
   then raise exception 'intro mastery or immutable old policy changed: %',k; end if;
 end loop;
 foreach k in array array['J_KY_LAB_BASICS','J_KY_PARTICLES','J_KY_OXY_H2O2','J_KY_1_1_K04'] loop
   if app_private.chem_junior_route_inventory_valid('科粤版',k,7,7,0,1::smallint)
     or app_private.chem_junior_route_inventory_valid('科粤版',k,7,5,1,1::smallint)
     or not app_private.chem_junior_route_inventory_valid('科粤版',k,7,5,2,1::smallint)
     or app_private.chem_junior_demonstrated_level('科粤版',k,'spaced_review',1::smallint,3,0,null::smallint)<>0
     or app_private.chem_junior_demonstrated_level('科粤版',k,'spaced_review',1::smallint,2,1,2::smallint)<>2
   then raise exception 'non-intro higher-tier requirement relaxed: %',k; end if;
 end loop;
 if app_private.chem_junior_route_inventory_valid('other','J_KY_1_1_K01',7,7,0,1::smallint)
   or app_private.chem_junior_route_inventory_valid(null,null,null,null,null,null)
 then raise exception 'unrecognized or null inventory accepted'; end if;
 q.id:='QA-FOUNDATION-ONLY';q.textbook_version:='科粤版';q.knowledge_id:='J_KY_1_1_K01';q.level:=2;
 if app_private.chem_junior_repetition_state(q,'[]',null,'spaced_review',current_date)->>'kind'<>'foundation_only'
   or app_private.chem_junior_repetition_state(q,'[]',null,'fresh_only',current_date)->>'eligible'<>'true'
 then raise exception 'availability must enforce L1 only without reinterpreting old sessions'; end if;
 q.level:=1;
 if app_private.chem_junior_repetition_state(q,'[]',null,'spaced_review',current_date)->>'eligible'<>'true'
 then raise exception 'new introductory foundation question unexpectedly rejected'; end if;
 q.level:=2;q.knowledge_id:='J_KY_LAB_BASICS';
 if app_private.chem_junior_repetition_state(q,'[]',null,'spaced_review',current_date)->>'eligible'<>'true'
 then raise exception 'other routes higher-tier questions unexpectedly rejected'; end if;
 if has_function_privilege('anon','app_private.chem_junior_route_inventory_valid(text,text,bigint,bigint,bigint,smallint)','EXECUTE')
   or has_function_privilege('authenticated','app_private.chem_junior_demonstrated_level(text,text,text,smallint,bigint,bigint,smallint)','EXECUTE')
 then raise exception 'internal curriculum helper exposed to client roles'; end if;
end;$test$;
rollback;
select 'foundation-only exact whitelist, 7/6 parent boundary, L1-only availability, old-policy and other-route mastery unchanged' result;
