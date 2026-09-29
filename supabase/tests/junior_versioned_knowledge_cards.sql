begin;
do $test$
declare
 old_card public.chem_knowledge_cards%rowtype;
 new_card public.chem_knowledge_cards%rowtype;
 binding app_private.chem_junior_knowledge_card_bindings%rowtype;
 target app_private.chem_question_source_releases%rowtype;
 active_r app_private.chem_question_source_releases%rowtype;
 rights app_private.chem_junior_source_release_rights%rowtype;
 expected_old text; new_hash text; request jsonb; result_hash text;
 active_before jsonb; bindings_before jsonb; rights_before jsonb;
 n integer; rejected boolean; message text;
begin
 select * into target from app_private.chem_question_source_releases r
 where grade_band='初三' and status='staged' and activated_at is null and retired_at is null
   and exists(select 1 from app_private.chem_junior_source_release_rights x where x.release_id=r.id)
 order by created_at desc limit 1;
 if target.id is null then raise exception 'QA requires a sealed attested staged junior release'; end if;
 select * into binding from app_private.chem_junior_knowledge_card_bindings b
 where b.release_id=target.id and app_private.chem_junior_knowledge_card_is_ready('科粤版',b.knowledge_id)
 order by b.knowledge_id limit 1;
 if binding.card_id is null then raise exception 'QA needs a shared active/staged route'; end if;
 select * into old_card from public.chem_knowledge_cards where id=binding.card_id;
 select * into rights from app_private.chem_junior_source_release_rights where release_id=target.id;
 expected_old:=rights.attested_card_manifest_sha256;
 select jsonb_agg(to_jsonb(c) order by c.id) into active_before
 from public.chem_junior_bound_knowledge_cards('科粤版',null) c;
 select jsonb_agg(to_jsonb(b) order by b.knowledge_id) into bindings_before
 from app_private.chem_junior_knowledge_card_bindings b where b.release_id=target.id;
 rights_before:=to_jsonb(rights);
 new_card:=jsonb_populate_record(null::public.chem_knowledge_cards,to_jsonb(old_card)||
   jsonb_build_object('id','QA-CARD-VERSION-'||gen_random_uuid(),'core',old_card.core||'（事务测试卡片版本）'));
 insert into public.chem_knowledge_cards select new_card.*;
 new_hash:=app_private.chem_junior_knowledge_card_sha256(new_card);
 if not app_private.chem_junior_knowledge_card_binding_matches(target.id,'科粤版',binding.knowledge_id)
 then raise exception 'another approved version incorrectly invalidated original exact binding'; end if;
 if exists(select 1 from public.chem_junior_bound_knowledge_cards('科粤版',null) c where c.id=new_card.id)
 then raise exception 'unbound card version leaked into active delivery'; end if;
 if (select count(*) from public.chem_junior_bound_knowledge_cards('科粤版',array[]::text[]))<>0
 then raise exception 'empty requested skills unexpectedly returned all cards'; end if;
 request:=jsonb_build_array(jsonb_build_object('knowledge_id',binding.knowledge_id,
   'card_id',new_card.id,'card_sha256',new_hash,'canonical_source_id',binding.canonical_source_id,
   'canonical_source_sha256',binding.canonical_source_sha256));

 rejected:=false;
 begin
  perform public.chem_replace_staged_junior_knowledge_cards(target.id,target.manifest_sha256,expected_old,
    jsonb_set(request,'{0,card_sha256}',to_jsonb(repeat('0',64))),'QA-card-version');
 exception when others then
  if sqlerrm not like '%audit digest%' then raise; end if; rejected:=true;
 end;
 if not rejected then raise exception 'stale card hash accepted'; end if;
 rejected:=false;
 begin
  perform public.chem_replace_staged_junior_knowledge_cards(target.id,target.manifest_sha256,expected_old,
    request||request,'QA-card-version');
 exception when others then
  if sqlerrm not like '%ambiguous%' then raise; end if; rejected:=true;
 end;
 if not rejected then raise exception 'ambiguous route/card replacement accepted'; end if;
 rejected:=false;
 begin
  perform public.chem_replace_staged_junior_knowledge_cards(target.id,repeat('0',64),expected_old,
    request,'QA-card-version');
 exception when others then
  if sqlerrm not like '%frozen question manifest%' then raise; end if; rejected:=true;
 end;
 if not rejected then raise exception 'changed question manifest accepted'; end if;
 rejected:=false;
 begin
  perform public.chem_replace_staged_junior_knowledge_cards(target.id,target.manifest_sha256,repeat('0',64),
    request,'QA-card-version');
 exception when others then
  if sqlerrm not like '%prior rights/card manifest%' then raise; end if; rejected:=true;
 end;
 if not rejected then raise exception 'stale old card manifest accepted'; end if;
 rejected:=false;
 begin
  perform public.chem_replace_staged_junior_knowledge_cards(target.id,target.manifest_sha256,expected_old,
    jsonb_set(request,'{0,canonical_source_sha256}',to_jsonb(repeat('0',64))),'QA-card-version');
 exception when others then
  if sqlerrm not like '%independently verified release provenance%' then raise; end if; rejected:=true;
 end;
 if not rejected then raise exception 'wrong card source accepted'; end if;
 if (select to_jsonb(r) from app_private.chem_junior_source_release_rights r where release_id=target.id)
       is distinct from rights_before
   or (select jsonb_agg(to_jsonb(b) order by b.knowledge_id) from app_private.chem_junior_knowledge_card_bindings b where release_id=target.id)
       is distinct from bindings_before
   or exists(select 1 from app_private.chem_junior_card_replacement_audit where actor='QA-card-version')
 then raise exception 'failed replacement did not roll back all rights/bindings/audit'; end if;

 result_hash:=public.chem_replace_staged_junior_knowledge_cards(target.id,target.manifest_sha256,expected_old,request,'QA-card-version');
 if result_hash=expected_old or result_hash is distinct from app_private.chem_junior_knowledge_card_manifest_sha256(target.id)
   or not app_private.chem_junior_knowledge_card_binding_matches(target.id,'科粤版',binding.knowledge_id)
   or not exists(select 1 from app_private.chem_junior_knowledge_card_bindings b
      where b.release_id=target.id and b.knowledge_id=binding.knowledge_id and b.card_id=new_card.id and b.card_sha256=new_hash)
 then raise exception 'new exact approved card version was not correctly bound/re-attested'; end if;
 if (select jsonb_agg(to_jsonb(c) order by c.id) from public.chem_junior_bound_knowledge_cards('科粤版',null) c)
       is distinct from active_before
 then raise exception 'staged replacement changed active learner cards'; end if;
 if not exists(select 1 from app_private.chem_junior_card_replacement_audit a
   where actor='QA-card-version' and previous_rights=rights_before and previous_bindings=bindings_before
     and old_card_manifest_sha256=expected_old and new_card_manifest_sha256=result_hash)
 then raise exception 'previous attested evidence was not saved'; end if;

 rejected:=false;
 begin update app_private.chem_junior_card_replacement_audit set actor='changed' where actor='QA-card-version';
 exception when others then if sqlerrm not like '%append-only%' then raise; end if; rejected:=true; end;
 if not rejected then raise exception 'replacement audit mutated'; end if;
 rejected:=false;
 begin update public.chem_knowledge_cards set core=core||'bad' where id=old_card.id;
 exception when others then if sqlerrm not like '%immutable%' then raise; end if; rejected:=true; end;
 if not rejected then raise exception 'old bound card changed'; end if;
 rejected:=false;
 begin update public.chem_knowledge_cards set core=core||'bad' where id=new_card.id;
 exception when others then if sqlerrm not like '%immutable%' then raise; end if; rejected:=true; end;
 if not rejected then raise exception 'new attested card changed'; end if;

 for active_r in select * from app_private.chem_question_source_releases where grade_band='初三' and status in ('active','retired') loop
  rejected:=false;
  begin
   perform public.chem_replace_staged_junior_knowledge_cards(active_r.id,active_r.manifest_sha256,expected_old,request,'QA-card-version');
  exception when others then if sqlerrm not like '%staged-only%' then raise; end if; rejected:=true; end;
  if not rejected then raise exception 'active/retired release replaced'; end if;
 end loop;
 if has_function_privilege('anon','public.chem_junior_bound_knowledge_cards(text,text[])','execute')
   or has_function_privilege('authenticated','public.chem_replace_staged_junior_knowledge_cards(uuid,text,text,jsonb,text)','execute')
   or has_table_privilege('service_role','app_private.chem_junior_card_replacement_audit','UPDATE')
 then raise exception 'internal versioning API or audit is exposed'; end if;
end;$test$;
rollback;
select 'exact version, stale hashes/source, ambiguous replacement, atomic rollback, old/new immutable cards, append-only evidence and service-only privileges passed' result;
