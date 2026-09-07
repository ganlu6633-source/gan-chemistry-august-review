begin;
create table app_private.chem_question_delivery_holds(
 anchor_question_id text primary key references public.chem_questions(id) on delete restrict,
 reason text not null check(length(btrim(reason))>0),
 created_at timestamptz not null default now(),
 resolved_at timestamptz
);
alter table app_private.chem_question_delivery_holds enable row level security;
revoke all on table app_private.chem_question_delivery_holds from public,anon,authenticated,service_role;
create or replace function public.chem_question_delivery_holds()
returns table(question_id text,reason text)
language sql stable security definer set search_path=''
as $$
 select distinct q.id,h.reason from app_private.chem_question_delivery_holds h
 join public.chem_questions anchor on anchor.id=h.anchor_question_id
 join public.chem_questions q on q.id=anchor.id or q.source_item_key=anchor.source_item_key or q.content_fingerprint=anchor.content_fingerprint
 where h.resolved_at is null;
$$;
revoke all on function public.chem_question_delivery_holds() from public,anon,authenticated;
grant execute on function public.chem_question_delivery_holds() to service_role;
commit;
