begin;

do $exact_policy_checks$ begin
if exists(
(select question_id,reason from public.chem_question_delivery_holds()
 except select question_id,reason from public.chem_question_delivery_holds_for(array(select id from public.chem_questions)))
union all
(select question_id,reason from public.chem_question_delivery_holds_for(array(select id from public.chem_questions))
 except select question_id,reason from public.chem_question_delivery_holds())
)then raise exception 'targeted and full hold policy disagree';end if;
if exists(select 1 from public.chem_question_delivery_holds_for(array[]::text[])) or exists(select 1 from public.chem_question_delivery_holds_for(null::text[]))then raise exception 'empty requested IDs returned holds';end if;
if exists(select 1 from public.chem_question_delivery_holds_for(array['QH1FULL04_LAYOUT_273','QH1FULL04_LAYOUT_446'])where question_id<>all(array['QH1FULL04_LAYOUT_273','QH1FULL04_LAYOUT_446']))then raise exception 'nonrequested IDs escaped filter';end if;
if not exists(select 1 from public.chem_question_delivery_holds_for(array['QH1R_20260908_0200987363CD28F718F7A26D459D4ECA'])where question_id='QH1R_20260908_0200987363CD28F718F7A26D459D4ECA')then raise exception 'held original incorrectly released';end if;
if not exists(select 1 from public.chem_question_delivery_holds_for(array['QH1O_008AC0309A70_C9B4CBB852F5D709_28FA719B4605D371'])where question_id='QH1O_008AC0309A70_C9B4CBB852F5D709_28FA719B4605D371')then raise exception 'held original incorrectly released';end if;
if app_private.chem_replacement_has_exact_source_ancestor('9797100a-92f5-5ed8-a466-7fc6ec84708b','QH1FULL04_LAYOUT_273','QH1R_20260908_0200987363CD28F718F7A26D459D4ECA')then raise exception 'different canonical original accepted as ancestor';end if;
if has_function_privilege('anon','public.chem_question_delivery_holds_for(text[])','EXECUTE')or has_function_privilege('authenticated','public.chem_question_delivery_holds_for(text[])','EXECUTE')then raise exception 'private hold lookup privileges leaked';end if;
if not has_function_privilege('service_role','public.chem_question_delivery_holds_for(text[])','EXECUTE')then raise exception 'backend cannot use targeted hold lookup';end if;
end;$exact_policy_checks$;
select 'PASS: exact-source targeted/full hold parity and legacy holds preserved' result;
rollback;
