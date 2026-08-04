"""
Catalog DB manager. Owns schema + write path.

Bumps to SCHEMA_VERSION trigger an app-side wipe-and-redownload on
the next launch; we don't run live migrations.
"""
import json
import os
import sqlite3
import time
from typing import Any

from utils.parse_utils import create_slug, create_search_key

DB_NAME = 'romdb.db'
DB_TEMP_NAME = 'romdb_temp.db'
DB_OLD_NAME = 'romdb_old.db'

# Bump on any schema change. The app reads version.json#schema_version
# and wipes its local catalog DB on mismatch.
# Mirror of: lib/services/rom_database_service.dart `kAppExpectedSchemaVersion`.
SCHEMA_VERSION = 4

con: sqlite3.Connection | None = None
cur: sqlite3.Cursor | None = None

PLATFORMS = {
    'nes': {'brand': 'Nintendo', 'name': 'Nintendo Entertainment System'},
    'fds': {'brand': 'Nintendo', 'name': 'Famicom Disk System'},
    'snes': {'brand': 'Nintendo', 'name': 'Super Nintendo Entertainment System'},
    'gb': {'brand': 'Nintendo', 'name': 'Game Boy'},
    'gbc': {'brand': 'Nintendo', 'name': 'Game Boy Color'},
    'gba': {'brand': 'Nintendo', 'name': 'Game Boy Advance'},
    'min': {'brand': 'Nintendo', 'name': 'Pokemon Mini'},
    'vb': {'brand': 'Nintendo', 'name': 'Virtual Boy'},
    'n64': {'brand': 'Nintendo', 'name': 'Nintendo 64'},
    'ndd': {'brand': 'Nintendo', 'name': 'Nintendo 64DD'},
    'gc': {'brand': 'Nintendo', 'name': 'GameCube'},
    'nds': {'brand': 'Nintendo', 'name': 'Nintendo DS'},
    'dsi': {'brand': 'Nintendo', 'name': 'Nintendo DSi'},
    'wii': {'brand': 'Nintendo', 'name': 'Wii'},
    '3ds': {'brand': 'Nintendo', 'name': 'Nintendo 3DS'},
    'n3ds': {'brand': 'Nintendo', 'name': 'New Nintendo 3DS'},
    'wiiu': {'brand': 'Nintendo', 'name': 'Wii U'},
    'ps1': {'brand': 'Sony', 'name': 'PlayStation'},
    'ps2': {'brand': 'Sony', 'name': 'PlayStation 2'},
    'psp': {'brand': 'Sony', 'name': 'PlayStation Portable'},
    'ps3': {'brand': 'Sony', 'name': 'PlayStation 3'},
    'psv': {'brand': 'Sony', 'name': 'PlayStation Vita'},
    'xbox': {'brand': 'Microsoft', 'name': 'Xbox'},
    'x360': {'brand': 'Microsoft', 'name': 'Xbox 360'},
    'sms': {'brand': 'Sega', 'name': 'Master System - Mark III'},
    'gg': {'brand': 'Sega', 'name': 'Game Gear'},
    'smd': {'brand': 'Sega', 'name': 'Mega Drive - Genesis'},
    'scd': {'brand': 'Sega', 'name': 'Mega-CD - Sega CD'},
    '32x': {'brand': 'Sega', 'name': '32X'},
    'sat': {'brand': 'Sega', 'name': 'Sega Saturn'},
    'dc': {'brand': 'Sega', 'name': 'Dreamcast'},
    'mame': {'brand': 'Arcade', 'name': 'MAME'},
    'fbneo': {'brand': 'Arcade', 'name': 'FinalBurn Neo'},
    'a26': {'brand': 'Atari', 'name': 'Atari 2600'},
    'a52': {'brand': 'Atari', 'name': 'Atari 5200'},
    'a78': {'brand': 'Atari', 'name': 'Atari 7800'},
    'lynx': {'brand': 'Atari', 'name': 'Atari Lynx'},
    'jag': {'brand': 'Atari', 'name': 'Atari Jaguar'},
    'jcd': {'brand': 'Atari', 'name': 'Atari Jaguar CD'},
    'tg16': {'brand': 'NEC', 'name': 'PC Engine - TurboGrafx-16'},
    'tgcd': {'brand': 'NEC', 'name': 'PC Engine CD - TurboGrafx-CD'},
    'pcfx': {'brand': 'NEC', 'name': 'PC-FX'},
    'pc98': {'brand': 'NEC', 'name': 'PC-98'},
    'intv': {'brand': 'Mattel', 'name': 'Intellivision'},
    'cv': {'brand': 'Coleco', 'name': 'ColecoVision'},
    '3do': {'brand': 'The 3DO Company', 'name': '3DO Interactive Multiplayer'},
    'cdi': {'brand': 'Philips', 'name': 'CD-i'},
    'fmt': {'brand': 'Fujitsu', 'name': 'FM Towns'},
    'ngcd': {'brand': 'SNK', 'name': 'Neo Geo CD'},
    'pip': {'brand': 'Apple-Bandai', 'name': 'Pippin'}
}

