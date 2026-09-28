import unittest

from PIL import Image, ImageDraw

from scripts.question_image_gap_preflight import suspicious_inner_gap


class QuestionImageGapPreflightTest(unittest.TestCase):
    def test_flags_large_gap_between_question_fragments(self):
        image = Image.new("RGB", (900, 720), "white")
        draw = ImageDraw.Draw(image)
        draw.rectangle((50, 20, 800, 65), fill="black")
        draw.rectangle((50, 555, 800, 610), fill="black")
        gap = suspicious_inner_gap(image)
        self.assertIsNotNone(gap)
        self.assertGreater(gap[0], 400)

    def test_does_not_flag_normal_line_spacing(self):
        image = Image.new("RGB", (900, 720), "white")
        draw = ImageDraw.Draw(image)
        for top in range(25, 690, 75):
            draw.rectangle((50, top, 800, top + 18), fill="black")
        self.assertIsNone(suspicious_inner_gap(image))

    def test_ignores_outer_margin(self):
        image = Image.new("RGB", (900, 720), "white")
        draw = ImageDraw.Draw(image)
        for top in (300, 360, 420):
            draw.rectangle((50, top, 800, top + 20), fill="black")
        self.assertIsNone(suspicious_inner_gap(image))


if __name__ == "__main__":
    unittest.main()
