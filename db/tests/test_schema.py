"""
Catalog schema guarantees:

- All expected tables and link columns exist.
- register_source persists every manifest field.
- record_source_health upserts.
- insert_entry writes link fields with sane defaults.
- _tag_links defaults link.source_id to the manifest id and honours
  per-link overrides (e.g. IA marking a link as requires_auth).
- user_sources stays untouched by the build pipeline.

Run: python -m pytest tests
"""
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

import pytest

DB_ROOT = Path(__file__).resolve().parent.parent
if str(DB_ROOT) not in sys.path:
    sys.path.insert(0, str(DB_ROOT))

from core import load_registry  # noqa: E402
from database import db_manager  # noqa: E402
from make import _tag_links  # noqa: E402


@pytest.fixture()
def fresh_db(tmp_path, monkeypatch):
    """Run db_manager against a tmp working dir so we don't clobber db/."""
    monkeypatch.chdir(tmp_path)
    db_manager.con = None
    db_manager.cur = None
    db_manager.init_database()
    yield tmp_path
    db_manager.close_database()


def _table_columns(db_path: Path, table: str) -> list[str]:
    con = sqlite3.connect(db_path)
    try:
        return [r[1] for r in con.execute(f"PRAGMA table_info({table})").fetchall()]
    finally:
        con.close()


def test_schema_version_is_4():
    assert db_manager.SCHEMA_VERSION == 4


def test_init_creates_v2_tables(fresh_db):
    expected = {
        "platforms", "entries", "entries_fts", "regions",
        "regions_entries", "links",
        "sources", "source_health", "user_sources", "torrents",
        "entry_groups", "entry_group_members",
    }
    cur = db_manager.cur
    assert cur is not None
    rows = cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    actual = {r[0] for r in rows}
    missing = expected - actual
    assert not missing, f"Missing tables: {sorted(missing)}"


def test_entries_table_has_ra_columns(fresh_db):
    cur = db_manager.cur
    assert cur is not None
    cols = [r[1] for r in cur.execute("PRAGMA table_info(entries)").fetchall()]
    for required in ("ra_game_id", "ra_num_achievements"):
        assert required in cols, f"entries is missing column {required}"


def test_insert_entry_round_trips_ra_fields(fresh_db):
    registry = load_registry(DB_ROOT)
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)

    db_manager.insert_entry({
        "title": "Super Mario Bros.",
        "platform": "nes",
        "regions": ["us"],
        "links": [],
        "ra_game_id": 111,
        "ra_num_achievements": 30,
    })

    cur = db_manager.cur
    assert cur is not None
    row = cur.execute(
        "SELECT ra_game_id, ra_num_achievements FROM entries"
    ).fetchone()
    assert row == (111, 30)


def test_ra_fields_not_clobbered_on_reinsert(fresh_db):
    registry = load_registry(DB_ROOT)
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)

    base = {"title": "Super Mario Bros.", "platform": "nes",
            "regions": ["us"], "links": []}

    # First insert sets RA fields; a later insert of the same slug without
    # them must not COALESCE them back to NULL.
    db_manager.insert_entry({**base, "ra_game_id": 111, "ra_num_achievements": 30})
    db_manager.insert_entry(dict(base))

    cur = db_manager.cur
    assert cur is not None
    row = cur.execute(
        "SELECT ra_game_id, ra_num_achievements FROM entries"
    ).fetchone()
    assert row == (111, 30)


def test_links_table_has_v2_columns(fresh_db):
    cur = db_manager.cur
    assert cur is not None
    cols = [r[1] for r in cur.execute("PRAGMA table_info(links)").fetchall()]
    for required in (
        "source_id", "requires_auth",
        "torrent_infohash", "torrent_file_index", "torrent_file_path",
    ):
        assert required in cols, f"links is missing column {required}"


def test_register_source_persists_manifest(fresh_db):
    registry = load_registry(DB_ROOT)
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)

    cur = db_manager.cur
    assert cur is not None
    rows = cur.execute(
        "SELECT id, name, kind, auth_required, priority, manifest_json "
        "FROM sources ORDER BY id"
    ).fetchall()

    assert {r[0] for r in rows} == set(registry.ids())
    for source_id, name, kind, auth_required, priority, manifest_json in rows:
        m = registry.manifests[source_id]
        assert name == m.name
        assert kind == m.kind
        assert auth_required == int(bool(m.auth_required))
        assert priority == int(m.priority)
        # manifest_json should round-trip the raw dict
        parsed = json.loads(manifest_json)
        assert parsed["id"] == m.id
        assert parsed["name"] == m.name


