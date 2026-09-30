-- An exported Word image marker is not a student-usable formula or diagram.
do $test$
begin
  if not 'unresolved_embedded_image_reference' = any (
    app_private.chem_question_formula_gap_flags(
      '流程图：[图片:media/image3.png]',
      '["正确选项", "错误选项", "另一选项", "最后选项"]'::jsonb,
      '按原图判断。'
    )
  ) then
    raise exception 'unresolved stem image marker escaped the delivery check';
  end if;

  if not 'unresolved_embedded_image_reference' = any (
    app_private.chem_question_formula_gap_flags(
      '下列说法正确的是',
      '["A", "B", "[图片:media/image5.png]", "D"]'::jsonb,
      '见原卷。'
    )
  ) then
    raise exception 'unresolved option image marker escaped the delivery check';
  end if;

  if 'unresolved_embedded_image_reference' = any (
    app_private.chem_question_formula_gap_flags(
      '下列说法正确的是',
      '["A", "B", "C", "D"]'::jsonb,
      '原题图和解析图均已核对。'
    )
  ) then
    raise exception 'a complete question was rejected as an image marker';
  end if;

  if exists (
    select 1 from app_private.chem_teaching_ready_questions q
    where (coalesce(q.stem,'') || coalesce(q.options::text,'') ||
           coalesce(q.explanation,'')) ~*
          '\[[[:space:]]*(图片|图像|image|img)[[:space:]]*[:：][^]]+\]'
  ) then
    raise exception 'a student-ready question still contains an image marker';
  end if;
end;
$test$;
