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


def candidate_flags(stem: str, options: list[str], explanation: str = "") -> list[str]:
    """Return high-confidence triage codes; never infer a missing formula.

    A terminal '+' is intentionally *not* treated as an unfinished equation:
    ions such as H+ and Pb2+ legitimately end with a charge sign.
    """

    flags: set[str] = set()
    question_lines = stem.splitlines()
    bare_steps = sum(bool(_BARE_STEP.fullmatch(line)) for line in question_lines)
    if bare_steps >= 2:
        flags.add("bare_reaction_steps")

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

    for option in options:
        stripped = option.strip()
        if _TERMINAL_COLON.search(stripped):
            flags.add("option_formula_missing_after_colon")
        if _TERMINAL_REACTION.search(stripped):
            flags.add("option_reaction_missing_product")
        if _MISSING_VALUE.search(stripped):
            flags.add("missing_value_after_wei")

    # Explanation text is inspected only for a hanging reaction arrow/equality.
    # A paragraph ending in a colon can legitimately introduce a figure.
    for line in explanation.splitlines():
        if _TERMINAL_REACTION.search(line.strip()):
            flags.add("explanation_reaction_missing_product")
    return sorted(flags)