def test_record_source_health_upserts(fresh_db):
    registry = load_registry(DB_ROOT)
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)

    db_manager.record_source_health(
        "minerva", "ok", entry_count=5, link_count=10, last_checked=1000
    )
    cur = db_manager.cur
    assert cur is not None
    row = cur.execute(
        "SELECT status, entry_count, link_count, last_checked "
        "FROM source_health WHERE source_id='minerva'"
    ).fetchone()
    assert row == ("ok", 5, 10, 1000)

    # upsert: same source_id replaces
    db_manager.record_source_health(
        "minerva", "down", reason="404", last_checked=2000,
    )
    row = cur.execute(
        "SELECT status, reason, last_checked FROM source_health "
        "WHERE source_id='minerva'"
    ).fetchone()
    assert row == ("down", "404", 2000)


def test_insert_entry_writes_v2_link_columns(fresh_db):
    registry = load_registry(DB_ROOT)
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)

    entry = {
        "title": "Sample",
        "platform": "nes",
        "regions": ["us"],
        "links": [
            {
                "name": "Sample",
                "type": "Game",
                "format": "nes",
                "url": "magnet:?xt=urn:btih:" + ("a" * 40),
                "filename": "x.zip",
                "host": "MiNERVA Archive",
                "size": 100,
                "size_str": "100",
                "source_url": "https://minerva-archive.org/",
                "source_id": "minerva",
                "requires_auth": 0,
            },
            {
                "name": "Sample (restricted)",
                "type": "Game",
                "format": "nes",
                "url": "https://archive.org/x.zip",
                "filename": "x.zip",
                "host": "Internet Archive",
                "size": 100,
                "size_str": "100",
                "source_url": "https://archive.org/",
                "source_id": "internet_archive",
                "requires_auth": 1,
            },
        ],
    }
    db_manager.insert_entry(entry)

    cur = db_manager.cur
    assert cur is not None
    rows = cur.execute(
        "SELECT source_id, requires_auth, torrent_infohash "
        "FROM links ORDER BY source_id"
    ).fetchall()
    assert rows == [
        ("internet_archive", 1, None),
        ("minerva", 0, None),
    ]


def test_tag_links_defaults_to_manifest_id():
    registry = load_registry(DB_ROOT)
    source = registry.get("minerva")
    assert source is not None

    entries = [
        {"links": [{"name": "a"}, {"name": "b"}]},
        {"links": [{"name": "c"}]},
    ]
    n_entries, n_links = _tag_links(entries, source)
    assert (n_entries, n_links) == (2, 3)
    for entry in entries:
        for link in entry["links"]:
            assert link["source_id"] == "minerva"
            assert link["requires_auth"] == 0


def test_tag_links_respects_per_link_override():
    registry = load_registry(DB_ROOT)
    source = registry.get("internet_archive")
    assert source is not None

    entries = [{
        "links": [
            {"name": "public"},
            {"name": "restricted", "requires_auth": 1},
        ],
    }]
    _tag_links(entries, source)
    assert entries[0]["links"][0]["requires_auth"] == 0
    assert entries[0]["links"][1]["requires_auth"] == 1
    for link in entries[0]["links"]:
        assert link["source_id"] == "internet_archive"


def test_user_sources_table_is_empty_after_build(fresh_db):
    registry = load_registry(DB_ROOT)
    for manifest in registry.manifests.values():
        db_manager.register_source(manifest)
    cur = db_manager.cur
    assert cur is not None
    count = cur.execute("SELECT COUNT(*) FROM user_sources").fetchone()[0]
    assert count == 0, "user_sources is reserved; build pipeline must not write to it"


def test_torrents_table_starts_empty(fresh_db):
    cur = db_manager.cur
    assert cur is not None
    count = cur.execute("SELECT COUNT(*) FROM torrents").fetchone()[0]
    assert count == 0
