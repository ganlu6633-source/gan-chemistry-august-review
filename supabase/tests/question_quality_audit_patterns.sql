-- Run against a database with 20260929035000 applied.  No persistent writes.
begin;
do $qa$ begin
  if not ('empty_labeled_reactions' = any(
    app_private.chem_question_ocr_gap_flags(E'反应Ⅰ：\n反应Ⅱ：\n反应Ⅲ：\n4NH₃＋5O₂ 4NO', '[]'::jsonb)))
  then raise exception 'empty reaction table labels escaped the audit'; end if;

  if not ('missing_subject_after_known' = any(
    app_private.chem_question_ocr_gap_flags('已知：为浅黄色粉末，遇水反应', '[]'::jsonb)))
  then raise exception 'omitted chemical before colour escaped the audit'; end if;

  if not ('missing_reaction_expression' = any(
    app_private.chem_question_ocr_gap_flags('可利用反应制备目标气体', '[]'::jsonb)))
  then raise exception 'missing reaction expression escaped the audit'; end if;

  if not ('missing_step_name' = any(
    app_private.chem_question_ocr_gap_flags('H₂O(g)脱去步骤如下', '[]'::jsonb)))
  then raise exception 'missing step name escaped the audit'; end if;

  if not ('generated_and_consumed_without_object' = any(
    app_private.chem_question_ocr_gap_flags('反应过程中生成并消耗，计算质量', '[]'::jsonb)))
  then raise exception 'missing generated/consumed object escaped the audit'; end if;

  if cardinality(app_private.chem_question_ocr_gap_flags(
    '已知：MnO₂ 为黑色粉末；反应Ⅰ：4NH₃＋5O₂⇌4NO＋6H₂O。',
    '["Fe³⁺ 电荷为 +3", "ΔH＝－105.4 kJ·mol⁻¹", "反应Ⅰ是放热反应", "Kₐ＞K_b"]'::jsonb)) <> 0
  then raise exception 'complete formulas or ionic charge were falsely flagged'; end if;

  if exists(select 1 from app_private.chem_question_quality_audit_queue
      where suspected_formula_gap is distinct from
        (cardinality(suspected_formula_gap_flags) > 0))
  then raise exception 'audit boolean and explicit flags disagree'; end if;
end $qa$;
rollback;
