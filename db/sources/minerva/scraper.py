"""
MiNERVA source plugin.

Reads two upstream artefacts the build pipeline mirrors locally:

    data/minerva/hashes.db   SQLite per-file metadata (magnet, so_id,
                             torrents, sha1, ...)
    data/minerva/index.txt   optional flat list of every path; derived
                             from hashes.db when absent (upstream
                             removed the file in Aug 2026)

For each platform's path prefix(es), join the index with hashes.db and
emit one entry per ROM file. Each link carries the torrent infohash and
file index so the TorrentAdapter can do selective-file downloads.
"""
from __future__ import annotations

import gzip
import os
import re
import sqlite3
import urllib.parse
from pathlib import Path

from typing import Any
from core.contract import BuildContext, PlatformConfig, SourceManifest


HOST_NAME = 'MiNERVA Archive'
ENV_HASHES_DB = 'MINERVA_HASHES_DB'
ENV_INDEX_TXT = 'MINERVA_INDEX_TXT'
DEFAULT_DATA_DIR = 'data/minerva'

_INFOHASH_RE = re.compile(r'urn:btih:([0-9a-fA-F]{40}|[A-Z2-7]{32})', re.IGNORECASE)
_TRACKER_RE = re.compile(r'[?&]tr=([^&]+)', re.IGNORECASE)


def _resolve_artefact(env_key: str, default_relpath: str) -> Path | None:
    """Find a MiNERVA artefact via env var or default-cache location."""
    env = os.environ.get(env_key)
    if env:
        p = Path(env)
        return p if p.is_file() else None
    p = Path(default_relpath)
    return p if p.is_file() else None


def _load_index(index_path: Path) -> list[str]:
    """Load index.txt(.gz) as a list of paths."""
    if str(index_path).endswith('.gz'):
        with gzip.open(index_path, 'rb') as f:
            data = f.read()
    else:
        data = index_path.read_bytes()
    return [
        line.decode('utf-8', errors='replace')
        for line in data.splitlines()
        if line
    ]


def _extract_infohash(magnet: str) -> str | None:
    """Pull the BTIH infohash out of a magnet URI. Lowercase hex."""
    if not magnet:
        return None
    m = _INFOHASH_RE.search(magnet)
    if not m:
        return None
    raw = m.group(1)
    if len(raw) == 40:  # already hex
        return raw.lower()
    # Base32 encoding (legacy v1 magnets); decode to hex.
    import base64
    try:
        return base64.b32decode(raw.upper(), casefold=True).hex()
    except Exception:
        return None


def _extract_trackers(magnet: str) -> list[str]:
    if not magnet:
        return []
    return [urllib.parse.unquote(m.group(1)) for m in _TRACKER_RE.finditer(magnet)]


def _strip_extension(filename: str) -> str:
    """ROM-aware: take everything before the *last* dot, keep dotted titles."""
    return filename.rsplit('.', 1)[0] if '.' in filename else filename


def _path_to_filename(full_path: str) -> str:
    return full_path.rsplit('/', 1)[-1]


def _file_extension(filename: str) -> str:
    return filename.rsplit('.', 1)[-1].lower() if '.' in filename else ''


def _query_metadata(
    db: sqlite3.Connection,
    paths: list[str],
) -> dict[str, sqlite3.Row]:
    """Pull magnet/torrent/size info for the given full_paths.

    SQLite IN-clauses are limited (~999 params). Chunk to stay under the limit.
    """
    if not paths:
        return {}
    db.row_factory = sqlite3.Row
    out: dict[str, sqlite3.Row] = {}
    chunk = 800
    for i in range(0, len(paths), chunk):
        batch = paths[i:i + chunk]
        placeholders = ','.join('?' * len(batch))
        rows = db.execute(
            f'SELECT * FROM files WHERE full_path IN ({placeholders})',
            batch,
        ).fetchall()
        for r in rows:
            out[r['full_path']] = r
    return out


def _select_paths(index: list[str], prefixes: list[str]) -> list[str]:
    """Filter the path index by prefix match against any of the provided paths."""
    norm = [p if p.endswith('/') else p + '/' for p in prefixes]
    return [line for line in index if any(line.startswith(p) for p in norm)]


