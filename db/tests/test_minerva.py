"""
MiNERVA scraper tests.

Fixture-driven (db/tests/fixtures/minerva_index.txt.gz +
minerva_hashes.db); doesn't touch the 1.76 GB upstream DB.
"""
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

import pytest

DB_ROOT = Path(__file__).resolve().parent.parent
if str(DB_ROOT) not in sys.path:
    sys.path.insert(0, str(DB_ROOT))

from core.contract import BuildContext, PlatformConfig  # noqa: E402
from sources.minerva.scraper import (  # noqa: E402
    MinervaSource,
    _extract_infohash,
    _extract_trackers,
    _load_index,
    _select_paths,
    scrape_with_artefacts,
)


FIXTURES = DB_ROOT / "tests" / "fixtures"
INDEX_FIXTURE = FIXTURES / "minerva_index.txt.gz"
DB_FIXTURE = FIXTURES / "minerva_hashes.db"

NES_PREFIX = "./No-Intro/Nintendo - Nintendo Entertainment System (Headered)/"
SNES_PREFIX = "./No-Intro/Nintendo - Super Nintendo Entertainment System/"
NES_HASH = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SNES_HASH = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


@pytest.fixture(scope="module")
def index() -> list[str]:
    assert INDEX_FIXTURE.is_file(), (
        "minerva_index.txt.gz fixture missing; run "
        "tests/fixtures/build_minerva_fixture.py"
    )
    return _load_index(INDEX_FIXTURE)


@pytest.fixture()
def db():
    assert DB_FIXTURE.is_file(), (
        "minerva_hashes.db fixture missing; run "
        "tests/fixtures/build_minerva_fixture.py"
    )
    con = sqlite3.connect(f"file:{DB_FIXTURE}?mode=ro", uri=True)
    yield con
    con.close()


def _config_for(platform: str, prefixes: list[str]) -> PlatformConfig:
    return PlatformConfig(
        format=platform,
        regions=["us"],
        urls=prefixes,
        type="Game",
        parsers={},
        filter=r"(.*)\.zip",
    )


# -- pure helpers ------------------------------------------------------------

def test_extract_infohash_hex():
    magnet = f"magnet:?xt=urn:btih:{NES_HASH}&dn=foo"
    assert _extract_infohash(magnet) == NES_HASH


def test_extract_infohash_returns_none_when_absent():
    assert _extract_infohash("magnet:?dn=foo") is None
    assert _extract_infohash("") is None


def test_extract_trackers_unwraps_percent_encoding():
    magnet = (
        "magnet:?xt=urn:btih:" + NES_HASH +
        "&tr=udp%3A%2F%2Ftracker.example%3A1337%2Fannounce"
    )
    assert _extract_trackers(magnet) == [
        "udp://tracker.example:1337/announce"
    ]


def test_select_paths_prefix_match():
    idx = ["./a/x.zip", "./a/sub/y.zip", "./b/z.zip"]
    assert _select_paths(idx, ["./a/"]) == ["./a/x.zip", "./a/sub/y.zip"]
    assert _select_paths(idx, ["./b/"]) == ["./b/z.zip"]


# -- end-to-end with fixtures ------------------------------------------------

def test_scrape_with_artefacts_emits_one_entry_per_file(index, db):
    cfg = _config_for("nes", [NES_PREFIX])
    entries = scrape_with_artefacts(cfg, "nes", index=index, db=db)

    titles = sorted(e["title"] for e in entries)
    assert titles == [
        "Legend of Zelda, The (USA)",
        "Megaman 2 (USA)",
        "Super Mario Bros. (USA)",
    ]


def test_scrape_links_carry_torrent_metadata(index, db):
    cfg = _config_for("nes", [NES_PREFIX])
    entries = scrape_with_artefacts(cfg, "nes", index=index, db=db)

    for entry in entries:
        link = entry["links"][0]
        assert link["host"] == "MiNERVA Archive"
        assert link["torrent_infohash"] == NES_HASH
        assert link["torrent_file_index"] in {0, 1, 2}
        assert link["torrent_file_path"].startswith(
            "No-Intro/Nintendo - Nintendo Entertainment System"
        )
        meta = link["_torrent_meta"]
        assert meta["infohash"] == NES_HASH
        assert meta["source_id"] == "minerva"
        assert meta["name"] == "nes_pack.torrent"
        assert meta["magnet"].startswith("magnet:?xt=urn:btih:")


