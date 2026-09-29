-- Multiple unfinished assigned dates are supported only by the policy with
-- a shared student/day budget. Legacy sessions remain exclusive.
create or replace function app_private.chem_guard_junior_active_session_policy()
returns trigger language plpgsql security definer set search_path='' as $function$
declare new_policy boolean;
begin
 if new.status<>'active' then return new; end if;
 if tg_op='UPDATE' then
   if old.status='active' and new.student_id=old.student_id
     and new.initial_question_target=old.initial_question_target
     and new.hard_question_cap=old.hard_question_cap
     and new.recovery_round_limit=old.recovery_round_limit
   then return new;end if;
   -- UPDATE already holds its row. Never wait for a parent/global lock in the
   -- inverse order: fail with a retryable conflict instead of risking deadlock.
   if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0))
     or not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0))
   then raise exception 'junior_session_activation_retry' using errcode='40001';end if;
   begin
     perform s.id from public.chem_students_v2 s where s.id=new.student_id for update nowait;
   exception when lock_not_available then
     raise exception 'junior_session_activation_retry' using errcode='40001';
   end;
 else
   -- Match normal issue/answer/finalize lock order. This also serializes two
   -- simultaneous legacy/new inserts before their snapshot is checked.
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-source-original-release',0));
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('chem-h3-original-release',0));
   perform s.id from public.chem_students_v2 s where s.id=new.student_id for update;
 end if;
 new_policy:=new.initial_question_target=8 and new.hard_question_cap=30 and new.recovery_round_limit=3;
 if exists(select 1 from public.chem_junior_daily_sessions other
   where other.student_id=new.student_id and other.status='active' and other.id<>new.id
     and (not new_policy or other.initial_question_target<>8 or other.hard_question_cap<>30 or other.recovery_round_limit<>3))
 then raise exception 'junior_session_legacy_active_conflict' using errcode='23505';end if;
 return new;
end;
$function$;
revoke all on function app_private.chem_guard_junior_active_session_policy() from public,anon,authenticated;

-- Take the table lock in one short DDL transaction; no learner data changes.
drop index public.chem_junior_daily_sessions_one_active_student_uidx;
create unique index chem_junior_daily_sessions_one_active_legacy_student_uidx
 on public.chem_junior_daily_sessions(student_id)
 where status='active' and not(initial_question_target=8 and hard_question_cap=30 and recovery_round_limit=3);
create trigger chem_junior_sessions_guard_active_policy
 before insert or update of status,student_id,initial_question_target,hard_question_cap,recovery_round_limit
 on public.chem_junior_daily_sessions for each row
 execute function app_private.chem_guard_junior_active_session_policy();