REGIONS = {
    'eu': 'Europe',
    'us': 'USA',
    'jp': 'Japan',
    'other': 'Other'
}


def init_database() -> None:
    """Initialize the database: create tables, indexes, seed static data."""
    global con, cur

    if os.path.exists(DB_TEMP_NAME):
        os.remove(DB_TEMP_NAME)

    con = sqlite3.connect(DB_TEMP_NAME)
    cur = con.cursor()

    cur.execute('PRAGMA foreign_keys = ON;')

    cur.execute('''
        CREATE TABLE platforms (
            id TEXT PRIMARY KEY,
            brand TEXT,
            name TEXT
        )
    ''')

    cur.execute('''
        CREATE TABLE entries (
            slug TEXT PRIMARY KEY,
            rom_id TEXT,
            search_key TEXT,
            title TEXT,
            platform TEXT,
            boxart_url TEXT,
            ra_game_id INTEGER,
            ra_num_achievements INTEGER,
            FOREIGN KEY (platform) REFERENCES platforms (id)
        )
    ''')

    cur.execute('''
        CREATE VIRTUAL TABLE entries_fts USING fts4(
            search_key,
            content='entries',
            tokenize=unicode61
        )
    ''')

    cur.execute('''
        CREATE TABLE regions (
            id TEXT PRIMARY KEY,
            name TEXT
        )
    ''')

    cur.execute('''
        CREATE TABLE regions_entries (
            entry TEXT,
            region TEXT,
            FOREIGN KEY (entry) REFERENCES entries (slug),
            FOREIGN KEY (region) REFERENCES regions (id)
        )
    ''')

    cur.execute('''
        CREATE TABLE sources (
            id            TEXT PRIMARY KEY,
            name          TEXT NOT NULL,
            homepage      TEXT,
            kind          TEXT NOT NULL,
            auth_required INTEGER NOT NULL DEFAULT 0,
            priority      INTEGER NOT NULL DEFAULT 0,
            manifest_json TEXT NOT NULL
        )
    ''')

    cur.execute('''
        CREATE TABLE source_health (
            source_id     TEXT PRIMARY KEY REFERENCES sources(id),
            status        TEXT NOT NULL,
            last_checked  INTEGER NOT NULL,
            reason        TEXT,
            entry_count   INTEGER,
            link_count    INTEGER
        )
    ''')

    # Reserved for user-supplied sources. The build pipeline never writes
    # here; the app owns it.
    cur.execute('''
        CREATE TABLE user_sources (
            id           TEXT PRIMARY KEY,
            name         TEXT NOT NULL,
            kind         TEXT NOT NULL,
            config_json  TEXT NOT NULL,
            created_at   INTEGER NOT NULL
        )
    ''')

    # Torrent metadata, deduped by infohash. Each links row that
    # represents a file inside a torrent points here via source_id.
    cur.execute('''
        CREATE TABLE torrents (
            infohash       TEXT PRIMARY KEY,
            source_id      TEXT NOT NULL REFERENCES sources(id),
            name           TEXT,
            magnet         TEXT,
            torrent_blob   BLOB,
            total_size     INTEGER,
            piece_length   INTEGER,
            file_count     INTEGER,
            trackers_json  TEXT,
            added_at       INTEGER NOT NULL
        )
    ''')

    cur.execute('''
        CREATE TABLE links (
            entry              TEXT,
            name               TEXT,
            type               TEXT,
            format             TEXT,
            url                TEXT,
            filename           TEXT,
            host               TEXT,
            size               INTEGER,
            size_str           TEXT,
            source_url         TEXT,
            source_id          TEXT REFERENCES sources(id),
            requires_auth      INTEGER NOT NULL DEFAULT 0,
            torrent_infohash   TEXT REFERENCES torrents(infohash),
            torrent_file_index INTEGER,
            torrent_file_path  TEXT,
            FOREIGN KEY (entry) REFERENCES entries (slug)
        )
    ''')

    # Logical groups relating entries (multi-disc games today; the `kind`
    # discriminator + metadata_json leave room for revisions/bundles later).
    cur.execute('''
        CREATE TABLE entry_groups (
            id            TEXT PRIMARY KEY,
            kind          TEXT NOT NULL,
            title         TEXT,
            platform      TEXT,
            member_count  INTEGER NOT NULL,
            metadata_json TEXT
        )
    ''')

    cur.execute('''
        CREATE TABLE entry_group_members (
            group_id     TEXT NOT NULL REFERENCES entry_groups (id),
            entry        TEXT NOT NULL REFERENCES entries (slug),
            member_index INTEGER,
            member_label TEXT,
            PRIMARY KEY (group_id, entry)
        )
    ''')

    cur.execute('CREATE INDEX idx_entries_platform ON entries (platform);')
    cur.execute('CREATE INDEX idx_entry_groups_kind ON entry_groups (kind);')
    cur.execute(
        'CREATE INDEX idx_group_members_entry ON entry_group_members (entry);')
    cur.execute(
        'CREATE INDEX idx_regions_entries_entry ON regions_entries (entry);')
    cur.execute(
        'CREATE INDEX idx_regions_entries_region ON regions_entries (region);')
    cur.execute('CREATE INDEX idx_links_entry ON links (entry);')
    cur.execute('CREATE INDEX idx_links_source ON links (source_id);')
    cur.execute('CREATE INDEX idx_links_torrent ON links (torrent_infohash);')

    for id, info in PLATFORMS.items():
        cur.execute('INSERT INTO platforms (id, brand, name) VALUES (?, ?, ?)',
                    (id, info['brand'], info['name']))

    for id, name in REGIONS.items():
        cur.execute('INSERT INTO regions (id, name) VALUES (?, ?)', (id, name))