def test_scrape_distinguishes_torrents_per_platform(index, db):
    cfg = _config_for("snes", [SNES_PREFIX])
    entries = scrape_with_artefacts(cfg, "snes", index=index, db=db)
    titles = sorted(e["title"] for e in entries)
    assert titles == ["Final Fantasy III (USA)", "Super Metroid (USA)"]
    for entry in entries:
        assert entry["links"][0]["torrent_infohash"] == SNES_HASH


def test_scrape_filter_excludes_non_matches(index, db):
    # filter narrows to .zip; if we provide a filter that matches nothing,
    # we get zero entries, not a crash.
    cfg = PlatformConfig(
        format="nes",
        regions=[],
        urls=[NES_PREFIX],
        type="Game",
        parsers={},
        filter=r"(.*)\.never_matches$",
    )
    assert scrape_with_artefacts(cfg, "nes", index=index, db=db) == []


def test_scrape_skips_paths_without_db_metadata(index, tmp_path):
    """If a path is in the index but missing from hashes.db, drop it."""
    empty_db_path = tmp_path / "empty.db"
    con = sqlite3.connect(empty_db_path)
    con.execute(
        "CREATE TABLE files (full_path TEXT PRIMARY KEY, file_name TEXT, "
        "size INTEGER, magnet TEXT, so_id TEXT, torrents TEXT)"
    )
    con.commit()
    con.close()

    con = sqlite3.connect(f"file:{empty_db_path}?mode=ro", uri=True)
    cfg = _config_for("nes", [NES_PREFIX])
    assert scrape_with_artefacts(cfg, "nes", index=index, db=con) == []
    con.close()


def test_scrape_returns_empty_when_no_urls(index, db):
    cfg = _config_for("nes", [])
    assert scrape_with_artefacts(cfg, "nes", index=index, db=db) == []


def test_minerva_source_skips_when_artefacts_missing(monkeypatch, tmp_path):
    """Build pipeline must keep going if MiNERVA artefacts aren't mirrored."""
    monkeypatch.delenv("MINERVA_HASHES_DB", raising=False)
    monkeypatch.delenv("MINERVA_INDEX_TXT", raising=False)
    monkeypatch.chdir(tmp_path)

    src = MinervaSource(_dummy_manifest())
    cfg = _config_for("nes", [NES_PREFIX])
    out = src.scrape("nes", cfg, BuildContext())
    assert out == []


def test_minerva_source_derives_index_when_index_file_is_gone(monkeypatch, tmp_path):
    """Upstream removed index.txt.gz; the path index comes from hashes.db."""
    monkeypatch.setenv("MINERVA_HASHES_DB", str(DB_FIXTURE))
    monkeypatch.delenv("MINERVA_INDEX_TXT", raising=False)
    monkeypatch.chdir(tmp_path)

    src = MinervaSource(_dummy_manifest())
    cfg = _config_for("nes", [NES_PREFIX])
    out = src.scrape("nes", cfg, BuildContext())
    assert sorted(e["title"] for e in out) == [
        "Legend of Zelda, The (USA)",
        "Megaman 2 (USA)",
        "Super Mario Bros. (USA)",
    ]


def test_minerva_source_uses_env_vars(monkeypatch):
    monkeypatch.setenv("MINERVA_HASHES_DB", str(DB_FIXTURE))
    monkeypatch.setenv("MINERVA_INDEX_TXT", str(INDEX_FIXTURE))

    src = MinervaSource(_dummy_manifest())
    cfg = _config_for("nes", [NES_PREFIX])
    out = src.scrape("nes", cfg, BuildContext())
    assert len(out) == 3


def _dummy_manifest():
    from core.contract import SourceManifest
    return SourceManifest(
        id="minerva",
        name="MiNERVA Archive",
        kind="catalog",
        homepage="https://minerva-archive.org",
        priority=200,
        platforms=("nes", "snes"),
        raw={"id": "minerva", "name": "MiNERVA Archive", "kind": "catalog"},
    )
