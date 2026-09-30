import tempfile
import unittest
import zipfile
from pathlib import Path

try:
    from scripts.audit_docx_formula_objects import audit_docx
except ModuleNotFoundError:
    from audit_docx_formula_objects import audit_docx


class AuditDocxFormulaObjectsTests(unittest.TestCase):
    def test_split_eq_field_omml_and_drawing_are_reported_without_question_text(self):
        xml = '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
          <w:body>
            <w:p><w:r><w:t>普通文字</w:t></w:r></w:p>
            <w:p><w:r><w:t>硫酸根</w:t></w:r><w:r><w:instrText>EQ \\o</w:instrText></w:r>
              <w:r><w:instrText>\\al(2,-)</w:instrText></w:r></w:p>
            <w:p><m:oMath><m:r><m:t>2</m:t></m:r></m:oMath></w:p>
            <w:p><w:r><w:drawing/></w:r></w:p>
          </w:body></w:document>'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "example.docx"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("word/document.xml", xml)
            result = audit_docx(source)
            self.assertEqual(result["counts"]["paragraphs_with_objects"], 3)
            self.assertEqual(result["counts"]["eq_fields"], 1)
            self.assertEqual(result["counts"]["omml_formulas"], 1)
            self.assertEqual(result["counts"]["drawings"], 1)
            self.assertNotIn("visible_text_preview", result["items"][0])
            self.assertEqual(result["items"][0]["paragraph"], 2)
            preview = audit_docx(source, include_preview=True)
            self.assertEqual(preview["items"][0]["visible_text_preview"], "硫酸根")

    def test_missing_document_part_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.docx"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("word/styles.xml", "<styles/>")
            with self.assertRaisesRegex(ValueError, "not a DOCX"):
                audit_docx(source)


if __name__ == "__main__":
    unittest.main()