def register_source(manifest: Any) -> None:
    """Insert a source row from a SourceManifest. Called once per source."""
    assert cur is not None
    cur.execute(
        'INSERT INTO sources '
        '(id, name, homepage, kind, auth_required, priority, manifest_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        (
            manifest.id,
            manifest.name,
            manifest.homepage,
            manifest.kind,
            int(bool(manifest.auth_required)),
            int(manifest.priority),
            json.dumps(manifest.raw, sort_keys=True),
        ),
    )


def register_torrent(
    *,
    infohash: str,
    source_id: str,
    name: str | None = None,
    magnet: str | None = None,
    torrent_blob: bytes | None = None,
    total_size: int | None = None,
    piece_length: int | None = None,
    file_count: int | None = None,
    trackers: list[str] | None = None,
    added_at: int | None = None,
) -> None:
    """Insert a torrent row idempotently (no-op if infohash already present)."""
    assert cur is not None
    ts = added_at if added_at is not None else int(time.time())
    cur.execute(
        'INSERT OR IGNORE INTO torrents '
        '(infohash, source_id, name, magnet, torrent_blob, '
        ' total_size, piece_length, file_count, trackers_json, added_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (
            infohash.lower(),
            source_id,
            name,
            magnet,
            torrent_blob,
            total_size,
            piece_length,
            file_count,
            json.dumps(trackers) if trackers is not None else None,
            ts,
        ),
    )


def record_source_health(
    source_id: str,
    status: str,
    *,
    reason: str | None = None,
    entry_count: int = 0,
    link_count: int = 0,
    last_checked: int | None = None,
) -> None:
    """Upsert a source_health row."""
    assert cur is not None
    ts = last_checked if last_checked is not None else int(time.time())
    cur.execute(
        'INSERT OR REPLACE INTO source_health '
        '(source_id, status, last_checked, reason, entry_count, link_count) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        (source_id, status, ts, reason, entry_count, link_count),
    )


