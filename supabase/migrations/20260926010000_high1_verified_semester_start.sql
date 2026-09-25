-- First released stretch of the Sujiao compulsory-book-1 semester.
-- Only the question's audited primary concept can name a daily lesson.
-- Never infer a lesson from a keyword found in a different option.
-- The rest of the textbook outline is tracked separately until exact original
-- questions, four options, and teacher explanations are visually verified.
do $release$
declare
  v_student record;
  v_day record;
  v_question record;
  v_selected text;
  v_used text[];
  v_identities text[];
  v_assignments jsonb;
  v_program jsonb;
  v_title text;
  v_summary text;
  v_skill_title text;
  v_skills text[];
begin
  for v_student in
    select id, display_name, metadata
    from public.chem_students_v2
    where grade_band = '高一' and record_status = 'active'
      and not coalesce((metadata->>'demo')::boolean, false)
    order by id
  loop
    v_program := coalesce(v_student.metadata->'reviewProgram', '{}'::jsonb);
    v_assignments := coalesce(v_program->'questionAssignments', '{}'::jsonb);
    select coalesce(array_agg(distinct identifier), '{}'::text[]) into v_used
    from (
      select unnest(app_private.chem_teaching_identities(
        q.id, q.mother_id, q.source_item_key, q.content_fingerprint, q.parent_source_item_key
      )) identifier
      from public.chem_questions q
      where q.id in (
        select jsonb_array_elements_text(value)
        from jsonb_each(v_assignments)
        where jsonb_typeof(value) = 'array'
      )
      union all
      select unnest(app_private.chem_teaching_identities(
        q.id, q.mother_id, q.source_item_key, q.content_fingerprint, q.parent_source_item_key
      ))
      from public.chem_attempt_answers answer
      join public.chem_learning_attempts attempt on attempt.id = answer.attempt_id
      join public.chem_questions q on q.id = answer.question_id
      where attempt.student_id = v_student.id
    ) used_originals;

    for v_day in
      with units(unit_order, unit_title, concepts) as (
        values
        (1, '专题1·物质及其反应的分类', array[
          'H1_CLASSIFY__C01','H1_CLASSIFY__C02','H1_CLASSIFY__C04',
          'H1_CLASSIFY__C05','H1_REACTION_CLASSIFICATION__C03',
          'H1_REACTION_CLASSIFICATION__C04','H1_CLASSIFY__C01']),
        (2, '专题1·物质转化与反应类型', array[
          'H1_REACTION_CLASSIFICATION__C01','H1_REACTION_CLASSIFICATION__C02',
          'H1_REACTION_CLASSIFICATION__C03','H1_REACTION_CLASSIFICATION__C04',
          'H1_REACTION_CLASSIFICATION__C05']),
        (3, '专题1·物质的化学计量', array[
          'H1_MOLE_INTRO__C01','H1_MOLE_INTRO__C02','H1_MOLE_INTRO__C03',
          'H1_MOLE_INTRO__C04','H1_MOLE_INTRO__C05']),
        (4, '专题1·物质分类与分散系', array[
          'H1_CLASSIFY__C03','H1_MATERIAL_DISPERSION__C01',
          'H1_CLASSIFY__C02','H1_CLASSIFY__C03']),
        (5, '专题1·电解质、离子反应与氧化还原', array[
          'H1_ELECTROLYTE__C52','H1_ELECTROLYTE__C53','H1_ELECTROLYTE__C54',
          'H1_REDOX__C01','H1_REDOX__C02','H1_REDOX__C03',
          'H1_REDOX__C04','H1_REDOX__C05','H1_REDOX__C01']),
        (6, '专题2·实验方法与溶液定量', array[
          'H1_MATERIAL_EXPERIMENT__C01','H1_MATERIAL_EXPERIMENT__C02',
          'H1_MATERIAL_EXPERIMENT__C03','H1_MATERIAL_EXPERIMENT__C04',
          'H1_MATERIAL_EXPERIMENT__C05','H1_SOLUTION_CONCENTRATION__C01',
          'H1_SOLUTION_CONCENTRATION__C02','H1_SOLUTION_CONCENTRATION__C03']),
        (7, '专题2·溶液定量与气体摩尔体积', array[
          'H1_SOLUTION_CONCENTRATION__C04','H1_SOLUTION_CONCENTRATION__C05',
          'H1_GAS_MOLAR_VOLUME__C01','H1_GAS_MOLAR_VOLUME__C02',
          'H1_GAS_MOLAR_VOLUME__C03','H1_GAS_MOLAR_VOLUME__C04']),
        (8, '专题2·气体计量、原子结构与周期表', array[
          'H1_GAS_MOLAR_VOLUME__C05','H1_MATERIAL_ATOM__C01',
          'H1_PERIODIC__C01','H1_PERIODIC__C02','H1_PERIODIC__C03',
          'H1_PERIODIC__C04']),
        (9, '专题3·氯、钠及其化合物', array[
          'H1_NACL__C52','H1_NACL__C53','H1_NACL__C54','H1_NACL__C55',
          'H1_NACL__C56','H1_NACL__C57','H1_NACL__C58',
          'H1_NACL__C54']),
        (10, '专题3·海水资源与单元回看', array[
          'H1_MATERIAL_SEAWATER__C01','H1_NACL__C56',
          'H1_MATERIAL_SEAWATER__C01'])
      ), dated as (
        select u.*, coalesce(sum(cardinality(concepts)) over (
          order by unit_order rows between unbounded preceding and 1 preceding
        ), 0)::integer first_offset
        from units u
      )
      select date '2026-09-12' + u.first_offset + item.day_number::integer - 1 plan_date,
        u.unit_title, item.concept_key,
        split_part(item.concept_key, '__', 1) skill_id,
        case when row_number() over (
          partition by item.concept_key order by u.unit_order, item.day_number
        ) > 1 then '回看' else '新学' end phase,
        catalog.concept_title, skill.title skill_title
      from dated u
      cross join lateral unnest(u.concepts) with ordinality as item(concept_key, day_number)
      left join public.chem_review_concept_catalog_rows() catalog
        on catalog.grade_band = '高一' and catalog.concept_key = item.concept_key
      join public.chem_skills skill
        on skill.id = split_part(item.concept_key, '__', 1)
      order by plan_date
    loop
      if exists (
        select 1 from public.chem_learning_plans plan
        where plan.student_id = v_student.id and plan.plan_date = v_day.plan_date
          and plan.mode = 'REVIEW' and plan.is_scheduled
      ) then continue; end if;

      v_selected := null;
      for v_question in
        select q.* from app_private.chem_teaching_ready_questions q
        where q.grade_band = '高一' and q.skill_id = v_day.skill_id
        order by (q.concept_key = v_day.concept_key) desc, q.level, q.id
      loop
        v_identities := app_private.chem_teaching_identities(
          v_question.id, v_question.mother_id, v_question.source_item_key,
          v_question.content_fingerprint, v_question.parent_source_item_key
        );
        if v_used && v_identities then continue; end if;
        v_selected := v_question.id;
        v_used := v_used || v_identities;
        exit;
      end loop;
      if v_selected is null then
        raise exception 'No unused verified question in % for student %, date %',
          v_day.skill_id, v_student.display_name, v_day.plan_date;
      end if;
      -- If the exact fine concept has run out, name the broader skill honestly.
      v_summary := case when v_question.concept_key = v_day.concept_key
        then coalesce(v_day.concept_title, v_day.skill_title)
        else v_day.skill_title || '·同专题原题' end;
      v_title := v_day.unit_title || '｜' || v_day.phase || '·' || v_summary;

      update public.chem_learning_plans plan
      set title = v_title, skill_ids = array[v_question.skill_id],
        target_concept_keys = array[v_question.concept_key],
        knowledge_summaries = array[v_summary], estimated_minutes = 12,
        source = 'course', is_scheduled = true, question_count = 1,
        round_limit = 1, max_question_level = 8, delivery_mode = 'legacy_round',
        teaching_managed = true, teaching_source_grade = '高一'
      where plan.student_id = v_student.id and plan.plan_date = v_day.plan_date
        and plan.mode = 'REVIEW'
        and not app_private.chem_teaching_plan_started(plan.id);
      if not found then
        if exists (
          select 1 from public.chem_learning_plans plan
          where plan.student_id = v_student.id and plan.plan_date = v_day.plan_date
            and plan.mode = 'REVIEW'
        ) then raise exception 'Cannot replace a started plan on %', v_day.plan_date; end if;
        insert into public.chem_learning_plans (
          student_id, plan_date, mode, title, skill_ids, target_concept_keys,
          knowledge_summaries, estimated_minutes, source, is_scheduled,
          question_count, round_limit, max_question_level, delivery_mode,
          teaching_managed, teaching_source_grade
        ) values (
          v_student.id, v_day.plan_date, 'REVIEW', v_title,
          array[v_question.skill_id], array[v_question.concept_key],
          array[v_summary], 12, 'course', true, 1, 1, 8,
          'legacy_round', true, '高一'
        );
      end if;
      v_assignments := v_assignments || jsonb_build_object(
        v_day.plan_date::text, jsonb_build_array(v_selected)
      );
    end loop;

    select array_agg(distinct skill order by skill) into v_skills
    from public.chem_learning_plans plan
    cross join lateral unnest(plan.skill_ids) skill
    where plan.student_id = v_student.id and plan.mode = 'REVIEW'
      and plan.is_scheduled
      and plan.plan_date between date '2026-09-12' and date '2026-11-11';
    v_program := v_program || jsonb_build_object(
      'participating', true, 'choiceOnly', true,
      'startDate', '2026-09-12', 'endDate', '2026-11-11',
      'allowedSkillIds', to_jsonb(coalesce(v_skills, '{}'::text[])),
      'questionAssignments', v_assignments
    );
    update public.chem_students_v2
    set metadata = jsonb_set(metadata, '{reviewProgram}', v_program),
        updated_at = now()
    where id = v_student.id;
  end loop;
end
$release$;
