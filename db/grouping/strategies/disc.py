"""
Multi-disc grouping strategy.

Recognizes the ``(Disc N)`` family of tokens that Redump/No-Intro style
titles use for multi-disc games, strips the token to derive a canonical
group title, and combines it with platform + region into a stable key.
"""
from __future__ import annotations

import re

from utils.parse_utils import create_slug

from ..base import EntryRef, Membership

_DISC_TOKEN = re.compile(
    r"\s*\(\s*(?:Disc|Disk|Disco)\s+"
    r"(?P<idx>\d+|[IVXLCDM]+|[A-Za-z])"
    r"(?:\s+of\s+(?:\d+|[IVXLCDM]+|[A-Za-z]))?"
    r"\s*\)",
    re.IGNORECASE,
)

_ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}


def _roman_to_int(raw: str) -> int | None:
    """Parse a roman numeral, or None if it is not well-formed."""
    total = 0
    prev = 0
    for ch in reversed(raw.upper()):
        value = _ROMAN.get(ch)
        if value is None:
            return None
        if value < prev:
            total -= value
        else:
            total += value
            prev = value
    return total or None


def _parse_index(raw: str) -> int | None:
    """Turn a disc token's index into an orderable integer.

    Numbers win outright. A lone ``I`` is read as roman 1 (so ``I``/``II``
    order as 1/2), while any other single letter is read as an A=1 series
    position (so ``A``/``B``/``C`` order as 1/2/3). This resolves the
    letter-vs-roman ambiguity in favor of how these labels are used on disc.
    """
    if raw.isdigit():
        return int(raw)
    upper = raw.upper()
    if len(upper) == 1 and upper != "I":
        if "A" <= upper <= "Z":
            return ord(upper) - ord("A") + 1
        return None
    return _roman_to_int(upper)


def _clean_title(title: str) -> str:
    """Strip every disc token and tidy the leftover whitespace/separators."""
    stripped = _DISC_TOKEN.sub(" ", title)
    stripped = re.sub(r"\s+", " ", stripped).strip()
    return stripped.strip(" -")


class DiscStrategy:
    kind = "disc"

    def membership(self, entry: EntryRef) -> Membership | None:
        match = _DISC_TOKEN.search(entry.title)
        if match is None:
            return None

        index = _parse_index(match.group("idx"))
        if index is None:
            return None

        base_title = _clean_title(entry.title)
        if not base_title:
            return None

        key = create_slug(
            {
                "title": base_title,
                "platform": entry.platform,
                "regions": list(entry.regions),
            }
        )
        label = re.sub(r"\s+", " ", match.group(0).strip().strip("()").strip())

        return Membership(
            key=key,
            index=index,
            label=label,
            title=base_title,
        )


STRATEGY = DiscStrategy()