def scrape_with_artefacts(
    config: PlatformConfig,
    platform: str,
    *,
    index: list[str],
    db: sqlite3.Connection,
) -> list[dict[str, Any]]:
    """Pure function over pre-loaded artefacts. Tests use this directly."""
    if not config.urls:
        return []

    paths = _select_paths(index, config.urls)
    if not paths:
        return []

    if config.filter:
        compiled = re.compile(config.filter)
        paths = [p for p in paths if compiled.match(_path_to_filename(p))]
        if not paths:
            return []

    metadata = _query_metadata(db, paths)
    entries: list[dict[str, Any]] = []

    for full_path in paths:
        meta = metadata.get(full_path)
        if meta is None:
            continue

        magnet = meta['magnet'] if 'magnet' in meta.keys() else None
        infohash = _extract_infohash(magnet) if magnet else None
        if not infohash:
            continue

        filename = _path_to_filename(full_path)
        title = _strip_extension(filename)
        ext = _file_extension(filename)
        size = int(meta['size']) if meta['size'] is not None else 0
        torrent_filename = meta['torrents'] if 'torrents' in meta.keys() else None
        so_id = meta['so_id'] if 'so_id' in meta.keys() else None
        try:
            file_index = int(so_id) if so_id is not None else None
        except (TypeError, ValueError):
            file_index = None

        full_magnet = magnet
        torrent_url = (
            f'https://minerva-archive.org/assets/{urllib.parse.quote(torrent_filename)}'
            if torrent_filename else None
        )

        entries.append({
            'title': title,
            'platform': platform,
            'regions': list(config.regions),
            'links': [
                {
                    'name': title,
                    'type': config.type or 'Game',
                    'format': config.format or ext,
                    'url': torrent_url or '',
                    'filename': filename,
                    'host': HOST_NAME,
                    'size': size,
                    'size_str': '',  # parsers will fill this from `size`
                    'source_url': torrent_url or '',
                    'torrent_infohash': infohash,
                    'torrent_file_index': file_index,
                    'torrent_file_path': full_path.lstrip('./'),
                    '_torrent_meta': {
                        'infohash': infohash,
                        'source_id': 'minerva',
                        'name': torrent_filename,
                        'magnet': full_magnet,
                        'trackers': _extract_trackers(full_magnet or ''),
                    },
                }
            ],
        })

    return entries


class MinervaSource:
    """Plugin entry point. Skips gracefully if artefacts aren't mirrored
    or the local hashes.db is corrupt (e.g. truncated mid-download).
    """

    def __init__(self, manifest: SourceManifest):
        self.manifest = manifest
        self._index: list[str] | None = None
        self._db: sqlite3.Connection | None = None
        self._artefacts_unusable = False

    def _ensure_artefacts(self) -> bool:
        if self._artefacts_unusable:
            return False
        if self._index is not None and self._db is not None:
            return True
        index_path = _resolve_artefact(ENV_INDEX_TXT, f'{DEFAULT_DATA_DIR}/index.txt.gz')
        if index_path is None:
            index_path = _resolve_artefact(ENV_INDEX_TXT, f'{DEFAULT_DATA_DIR}/index.txt')
        db_path = _resolve_artefact(ENV_HASHES_DB, f'{DEFAULT_DATA_DIR}/hashes.db')

        if db_path is None:
            print(
                f"  [minerva] hashes.db missing; skipping. Set "
                f"{ENV_HASHES_DB} or place it under {DEFAULT_DATA_DIR}/."
            )
            self._artefacts_unusable = True
            return False

        try:
            db = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
            # Trip a fast read to confirm the file is actually a SQLite
            # database. A truncated download will fail here rather than
            # later when we try to scan the files table.
            db.execute('SELECT name FROM sqlite_master LIMIT 1').fetchone()
            db.execute('SELECT 1 FROM files LIMIT 1').fetchone()
            self._db = db
        except sqlite3.DatabaseError as e:
            print(
                f"  [minerva] hashes.db at {db_path} is unusable ({e}); "
                f"skipping. Re-run `python workflow.py` to resume the "
                f"download (a .part file is preserved on disk)."
            )
            self._artefacts_unusable = True
            return False

        if index_path is not None:
            try:
                self._index = _load_index(index_path)
            except Exception as e:
                print(f"  [minerva] index unreadable ({index_path}): {e}; deriving from hashes.db.")

        if self._index is None:
            self._index = [
                row[0] for row in self._db.execute('SELECT full_path FROM files')
            ]
            print(f"  [minerva] index derived from hashes.db ({len(self._index):,} paths).")

        return True

    def scrape(
        self,
        platform: str,
        config: PlatformConfig,
        ctx: BuildContext,
    ) -> list[dict[str, Any]]:
        if not self._ensure_artefacts():
            return []
        assert self._index is not None and self._db is not None
        try:
            return scrape_with_artefacts(
                config, platform, index=self._index, db=self._db,
            )
        except sqlite3.DatabaseError as e:
            print(f"  [minerva] query failed ({e}); skipping rest of build.")
            self._artefacts_unusable = True
            return []


SOURCE = MinervaSource
