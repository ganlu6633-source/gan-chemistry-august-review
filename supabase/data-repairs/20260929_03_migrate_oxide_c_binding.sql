-- Run only after 02-e95-exact-source-revision.sql passes full source review.
-- Three exact same-point independent originals; no stale C41 used until its source locator is verified.
begin;
select pg_advisory_xact_lock(hashtextextended('chem-option-practice-binding-reviewed',0));
create temporary table _oxide_candidates(id text primary key,expected_revision text,reason text) on commit drop;
insert into _oxide_candidates values
('QH1OCR29_3BFF3FF7BEC042AF0D139F7A37FB13EA','0794cd5d3a8e84a3c80f5074afcc6260ecae7fb8479fda0d2e5a1c2f61905255','B项直接否定“非金属氧化物一定是酸性氧化物”；用CO、NO反例判断，和原C项为同一全称判断错误。'),
('QH1OCR29_E25836BF9DD1FCD8A198C6635791E71D','b51a2984f6a5795303b1bc90742532788ff160097f8093fa9cebcc4ce113532b','D项是同一错误全称判断，图中NO、CO为非金属氧化物但不是酸性氧化物；需区分按组成和按性质分类。'),
('QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90',null,'③将NO与SO₂、SO₃并列为酸性氧化物，需识别NO是不成盐氧化物，正是原C项所需的具体反例判断。');
do $guard$ begin
 if not exists(select 1 from app_private.chem_option_practice_bindings where anchor_question_id='QH1R_20260908_F61D55EB06E6487DCF86A29B2CE0F24A' and option_index=2 and anchor_revision_token='83a5d99546aefd22735d780464f2906f66ff8edf216a0675bebddc49992fb7c8' and same_type_key='nonmetal_oxide_not_always_acidic' and review_status='verified') then raise exception 'existing exact C route changed';end if;
 if (select count(*) from _oxide_candidates c join app_private.chem_teaching_ready_questions r on r.id=c.id join public.chem_questions q on q.id=c.id where (c.expected_revision is null or q.question_revision_token=c.expected_revision) and app_private.chem_question_item_visual_reviewed(q.id))<>3 then raise exception 'three current reviewed candidates required';end if;
 if not exists(select 1 from public.chem_questions where id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90' and source_release_id='234a03b1-f756-48be-ac93-c9b8b2b93cb6') then raise exception 'exact E95 release required';end if;
 if (select count(distinct coalesce(nullif(q.parent_source_item_key,''),q.source_item_key,q.mother_id)) from _oxide_candidates c join public.chem_questions q on q.id=c.id)<>3 then raise exception 'three independent source parents required';end if;
 if exists(select 1 from _oxide_candidates c join public.chem_questions q on q.id=c.id join public.chem_questions a on a.id='QH1R_20260908_F61D55EB06E6487DCF86A29B2CE0F24A' where q.grade_band<>a.grade_band or coalesce(nullif(q.parent_source_item_key,''),q.source_item_key,q.mother_id)=coalesce(nullif(a.parent_source_item_key,''),a.source_item_key,a.mother_id)) then raise exception 'anchor parent repeated or grade mismatch';end if;
end $guard$;
update app_private.chem_option_practice_bindings b set candidates=(select jsonb_agg(jsonb_build_object('questionId',q.id,'revisionToken',q.question_revision_token,'reason',c.reason) order by q.id) from _oxide_candidates c join public.chem_questions q on q.id=c.id),reviewed_by='codex-source-option-qa-20260929',reviewed_at=now(),review_note='2026-09-29逐源图与教师解析复核：H1_CLASSIFY_LAYERED.pdf第5-6页第6题、H1_CLASSIFY_BASIC.pdf第6-7页第1题及第17页第2题。迁移同源修订版本，保留原母题去重。仅3道严格对应“非金属氧化物不一定是酸性氧化物”的独立原题；暂不使用来源定位未复核的C41题。'
where b.anchor_question_id='QH1R_20260908_F61D55EB06E6487DCF86A29B2CE0F24A' and b.option_index=2;
do $qa$ begin
 if(select jsonb_array_length(candidates) from app_private.chem_option_practice_bindings where anchor_question_id='QH1R_20260908_F61D55EB06E6487DCF86A29B2CE0F24A' and option_index=2)<>3 then raise exception 'migration affected wrong route';end if;
end $qa$;
commit;
