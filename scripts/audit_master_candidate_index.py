#!/usr/bin/env python3
"""Prioritize four-option candidates in the private full-library SQLite index.

This never reads answer text or changes review/delivery state. A candidate with
all metadata fields remains unverified until the original page is inspected.
"""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path


def audit(index: Path, output: Path) -> dict:
    connection = sqlite3.connect(f"file:{index.as_posix()}?mode=ro", uri=True)
    connection.execute("pragma query_only=on")
    groups: dict[tuple[str, str], Counter] = defaultdict(Counter)
    source_ids: set[str] = set()
    for grade_json, source_id, question_type, has_assets in connection.execute(
        """select grade_hints_json,source_id,question_type,has_assets
           from questions
           where option_count=4 and has_answer=1 and has_explanation=1"""
    ):
        try:
            grades = json.loads(grade_json or "[]")
        except json.JSONDecodeError:
            grades = []
        grade = grades[0] if len(grades) == 1 else "多年段待确认" if grades else "年段待确认"
        key = (grade, str(source_id or ""))
        groups[key]["candidates"] += 1
        groups[key][str(question_type or "unknown")] += 1
        groups[key]["has_assets"] += int(bool(has_assets))
        source_ids.add(str(source_id or ""))
    source_rows = {
        row[0]: row[1:]
        for row in connection.execute("select source_id,file_name,relative_path,review_status from sources")
        if row[0] in source_ids
    }
    connection.close()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8-sig", newline="") as stream:
        fields = ["年段判断", "题源编号", "题源文件", "相对路径", "候选题数", "选择题候选", "综合题候选", "带资源标记", "来源审核状态"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for (grade, source_id), count in sorted(groups.items(), key=lambda item: (item[0][0], -item[1]["candidates"], item[0][1])):
            file_name, relative_path, review_status = source_rows.get(source_id, ("", "", ""))
            writer.writerow({
                "年段判断": grade, "题源编号": source_id, "题源文件": file_name,
                "相对路径": relative_path, "候选题数": count["candidates"],
                "选择题候选": count["choice_candidate"], "综合题候选": count["composite_candidate"],
                "带资源标记": count["has_assets"], "来源审核状态": review_status,
            })
    by_grade = Counter()
    for (grade, _), counts in groups.items():
        by_grade[grade] += counts["candidates"]
    return {"candidates": sum(by_grade.values()), "source_sets": len(source_ids), "by_grade": dict(by_grade)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("index", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(audit(args.index, args.output), ensure_ascii=False, indent=2))
