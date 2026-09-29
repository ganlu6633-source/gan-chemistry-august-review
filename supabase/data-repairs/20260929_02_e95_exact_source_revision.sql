-- Source-reviewed E95 exact revision; prepared for parent review. All writes atomic.
begin;
select pg_advisory_xact_lock(hashtextextended('chem-source-original-release',0));
do $guard$ begin
 if not exists(select 1 from public.chem_questions where id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90' and question_revision_token='092c3eb903f1267a8cf9fddf6e07c7ecf9a9726c9144a7737889a76faa367b3c' and correct_option=1) then raise exception 'E95 original revision changed';end if;
 if exists(select 1 from public.chem_questions where id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90') or exists(select 1 from app_private.chem_question_source_releases where id='234a03b1-f756-48be-ac93-c9b8b2b93cb6') then raise exception 'revision already exists';end if;
 if exists(select 1 from app_private.chem_question_delivery_holds where anchor_question_id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90' and resolved_at is null) then raise exception 'hold baseline changed';end if;
 if not exists(select 1 from app_private.chem_question_assets where question_id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90' and asset_kind='analysis_image' and sha256='6de9a136b8b9fada2a0bc0b43c9102ae6ea2ea4ecb7bc3d7c62c231182c468a8') then raise exception 'reviewed image changed';end if;
 if not exists(select 1 from app_private.chem_question_assets where question_id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90' and asset_kind='question_image' and sha256='6d0ac5044b02424fa315f637b88063cce87c51bcff447cd3df7d191cf2b158a1') then raise exception 'reviewed image changed';end if;
end $guard$;
insert into app_private.chem_question_delivery_holds(anchor_question_id,reason) values('QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90','2026-09-29与H1_CLASSIFY_BASIC教师原件第17页第2题逐项核对：旧文字稿SO₃、SO₂、C₇₀上下标拆散；保持旧记录，新版本恢复正确文字并保留原题图。');
insert into app_private.chem_question_source_releases(id,manifest_sha256,grade_band,status,expected_question_count,verification_status,revision_contract,release_kind)
values('234a03b1-f756-48be-ac93-c9b8b2b93cb6',encode(extensions.digest('h1-e95-exact-revision-20260929','sha256'),'hex'),'高一','staged',1,'pending','v2_explanation_assets','teaching_material');
with old_q as(select * from public.chem_questions where id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90')
insert into public.chem_questions
select (jsonb_populate_record(null::public.chem_questions,to_jsonb(old_q)||jsonb_build_object(
 'id','QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90','source_release_id','234a03b1-f756-48be-ac93-c9b8b2b93cb6','stem','下列各组物质的分类正确的是：
①混合物：纯牛奶、冰水混合物、水煤气；
②电解质：氧化钠、氢氧化铁、胆矾；
③酸性氧化物：SO₃、SO₂、NO；
④同素异形体：C₇₀、金刚石、石墨；
⑤非电解质：干冰、液氯、乙醇。','options','["①②④", "②④", "①②③", "②④⑤"]'::jsonb,
 'content_fingerprint',app_private.chem_h3_content_fingerprint('下列各组物质的分类正确的是：
①混合物：纯牛奶、冰水混合物、水煤气；
②电解质：氧化钠、氢氧化铁、胆矾；
③酸性氧化物：SO₃、SO₂、NO；
④同素异形体：C₇₀、金刚石、石墨；
⑤非电解质：干冰、液氯、乙醇。','["①②④", "②④", "①②③", "②④⑤"]'::jsonb),
 'source_item_key',encode(extensions.digest(old_q.source_item_key||'|h1-e95-exact-20260929','sha256'),'hex'),
 'mother_id','MH1AUD29_'||upper(md5(old_q.id)),'parent_source_item_key',old_q.source_item_key,
 'usable_for_review',false,'usable_for_class_quiz',false,'usable_for_exam_sprint',false,'usable_for_demo',false,
 'source_info',old_q.source_info||jsonb_build_object('locator','H1_CLASSIFY_BASIC.pdf p17 素养提升第2题','questionNo','2','transcriptionPolicy','teacher_verified_exact_reflow_of_registered_source','optionTranscriptionPolicy','four options and chemical subscripts matched to exact original page','transcriptionAuditMethod','original PDF p17 plus current complete question and analysis assets individually visually verified'),
 'asset_refs',(select jsonb_agg(ref||jsonb_build_object('path','h1audit20260929e95/'||md5(old_q.id)||'/'||(ref->>'kind')) order by ref->>'kind') from jsonb_array_elements(old_q.asset_refs) ref),
 'created_at',now(),'updated_at',now()))).*
from old_q;
insert into app_private.chem_question_assets(asset_path,question_id,asset_kind,mime_type,payload_base64,sha256,width,height)
select 'h1audit20260929e95/'||md5('QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90')||'/'||a.asset_kind,'QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90',a.asset_kind,a.mime_type,a.payload_base64,a.sha256,a.width,a.height from app_private.chem_question_assets a where a.question_id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90';
update public.chem_questions q set question_revision_token=app_private.chem_h3_question_revision_sha256(q,a.sha256,b.sha256)
from app_private.chem_question_assets a,app_private.chem_question_assets b where q.id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90' and a.question_id=q.id and a.asset_kind='question_image' and b.question_id=q.id and b.asset_kind='analysis_image';
insert into app_private.chem_question_source_release_items(release_id,question_id,canonical_source_id,question_asset_sha256,analysis_asset_sha256,item_sha256)
select '234a03b1-f756-48be-ac93-c9b8b2b93cb6',n.id,o.canonical_source_id,a.sha256,b.sha256,app_private.chem_h3_release_item_sha256(n,o.canonical_source_id,a.sha256,b.sha256)
from public.chem_questions n join app_private.chem_question_source_release_items o on o.question_id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90' join app_private.chem_question_assets a on a.question_id=n.id and a.asset_kind='question_image' join app_private.chem_question_assets b on b.question_id=n.id and b.asset_kind='analysis_image' where n.id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90';
update app_private.chem_question_source_releases r set manifest_sha256=(select encode(extensions.digest(i.item_sha256,'sha256'),'hex') from app_private.chem_question_source_release_items i where i.release_id=r.id) where r.id='234a03b1-f756-48be-ac93-c9b8b2b93cb6';
select public.chem_record_question_item_visual_review(q.id,q.question_revision_token,q.source_info->>'locator','codex-source-item-audit-20260929','2026-09-29 原教师H1_CLASSIFY_BASIC.pdf（SHA256 b7b2373aeb41b8561da324156f70c8a0522169c06970f93d298f5b21fe8590d8）第17/22页素养提升第2题，原页、当前注册原题图及完整教师解析均逐项目视。准确恢复SO₃、SO₂和C₇₀上下标；①冰水为纯净物，②三者为电解质，③NO是不成盐氧化物，④三者为碳单质，⑤液氯为单质，唯一②④即B。现行原图完整，无须AI绘制或改图。','{"stem_options_and_formula":true,"answer_and_explanation":true,"source_image_complete":true,"source_locator_matches":true}'::jsonb) from public.chem_questions q where q.id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90';
insert into app_private.chem_question_source_release_lineage(release_id,question_id,previous_release_id,previous_question_id) select '234a03b1-f756-48be-ac93-c9b8b2b93cb6','QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90',source_release_id,id from public.chem_questions where id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90';
select public.chem_mark_source_original_release_visually_verified('234a03b1-f756-48be-ac93-c9b8b2b93cb6',(select manifest_sha256 from app_private.chem_question_source_releases where id='234a03b1-f756-48be-ac93-c9b8b2b93cb6'),'codex-full-visual-qa');
select * from public.chem_activate_teaching_material_release('234a03b1-f756-48be-ac93-c9b8b2b93cb6',(select manifest_sha256 from app_private.chem_question_source_releases where id='234a03b1-f756-48be-ac93-c9b8b2b93cb6'));
insert into app_private.chem_teaching_question_topics(question_id,topic_id,evidence)
select n.id,t.topic_id,jsonb_build_object('method','visually_verified_revision_lineage','evidence',jsonb_build_object('parentQuestionId','QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90','sourceReleaseId',n.source_release_id,'sourceLocator',n.source_info->>'locator','sourceDocumentSha256','b7b2373aeb41b8561da324156f70c8a0522169c06970f93d298f5b21fe8590d8','basis','same exact parent question, restores chemical subscripts'),'sameTypeClaim',false,'questionRevisionToken',n.question_revision_token)
from public.chem_questions n cross join app_private.chem_teaching_question_topics t where n.id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90' and t.question_id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90';
do $qa$ begin
 if not exists(select 1 from app_private.chem_teaching_ready_questions where id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90') or exists(select 1 from app_private.chem_teaching_ready_questions where id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90') then raise exception 'repaired ready and damaged held postcondition failed';end if;
 if not exists(select 1 from public.chem_questions n join public.chem_questions o on o.id='QH1R_20260908_E95B5C29D1204B56C44B8EAF9257CE90' where n.id='QH1AUD29_E95B5C29D1204B56C44B8EAF9257CE90' and n.parent_source_item_key=o.source_item_key and n.correct_option=o.correct_option) then raise exception 'exact parent or answer changed';end if;
end $qa$;
commit;
