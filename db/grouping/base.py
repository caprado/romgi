"""
Entry-grouping contract.

A grouping strategy decides whether a single catalog entry participates in
a larger logical group (multi-disc games today; revisions, bundles, and
multi-part releases are natural future additions). Each strategy is pure:
it inspects one entry at a time and never depends on the others. The build
pass (see `build.py`) is what buckets memberships and promotes buckets with
enough members into real groups.

Strategies are discovered as plugins under `db/grouping/strategies/` — drop
a module exposing a `STRATEGY` symbol and nothing else in the pipeline needs
editing. This mirrors the source-plugin idiom in `db/sources/`.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable


@dataclass(frozen=True)
class EntryRef:
    """Minimal, read-only view of one catalog entry the grouping layer sees.

    `regions` is normalized (sorted, deduped) by the caller so that two
    members of the same product always hash to the same group key.
    """

    slug: str
    title: str
    platform: str
    regions: tuple[str, ...]


@dataclass(frozen=True)
class Membership:
    """A strategy's verdict that one entry belongs to a group.

    `key` is a stable bucket identifier shared by every member of the same
    group within a build. `index` orders members (e.g. disc number). `title`
    is the canonical group title with the grouping token stripped out.
    """

    key: str
    index: int
    label: str
    title: str
    metadata: dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class GroupingStrategy(Protocol):
    """Plugin contract. Expose an instance (or class) as `STRATEGY`."""

    #: Discriminator persisted on every group this strategy produces
    #: (e.g. 'disc'). Lets the app and future strategies coexist.
    kind: str

    def membership(self, entry: EntryRef) -> Membership | None:
        """Return a Membership if `entry` participates in a group of this
        kind, otherwise None. Must be pure — no dependence on other entries.
        """
        ...
