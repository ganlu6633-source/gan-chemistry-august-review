"""Find large blank bands inside a question or explanation image.

This is a conservative layout preflight, not a proof that the chemistry is
correct. Original-page and teacher-answer review are still required.
"""

from __future__ import annotations

from PIL import Image


def suspicious_inner_gap(image: Image.Image) -> tuple[int, float] | None:
    """Return (gap pixels, share of occupied height) for a large internal band.

    Scan a downsampled central strip so thin page borders and compression noise
    do not turn a nearly empty row into apparent question content. Outer margins
    are ignored: they can be trimmed safely without joining unrelated text.
    """

    width, height = image.size
    # A scanned question assembled from two half-page crops may be only
    # 300–450 px tall after downsampling.  The old 480 px floor let those
    # releases through even when a blank band split the choices.
    if width < 160 or height < 220:
        return None
    left = int(width * 0.04)
    right = max(left + 1, int(width * 0.96))
    scan_width = min(128, right - left)
    gray = image.convert("L").crop((left, 0, right, height))
    sampled = gray.resize((scan_width, height), Image.Resampling.BOX).tobytes()
    occupied = [
        sum(value < 245 for value in sampled[y * scan_width : (y + 1) * scan_width]) >= 2
        for y in range(height)
    ]
    first = next((index for index, value in enumerate(occupied) if value), None)
    if first is None:
        return None
    last = next(index for index in range(height - 1, -1, -1) if occupied[index])
    content_height = last - first + 1
    longest = current = 0
    for value in occupied[first : last + 1]:
        current = 0 if value else current + 1
        longest = max(longest, current)
    share = longest / content_height
    # A split at a page boundary can leave a 20–30% hole while the remaining
    # diagram and four choices keep the overall image quite tall.  This only
    # sends the crop for human review; it does not reject legitimate figures.
    if longest >= max(140, int(content_height * 0.20)) and share >= 0.20:
        return longest, round(share, 3)
    return None
