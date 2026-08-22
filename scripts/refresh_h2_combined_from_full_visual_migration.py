#!/usr/bin/env python3
"""Refresh the 200 legacy H2 rows from a hash-bound full-visual migration.

This is a local-only transformer.  It never connects to Supabase and never
publishes.  The migration's ``$full_visual_expected$`` JSON is treated as the
authoritative current student text only after all embedded hashes, row counts,
identity joins, marker contracts, and SQL post-migration assertions are
validated.

The input row order and every field outside the six public-text aliases are
preserved.  Matching is deliberately narrow:

    migration.source_manifest_id == input.candidate_id

The script refuses partial or duplicate matches.  It also records ordinary
A/B/C/D marker coverage separately from original combination questions, whose
source-faithful explanations are audited by their required ①/②/... markers.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


EXPECTED_TOTAL_ROWS = 363
EXPECTED_MIGRATION_ROWS = 325
EXPECTED_H1_ROWS = 125
EXPECTED_H2_ROWS = 200
EXPECTED_GLOBAL_AUDIT_COUNTS = {"PASS": 57, "FAIL": 268}
REPLACED_FIELDS = {
    "question_text",
    "student_question_text",
    "options",
    "correct_option",
    "analysis_text",
    "content_fingerprint",
}
SHA256_RE = re.compile(r"[0-9a-f]{64}")
CONTENT_WHITESPACE = frozenset(" \t\n\v\f\r\u00a0\u3000")
EXPECTED_BLOCK_RE = re.compile(
    r"\$full_visual_expected\$(\[.*?\])\$full_visual_expected\$::jsonb",
    re.DOTALL,
)
FORBIDDEN_EXPLANATION_RE = re.compile(
    r"学科网|股份有限公司|原题来源|来源[：:]|题面PDF|解析PDF|原解析图|下一题|"
    r"物理页\s*[0-9]+|练[·・]高考真题|题组[一二三四五六七八九十]|�|[\ue000-\uf8ff]"
)
STANDALONE_ANSWER_ANALYSIS_RE = re.compile(
    r"^\s*(?:答案解析|答案|解析)\s*(?:[：:]|\s|$)", re.MULTILINE
)
OPTION_LETTERS = "ABCD"


class RefreshError(ValueError):
    """The local refresh cannot be completed without weakening an invariant."""


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_text(value: str) -> str:
    return sha256_bytes(value.encode("utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def normalized(value: str) -> str:
    return "".join(ch for ch in value if ch not in CONTENT_WHITESPACE).replace("\uf028", "(").replace("\uf029", ")")


def release_manifest_field(value: object | None) -> str:
    text = "" if value is None else str(value)
    return f"{len(text)}:{text}"


def release_item_sha256(values: Iterable[object | None]) -> str:
    return sha256_text("".join(release_manifest_field(value) for value in values))


def legacy_content_fingerprint(stem: str, options: list[str]) -> str:
    if len(options) != 4:
        raise RefreshError("legacy fingerprint contract requires four options")
    return release_item_sha256([normalized(stem), *(normalized(option) for option in options)])


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RefreshError(message)


def load_json_list(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(data, list), f"input is not a JSON list: {path}")
    require(all(isinstance(row, dict) for row in data), "every input row must be a JSON object")
    return data


def extract_expected_rows(sql: str) -> list[dict[str, Any]]:
    matches = EXPECTED_BLOCK_RE.findall(sql)
    require(len(matches) == 1, f"expected exactly one $full_visual_expected$ block, found {len(matches)}")
    data = json.loads(matches[0])
    require(isinstance(data, list), "embedded full-visual expected payload is not a list")
    require(all(isinstance(row, dict) for row in data), "embedded expected payload contains a non-object row")
    return data


def option_marker_positions(explanation: str) -> tuple[dict[str, list[int]], list[str]]:
    positions: dict[str, list[int]] = {}
    errors: list[str] = []
    previous = -1
    for letter in OPTION_LETTERS:
        # Accepted forms include A．, A., A、, A：, A:, A项/A 项,
        # and the explicitly requested A正确/A错误 forms.
        pattern = re.compile(
            rf"(?<![A-Za-z0-9]){letter}\s*(?:[．.、:：]|项|(?=正确|错误))"
        )
        found = [match.start() for match in pattern.finditer(explanation)]
        positions[letter] = found
        if not found:
            errors.append(f"MISSING_{letter}_SEGMENT")
            continue
        if found[0] <= previous:
            errors.append(f"OUT_OF_ORDER_{letter}_SEGMENT")
        previous = found[0]
    return positions, errors


def combination_marker_positions(explanation: str, required_markers: list[str]) -> tuple[dict[str, list[int]], list[str]]:
    positions: dict[str, list[int]] = {}
    errors: list[str] = []
    previous = -1
    for marker in required_markers:
        # Source analyses often place the next numbered statement after a
        # semicolon rather than on a fresh line.  The migration contract uses
        # ordered ``strpos`` checks, so mirror that exact anywhere-in-text
        # semantics here.
        pattern = re.compile(re.escape(marker))
        found = [match.start() for match in pattern.finditer(explanation)]
        positions[marker] = found
        if not found:
            errors.append(f"MISSING_{marker}_SEGMENT")
            continue
        if found[0] <= previous:
            errors.append(f"OUT_OF_ORDER_{marker}_SEGMENT")
        previous = found[0]
    return positions, errors


def assert_sql_contract(sql: str) -> list[str]:
    required_snippets = [
        "full visual release specification is not H1=125/H2=200",
        "full visual expected mapping is incomplete",
        "replacement release inventory is not 325 questions/650 assets/325 ledger rows",
        "PASS byte preservation or FAIL hash binding failed",
        "forbidden notation, source/page text, garbling, or cross-question fragment remains",
        "an ordinary single-choice explanation lacks ordered A/B/C/D segments",
        "a combination question lacks ordered statement-by-statement analysis",
        "commit;",
    ]
    missing = [snippet for snippet in required_snippets if snippet not in sql]
    require(not missing, f"migration is missing required post-apply assertions: {missing}")
    return required_snippets


def validate_migration_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    require(len(rows) == EXPECTED_MIGRATION_ROWS, f"migration rows must be {EXPECTED_MIGRATION_ROWS}, got {len(rows)}")
    grade_counts = Counter(str(row.get("grade_band", "")) for row in rows)
    require(grade_counts == Counter({"高一": EXPECTED_H1_ROWS, "高二": EXPECTED_H2_ROWS}), f"unexpected grade counts: {dict(grade_counts)}")
    audit_counts = Counter(str(row.get("audit_status", "")) for row in rows)
    require(audit_counts == Counter(EXPECTED_GLOBAL_AUDIT_COUNTS), f"unexpected audit-status counts: {dict(audit_counts)}")

    identity_fields = ("source_manifest_id", "canonical_source_id", "old_question_id", "new_question_id")
    for field in identity_fields:
        values = [row.get(field) for row in rows]
        require(all(isinstance(value, str) and value for value in values), f"blank {field} in migration")
        require(len(values) == len(set(values)), f"duplicate {field} in migration")

    hash_errors: list[dict[str, str]] = []
    structure_errors: list[dict[str, str]] = []
    for row in rows:
        source_id = str(row["source_manifest_id"])
        stem = row.get("expected_stem")
        options = row.get("expected_options")
        explanation = row.get("expected_explanation")
        correct_option = row.get("correct_option")
        fingerprint = str(row.get("expected_content_fingerprint", "")).lower()
        explanation_sha = str(row.get("expected_explanation_sha256", "")).lower()
        baseline_sha = str(row.get("baseline_explanation_sha256", "")).lower()
        audit_status = str(row.get("audit_status", ""))
        if not isinstance(stem, str) or not stem.strip():
            structure_errors.append({"source_manifest_id": source_id, "reason": "BLANK_EXPECTED_STEM"})
            continue
        if not isinstance(options, list) or len(options) != 4 or not all(isinstance(option, str) and option.strip() for option in options):
            structure_errors.append({"source_manifest_id": source_id, "reason": "INVALID_EXPECTED_OPTIONS"})
            continue
        if not isinstance(explanation, str) or not explanation.strip():
            structure_errors.append({"source_manifest_id": source_id, "reason": "BLANK_EXPECTED_EXPLANATION"})
            continue
        if type(correct_option) is not int or correct_option not in range(4):
            structure_errors.append({"source_manifest_id": source_id, "reason": "INVALID_CORRECT_OPTION"})
        if not SHA256_RE.fullmatch(fingerprint):
            hash_errors.append({"source_manifest_id": source_id, "reason": "INVALID_CONTENT_FINGERPRINT"})
        elif legacy_content_fingerprint(stem, options) != fingerprint:
            hash_errors.append({"source_manifest_id": source_id, "reason": "CONTENT_FINGERPRINT_MISMATCH"})
        if not SHA256_RE.fullmatch(explanation_sha) or sha256_text(explanation) != explanation_sha:
            hash_errors.append({"source_manifest_id": source_id, "reason": "EXPLANATION_SHA256_MISMATCH"})
        if not SHA256_RE.fullmatch(baseline_sha):
            hash_errors.append({"source_manifest_id": source_id, "reason": "INVALID_BASELINE_EXPLANATION_SHA256"})
        elif audit_status == "PASS" and baseline_sha != explanation_sha:
            hash_errors.append({"source_manifest_id": source_id, "reason": "PASS_EXPLANATION_NOT_BYTE_IDENTICAL"})
        elif audit_status == "FAIL" and baseline_sha == explanation_sha:
            hash_errors.append({"source_manifest_id": source_id, "reason": "FAIL_EXPLANATION_NOT_REPLACED"})
    require(not structure_errors, f"migration expected-field errors: {structure_errors[:5]}")
    require(not hash_errors, f"migration hash-contract errors: {hash_errors[:5]}")
    return {
        "gradeCounts": dict(sorted(grade_counts.items())),
        "auditStatusCounts": dict(sorted(audit_counts.items())),
        "allExpectedFieldHashesPass": True,
    }


def audit_h2_explanations(rows: list[dict[str, Any]]) -> dict[str, Any]:
    ordinary_passed: list[str] = []
    combination_passed: list[str] = []
    strict_abcd_not_applicable: list[str] = []
    blocked: list[dict[str, Any]] = []
    marker_details: list[dict[str, Any]] = []

    for row in rows:
        source_id = str(row["source_manifest_id"])
        explanation = str(row["expected_explanation"])
        cross_reasons: list[str] = []
        if FORBIDDEN_EXPLANATION_RE.search(explanation):
            cross_reasons.append("FORBIDDEN_SOURCE_OR_CROSS_QUESTION_FRAGMENT")
        if STANDALONE_ANSWER_ANALYSIS_RE.search(explanation):
            cross_reasons.append("STANDALONE_ANSWER_OR_ANALYSIS_HEADER")

        mode = str(row.get("segment_mode", ""))
        if mode == "ABCD":
            positions, marker_errors = option_marker_positions(explanation)
            reasons = cross_reasons + marker_errors
            marker_details.append({
                "source_manifest_id": source_id,
                "segment_mode": mode,
                "firstMarkerPositions": {key: (values[0] if values else None) for key, values in positions.items()},
                "status": "PASS" if not reasons else "BLOCKED",
                "reasons": reasons,
            })
            if reasons:
                blocked.append({"source_manifest_id": source_id, "reasons": reasons})
            else:
                ordinary_passed.append(source_id)
        elif mode == "COMBINATION":
            required_markers = row.get("required_markers")
            if not isinstance(required_markers, list) or len(required_markers) < 2 or not all(isinstance(marker, str) and marker for marker in required_markers):
                positions, marker_errors = {}, ["INVALID_REQUIRED_MARKERS"]
            else:
                positions, marker_errors = combination_marker_positions(explanation, required_markers)
            reasons = cross_reasons + marker_errors
            strict_abcd_not_applicable.append(source_id)
            marker_details.append({
                "source_manifest_id": source_id,
                "segment_mode": mode,
                "requiredMarkers": required_markers,
                "firstMarkerPositions": {key: (values[0] if values else None) for key, values in positions.items()},
                "strictAbcdAudit": "NOT_APPLICABLE_ORIGINAL_COMBINATION_TYPE",
                "status": "PASS" if not reasons else "BLOCKED",
                "reasons": reasons,
            })
            if reasons:
                blocked.append({"source_manifest_id": source_id, "reasons": reasons})
            else:
                combination_passed.append(source_id)
        else:
            blocked.append({"source_manifest_id": source_id, "reasons": [f"UNSUPPORTED_SEGMENT_MODE:{mode}"]})

    return {
        "ordinaryAbcdCount": len(ordinary_passed),
        "ordinaryAbcdPassedCount": len(ordinary_passed),
        "combinationCount": len(strict_abcd_not_applicable),
        "combinationStatementMarkerPassedCount": len(combination_passed),
        "strictAbcdNotApplicableCombinationIds": sorted(strict_abcd_not_applicable),
        "blocked": blocked,
        "details": marker_details,
    }


def stripped_row(row: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in row.items() if key not in REPLACED_FIELDS}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="existing combined H2 selected_questions.json")
    parser.add_argument("--migration", type=Path, required=True, help="full-visual SQL migration")
    parser.add_argument("--output-dir", type=Path, required=True, help="new local-only output directory")
    args = parser.parse_args()

    input_path = args.input.resolve()
    migration_path = args.migration.resolve()
    output_dir = args.output_dir.resolve()
    require(input_path.is_file(), f"input does not exist: {input_path}")
    require(migration_path.is_file(), f"migration does not exist: {migration_path}")
    require(not output_dir.exists(), f"refusing to overwrite existing output directory: {output_dir}")

    original_rows = load_json_list(input_path)
    require(len(original_rows) == EXPECTED_TOTAL_ROWS, f"combined input must have {EXPECTED_TOTAL_ROWS} rows, got {len(original_rows)}")
    candidate_ids = [row.get("candidate_id") for row in original_rows]
    require(all(isinstance(value, str) and value for value in candidate_ids), "every combined row must have a nonblank candidate_id")
    require(len(candidate_ids) == len(set(candidate_ids)), "combined input contains duplicate candidate_id values")

    sql = migration_path.read_text(encoding="utf-8")
    sql_assertions = assert_sql_contract(sql)
    migration_rows = extract_expected_rows(sql)
    migration_validation = validate_migration_rows(migration_rows)
    h2_rows = [row for row in migration_rows if row["grade_band"] == "高二"]
    require(len(h2_rows) == EXPECTED_H2_ROWS, f"expected {EXPECTED_H2_ROWS} H2 migration rows, got {len(h2_rows)}")
    h2_by_id = {str(row["source_manifest_id"]): row for row in h2_rows}
    require(len(h2_by_id) == EXPECTED_H2_ROWS, "H2 migration source_manifest_id values are not unique")

    matched_input_ids = [str(row["candidate_id"]) for row in original_rows if row["candidate_id"] in h2_by_id]
    require(len(matched_input_ids) == EXPECTED_H2_ROWS, f"candidate_id join must match exactly {EXPECTED_H2_ROWS}, got {len(matched_input_ids)}")
    missing_migration_ids = sorted(set(h2_by_id) - set(matched_input_ids))
    require(not missing_migration_ids, f"migration H2 IDs missing from combined input: {missing_migration_ids[:10]}")

    explanation_audit = audit_h2_explanations(h2_rows)
    require(not explanation_audit["blocked"], f"migration explanation audit blocked rows: {explanation_audit['blocked'][:5]}")

    refreshed_rows = copy.deepcopy(original_rows)
    field_change_counts: Counter[str] = Counter()
    private_field_mismatches: list[str] = []
    answer_mismatches: list[dict[str, Any]] = []
    update_records: list[dict[str, Any]] = []
    for index, (before, after) in enumerate(zip(original_rows, refreshed_rows, strict=True)):
        candidate_id = str(before["candidate_id"])
        expected = h2_by_id.get(candidate_id)
        if expected is None:
            require(before == after, f"non-target row changed before refresh: {candidate_id}")
            continue

        option_list = list(expected["expected_options"])
        expected_letter = OPTION_LETTERS[int(expected["correct_option"])]
        current_answer = str(before.get("correct_option", "")).strip().upper()
        if current_answer != expected_letter:
            answer_mismatches.append({
                "candidate_id": candidate_id,
                "input_correct_option": before.get("correct_option"),
                "migration_correct_option": expected_letter,
            })

        replacements: dict[str, Any] = {
            "question_text": expected["expected_stem"],
            "student_question_text": expected["expected_stem"],
            "options": dict(zip(OPTION_LETTERS, option_list, strict=True)),
            "correct_option": expected_letter,
            "analysis_text": expected["expected_explanation"],
            "content_fingerprint": expected["expected_content_fingerprint"],
        }
        for field, value in replacements.items():
            if before.get(field) != value:
                field_change_counts[field] += 1
            after[field] = value

        if stripped_row(before) != stripped_row(after):
            private_field_mismatches.append(candidate_id)
        update_records.append({
            "inputIndex": index,
            "candidate_id": candidate_id,
            "audit_status": expected["audit_status"],
            "segment_mode": expected["segment_mode"],
            "expected_explanation_sha256": expected["expected_explanation_sha256"],
            "expected_content_fingerprint": expected["expected_content_fingerprint"],
        })

    require(not answer_mismatches, f"input answers differ from hash-bound migration: {answer_mismatches[:5]}")
    require(not private_field_mismatches, f"fields outside the public-text allowlist changed: {private_field_mismatches[:5]}")
    require(len(update_records) == EXPECTED_H2_ROWS, f"refresh wrote {len(update_records)} rows, expected {EXPECTED_H2_ROWS}")

    # Re-check the complete output rather than trusting the assignment loop.
    non_target_unchanged = 0
    target_exact = 0
    for before, after in zip(original_rows, refreshed_rows, strict=True):
        candidate_id = str(before["candidate_id"])
        expected = h2_by_id.get(candidate_id)
        if expected is None:
            require(before == after, f"non-target row changed: {candidate_id}")
            non_target_unchanged += 1
            continue
        expected_options_dict = dict(zip(OPTION_LETTERS, expected["expected_options"], strict=True))
        require(after["question_text"] == expected["expected_stem"], f"question_text refresh mismatch: {candidate_id}")
        require(after["student_question_text"] == expected["expected_stem"], f"student_question_text refresh mismatch: {candidate_id}")
        require(after["options"] == expected_options_dict, f"options refresh mismatch: {candidate_id}")
        require(after["correct_option"] == OPTION_LETTERS[int(expected["correct_option"])], f"correct_option refresh mismatch: {candidate_id}")
        require(after["analysis_text"] == expected["expected_explanation"], f"analysis_text refresh mismatch: {candidate_id}")
        require(after["content_fingerprint"] == expected["expected_content_fingerprint"], f"content fingerprint refresh mismatch: {candidate_id}")
        require(stripped_row(before) == stripped_row(after), f"private/source/image field drift: {candidate_id}")
        target_exact += 1

    require(target_exact == EXPECTED_H2_ROWS, f"post-refresh exact targets={target_exact}")
    require(non_target_unchanged == EXPECTED_TOTAL_ROWS - EXPECTED_H2_ROWS, f"post-refresh unchanged non-targets={non_target_unchanged}")

    selected_text = json.dumps(refreshed_rows, ensure_ascii=False, indent=2) + "\n"
    selected_sha = sha256_text(selected_text)
    h2_audit_counts = Counter(str(row["audit_status"]) for row in h2_rows)
    qa: dict[str, Any] = {
        "schemaVersion": "gan.h2-current-text-refresh-qa.v1",
        "status": "PASS",
        "localOnly": True,
        "databaseQueried": False,
        "published": False,
        "input": {
            "path": str(input_path),
            "sha256": sha256_file(input_path),
            "rowCount": len(original_rows),
        },
        "migration": {
            "path": str(migration_path),
            "sha256": sha256_file(migration_path),
            "embeddedRowCount": len(migration_rows),
            "h2RowCount": len(h2_rows),
            "validation": migration_validation,
            "h2AuditStatusCounts": dict(sorted(h2_audit_counts.items())),
            "auditStatusSemantics": "PASS preserves the old explanation byte-for-byte; FAIL is the old row being repaired by expected_explanation. Both expected rows are hash-bound current migration output.",
            "localSqlPostApplyAssertionsPresent": sql_assertions,
            "deploymentState": "NOT_QUERIED_LOCAL_ONLY",
        },
        "join": {
            "predicate": "migration.source_manifest_id == input.candidate_id",
            "matchedExactly": len(update_records),
            "missingMigrationIds": [],
            "duplicateInputCandidateIds": 0,
            "duplicateMigrationSourceManifestIds": 0,
        },
        "refresh": {
            "updatedRows": target_exact,
            "unchangedNonTargetRows": non_target_unchanged,
            "fieldChangeCounts": dict(sorted(field_change_counts.items())),
            "privateSourceAndImageFieldsPreserved": True,
            "answerAgreementCount": target_exact,
            "updatedIds": [record["candidate_id"] for record in update_records],
        },
        "explanationAudit": explanation_audit,
        "releaseBlockedIds": [item["source_manifest_id"] for item in explanation_audit["blocked"]],
        "output": {
            "selectedQuestions": str(output_dir / "selected_questions.json"),
            "selectedQuestionsSha256": selected_sha,
            "rowCount": len(refreshed_rows),
        },
        "updateRecords": update_records,
    }

    output_dir.mkdir(parents=True)
    selected_path = output_dir / "selected_questions.json"
    qa_path = output_dir / "refresh_qa_summary_20260822.json"
    selected_path.write_text(selected_text, encoding="utf-8", newline="\n")
    qa_path.write_text(json.dumps(qa, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({
        "status": "PASS",
        "selected_questions": str(selected_path),
        "qa_summary": str(qa_path),
        "row_count": len(refreshed_rows),
        "refreshed_count": target_exact,
        "unchanged_count": non_target_unchanged,
        "selected_questions_sha256": selected_sha,
        "ordinary_abcd_passed": explanation_audit["ordinaryAbcdPassedCount"],
        "combination_marker_passed": explanation_audit["combinationStatementMarkerPassedCount"],
        "blocked_ids": qa["releaseBlockedIds"],
    }, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RefreshError, FileNotFoundError, FileExistsError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
