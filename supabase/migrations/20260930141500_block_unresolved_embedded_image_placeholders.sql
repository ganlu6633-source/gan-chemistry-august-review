-- A Word extraction marker means the embedded picture was not recovered.
-- The student-facing gate must reject that version even when a manually
-- rendered question image exists: the rendered image may contain the marker.
create or replace function app_private.chem_question_formula_gap_flags(
  p_stem text,
  p_options jsonb,
  p_explanation text
)
returns text[]
language sql
immutable
set search_path to ''
as $function$
  select array_cat(
    app_private.chem_question_ocr_gap_flags(p_stem,p_options),
    array_remove(array[
      case when position(chr(65533) in
             (coalesce(p_stem,'') || coalesce(p_options::text,'') ||
              coalesce(p_explanation,''))) > 0
           then 'replacement_character_in_question' end,
      case when (coalesce(p_stem,'') || coalesce(p_options::text,'') ||
                 coalesce(p_explanation,'')) ~
                '(6[.]02|1[.]505)[[:space:]]*[×xX][[:space:]]*10(23|22|24)([^0-9]|$)'
           then 'flattened_scientific_exponent' end,
      case when (select count(*) from regexp_matches(
                  coalesce(p_stem,''),
                  '反应[ⅠⅡⅢⅣIVX0-9]+[：:]', 'g')) >= 2
                and coalesce(p_stem,'') !~ '[→⟶⇌⇄↔=＝]'
           then 'reaction_table_arrows_missing' end,
      case when (coalesce(p_stem,'') || coalesce(p_options::text,'') ||
                 coalesce(p_explanation,'')) ~*
                '\[[[:space:]]*(图片|图像|image|img)[[:space:]]*[:：][^]]+\]'
           then 'unresolved_embedded_image_reference' end
    ]::text[], null::text)
  );
$function$;
