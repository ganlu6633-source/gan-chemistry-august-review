-- Keep the REVIEW knowledge-card copy aligned with the diagram-led UI.
-- This intentionally does not touch quiz_sessions or the independent quiz site.
do $$
declare
  affected integer;
  concise_path constant text := 'Mn：+7→+2，得5e⁻｜Fe：+2→+3，每个失1e⁻｜电子守恒定1∶5｜酸性介质补8H⁺、4H₂O｜最后查原子、电荷、电子。';
begin
  update public.chem_knowledge_cards
  set structured_content = replace(
        replace(
          replace(
            structured_content::text,
            'Mn从+7降到+2，每个Mn得5e⁻；Fe从+2升到+3，每个Fe失1e⁻，因此1个MnO₄⁻对应5个Fe²⁺，再用H⁺、H₂O补H和O并检查电荷。',
            concise_path
          ),
          '先定1:5',
          '先定1∶5'
        ),
        '查电荷',
        '查三守恒'
      )::jsonb,
      updated_at = now()
  where id = 'KC_H1_REDOX'
    and skill_id = 'H1_REDOX'
    and review_status = 'approved';
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Expected one approved H1 redox card, updated %', affected;
  end if;

  update public.chem_knowledge_cards
  set structured_content = replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  structured_content::text,
                  'Mn从+7到+2得5e⁻，Fe从+2到+3失1e⁻，先定1:5；酸性用H₂O补O、H⁺补H，得MnO₄⁻+5Fe²⁺+8H⁺=Mn²⁺+5Fe³⁺+4H₂O。',
                  concise_path
                ),
                'Mn(+7)得5e⁻变Mn²⁺，Fe²⁺失1e⁻变Fe³⁺，先定1:5；补H和O得MnO₄⁻+5Fe²⁺+8H⁺=Mn²⁺+5Fe³⁺+4H₂O；左右电荷均+17。',
                concise_path
              ),
              '电子1:5',
              '电子1∶5'
            ),
            '原子电荷复核',
            '三守恒复核'
          ),
          '电荷复核',
          '三守恒复核'
        ),
        '先定1:5',
        '先定1∶5'
      )::jsonb,
      updated_at = now()
  where id = 'KC_H3_ION_REDOX'
    and skill_id = 'H3_ION_REDOX'
    and review_status = 'approved';
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Expected one approved H3 ion-redox card, updated %', affected;
  end if;

  if exists (
    select 1
    from public.chem_knowledge_cards
    where id in ('KC_H1_REDOX', 'KC_H3_ION_REDOX')
      and structured_content::text like any (array[
        '%Mn从+7降到+2，每个Mn得5e⁻%',
        '%Mn从+7到+2得5e⁻%',
        '%Mn(+7)得5e⁻变Mn²⁺%'
      ])
  ) then
    raise exception 'A paragraph-form permanganate/iron example remains';
  end if;

  if (select count(*)
      from public.chem_knowledge_cards
      where id in ('KC_H1_REDOX', 'KC_H3_ION_REDOX')
        and structured_content::text like '%' || concise_path || '%') <> 2 then
    raise exception 'Concise diagram companion copy is missing from a target card';
  end if;
end
$$;
