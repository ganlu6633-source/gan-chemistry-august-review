#!/usr/bin/env python3
"""Build a deterministic, local-only private REVIEW question release.

The builder deliberately has no database client, SQL writer, or publishing
operation.  It accepts audited JSON/JSONL rows, verifies the exact source
images and immutable source identity, blocks semantic duplicates, and emits
three independent manifests:

* questions.jsonl: canonical question records (no source locator/path fields)
* assets.jsonl: student question images and teacher-only analysis images
* release_items.jsonl: hashes plus private source provenance

The input aliases cover the selected_questions manifests used by the H1/H2/H3
original-question builders.  Counts and question types are never hard-coded.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import re
import shutil
import sys
import tempfile
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from PIL import Image


SCHEMA_VERSION = "gan.private-review-release.v1"
REVISION_CONTRACTS = {"v1_assets", "v2_explanation_assets"}
GRADE_CODES = {"高一": "H1", "高二": "H2", "高三": "H3"}
CONTENT_WHITESPACE = frozenset(" \t\n\v\f\r\u00a0\u3000")
SHA256_RE = re.compile(r"[0-9a-fA-F]{64}")
CONCEPT_RE = re.compile(r"__C(\d+)$")
MAX_WIDTH = 6000
MAX_HEIGHT = 12000
MAX_BASE64_BYTES = 4_000_000


class BuildError(ValueError):
    """An audited input cannot safely enter a release."""


@dataclass(frozen=True)
class InputRow:
    row: dict[str, Any]
    input_path: Path
    input_sha256: str
    row_number: int


@dataclass(frozen=True)
class AssetPayload:
    role: str
    source_path: Path
    source_sha256: str
    output_payload: bytes | None
    output_sha256: str
    width: int
    height: int
    output_mime_type: str


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def normalized(value: str) -> str:
    return "".join(ch for ch in value if ch not in CONTENT_WHITESPACE).replace("\uf028", "(").replace("\uf029", ")")


def release_manifest_field(value: object | None) -> str:
    text = "" if value is None else str(value)
    return f"{len(text)}:{text}"


def release_item_sha256(values: Iterable[object | None]) -> str:
    canonical = "".join(release_manifest_field(value) for value in values)
    return sha256_bytes(canonical.encode("utf-8"))


def legacy_content_fingerprint(stem: str, options: list[str]) -> str:
    """Mirror the existing Postgres/Python four-option fingerprint contract."""
    if len(options) != 4:
        raise BuildError("legacy content fingerprint requires exactly four options")
    return release_item_sha256([normalized(stem), *(normalized(option) for option in options)])


def content_fingerprint(question_type: str, stem: str, options: list[str]) -> tuple[str, str]:
    if len(options) == 4:
        return legacy_content_fingerprint(stem, options), "db_v1_four_option"
    # The portable contract permits original non-four-option types without
    # coercing them into a multiple-choice or judgment question.
    return (
        release_item_sha256(
            ["typed_v1", normalized(question_type), normalized(stem), len(options), *(normalized(option) for option in options)]
        ),
        "portable_typed_v1",
    )


def question_revision_token(
    fingerprint: str,
    render_mode: str,
    refs: list[dict[str, Any]],
    question_asset_sha256: str,
    analysis_asset_sha256: str,
    *,
    explanation: str,
    revision_contract: str,
) -> str:
    if revision_contract not in REVISION_CONTRACTS:
        raise BuildError(f"unsupported revision contract: {revision_contract}")
    question_ref = next(ref for ref in refs if ref["kind"] == "question_image")
    analysis_ref = next(ref for ref in refs if ref["kind"] == "analysis_image")
    fields: list[object | None] = [fingerprint]
    if revision_contract == "v2_explanation_assets":
        fields.append(explanation)
    fields.extend(
        [
            render_mode,
            question_ref["kind"],
            question_ref["path"],
            question_ref["alt"],
            question_ref["width"],
            question_ref["height"],
            question_asset_sha256,
            analysis_ref["kind"],
            analysis_ref["path"],
            analysis_ref["alt"],
            analysis_ref["width"],
            analysis_ref["height"],
            analysis_asset_sha256,
        ]
    )
    return release_item_sha256(fields)


def database_release_item_sha256(
    *,
    question_id: str,
    mother_id: str,
    skill_id: str,
    concept_key: str,
    level: int,
    grade_band: str,
    stem: str,
    options: list[str],
    correct_option: int,
    explanation: str,
    scaffold: str,
    source_kind: str,
    render_mode: str,
    source_item_key: str,
    content_fingerprint_value: str,
    revision_token: str,
    source_info: dict[str, str],
    refs: list[dict[str, Any]],
    canonical_source_id_value: str,
    question_asset_sha256: str,
    analysis_asset_sha256: str,
) -> str:
    """Mirror ``app_private.chem_h3_release_item_sha256`` exactly.

    Activation recomputes this digest from the staged public row and both
    private assets. Local-only provenance fields must never enter it.
    """
    if len(options) != 4 or correct_option not in range(4):
        raise BuildError("database release-item digest requires one four-option answer")
    question_ref = next(ref for ref in refs if ref["kind"] == "question_image")
    analysis_ref = next(ref for ref in refs if ref["kind"] == "analysis_image")
    fields: list[object | None] = [
        question_id,
        mother_id,
        skill_id,
        concept_key,
        level,
        grade_band,
        stem,
        *options,
        correct_option,
        explanation,
        scaffold,
        source_kind,
        render_mode,
        source_item_key,
        content_fingerprint_value,
        revision_token,
        source_info["title"],
        source_info["exam"],
        source_info["questionNo"],
        source_info["locator"],
        source_info["year"],
        source_info["conceptLabel"],
        source_info["sourceMarkerStyle"],
        source_info["transcriptionPolicy"],
        source_info["optionTranscriptionPolicy"],
        source_info["transcriptionAuditMethod"],
        source_info["sourcePairingStatus"],
        source_info["sourceMarkerLabel"],
        question_ref["path"],
        question_ref["alt"],
        question_ref["width"],
        question_ref["height"],
        analysis_ref["path"],
        analysis_ref["alt"],
        analysis_ref["width"],
        analysis_ref["height"],
        canonical_source_id_value,
        question_asset_sha256,
        analysis_asset_sha256,
    ]
    return release_item_sha256(fields)


def first(row: dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        value = row.get(key)
        if value not in (None, ""):
            return value
    return default


def as_sha256(value: Any) -> str | None:
    text = str(value or "").strip().lower()
    return text if SHA256_RE.fullmatch(text) else None


def load_rows(path: Path) -> list[InputRow]:
    if not path.is_file():
        raise FileNotFoundError(path)
    raw = path.read_bytes()
    manifest_sha = sha256_bytes(raw)
    suffix = path.suffix.lower()
    rows: list[Any]
    if suffix in {".jsonl", ".ndjson"}:
        rows = []
        for line_number, line in enumerate(raw.decode("utf-8-sig").splitlines(), start=1):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise BuildError(f"{path}:{line_number}: invalid JSONL: {exc}") from exc
    else:
        try:
            data = json.loads(raw.decode("utf-8-sig"))
        except json.JSONDecodeError as exc:
            raise BuildError(f"{path}: invalid JSON: {exc}") from exc
        if isinstance(data, list):
            rows = data
        elif isinstance(data, dict):
            for key in ("questions", "rows", "selected_questions", "items", "data"):
                candidate = data.get(key)
                if isinstance(candidate, list):
                    rows = candidate
                    break
            else:
                raise BuildError(f"{path}: JSON object must contain a question array")
        else:
            raise BuildError(f"{path}: JSON root must be an array or object")
    output: list[InputRow] = []
    for index, row in enumerate(rows, start=1):
        if not isinstance(row, dict):
            raise BuildError(f"{path}: row {index} is not an object")
        output.append(InputRow(dict(row), path.resolve(), manifest_sha, index))
    return output


def options_list(value: Any) -> list[str]:
    if value in (None, ""):
        return []
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith("[") or stripped.startswith("{"):
            try:
                value = json.loads(stripped)
            except json.JSONDecodeError:
                return []
        else:
            return []
    if isinstance(value, dict):
        keys = list(value)
        letter_keys = [key for key in keys if re.fullmatch(r"[A-Za-z]", str(key))]
        order = sorted(letter_keys, key=lambda item: str(item).upper()) if len(letter_keys) == len(keys) else sorted(keys, key=str)
        return [str(value[key]).strip() for key in order]
    if isinstance(value, list):
        return [str(item).strip() for item in value]
    return []


def normalize_answer(value: Any, option_count: int) -> tuple[int | None, Any]:
    if value is None:
        raise BuildError("answer/correct_option is missing")
    raw = value
    if option_count:
        if isinstance(value, int) and not isinstance(value, bool):
            index = value
        else:
            text = str(value).strip().upper()
            if len(text) == 1 and "A" <= text <= "Z":
                index = ord(text) - ord("A")
            elif re.fullmatch(r"\d+", text):
                index = int(text)
            else:
                return None, raw
        if not 0 <= index < option_count:
            raise BuildError(f"correct option {value!r} outside {option_count} options")
        return index, raw
    if isinstance(raw, str) and not raw.strip():
        raise BuildError("answer is blank")
    return None, raw


def infer_grade(row: dict[str, Any], skill_id: str) -> tuple[str, str]:
    grade = str(first(row, "grade_band", "grade", default="")).strip()
    if grade not in GRADE_CODES:
        prefix = skill_id[:2].upper()
        grade = {"H1": "高一", "H2": "高二", "H3": "高三"}.get(prefix, "")
    if grade not in GRADE_CODES:
        raise BuildError(f"cannot infer grade from grade_band={grade!r}, skill_id={skill_id!r}")
    grade_code = GRADE_CODES[grade]
    if skill_id.upper().startswith(("H1_", "H2_", "H3_")) and not skill_id.upper().startswith(grade_code + "_"):
        raise BuildError(f"grade {grade} conflicts with skill {skill_id}")
    return grade, grade_code


def concept_identity(row: dict[str, Any], skill_id: str) -> tuple[str, str, int]:
    raw_key = str(first(row, "concept_id", "concept_key", default="")).strip()
    match = CONCEPT_RE.search(raw_key)
    raw_order = first(row, "concept_order")
    if raw_order in (None, "") and match:
        raw_order = match.group(1)
    try:
        order = int(raw_order)
    except (TypeError, ValueError) as exc:
        raise BuildError(f"{skill_id}: concept order is missing") from exc
    if order < 1:
        raise BuildError(f"{skill_id}: concept order must be positive")
    key = f"{skill_id}__C{order:02d}"
    label = str(first(row, "concept_label", "concept_name", default="")).strip()
    if not label and raw_key and not CONCEPT_RE.search(raw_key):
        label = raw_key
    if not label:
        label = key
    return key, label, order


def visibility_checks(row: dict[str, Any], label: str) -> None:
    for key in ("source_visible_to_student", "student_source_visible"):
        if row.get(key) is True:
            raise BuildError(f"{label}: private source is marked visible to students ({key})")
    for key in ("analysis_image_visible_to_student", "analysis_image_student_visible"):
        if row.get(key) is True:
            raise BuildError(f"{label}: teacher analysis image is marked visible to students ({key})")
    private_source = row.get("source_info_private")
    if isinstance(private_source, dict) and private_source.get("student_source_hidden") is False:
        raise BuildError(f"{label}: source_info_private.student_source_hidden is false")


def source_locator(row: dict[str, Any]) -> Any:
    value = first(
        row,
        "source_locator_private",
        "source_docx_locator_private",
        "public_citation",
        "source_locator",
        "physical_page_range",
        "source_question_no",
        "compilation_question_no",
        "question_no",
    )
    if value not in (None, ""):
        return value
    public = row.get("source_info")
    if isinstance(public, dict):
        return first(public, "locator", "questionNo", default="")
    return ""


def source_document_sha(row: dict[str, Any]) -> str | None:
    direct = first(row, "source_pdf_sha256", "source_document_sha256", "source_docx_sha256")
    digest = as_sha256(direct)
    if digest:
        return digest
    for key in ("source_info_private", "source_info"):
        nested = row.get(key)
        if not isinstance(nested, dict):
            continue
        for nested_key in ("source_pdf_sha256", "source_document_sha256", "source_docx_sha256"):
            digest = as_sha256(nested.get(nested_key))
            if digest:
                return digest
    return None


def canonical_source_id(row: dict[str, Any], source_item_key: str | None = None) -> str:
    value = first(
        row,
        "canonical_source_id",
        "canonical_id",
        "source_item_id",
        "occurrence_id",
        "candidate_id",
        "source_manifest_id",
        "question_id",
    )
    if value not in (None, ""):
        return str(value).strip()
    if source_item_key:
        return "SRC-" + source_item_key[:24].upper()
    raise BuildError("canonical source identity is missing")


def private_source_record(item: InputRow, canonical_id: str, document_sha: str | None, item_key: str, locator: Any) -> dict[str, Any]:
    row = item.row
    private = row.get("source_info_private") if isinstance(row.get("source_info_private"), dict) else {}
    public = row.get("source_info") if isinstance(row.get("source_info"), dict) else {}
    title = first(private, "private_title", "title", default=first(row, "source_title", "compilation_topic", default=public.get("title")))
    manifest_id = first(row, "source_manifest_id", "occurrence_id", "candidate_id", "question_id")
    return {
        "canonical_source_id": canonical_id,
        "source_manifest_id": None if manifest_id in (None, "") else str(manifest_id),
        "source_document_sha256": document_sha,
        "source_item_key_sha256": item_key,
        "source_locator_private": locator,
        "source_title_private": None if title in (None, "") else str(title),
        "input_manifest_name": item.input_path.name,
        "input_manifest_sha256": item.input_sha256,
        "input_row_number": item.row_number,
    }


def asset_descriptor(item: InputRow, role: str) -> tuple[Path, str | None, int | None, int | None, str]:
    row = item.row
    if role == "student_question_image":
        nested_keys = ("question_asset",)
        flat_paths = ("question_asset_path", "asset_path")
        sha_keys = ("question_asset_sha256", "question_image_sha256")
        width_keys = ("question_asset_width", "question_image_width_px")
        height_keys = ("question_asset_height", "question_image_height_px")
        ref_kind = "question_image"
        file_suffix = "question"
    else:
        nested_keys = ("analysis_asset_private", "analysis_asset")
        flat_paths = ("analysis_asset_path",)
        sha_keys = ("analysis_asset_sha256", "analysis_image_sha256")
        width_keys = ("analysis_asset_width", "analysis_image_width_px")
        height_keys = ("analysis_asset_height", "analysis_image_height_px")
        ref_kind = "analysis_image"
        file_suffix = "analysis"

    nested: dict[str, Any] = {}
    for key in nested_keys:
        if isinstance(row.get(key), dict):
            nested = row[key]
            break
    raw_path = first(nested, "path") if nested else None
    if raw_path in (None, ""):
        raw_path = first(row, *flat_paths)

    asset_ref: dict[str, Any] = {}
    refs = row.get("asset_refs")
    if isinstance(refs, list):
        asset_ref = next((ref for ref in refs if isinstance(ref, dict) and ref.get("kind") == ref_kind), {})

    if raw_path in (None, ""):
        existing_id = str(first(row, "question_id", default="")).strip().lower()
        if existing_id:
            candidate = item.input_path.parent / "assets" / f"{existing_id}_{file_suffix}.webp"
            if candidate.is_file():
                raw_path = candidate
    if raw_path in (None, ""):
        raise BuildError(f"{item.input_path}:{item.row_number}: missing {role} path")

    path = Path(str(raw_path))
    if not path.is_absolute():
        path = item.input_path.parent / path
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)

    expected_sha = as_sha256(first(nested, "sha256") if nested else None)
    expected_sha = expected_sha or as_sha256(first(row, *sha_keys)) or as_sha256(asset_ref.get("sha256"))
    raw_width = first(nested, "width") if nested else None
    raw_height = first(nested, "height") if nested else None
    raw_width = raw_width if raw_width not in (None, "") else first(row, *width_keys, default=asset_ref.get("width"))
    raw_height = raw_height if raw_height not in (None, "") else first(row, *height_keys, default=asset_ref.get("height"))
    expected_width = int(raw_width) if raw_width not in (None, "") else None
    expected_height = int(raw_height) if raw_height not in (None, "") else None
    return path, expected_sha, expected_width, expected_height, str(raw_path)


def prepare_asset(item: InputRow, role: str, *, validate_only: bool) -> tuple[AssetPayload, str]:
    path, expected_sha, expected_width, expected_height, original_path = asset_descriptor(item, role)
    source_bytes = path.read_bytes()
    source_sha = sha256_bytes(source_bytes)
    if expected_sha and source_sha != expected_sha:
        raise BuildError(f"{item.input_path}:{item.row_number}: {role} SHA-256 mismatch for {path}")
    try:
        with Image.open(io.BytesIO(source_bytes)) as image:
            image.load()
            width, height = image.size
            if width < 1 or height < 1 or width > MAX_WIDTH or height > MAX_HEIGHT:
                raise BuildError(f"{role} dimensions outside contract: {path} = {image.size}")
            if expected_width is not None and width != expected_width:
                raise BuildError(f"{role} width mismatch for {path}: {width} != {expected_width}")
            if expected_height is not None and height != expected_height:
                raise BuildError(f"{role} height mismatch for {path}: {height} != {expected_height}")
            if validate_only:
                payload = None
                output_sha = source_sha
                output_mime = Image.MIME.get(image.format, "application/octet-stream")
            else:
                rgb = image.convert("RGB")
                source_pixel_sha = sha256_bytes(rgb.tobytes())
                buffer = io.BytesIO()
                rgb.save(buffer, "WEBP", lossless=True, quality=100, method=4, exact=True)
                payload = buffer.getvalue()
                output_sha = sha256_bytes(payload)
                output_mime = "image/webp"
                with Image.open(io.BytesIO(payload)) as rebuilt:
                    rebuilt.load()
                    if rebuilt.size != (width, height) or sha256_bytes(rebuilt.convert("RGB").tobytes()) != source_pixel_sha:
                        raise BuildError(f"lossless pixel verification failed: {path}")
                if len(base64.b64encode(payload)) > MAX_BASE64_BYTES:
                    raise BuildError(f"lossless WebP exceeds private payload limit: {path}")
    except BuildError:
        raise
    except Exception as exc:
        raise BuildError(f"cannot decode {role} {path}: {exc}") from exc
    return (
        AssetPayload(role, path, source_sha, payload, output_sha, width, height, output_mime),
        original_path,
    )


def question_type_text(row: dict[str, Any], options: list[str]) -> tuple[str, bool]:
    value = first(row, "question_type", "type")
    if value not in (None, ""):
        return str(value).strip(), False
    # Compatibility fallback for old release manifests that predate the field.
    # It is surfaced in QA so reviewed selected_questions should be preferred.
    if len(options) == 4:
        return "单项选择", True
    raise BuildError("question_type is missing and cannot be inferred safely")


def normalize_row(
    item: InputRow,
    *,
    validate_only: bool,
    revision_contract: str,
    generation_namespace: str,
) -> dict[str, Any]:
    row = item.row
    label = f"{item.input_path}:{item.row_number}"
    # Selection manifests may retain the source classifier's provisional
    # ``skill_id`` while recording the manually verified production taxonomy
    # in ``assigned_skill_id``.  The audited assignment is authoritative.
    skill_id = str(first(row, "assigned_skill_id", "skill_id", default="")).strip()
    if not re.fullmatch(r"H[123]_[A-Z0-9_]+", skill_id):
        raise BuildError(f"{label}: invalid skill_id {skill_id!r}")
    grade, grade_code = infer_grade(row, skill_id)
    visibility_checks(row, label)

    stem = str(first(row, "student_question_text", "question_text", "stem_text", "stem", default="")).strip()
    if not stem:
        raise BuildError(f"{label}: student question stem is blank")
    options = options_list(row.get("options"))
    if options and any(not option for option in options):
        raise BuildError(f"{label}: one or more options are blank")
    qtype, inferred_type = question_type_text(row, options)
    raw_answer = first(row, "correct_option", "correct_answer", "answer", "answer_text")
    correct_option, answer_raw = normalize_answer(raw_answer, len(options))
    explanation = str(first(row, "explanation", "analysis_text", "parsed_explanation", default="")).strip()
    if not explanation:
        raise BuildError(f"{label}: explanation is blank")

    raw_level = first(row, "difficulty_1_5", "difficulty_level", "level")
    try:
        level = int(raw_level)
    except (TypeError, ValueError) as exc:
        raise BuildError(f"{label}: difficulty level is missing") from exc
    if level not in range(1, 6):
        raise BuildError(f"{label}: difficulty level must be 1..5")

    concept_key, concept_label, concept_order = concept_identity(row, skill_id)
    document_sha = source_document_sha(row)
    existing_item_key = as_sha256(first(row, "source_item_key"))
    locator = source_locator(row)
    preliminary_id = canonical_source_id(row, existing_item_key)
    if existing_item_key:
        source_item_key = existing_item_key
        source_identity_kind = "source_item_key"
    elif document_sha:
        source_item_key = sha256_bytes(
            (document_sha + "|" + preliminary_id + "|" + canonical_json(locator)).encode("utf-8")
        )
        source_identity_kind = "source_document_sha256"
    else:
        raise BuildError(f"{label}: immutable source_document_sha256 or source_item_key is required")
    canonical_id = canonical_source_id(row, source_item_key)
    if not re.fullmatch(r"[A-Za-z0-9._:-]{3,160}", canonical_id):
        raise BuildError(f"{label}: canonical_source_id is not database-safe: {canonical_id!r}")

    question_asset, question_input_path = prepare_asset(item, "student_question_image", validate_only=validate_only)
    analysis_asset, analysis_input_path = prepare_asset(item, "teacher_analysis_image", validate_only=validate_only)
    fingerprint, fingerprint_contract = content_fingerprint(qtype, stem, options)
    input_render_mode = str(first(row, "render_mode", default="image_primary")).strip()
    # This builder always emits a verified question image and makes that
    # original source crop authoritative.  ``source_crop_exact`` is an older
    # local audit label, not a value accepted by the production table.
    render_mode = "image_primary"
    mother_id = f"M{grade_code}O_{source_item_key[:24].upper()}"

    # Asset paths are opaque database identifiers; MIME type is stored apart.
    question_path = f"{grade_code.lower()}orig/{generation_namespace}/{source_item_key[:16]}/{question_asset.output_sha256[:16]}/question/v1"
    analysis_path = f"{grade_code.lower()}orig/{generation_namespace}/{source_item_key[:16]}/{analysis_asset.output_sha256[:16]}/analysis/v1"
    refs = [
        {
            "kind": "question_image",
            "path": question_path,
            "alt": f"{grade}化学原题题面",
            "sha256": question_asset.output_sha256,
            "width": question_asset.width,
            "height": question_asset.height,
        },
        {
            "kind": "analysis_image",
            "path": analysis_path,
            "alt": "教师核对用解析图",
            "sha256": analysis_asset.output_sha256,
            "width": analysis_asset.width,
            "height": analysis_asset.height,
        },
    ]
    revision = question_revision_token(
        fingerprint,
        render_mode,
        refs,
        question_asset.output_sha256,
        analysis_asset.output_sha256,
        explanation=explanation,
        revision_contract=revision_contract,
    )
    question_id = f"Q{grade_code}O_{generation_namespace.upper()}_{source_item_key[:16].upper()}_{revision[:16].upper()}"
    scaffold = "先读题设与图表，再逐项核对条件、结论和单位。"
    source_kind = "licensed_local"
    source_info = {
        "title": f"{grade}化学原题",
        "exam": "原题练习",
        "year": "审定版",
        "questionNo": "原题",
        "locator": "教师私有来源映射",
        "transcriptionPolicy": "source_image_authoritative",
        "optionTranscriptionPolicy": "source_image_authoritative",
        "transcriptionAuditMethod": "manual_full_visual_and_science_review",
        "sourcePairingStatus": "SOURCE_NATIVE_PAIR",
        "sourceMarkerStyle": "plain_answer_analysis",
        "sourceMarkerLabel": "原题",
        "conceptLabel": concept_label,
    }
    private_source = private_source_record(item, canonical_id, document_sha, source_item_key, locator)
    private_source.update(
        {
            "source_identity_kind": source_identity_kind,
            "question_image_input_path": question_input_path,
            "question_image_source_sha256": question_asset.source_sha256,
            "analysis_image_input_path": analysis_input_path,
            "analysis_image_source_sha256": analysis_asset.source_sha256,
            "input_render_mode": input_render_mode,
            "release_generation_namespace": generation_namespace,
        }
    )

    if correct_option is None:
        raise BuildError(f"{label}: database release requires an original four-option single-select question")
    item_sha = database_release_item_sha256(
        question_id=question_id,
        mother_id=mother_id,
        skill_id=skill_id,
        concept_key=concept_key,
        level=level,
        grade_band=grade,
        stem=stem,
        options=options,
        correct_option=correct_option,
        explanation=explanation,
        scaffold=scaffold,
        source_kind=source_kind,
        render_mode=render_mode,
        source_item_key=source_item_key,
        content_fingerprint_value=fingerprint,
        revision_token=revision,
        source_info=source_info,
        refs=refs,
        canonical_source_id_value=canonical_id,
        question_asset_sha256=question_asset.output_sha256,
        analysis_asset_sha256=analysis_asset.output_sha256,
    )
    return {
        "question_id": question_id,
        "mother_id": mother_id,
        "grade_band": grade,
        "grade_code": grade_code,
        "generation_namespace": generation_namespace,
        "skill_id": skill_id,
        "concept_key": concept_key,
        "concept_label": concept_label,
        "concept_order": concept_order,
        "level": level,
        "question_type": qtype,
        "question_type_inferred": inferred_type,
        "stem": stem,
        "options": options,
        "correct_option": correct_option,
        "answer_raw": answer_raw,
        "explanation": explanation,
        "scaffold": scaffold,
        "source_kind": source_kind,
        "source_info": source_info,
        "render_mode": render_mode,
        "source_item_key": source_item_key,
        "canonical_source_id": canonical_id,
        "content_fingerprint": fingerprint,
        "fingerprint_contract": fingerprint_contract,
        "question_revision_token": revision,
        "item_sha256": item_sha,
        "refs": refs,
        "question_asset": question_asset,
        "analysis_asset": analysis_asset,
        "private_source": private_source,
    }


def assert_unique(prepared: list[dict[str, Any]], field: str, human_name: str) -> None:
    grouped: dict[str, list[str]] = defaultdict(list)
    for row in prepared:
        grouped[str(row[field])].append(row["canonical_source_id"])
    duplicates = {value: ids for value, ids in grouped.items() if len(ids) > 1}
    if duplicates:
        sample = list(duplicates.items())[:5]
        raise BuildError(f"duplicate {human_name} blocked: {sample}")


def qa_summary(prepared: list[dict[str, Any]], inputs: list[InputRow], *, validate_only: bool, revision_contract: str) -> dict[str, Any]:
    by_grade = Counter(row["grade_band"] for row in prepared)
    by_skill = Counter(row["skill_id"] for row in prepared)
    by_type = Counter(row["question_type"] for row in prepared)
    by_level = Counter(str(row["level"]) for row in prepared)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS",
        "validateOnly": validate_only,
        "databaseWritten": False,
        "published": False,
        "questionCount": len(prepared),
        "assetCount": len(prepared) * 2,
        "studentQuestionImageCount": len(prepared),
        "teacherAnalysisImageCount": len(prepared),
        "inputManifestCount": len({row.input_path for row in inputs}),
        "inputRowCount": len(inputs),
        "countsByGrade": dict(sorted(by_grade.items())),
        "countsBySkill": dict(sorted(by_skill.items())),
        "countsByQuestionType": dict(sorted(by_type.items())),
        "countsByDifficulty": dict(sorted(by_level.items())),
        "questionTypesPreserved": True,
        "inferredQuestionTypeCount": sum(bool(row["question_type_inferred"]) for row in prepared),
        "databaseCompatibleFingerprintCount": sum(row["fingerprint_contract"] == "db_v1_four_option" for row in prepared),
        "portableTypedFingerprintCount": sum(row["fingerprint_contract"] == "portable_typed_v1" for row in prepared),
        "sourceDocumentSha256Count": sum(row["private_source"]["source_document_sha256"] is not None for row in prepared),
        "sourceItemKeyFallbackCount": sum(row["private_source"]["source_identity_kind"] == "source_item_key" for row in prepared),
        "contentFingerprintsUnique": len({row["content_fingerprint"] for row in prepared}) == len(prepared),
        "sourceItemKeysUnique": len({row["source_item_key"] for row in prepared}) == len(prepared),
        "questionRevisionTokensUnique": len({row["question_revision_token"] for row in prepared}) == len(prepared),
        "releaseItemSha256Unique": len({row["item_sha256"] for row in prepared}) == len(prepared),
        "privateSourceLocatorsExcludedFromQuestionManifest": True,
        "questionAssetRefsIncludeBothDeclaredImages": all(len(row["refs"]) == 2 for row in prepared),
        "revisionContract": revision_contract,
        "releaseGenerationNamespace": next(iter({row["generation_namespace"] for row in prepared})),
        "assetPayloadMode": "source_bytes_validation_only" if validate_only else "lossless_webp_pixel_verified",
    }


def question_record(row: dict[str, Any]) -> dict[str, Any]:
    record = {
        "question_id": row["question_id"],
        "mother_id": row["mother_id"],
        "grade_band": row["grade_band"],
        "skill_id": row["skill_id"],
        "concept_key": row["concept_key"],
        "concept_label": row["concept_label"],
        "level": row["level"],
        "question_type": row["question_type"],
        "stem": row["stem"],
        "options": row["options"],
        "correct_option": row["correct_option"],
        "explanation": row["explanation"],
        "scaffold": row["scaffold"],
        "source_kind": row["source_kind"],
        "source_info": row["source_info"],
        "render_mode": row["render_mode"],
        "asset_refs": row["refs"],
        "source_item_key": row["source_item_key"],
        "content_fingerprint": row["content_fingerprint"],
        "fingerprint_contract": row["fingerprint_contract"],
        "question_revision_token": row["question_revision_token"],
    }
    if row["correct_option"] is None:
        record["answer_text"] = row["answer_raw"]
    return record


def asset_records(row: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "asset_id": release_item_sha256([row["question_id"], "student_question_image", row["question_asset"].output_sha256]),
            "question_id": row["question_id"],
            "role": "student_question_image",
            "asset_kind": "question_image",
            "visibility": "student",
            "path": row["refs"][0]["path"],
            "mime_type": row["question_asset"].output_mime_type,
            "sha256": row["question_asset"].output_sha256,
            "width": row["question_asset"].width,
            "height": row["question_asset"].height,
        },
        {
            "asset_id": release_item_sha256([row["question_id"], "teacher_analysis_image", row["analysis_asset"].output_sha256]),
            "question_id": row["question_id"],
            "role": "teacher_analysis_image",
            "asset_kind": "analysis_image",
            "visibility": "teacher_private",
            "path": row["refs"][1]["path"],
            "mime_type": row["analysis_asset"].output_mime_type,
            "sha256": row["analysis_asset"].output_sha256,
            "width": row["analysis_asset"].width,
            "height": row["analysis_asset"].height,
        },
    ]


def release_item_record(row: dict[str, Any], release_id: str, manifest_sha: str) -> dict[str, Any]:
    return {
        "release_id": release_id,
        "release_manifest_sha256": manifest_sha,
        "question_id": row["question_id"],
        "canonical_source_id": row["canonical_source_id"],
        "source_item_key": row["source_item_key"],
        "content_fingerprint": row["content_fingerprint"],
        "fingerprint_contract": row["fingerprint_contract"],
        "question_revision_token": row["question_revision_token"],
        "question_asset_sha256": row["question_asset"].output_sha256,
        "analysis_asset_sha256": row["analysis_asset"].output_sha256,
        "item_sha256": row["item_sha256"],
        "private_source": row["private_source"],
    }


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")


def write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    text = "".join(canonical_json(row) + "\n" for row in rows)
    path.write_text(text, encoding="utf-8", newline="\n")


def build_outputs(prepared: list[dict[str, Any]], inputs: list[InputRow], output: Path, *, revision_contract: str) -> dict[str, Any]:
    prepared = sorted(prepared, key=lambda row: row["question_id"])
    manifest_bytes = "\n".join(row["item_sha256"] for row in prepared).encode("utf-8")
    manifest_sha = sha256_bytes(manifest_bytes)
    release_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"gan-private-review-release:{manifest_sha}"))
    qa = qa_summary(prepared, inputs, validate_only=False, revision_contract=revision_contract)
    qa.update(
        {
            "releaseId": release_id,
            "manifestSha256": manifest_sha,
            "manifestCanonicalBytes": len(manifest_bytes),
            "manifestCanonicalHasNoTrailingLf": not manifest_bytes.endswith(b"\n"),
        }
    )

    parent = output.resolve().parent
    parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{output.name}.", dir=parent))
    try:
        (temporary / "assets" / "student_questions").mkdir(parents=True)
        (temporary / "assets" / "teacher_analyses").mkdir(parents=True)
        questions = [question_record(row) for row in prepared]
        assets = [asset for row in prepared for asset in asset_records(row)]
        release_items = [release_item_record(row, release_id, manifest_sha) for row in prepared]
        write_jsonl(temporary / "questions.jsonl", questions)
        write_jsonl(temporary / "assets.jsonl", assets)
        write_jsonl(temporary / "release_items.jsonl", release_items)
        (temporary / "manifest_canonical.txt").write_bytes(manifest_bytes)

        for row in prepared:
            for asset, ref in ((row["question_asset"], row["refs"][0]), (row["analysis_asset"], row["refs"][1])):
                if asset.output_payload is None:
                    raise AssertionError("full build is missing an encoded asset payload")
                destination = temporary / ref["path"]
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(asset.output_payload)

        release_manifest = {
            "schemaVersion": SCHEMA_VERSION,
            "releaseId": release_id,
            "manifestSha256": manifest_sha,
            "status": "local_only_not_staged",
            "databaseWritten": False,
            "published": False,
            "revisionContract": revision_contract,
            "questionCount": len(prepared),
            "assetCount": len(assets),
            "countsByGrade": qa["countsByGrade"],
            "files": {
                "questions": "questions.jsonl",
                "assets": "assets.jsonl",
                "releaseItems": "release_items.jsonl",
                "qaSummary": "qa_summary.json",
                "canonicalManifest": "manifest_canonical.txt",
            },
            "canonicalization": {
                "itemSha256": "SHA-256 of ordered length-prefixed fields",
                "manifestBytes": "item_sha256 sorted by question_id, LF joined, no trailing LF",
                "manifestDigest": "SHA-256 of UTF-8 manifestBytes",
            },
        }
        write_json(temporary / "release_manifest.json", release_manifest)
        write_json(temporary / "qa_summary.json", qa)

        if output.exists():
            raise FileExistsError(f"refusing to overwrite existing output directory: {output}")
        temporary.replace(output)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    return qa


def verify_hash_contract() -> dict[str, str]:
    options = [" 甲 ", "乙\n项", "\u3000丙", "丁\u00a0"]
    fingerprint = legacy_content_fingerprint(" A\uf028 B \n", options)
    if fingerprint != "6e52a2ebb38b5e7cb8a51fa3fe703ee2e375e9598e09ff9b06f20d8c74c292ac":
        raise AssertionError("content fingerprint canonicalization changed")
    refs = [
        {
            "kind": "question_image",
            "path": "h2orig/0123456789ab/0123456789abcdef/abcdef0123456789/question/v1",
            "alt": "高二化学原题题面",
            "sha256": "a" * 64,
            "width": 1234,
            "height": 567,
        },
        {
            "kind": "analysis_image",
            "path": "h2orig/0123456789ab/0123456789abcdef/fedcba9876543210/analysis/v1",
            "alt": "教师核对用解析图",
            "sha256": "b" * 64,
            "width": 1200,
            "height": 890,
        },
    ]
    explanation = "A．甲。\nB．乙。\nC．丙。\nD．丁。"
    revision = question_revision_token(
        fingerprint,
        "image_primary",
        refs,
        "a" * 64,
        "b" * 64,
        explanation=explanation,
        revision_contract="v2_explanation_assets",
    )
    if revision != "af47bc64af694db3920073b27a120ccf1221ad2d3efbb5ea034b1ae0a2f8462f":
        raise AssertionError("v2 question revision canonicalization changed")
    source_info = {
        "title": "高二化学原题",
        "exam": "原题练习",
        "year": "审定版",
        "questionNo": "原题",
        "locator": "教师私有来源映射",
        "transcriptionPolicy": "source_image_authoritative",
        "optionTranscriptionPolicy": "source_image_authoritative",
        "transcriptionAuditMethod": "manual_full_visual_and_science_review",
        "sourcePairingStatus": "SOURCE_NATIVE_PAIR",
        "sourceMarkerStyle": "plain_answer_analysis",
        "sourceMarkerLabel": "原题",
        "conceptLabel": "示例概念",
    }
    item = database_release_item_sha256(
        question_id="QH2O_TEST",
        mother_id="MH2O_TEST",
        skill_id="H2_K",
        concept_key="H2_K__C01",
        level=3,
        grade_band="高二",
        stem="示例题干",
        options=["甲", "乙", "丙", "丁"],
        correct_option=1,
        explanation=explanation,
        scaffold="先读题设与图表，再逐项核对条件、结论和单位。",
        source_kind="licensed_local",
        render_mode="image_primary",
        source_item_key="0" * 64,
        content_fingerprint_value=fingerprint,
        revision_token=revision,
        source_info=source_info,
        refs=refs,
        canonical_source_id_value="TEST:H2_K:001",
        question_asset_sha256="a" * 64,
        analysis_asset_sha256="b" * 64,
    )
    if item != "fd1598ec56bac8d09a11c39eb88da88d72fcb8cc6fffae8438fb7929b4077107":
        raise AssertionError("database release-item canonicalization changed")
    return {"contentFingerprint": fingerprint, "v2Revision": revision, "databaseReleaseItem": item}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path, help="audited JSON, JSONL, or NDJSON question manifests")
    parser.add_argument("--output", type=Path, help="new local output directory (required unless --validate-only)")
    parser.add_argument("--validate-only", action="store_true", help="validate every row and asset without writing output")
    parser.add_argument(
        "--revision-contract",
        choices=sorted(REVISION_CONTRACTS),
        default="v2_explanation_assets",
        help="immutable question revision digest contract",
    )
    parser.add_argument(
        "--generation-label",
        default="",
        help="optional immutable label used to force a new cumulative release generation",
    )
    args = parser.parse_args()
    if not args.validate_only and args.output is None:
        parser.error("--output is required unless --validate-only is used")

    hash_contract = verify_hash_contract()
    inputs = [row for path in args.inputs for row in load_rows(path.resolve())]
    if not inputs:
        raise BuildError("no question rows were loaded")
    generation_material = canonical_json(
        {
            "schemaVersion": SCHEMA_VERSION,
            "revisionContract": args.revision_contract,
            "inputManifestSha256": sorted({row.input_sha256 for row in inputs}),
            "generationLabel": args.generation_label,
        }
    )
    generation_namespace = sha256_bytes(generation_material.encode("utf-8"))[:12]
    prepared = [
        normalize_row(
            row,
            validate_only=args.validate_only,
            revision_contract=args.revision_contract,
            generation_namespace=generation_namespace,
        )
        for row in inputs
    ]
    for field, human in (
        ("question_id", "question id"),
        ("source_item_key", "source item key"),
        ("canonical_source_id", "canonical source id"),
        ("content_fingerprint", "semantic content fingerprint"),
        ("question_revision_token", "question revision token"),
        ("item_sha256", "release item digest"),
    ):
        assert_unique(prepared, field, human)

    if args.validate_only:
        qa = qa_summary(prepared, inputs, validate_only=True, revision_contract=args.revision_contract)
        qa["hashContract"] = hash_contract
        print(json.dumps(qa, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        qa = build_outputs(prepared, inputs, args.output.resolve(), revision_contract=args.revision_contract)
        qa["output"] = str(args.output.resolve())
        print(json.dumps(qa, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BuildError, FileNotFoundError, FileExistsError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
