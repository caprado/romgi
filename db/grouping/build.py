"""
Grouping build pass.

Pure orchestration: given the full entry list and the loaded strategies,
bucket every membership by key and promote only the buckets that look like
genuine groups (enough members, more than one distinct position). Kept free
of SQL so it is trivially unit-testable; `make.py` feeds it rows and hands
the result to `db_manager` for persistence.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any, Iterable, Sequence

from .base import EntryRef, GroupingStrategy


@dataclass(frozen=True)
class GroupMember:
    slug: str
    index: int
    label: str


@dataclass(frozen=True)
class EntryGroup:
    id: str
    kind: str
    title: str
    platform: str
    members: list[GroupMember]
    metadata: dict[str, Any] = field(default_factory=dict)


#: A bucket is only a real group when at least this many entries land in it.
DEFAULT_MIN_MEMBERS = 2


def _group_id(kind: str, key: str) -> str:
    """Namespace the bucket key by kind so ids stay unique across strategies."""
    return f"{kind}:{key}"


def build_groups(
    entries: Iterable[EntryRef],
    strategies: Sequence[GroupingStrategy],
    *,
    min_members: int = DEFAULT_MIN_MEMBERS,
) -> list[EntryGroup]:
    """Bucket memberships per strategy and return the promoted groups.

    A bucket is promoted only when it holds >= `min_members` entries AND
    spans more than one distinct index. The index guard is what keeps
    unrelated same-titled dumps (or a lone ``(Disc 1)``) from forming a
    bogus one-position "group".
    """
    entries = list(entries)
    groups: list[EntryGroup] = []

    for strategy in strategies:
        buckets: dict[str, list[tuple[EntryRef, Any]]] = defaultdict(list)
        for entry in entries:
            member = strategy.membership(entry)
            if member is not None:
                buckets[member.key].append((entry, member))

        for key, items in buckets.items():
            # Collapse to one entry per position. The same physical
            # disc is sometimes catalogued twice under different labels
            by_index: dict[int, tuple[EntryRef, Any]] = {}
            for entry, member in items:
                current = by_index.get(member.index)
                if current is None or entry.slug < current[0].slug:
                    by_index[member.index] = (entry, member)

            if len(by_index) < min_members:
                continue

            ordered = sorted(by_index.values(), key=lambda im: im[1].index)
            canonical = ordered[0][1]
            groups.append(
                EntryGroup(
                    id=_group_id(strategy.kind, key),
                    kind=strategy.kind,
                    title=canonical.title,
                    platform=ordered[0][0].platform,
                    members=[
                        GroupMember(slug=e.slug, index=m.index, label=m.label)
                        for e, m in ordered
                    ],
                    metadata=dict(canonical.metadata),
                )
            )

    return groups
