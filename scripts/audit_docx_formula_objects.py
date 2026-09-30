#!/usr/bin/env python3
"""Locate formula and picture objects that plain DOCX text extraction can lose.

This is a source triage aid, not a correctness check.  Every reported object
still needs comparison with the original page before a question is released.
By default the report contains no question text; --include-preview is intended
only for a private local report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
M = "{http://schemas.openxmlformats.org/officeDocument/2006/math}"
V = "{urn:schemas-microsoft-com:vml}"
EQ_FIELD = re.compile(r"\bEQ\s+(?:\\|\S)", re.IGNORECASE)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _scan_part(name: str, xml: bytes, include_preview: bool) -> list[dict]:
    root = ET.fromstring(xml)
    found: list[dict] = []
    for ordinal, paragraph in enumerate(root.iter(W + "p"), 1):
        instructions = " ".join(
            node.text or "" for node in paragraph.iter(W + "instrText")
        )
        simple_fields = [node.attrib.get(W + "instr", "") for node in paragraph.iter(W + "fldSimple")]
        eq_count = len(EQ_FIELD.findall(instructions)) + sum(bool(EQ_FIELD.search(value)) for value in simple_fields)
        omml_count = sum(1 for _ in paragraph.iter(M + "oMath"))
        drawing_count = sum(1 for _ in paragraph.iter(W + "drawing"))
        picture_count = sum(1 for _ in paragraph.iter(W + "pict"))
        vml_count = sum(1 for _ in paragraph.iter(V + "shape"))
        if not (eq_count or omml_count or drawing_count or picture_count or vml_count):
            continue
        text = "".join(node.text or "" for node in paragraph.iter(W + "t"))
        item = {
            "part": name,
            "paragraph": ordinal,
            "paragraph_sha256": _sha256(ET.tostring(paragraph, encoding="utf-8")),
            "eq_field_count": eq_count,
            "omml_count": omml_count,
            "drawing_count": drawing_count,
            "picture_count": picture_count,
            "vml_shape_count": vml_count,
            "visible_text_characters": len(text.strip()),
            "review_required": True,
        }
        if include_preview:
            item["visible_text_preview"] = text.strip()[:100]
            item["field_instruction_preview"] = (instructions or " ".join(simple_fields))[:160]
        found.append(item)
    return found


def audit_docx(path: Path, include_preview: bool = False) -> dict:
    if not path.is_file():
        raise FileNotFoundError(path)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    with zipfile.ZipFile(path) as archive:
        parts = sorted(
            name for name in archive.namelist()
            if name == "word/document.xml"
            or re.fullmatch(r"word/(?:header|footer)\d+\.xml", name)
            or name in {"word/footnotes.xml", "word/endnotes.xml"}
        )
        if "word/document.xml" not in parts:
            raise ValueError(f"not a DOCX with word/document.xml: {path}")
        items = [item for name in parts for item in _scan_part(name, archive.read(name), include_preview)]
    return {
        "source": str(path.resolve()),
        "source_sha256": digest.hexdigest(),
        "counts": {
            "paragraphs_with_objects": len(items),
            "eq_fields": sum(item["eq_field_count"] for item in items),
            "omml_formulas": sum(item["omml_count"] for item in items),
            "drawings": sum(item["drawing_count"] for item in items),
            "pictures": sum(item["picture_count"] for item in items),
            "vml_shapes": sum(item["vml_shape_count"] for item in items),
        },
        "items": items,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", type=Path, help="Original .docx files to inspect")
    parser.add_argument("--json-out", type=Path, help="Save a local report; no question text by default")
    parser.add_argument("--include-preview", action="store_true", help="Include short source text and EQ field excerpts in the local report")
    args = parser.parse_args()
    results = []
    for source in args.sources:
        try:
            results.append(audit_docx(source, args.include_preview))
        except (OSError, ValueError, ET.ParseError, zipfile.BadZipFile) as exc:
            print(f"Cannot inspect {source}: {exc}", file=sys.stderr)
            return 2
    report = {"files": results, "requires_source_visual_review": True}
    output = json.dumps(report, ensure_ascii=False, indent=2)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
