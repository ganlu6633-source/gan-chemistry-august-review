import unittest

try:
    from scripts.question_integrity_preflight import candidate_flags
except ModuleNotFoundError:
    from question_integrity_preflight import candidate_flags


class QuestionIntegrityPreflightTests(unittest.TestCase):
    def test_flags_missing_formula_after_option_colon(self):
        flags = candidate_flags(
            "下列说法正确的是\nA．分子间氢键可表示为：\nB．杂化方式为sp³",
            ["分子间氢键可表示为：", "杂化方式为sp³", "丙", "丁"],
        )
        self.assertIn("option_formula_missing_after_colon", flags)

    def test_flags_bare_reaction_steps_and_missing_value(self):
        flags = candidate_flags(
            "某反应分三步进行：\n①\n②\n③\n当温度为时，测定速率。",
            ["甲", "乙", "丙", "丁"],
        )
        self.assertEqual(flags, ["bare_reaction_steps", "missing_value_after_wei"])

    def test_does_not_flag_ion_charge_or_wrapped_equation(self):
        flags = candidate_flags(
            "方程式正确的是\nA．充电时的反应为：\nPb²⁺ + 2H₂O − 2e⁻ → PbO₂ + 4H⁺\nB．溶液含H+",
            [
                "TiCl4+(x+2)H2O=TiO2·xH2O↓+4H++4Cl-",
                "Pb2++2H2O-2e-=PbO2+4H+",
                "溶液含H+",
                "Na+",
            ],
            "所以阳极放出H+。",
        )
        self.assertEqual(flags, [])

    def test_flags_hanging_reaction_but_not_finished_charge(self):
        self.assertIn(
            "option_reaction_missing_product",
            candidate_flags("下列反应正确的是", ["H₂ + O₂ →", "H₂O", "H+", "Cl-"]),
        )

    def test_flags_disappeared_formula_before_or_after_option_text(self):
        flags = candidate_flags(
            "下列说法正确的是\nA．，升高温度，平衡逆移\nB．，则",
            ["，升高温度，平衡逆移", "，则", "该条件下", "电解质溶液"],
        )
        self.assertIn("option_starts_after_lost_formula", flags)
        self.assertIn("option_ends_before_missing_formula", flags)

    def test_does_not_flag_complete_chemistry_sentence_with_then(self):
        self.assertEqual(
            candidate_flags(
                "根据题图判断正确的是",
                ["若升高温度，则平衡向左移动", "该条件下反应能自发进行", "C项", "D项"],
            ),
            [],
        )

    def test_flags_species_erased_from_original_chemistry_prose(self):
        flags = candidate_flags(
            "已知：为浅黄色粉末，可利用反应制备。",
            ["反应ⅱ中脱去步骤的活化能为2.69 eV", "由①到②，生成并消耗，故变红", "说明：②>③", "甲"],
            "中间体生成和，此时能量上升；随后转化为，溶液褪色。",
        )
        self.assertEqual(
            flags,
            [
                "comparison_quantity_missing",
                "generated_species_missing",
                "known_species_missing",
                "preparation_reaction_missing",
                "removed_species_missing",
                "transformed_species_missing",
            ],
        )

    def test_keeps_complete_species_and_reaction_descriptions(self):
        self.assertEqual(
            candidate_flags(
                "已知：[FeCl₄]⁻为黄色，可利用反应Ga₂O₃+2NH₃⇌2GaN+3H₂O制备GaN。",
                [
                    "反应ⅱ中H₂O(g)脱去步骤的活化能为2.69 eV",
                    "由①到②，生成[Fe(SCN)]²⁺并消耗[FeCl₄]⁻",
                    "说明c(Fe³⁺)：②>③",
                    "Ga₂O₃(s)+2NH₃(g)⇌2GaN(s)+3H₂O(g)",
                ],
                "Ga₂O₂NH生成Ga₂ON₂H₂和H₂O；之后转化为GaN，溶液中[Fe(SCN)]²⁺褪色。",
            ),
            [],
        )

    def test_flags_disappeared_cobalt_and_chromium_formula_objects(self):
        cobalt = candidate_flags(
            "探究催化剂能否催化的分解。①可催化的分解。",
            ["不能催化的分解", "可能是与发生氧化还原反应", "丙", "丁"],
            "实验可证明易转化为：+4=+2+8H₂O。",
        )
        self.assertIn("catalyzed_species_missing", cobalt)
        self.assertIn("reacting_species_missing", cobalt)
        self.assertIn("reaction_species_missing_before_coefficient", cobalt)

        chromium = candidate_flags(
            "是两性氢氧化物。某溶液中与的总和为c。",
            ["由M点可以计算", "乙", "丙", "丁"],
            "发生反应：2+10+H₂O₂=2+4+18H₂O。",
        )
        self.assertIn("amphoteric_subject_missing", chromium)
        self.assertIn("summed_species_missing", chromium)
        self.assertIn("reaction_species_missing_before_coefficient", chromium)

    def test_keeps_complete_catalyst_species_and_balance(self):
        self.assertEqual(
            candidate_flags(
                "Co²⁺可催化H₂O₂的分解，Cr(OH)₃是两性氢氧化物。",
                ["H₂O₂与Co²⁺发生氧化还原反应", "甲", "乙", "丙"],
                "反应：2Cr(OH)₃+4OH⁻=2[Cr(OH)₄]⁻+2H₂O。",
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
