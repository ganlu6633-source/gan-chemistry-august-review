/**
 * Examples for reviewed sub-points produced by getKnowledgeReviewPoints.
 * Key: skillId:sectionIndex:itemIndex:partIndex. These examples belong to the
 * precise sub-point, unlike a general section or parent-item demonstration.
 */
export const knowledgeFinePointExamples: Record<string, string[]> = {
  'H1_GAS_MOLAR_VOLUME:2:0:0': ['标准状况下11.2 L O₂，n＝V/Vₘ＝11.2/22.4＝0.50 mol。'],
  'H1_GAS_MOLAR_VOLUME:2:0:1': ['标准状况下0.50 mol O₂，V＝nVₘ＝0.50×22.4＝11.2 L。'],
  'H1_MOLE_INTRO:2:2:0': ['36 g H₂O ÷ 18 g·mol⁻¹＝2 mol H₂O。'],
  'H1_MOLE_INTRO:2:2:1': ['2 mol H₂O × 18 g·mol⁻¹＝36 g H₂O。'],

  'H1_MOLE:0:0:0': ['5.85 g NaCl ÷ 58.5 g·mol⁻¹＝0.100 mol NaCl。'],
  'H1_MOLE:0:0:1': ['0.200 mol NaCl × 58.5 g·mol⁻¹＝11.7 g NaCl。'],
  'H1_MOLE:0:1:0': ['0.50 mol O₂含0.50N_A个O₂分子；若数氧原子则是1.0N_A个。'],
  'H1_MOLE:0:1:1': ['若有1.204×10²⁴个H₂O分子，n＝N/N_A≈2.00 mol H₂O。'],
  'H1_MOLE:0:3:0': ['0.20 mol·L⁻¹ NaCl溶液0.50 L中，n＝cV＝0.10 mol。'],
  'H1_MOLE:0:3:1': ['0.050 mol NaCl配成0.250 L溶液，c＝n/V＝0.20 mol·L⁻¹。'],

  'H2_THERMO:4:0:0': ['反应前酸液20.1 ℃、碱液20.3 ℃，初始温度T₁取平均值20.2 ℃。'],
  'H2_THERMO:4:0:1': ['混合后温度先上升至25.0 ℃再回落，T₂取最高值25.0 ℃。'],
  'H2_THERMO:4:0:2': ['若T₁＝20.2 ℃、T₂＝25.0 ℃，则ΔT＝25.0−20.2＝4.8 ℃。'],
  'H2_THERMO:4:0:3': ['溶液质量100 g、比热容按4.18 J·g⁻¹·℃⁻¹、ΔT＝4.8 ℃，溶液吸热q≈2.01 kJ。'],
  'H2_THERMO:4:0:4': ['若生成0.050 mol H₂O时溶液吸热2.01 kJ，忽略散热，中和反应ΔH≈−2.01/0.050＝−40.2 kJ·mol⁻¹。'],

  'H3_STOICH:0:3:0': ['0.50 mol·L⁻¹溶液取0.200 L，溶质n＝cV＝0.100 mol。'],
  'H3_STOICH:0:3:1': ['0.100 mol溶质配成0.200 L溶液，c＝n/V＝0.50 mol·L⁻¹。'],
  'H3_STOICH:5:0:0': ['ρ＝1.20 g·cm⁻³、w＝0.10、M＝60 g·mol⁻¹时，c＝1000ρw/M＝2.0 mol·L⁻¹。'],
  'H3_STOICH:5:0:1': ['c＝2.0 mol·L⁻¹、M＝60 g·mol⁻¹、ρ＝1.20 g·cm⁻³时，w＝cM/(1000ρ)＝0.10。'],

  'H1_SOLUTION_CONCENTRATION:0:0:0': ['0.020 mol NaCl配成0.100 L溶液，c(NaCl)＝0.020/0.100＝0.20 mol·L⁻¹。'],
  'H1_SOLUTION_CONCENTRATION:0:0:1': ['配制100 mL NaCl溶液时，公式中的V是容量瓶定容后的100 mL，不是预先加入的水量。'],
  'H1_SOLUTION_CONCENTRATION:0:0:2': ['从0.20 mol·L⁻¹均一NaCl溶液中取出20 mL，所取部分的浓度仍为0.20 mol·L⁻¹。'],
  'H1_SOLUTION_CONCENTRATION:0:0:3': ['0.10 mol·L⁻¹ Na₂SO₄溶液中，c(Na⁺)≈0.20、c(SO₄²⁻)≈0.10 mol·L⁻¹。'],
  'H1_SOLUTION_CONCENTRATION:2:0:0': ['20 mL 1.0 mol·L⁻¹ NaCl溶液加水至100 mL，c₂＝c₁V₁/V₂＝0.20 mol·L⁻¹。'],
  'H1_SOLUTION_CONCENTRATION:2:0:1': ['两份NaCl溶液的溶质分别为0.10和0.20 mol，题给混合后总体积0.300 L，c＝0.30/0.300＝1.0 mol·L⁻¹。'],
  'H1_SOLUTION_CONCENTRATION:2:0:2': ['50 mL 1.0 mol·L⁻¹ HCl与50 mL 1.0 mol·L⁻¹ NaOH混合，先各算0.050 mol并中和，再处理剩余粒子。'],
}
