-- Prepared from the active 18-student roster on 2026-09-12.
-- Adds four progress groups and membership only. No plans, assignments, scores or history are changed.
-- Run only after verifying this snapshot is still current; any progress change aborts atomically.
begin;
select pg_advisory_xact_lock(66820260908);
create temporary table initial_group_members on commit drop as
 select * from jsonb_to_recordset('[{"id":"bc8cff33-8a2d-45c9-ac60-b3c4fd41c5f2","grade":"初三","cohort":"junior_foundation","expectedHash":"a6a742a7088a1751d1b1f5b6b0c97c15"},{"id":"b8212f91-8842-431c-a576-660a4b9dd785","grade":"初三","cohort":"junior_foundation","expectedHash":"839a6473b584e51431d712cfa35413a9"},{"id":"b8da8177-541e-4b4b-b9b5-7841bd3b76f5","grade":"初三","cohort":"junior_foundation","expectedHash":"3d7dfe474dca96a35277ac7e75db2870"},{"id":"f0306011-7ef5-4da2-b784-90279c7580be","grade":"高一","cohort":"high1_current","expectedHash":"3c26a3bc98dc34cf73554bbe5114f37b"},{"id":"bb381d35-0d5a-4b0e-bb50-7fbb263426f5","grade":"高一","cohort":"high1_current","expectedHash":"7f0d62857d1e5dbaf1091ea886953a2b"},{"id":"2e9dc98d-b4e3-4e67-a4fa-16298137c9bb","grade":"高一","cohort":"high1_current","expectedHash":"448ccdbc6615358fad7bae0843aa7e8e"},{"id":"bcaf39c7-9a9a-4c07-8efd-f21c0167229b","grade":"高三","cohort":"high3_quality_0827","expectedHash":"2e33eff1267469be95936e4406f9068e"},{"id":"5a785bdc-18f5-4ef2-b15d-675450e95cc2","grade":"高三","cohort":"high3_quality_0827","expectedHash":"3367ec098265c5a991e75252232c7365"},{"id":"f93b77fb-df22-4ff0-afa2-991938d9170f","grade":"高三","cohort":"high3_quality_0827","expectedHash":"e9794353aa45dea54d5699a4425cf560"},{"id":"d9f2888a-e429-4e0a-85e7-4af9704ed43f","grade":"高三","cohort":"high3_quality_0827","expectedHash":"2b4909705313c8a0a601f847943ac565"},{"id":"33ad13d0-a25b-48f7-803c-e1465c243bdb","grade":"高三","cohort":"high3_quality_0827","expectedHash":"d213e2b2f1991fd87d7f78564e72ffc7"},{"id":"3225463a-576d-4cd5-848a-674c7cd6a40c","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"fc47f64bab7521825077a55714c221e5"},{"id":"ed827260-8768-4b78-a0e1-496ba381752c","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"775a179c7bf87cd456b5792cbd145032"},{"id":"3dd6d210-3c1b-4a4d-a99f-689c17739712","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"4b2b2b6a0c0c790d451eb9dda0c4e508"},{"id":"c6ad7b31-8208-450b-8618-c36e740739c2","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"8889d91139839640d9702e4a2e47761f"},{"id":"4f7b0cb2-0da9-4978-b7ce-df83ff8e48f8","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"9273a58d39a4fe9a3f404f6e3062b643"},{"id":"6f16e7a1-c069-4929-8fca-f0d301b26bad","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"0280778d601dc9acae8910969b0b1036"},{"id":"58128d73-a62d-46c7-8ae7-5b8a6281f220","grade":"高二","cohort":"high2_xb1_complete","expectedHash":"b777fda8841ab5a4042d05b361c3563a"}]'::jsonb)
 as x(id uuid,grade text,cohort text,"expectedHash" text);
do $$
declare member record; v_class uuid; before_plan_hash text; after_plan_hash text;
begin
 perform 1 from public.chem_students_v2 s join initial_group_members m on m.id=s.id order by s.id for update;
 if (select count(*) from public.chem_students_v2 where record_status='active' and metadata#>>'{reviewProgram,participating}'='true')<>18 then raise exception '参与名单已变化，请重新生成初始化种子'; end if;
 if exists(select 1 from initial_group_members m left join public.chem_students_v2 s on s.id=m.id where s.id is null or s.grade_band<>m.grade or s.metadata->>'curriculumCohort' is distinct from m.cohort or s.record_status<>'active' or s.teaching_class_id is not null or app_private.chem_teaching_state_hash(array[s.id])<>m."expectedHash") then raise exception '学生档案或作答进度已变化，初始化未执行'; end if;
 select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.id)::text,'null')) into before_plan_hash from public.chem_learning_plans p;
 for member in select distinct grade,cohort from initial_group_members order by grade loop
  insert into app_private.chem_teaching_classes(name,grade_band,plan_items) values(member.grade||'·当前同步进度',member.grade,'[]') returning id into v_class;
  update public.chem_students_v2 s set teaching_class_id=v_class,updated_at=now() from initial_group_members m where s.id=m.id and m.cohort=member.cohort and m.grade=member.grade;
 end loop;
 select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.id)::text,'null')) into after_plan_hash from public.chem_learning_plans p;
 if before_plan_hash<>after_plan_hash then raise exception '初始化不应改变任何学习计划'; end if;
end $$;
select c.name,c.grade_band,count(s.id) member_count from app_private.chem_teaching_classes c join public.chem_students_v2 s on s.teaching_class_id=c.id group by c.id order by c.grade_band;
commit;
