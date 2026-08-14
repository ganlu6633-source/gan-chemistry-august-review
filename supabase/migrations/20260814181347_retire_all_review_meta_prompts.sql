begin;

-- Finish retiring legacy REVIEW meta-prompts that had already been marked
-- retired before the five-round bank migration but still carried a stale
-- usable_for_review=true flag. This does not touch the independent quiz bank.
with target_skills(skill_id) as (values
  ('H1_CLASSIFY'),('H1_GAS_MOLAR_VOLUME'),('H1_MOLE_INTRO'),('H1_PERIODIC'),('H1_REDOX'),
  ('H2_ELECTRO'),('H2_EQUIL'),('H2_K'),('H2_KSP'),('H2_PH_HYDRO'),('H2_RATE'),('H2_THERMO'),('H2_WEAK'),
  ('H3_AQ'),('H3_ELECTRO'),('H3_EQUILIBRIUM'),('H3_EXPERIMENT'),('H3_INORGANIC'),('H3_ION_REDOX'),
  ('H3_ORGANIC'),('H3_PROCESS'),('H3_STOICH'),('H3_STRUCTURE'),('H3_THERMO_RATE')
)
update public.chem_questions q
set review_status = 'retired',
    usable_for_review = false,
    updated_at = now()
where q.skill_id in (select skill_id from target_skills)
  and q.stem ~ '(核心规律|最可靠.{0,8}第一步|处理.{0,20}(第一步|优先)|优先检查|最先做)'
  and (q.review_status <> 'retired' or q.usable_for_review);

do $verify$
begin
  if exists (
    select 1
    from public.chem_questions q
    where q.skill_id in (
      'H1_CLASSIFY','H1_GAS_MOLAR_VOLUME','H1_MOLE_INTRO','H1_PERIODIC','H1_REDOX',
      'H2_ELECTRO','H2_EQUIL','H2_K','H2_KSP','H2_PH_HYDRO','H2_RATE','H2_THERMO','H2_WEAK',
      'H3_AQ','H3_ELECTRO','H3_EQUILIBRIUM','H3_EXPERIMENT','H3_INORGANIC','H3_ION_REDOX',
      'H3_ORGANIC','H3_PROCESS','H3_STOICH','H3_STRUCTURE','H3_THERMO_RATE'
    )
      and q.stem ~ '(核心规律|最可靠.{0,8}第一步|处理.{0,20}(第一步|优先)|优先检查|最先做)'
      and (q.review_status <> 'retired' or q.usable_for_review)
  ) then
    raise exception 'Legacy REVIEW meta-prompts remain active';
  end if;
end
$verify$;

commit;
