-- A nullable, plan-scoped original-question whitelist. NULL preserves legacy pools.
-- No plan data, student records, auth, RLS, grants or public RPC are changed here.
-- Populating a whitelist is a separately guarded publication action for future,
-- unstarted plans; it requires real original revision/evidence and exact closure.
do $guard$ begin
 if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_choice_projection(uuid,uuid,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')<>'3ca6dc778e43f94f98fb066640a7e0c068319b1ca77e4ac4816520f04851814b' then
   raise exception 'Choice projection full body changed since exact scoped-pool baseline';end if;
 if exists(select 1 from information_schema.columns where table_schema='app_private' and table_name='chem_choice_training_policy' and column_name='authorized_training_pool_ids') then
   raise exception 'Training whitelist column already exists; inspect rather than replace';end if;
end $guard$;
alter table app_private.chem_choice_training_policy add column authorized_training_pool_ids text[];
alter table app_private.chem_choice_training_policy add constraint chem_choice_training_pool_shape check (
 authorized_training_pool_ids is null or (
   array_ndims(authorized_training_pool_ids)=1 and cardinality(authorized_training_pool_ids) between 8 and 1000
   and array_position(authorized_training_pool_ids,null) is null and array_position(authorized_training_pool_ids,'') is null
 ));
comment on column app_private.chem_choice_training_policy.authorized_training_pool_ids is
 'NULL retains the legacy stage/release/grade/skill pool. Non-NULL narrows this plan to reviewed first and same-point branch originals; never expands source authorization.';
do $patch$
declare
 previous_definition text:=pg_get_functiondef('app_private.chem_choice_projection(uuid,uuid,jsonb)'::regprocedure);
 old_filter text:=$old$     and (p.max_question_level is null or pool_q.level<=p.max_question_level);$old$;
 new_filter text:=$new$     and (c.authorized_training_pool_ids is null or pool_q.id=any(c.authorized_training_pool_ids))
     and (p.max_question_level is null or pool_q.level<=p.max_question_level);$new$;
 patched_definition text;
begin
 if (length(previous_definition)-length(replace(previous_definition,old_filter,'')))/length(old_filter)<>1 then
   raise exception 'Expected one precise pool discovery filter; do not patch unrelated code';end if;
 patched_definition:=replace(previous_definition,old_filter,new_filter);
 if encode(extensions.digest(convert_to(patched_definition,'UTF8'),'sha256'),'hex')<>'6989e213614cb48dab260b4e7bbaa37064b18f6c4adb890d14fef96438c74000' then
   raise exception 'Scoped-pool patch changes more than the approved single filter';end if;
 execute patched_definition;
 if encode(extensions.digest(convert_to(pg_get_functiondef('app_private.chem_choice_projection(uuid,uuid,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')<>'6989e213614cb48dab260b4e7bbaa37064b18f6c4adb890d14fef96438c74000' then
   raise exception 'Scoped-pool exact projection postcondition failed';end if;
end $patch$;