def insert_entry(entry: dict[str, Any]) -> None:
    """Insert a new entry into the database or update it if it exists."""
    assert cur is not None
    entry['slug'] = create_slug(entry)
    entry['search_key'] = create_search_key(entry['title'])

    cur.execute("SELECT slug FROM entries WHERE slug = ?", (entry['slug'],))
    existing_entry = cur.fetchone()

    if existing_entry:
        cur.execute('''
            UPDATE entries
            SET rom_id = COALESCE(rom_id, ?),
                search_key = COALESCE(search_key, ?),
                title = COALESCE(title, ?),
                platform = COALESCE(platform, ?),
                boxart_url = COALESCE(boxart_url, ?),
                ra_game_id = COALESCE(ra_game_id, ?),
                ra_num_achievements = COALESCE(ra_num_achievements, ?)
            WHERE slug = ?
        ''', (
            entry.get('rom_id'),
            entry.get('search_key'),
            entry.get('title'),
            entry.get('platform'),
            entry.get('boxart_url'),
            entry.get('ra_game_id'),
            entry.get('ra_num_achievements'),
            entry['slug']
        ))

        for link in entry.get('links', []):
            _insert_link(entry['slug'], link, ignore_duplicates=True)
    else:
        cur.execute('''
            INSERT INTO entries (slug, rom_id, search_key, title, platform, boxart_url,
                                 ra_game_id, ra_num_achievements)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            entry.get('slug'),
            entry.get('rom_id'),
            entry.get('search_key'),
            entry.get('title'),
            entry.get('platform'),
            entry.get('boxart_url'),
            entry.get('ra_game_id'),
            entry.get('ra_num_achievements')
        ))

        cur.execute('''
            INSERT INTO entries_fts (docid, search_key)
            VALUES (last_insert_rowid(), ?)
        ''', (entry['search_key'],))

        for region in entry.get('regions', []):
            cur.execute('''
                INSERT OR IGNORE INTO regions_entries (entry, region)
                VALUES (?, ?)
            ''', (entry.get('slug'), region))

        for link in entry.get('links', []):
            _insert_link(entry['slug'], link, ignore_duplicates=False)


def _insert_link(entry_slug: str, link: dict[str, Any], *, ignore_duplicates: bool) -> None:
    """Insert one link row.

    If `_torrent_meta` is set on the link, the corresponding torrents
    row is upserted first so scrapers don't have to call register_torrent.
    """
    assert cur is not None
    meta = link.get('_torrent_meta')
    if meta is not None:
        register_torrent(**meta)

    sql = (
        'INSERT OR IGNORE INTO links (' if ignore_duplicates
        else 'INSERT INTO links ('
    ) + (
        'entry, name, type, format, url, filename, host, size, size_str, '
        'source_url, source_id, requires_auth, '
        'torrent_infohash, torrent_file_index, torrent_file_path'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )
    cur.execute(sql, (
        entry_slug,
        link.get('name'),
        link.get('type'),
        link.get('format'),
        link.get('url'),
        link.get('filename'),
        link.get('host'),
        link.get('size'),
        link.get('size_str'),
        link.get('source_url'),
        link.get('source_id'),
        int(bool(link.get('requires_auth'))),
        link.get('torrent_infohash'),
        link.get('torrent_file_index'),
        link.get('torrent_file_path'),
    ))


def fetch_entries_for_grouping() -> list[tuple[str, str, str, tuple[str, ...]]]:
    """Return (slug, title, platform, regions) for every entry.

    Regions are sorted+deduped so grouping keys are order-independent. Called
    by the build driver after all entries are inserted, before close.
    """
    assert cur is not None
    cur.execute('''
        SELECT e.slug, e.title, e.platform, GROUP_CONCAT(re.region)
        FROM entries e
        LEFT JOIN regions_entries re ON re.entry = e.slug
        GROUP BY e.slug
    ''')
    out: list[tuple[str, str, str, tuple[str, ...]]] = []
    for slug, title, platform, regions_csv in cur.fetchall():
        regions = tuple(sorted({r for r in (regions_csv or '').split(',') if r}))
        out.append((slug, title, platform, regions))
    return out


def store_entry_groups(groups: Any) -> None:
    """Persist grouping results into entry_groups / entry_group_members."""
    assert cur is not None
    for group in groups:
        cur.execute('''
            INSERT INTO entry_groups
                (id, kind, title, platform, member_count, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (
            group.id,
            group.kind,
            group.title,
            group.platform,
            len(group.members),
            json.dumps(group.metadata, sort_keys=True) if group.metadata else None,
        ))
        for member in group.members:
            cur.execute('''
                INSERT OR IGNORE INTO entry_group_members
                    (group_id, entry, member_index, member_label)
                VALUES (?, ?, ?, ?)
            ''', (group.id, member.slug, member.index, member.label))


def close_database() -> None:
    """Close the database connection and finalize changes."""
    assert con is not None
    assert cur is not None
    con.commit()

    cur.close()
    con.close()

    if os.path.exists(DB_NAME):
        if os.path.exists(DB_OLD_NAME):
            os.remove(DB_OLD_NAME)
        os.rename(DB_NAME, DB_OLD_NAME)
    os.rename(DB_TEMP_NAME, DB_NAME)
