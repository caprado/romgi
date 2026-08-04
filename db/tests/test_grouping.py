"""
Entry-grouping guarantees:

- The disc strategy recognizes the positioned ``(Disc N)`` family and derives
  a stable, region-aware key with the token stripped.
- Real-catalog traps (bare ``(Disc)``, ``(Disk Writer)``, ``(Side N)``) are
  NOT treated as disc positions.
- Letter and roman disc labels order correctly.
- build_groups only promotes buckets with enough members AND >1 distinct
  position; region and platform partition groups.
- Strategy discovery finds the disc plugin.

Run from db/: python -m pytest tests
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

DB_ROOT = Path(__file__).resolve().parent.parent
if str(DB_ROOT) not in sys.path:
    sys.path.insert(0, str(DB_ROOT))

from grouping import EntryRef, build_groups, load_strategies  # noqa: E402
from grouping.strategies.disc import (  # noqa: E402
    DiscStrategy,
    _parse_index,
)


def _entry(title, platform="ps1", regions=("us",)):
    return EntryRef(slug=title.lower().replace(" ", "-"), title=title,
                    platform=platform, regions=tuple(regions))


# -- disc token recognition --------------------------------------------------

def test_matches_numeric_disc():
    m = DiscStrategy().membership(_entry("Final Fantasy VII (Disc 1)"))
    assert m is not None
    assert m.index == 1
    assert m.label == "Disc 1"
    assert m.title == "Final Fantasy VII"


def test_key_stable_across_discs():
    s = DiscStrategy()
    a = s.membership(_entry("Baten Kaitos (Disc 1)", platform="gc"))
    b = s.membership(_entry("Baten Kaitos (Disc 2)", platform="gc"))
    assert a is not None and b is not None
    assert a.key == b.key
    assert a.index != b.index


def test_zero_padded_and_of_tail():
    s = DiscStrategy()
    padded = s.membership(_entry("X (Disc 01)"))
    assert padded is not None and padded.index == 1
    tail = s.membership(_entry("X (Disc 1 of 3)"))
    assert tail is not None and tail.index == 1


# -- traps (must NOT be treated as disc positions) ---------------------------

def test_bare_disc_is_ignored():
    assert DiscStrategy().membership(_entry("Some Game (Disc)")) is None


def test_disk_writer_is_ignored():
    assert DiscStrategy().membership(_entry("Famicom Thing (Disk Writer)")) is None


def test_side_token_is_ignored():
    assert DiscStrategy().membership(_entry("Tape Game (Side 1)")) is None


def test_plain_title_is_ignored():
    assert DiscStrategy().membership(_entry("Chrono Trigger")) is None


# -- index parsing -----------------------------------------------------------

def test_parse_numeric():
    assert _parse_index("1") == 1
    assert _parse_index("05") == 5


def test_parse_letter_series():
    assert _parse_index("A") == 1
    assert _parse_index("B") == 2
    assert _parse_index("C") == 3  # letter series, not roman 100


def test_parse_roman():
    assert _parse_index("I") == 1
    assert _parse_index("II") == 2
    assert _parse_index("IV") == 4


def test_letter_and_roman_discs_group():
    s = DiscStrategy()
    a = s.membership(_entry("Lunar (Disc A)"))
    b = s.membership(_entry("Lunar (Disc B)"))
    assert a is not None and b is not None
    assert a.index == 1 and b.index == 2 and a.key == b.key


# -- build_groups promotion --------------------------------------------------

def test_two_discs_form_a_group():
    entries = [
        _entry("Baten Kaitos (Disc 1)", platform="gc"),
        _entry("Baten Kaitos (Disc 2)", platform="gc"),
        _entry("Chrono Trigger", platform="snes"),
    ]
    groups = build_groups(entries, load_strategies())
    assert len(groups) == 1
    g = groups[0]
    assert g.kind == "disc"
    assert g.title == "Baten Kaitos"
    assert [m.index for m in g.members] == [1, 2]
    assert g.id.startswith("disc:")


def test_lone_disc_one_not_promoted():
    entries = [_entry("Solo (Disc 1)")]
    assert build_groups(entries, load_strategies()) == []


def test_same_index_twice_not_promoted():
    # Two dumps both labelled Disc 1 (e.g. revisions) — no real second disc.
    entries = [
        EntryRef("a", "Game (Disc 1)", "ps1", ("us",)),
        EntryRef("b", "Game (Disc 1)", "ps1", ("us",)),
    ]
    assert build_groups(entries, load_strategies()) == []


def test_region_partitions_groups():
    entries = [
        _entry("Game (Disc 1)", regions=("us",)),
        _entry("Game (Disc 2)", regions=("us",)),
        _entry("Game (Disc 1)", regions=("eu",)),
        _entry("Game (Disc 2)", regions=("eu",)),
    ]
    groups = build_groups(entries, load_strategies())
    assert len(groups) == 2
    assert len({g.id for g in groups}) == 2  # distinct keys
    assert all(len(g.members) == 2 for g in groups)


def test_platform_partitions_groups():
    entries = [
        _entry("Game (Disc 1)", platform="ps1"),
        _entry("Game (Disc 2)", platform="ps1"),
        _entry("Game (Disc 1)", platform="sat"),
        _entry("Game (Disc 2)", platform="sat"),
    ]
    groups = build_groups(entries, load_strategies())
    assert len(groups) == 2


# -- discovery ---------------------------------------------------------------

def test_disc_strategy_is_discovered():
    kinds = {s.kind for s in load_strategies()}
    assert "disc" in kinds


# -- end-to-end build write path ---------------------------------------------

def test_build_entry_groups_persists(tmp_path, monkeypatch):
    """Exercise the real build wiring: schema -> insert -> group -> store."""
    monkeypatch.chdir(tmp_path)
    from database import db_manager
    from make import build_entry_groups

    db_manager.con = None
    db_manager.cur = None
    db_manager.init_database()
    try:
        for title in [
            "Baten Kaitos (Disc 1)",
            "Baten Kaitos (Disc 2)",
            "Chrono Trigger",
        ]:
            db_manager.insert_entry({
                "title": title, "platform": "gc", "regions": ["us"], "links": [],
            })

        build_entry_groups()

        cur = db_manager.cur
        assert cur is not None
        groups: list[Any] = cur.execute(
            "SELECT id, kind, title, member_count FROM entry_groups"
        ).fetchall()
        assert len(groups) == 1
        group_id, kind, title, count = groups[0]
        assert kind == "disc"
        assert title == "Baten Kaitos"
        assert count == 2

        members: list[Any] = cur.execute(
            "SELECT member_index FROM entry_group_members "
            "WHERE group_id = ? ORDER BY member_index",
            (group_id,),
        ).fetchall()
        assert [m[0] for m in members] == [1, 2]
    finally:
        db_manager.close_database()
