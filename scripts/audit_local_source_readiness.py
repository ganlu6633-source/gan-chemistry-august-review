#!/usr/bin/env python3
"""Summarize local chemistry source readiness without exporting question text.

The 2026-08-15 split bank is a candidate index, not a publication manifest.
This audit deliberately reports evidence gaps rather than promoting rows.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from pathlib import Path

GRADES = ("初三", "高一", "高二", "高三")


def audit(path: Path, items_out: Path | None = None) -> dict:
    by_grade: dict[str, Counter] = defaultdict(Counter)
    types: dict[str, Counter] = defaultdict(Counter)
    source_sets: dict[str, set[str]] = defaultdict(set)
    knowledge: dict[str, set[str]] = defaultdict(set)
    missing_answer_examples: dict[str, list[str]] = defaultdict(list)
    item_rows: list[dict[str, str]] = []
    with path.open(encoding="utf-8-sig") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            grade = str(row.get("gradeLevel") or "未标年段")
            counts = by_grade[grade]
            counts["indexed"] += 1
            kind = str(row.get("type") or "unknown")
            types[grade][kind] += 1
            source_sets[grade].add(str(row.get("sourceSetID") or ""))
            knowledge[grade].update(str(point) for point in row.get("knowledgePoints") or [] if point)
            options = row.get("options")
            option_texts = [
                option if isinstance(option, str) else option.get("text", "") if isinstance(option, dict) else ""
                for option in options or []
            ] if isinstance(options, list) else []
            four_options = len(option_texts) == 4 and all(
                isinstance(option, str) and option.strip() for option in option_texts
            )
            if four_options:
                counts["four_options"] += 1
            unresolved_image = any("[[IMAGE:" in str(value) for value in [row.get("stem"), *option_texts])
            if unresolved_image:
                counts["contains_unresolved_image_marker"] += 1
            answer_index = row.get("answerIndex")
            answer_letter = str(row.get("answerLetter") or "").strip().upper()
            # This source index numbers answerIndex from 1 through 4.
            has_answer = (isinstance(answer_index, int) and not isinstance(answer_index, bool) and answer_index in range(1, 5)) or (answer_letter in "ABCD" and len(answer_letter) == 1)
            if has_answer:
                counts["answer_index_or_letter"] += 1
            has_explanation = bool(str(row.get("explain") or "").strip() or row.get("explanationAssetRefs"))
            if has_explanation:
                counts["has_explanation"] += 1
            if four_options and has_answer:
                counts["four_option_answer_candidates"] += 1
            if four_options and has_answer and has_explanation and not unresolved_image:
                counts["metadata_complete_without_image_markers"] += 1
            if isinstance(answer_index, int) and answer_index in range(1, 5) and answer_letter in "ABCD" and len(answer_letter) == 1 and "ABCD"[answer_index - 1] != answer_letter:
                counts["answer_index_letter_conflict"] += 1
            else:
                if len(missing_answer_examples[grade]) < 5:
                    missing_answer_examples[grade].append(str(row.get("sourceRef") or f"line:{line_number}"))
            if row.get("reviewStatus") == "候选题源，入学生端前逐题核对":
                counts["requires_manual_verification"] += 1
            if items_out is not None:
                gaps = []
                if not four_options:
                    gaps.append("非四选一：需改编并核对")
                if not has_answer:
                    gaps.append("缺可确认答案")
                if not has_explanation:
                    gaps.append("缺解析")
                if unresolved_image:
                    gaps.append("图片标记未转成题面")
                gaps.append("需对照原卷和答案逐题核验")
                item_rows.append({
                    "年段": grade,
                    "题源编号": str(row.get("sourceRef") or ""),
                    "题源标题": str(row.get("sourceTitle") or ""),
                    "原题号": str(row.get("questionNo") or ""),
                    "题型": kind,
                    "知识点标签": "、".join(str(point) for point in row.get("knowledgePoints") or []),
                    "待处理": "；".join(gaps),
                })
    if items_out is not None:
        items_out.parent.mkdir(parents=True, exist_ok=True)
        with items_out.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=["年段", "题源编号", "题源标题", "原题号", "题型", "知识点标签", "待处理"])
            writer.writeheader()
            writer.writerows(item_rows)
    return {
        "source": str(path),
        "grades": {
            grade: {
                **by_grade[grade],
                "source_sets": len(source_sets[grade] - {""}),
                "knowledge_labels": len(knowledge[grade]),
                "question_types": dict(types[grade].most_common()),
                "examples_needing_answer_or_options": missing_answer_examples[grade],
            }
            for grade in (*GRADES, *(grade for grade in by_grade if grade not in GRADES))
            if by_grade[grade]
        },
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--items-out", type=Path, help="Private CSV ledger of every indexed candidate; no question text is exported")
    args = parser.parse_args()
    print(json.dumps(audit(args.source, args.items_out), ensure_ascii=False, indent=2))
