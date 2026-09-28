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


if __name__ == "__main__":
    unittest.main()
