"""Conservative, text-only candidates for missing chemistry notation.

This never repairs a question or declares it correct. A candidate must be
compared with the original page/crop before an item-level visual attestation.
"""

from __future__ import annotations

import re


_OPTION_LABEL = re.compile(r"^\s*[A-D][．.、]\s*")
_BARE_STEP = re.compile(r"^\s*[①②③④⑤⑥⑦⑧⑨⑩]\s*$")
_MISSING_VALUE = re.compile(r"(?:为时[，。；]|为[，。；])")
_TERMINAL_REACTION = re.compile(r"(?:=|→|⇌|⇄)\s*$")
_TERMINAL_COLON = re.compile(r"[：:]\s*$")
_LEADING_SEPARATOR = re.compile(r"^[，,；;]\s*\S")
_UNFINISHED_CONCLUSION = re.compile(r"(?:，?则|该条件下|反应为|方程式为)\s*$")
_REACTION_TABLE_LABEL = re.compile(r"反应[ⅠⅡⅢⅣIVX\d]+[：:]")
_REACTION_ARROW_OR_EQUALITY = re.compile(r"(?:→|⟶|⇌|⇄|↔|=|＝)")
_FLATTENED_AVOGADRO_EXPONENT = re.compile(r"(?:6[.]02|1[.]505)\s*[×xX]\s*10(?:23|22|24)(?!\d)")
_LOST_CHEMICAL_TERMS = {
    "known_species_missing": re.compile(r"已知[：:]\s*为"),
    "preparation_reaction_missing": re.compile(r"可利用反应\s*制备"),
    "removed_species_missing": re.compile(r"(?:反应[ⅰⅱⅲIVX\d]+中|因)\s*脱去步骤"),
    "generated_species_missing": re.compile(r"生成(?:并消耗|和)\s*(?:[，。；]|$)"),
    "transformed_species_missing": re.compile(r"转化为\s*[，。；]"),
    "comparison_quantity_missing": re.compile(r"说明[：:]\s*[①②③④]\s*[>＞<＜]"),
    # Observed in two local-original comparisons: equation objects for
    # H₂O₂/Co complexes and Cr(OH)₃ disappeared completely from the OCR text.
    "catalyzed_species_missing": re.compile(r"(?:能否|可|不能)催化的分解"),
    "reacting_species_missing": re.compile(r"与发生(?:氧化还原)?反应"),
    "summed_species_missing": re.compile(r"与的总和"),
    "amphoteric_subject_missing": re.compile(r"^\s*是两性氢氧化物"),
    "reaction_species_missing_before_coefficient": re.compile(
        r"(?:反应|转化为|证明)[：:]\s*[+＋]?\d+\s*[+＋=＝]"
    ),
}


def candidate_flags(stem: str, options: list[str], explanation: str = "") -> list[str]:
    """Return high-confidence triage codes; never infer a missing formula.

    A terminal '+' is intentionally *not* treated as an unfinished equation:
    ions such as H+ and Pb2+ legitimately end with a charge sign.
    """

    flags: set[str] = set()
    if any('\ufffd' in value for value in (stem, *options, explanation)):
        flags.add('replacement_character_in_question')
    if any(_FLATTENED_AVOGADRO_EXPONENT.search(value) for value in (stem, *options, explanation)):
        flags.add('flattened_scientific_exponent')
    question_lines = stem.splitlines()
    bare_steps = sum(bool(_BARE_STEP.fullmatch(line)) for line in question_lines)
    if bare_steps >= 2:
        flags.add("bare_reaction_steps")

    # Word/PDF table conversion can drop all arrows while keeping reactants and
    # products in separate rows.  Multiple named reactions without a single
    # equality/arrow are a strong candidate, not a proof of corruption.
    if len(_REACTION_TABLE_LABEL.findall(stem)) >= 2 and not _REACTION_ARROW_OR_EQUALITY.search(stem):
        flags.add("reaction_table_arrows_missing")

    for index, line in enumerate(question_lines):
        stripped = line.strip()
        if not stripped:
            continue
        next_nonblank = next(
            (candidate.strip() for candidate in question_lines[index + 1 :] if candidate.strip()),
            "",
        )
        has_following_formula_line = bool(next_nonblank and not _OPTION_LABEL.match(next_nonblank))
        if _OPTION_LABEL.match(stripped) and _TERMINAL_COLON.search(stripped) and not has_following_formula_line:
            flags.add("option_formula_missing_after_colon")
        if _OPTION_LABEL.match(stripped) and _TERMINAL_REACTION.search(stripped) and not has_following_formula_line:
            flags.add("option_reaction_missing_product")
        if _MISSING_VALUE.search(stripped):
            flags.add("missing_value_after_wei")
        if _OPTION_LABEL.match(stripped):
            option_text = _OPTION_LABEL.sub("", stripped)
            if _LEADING_SEPARATOR.search(option_text):
                flags.add("option_starts_after_lost_formula")
            if _UNFINISHED_CONCLUSION.search(option_text) and not has_following_formula_line:
                flags.add("option_ends_before_missing_formula")

    for option in options:
        stripped = option.strip()
        if _TERMINAL_COLON.search(stripped):
            flags.add("option_formula_missing_after_colon")
        if _TERMINAL_REACTION.search(stripped):
            flags.add("option_reaction_missing_product")
        if _MISSING_VALUE.search(stripped):
            flags.add("missing_value_after_wei")
        if _LEADING_SEPARATOR.search(stripped):
            flags.add("option_starts_after_lost_formula")
        if _UNFINISHED_CONCLUSION.search(stripped):
            flags.add("option_ends_before_missing_formula")

    # Explanation text is inspected only for a hanging reaction arrow/equality.
    # A paragraph ending in a colon can legitimately introduce a figure.
    for line in explanation.splitlines():
        if _TERMINAL_REACTION.search(line.strip()):
            flags.add("explanation_reaction_missing_product")
    # OCR of Word equations can remove the *entire* object, leaving plausible
    # Chinese prose around the gap.  These shapes were observed against local
    # original/teacher pages, including missing GaN, H₂O and Fe complexes.
    # A match is only a candidate: it must be checked against the source.
    for code, pattern in _LOST_CHEMICAL_TERMS.items():
        if any(pattern.search(value) for value in (stem, *options, explanation)):
            flags.add(code)
    return sorted(flags)
