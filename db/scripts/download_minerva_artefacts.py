"""
Mirror MiNERVA's hashes.db into data/minerva/. The old index.txt.gz was
removed upstream; the scraper derives the path index from hashes.db.

ETag-cached: a HEAD request decides whether the local copy is fresh; if
so we skip the download. Supports resume via Range requests so a
partial 1.7 GB hashes.db can be picked up without restarting.
"""
from __future__ import annotations

import http.client
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable


_DEFAULT_DEST = Path('data/minerva')
_USER_AGENT = 'romgi/1.x (workflow.py)'
_TIMEOUT = 60

# (url, filename) pairs. The build pipeline references these by name.
_ARTEFACTS: list[tuple[str, str]] = [
    ('https://minerva-archive.org/assets/hashes.db', 'hashes.db'),
]


class MinervaDownloadError(RuntimeError):
    pass


def download_minerva_artefacts(
    *,
    dest: Path | None = None,
    artefacts: Iterable[tuple[str, str]] | None = None,
) -> None:
    """Download both artefacts. Network failures leave existing copies alone."""
    target = dest or _DEFAULT_DEST
    target.mkdir(parents=True, exist_ok=True)

    print('Downloading MiNERVA artefacts...')
    for url, name in (artefacts or _ARTEFACTS):
        _fetch_if_changed(url, target / name)


# -- internals ---------------------------------------------------------------

def _fetch_if_changed(url: str, dest: Path) -> None:
    """Download with atomic completion.

    The canonical file at `dest` is only created via `os.replace` after
    a complete download. In-progress bytes live in `dest.with_suffix(.part)`
    so a truncated download never gets handed to the scraper.
    """
    etag_path = dest.with_name(dest.name + '.etag')
    part_path = dest.with_name(dest.name + '.part')
    cached_etag = etag_path.read_text(encoding='utf-8').strip() if etag_path.is_file() else None

    try:
        head = _request(url, method='HEAD')
        remote_etag = (head.headers.get('ETag') or '').strip('"').strip()
        remote_size = int(head.headers.get('Content-Length') or 0)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
        print(f'  [minerva] HEAD {url} failed ({e}); leaving any existing copy in place.')
        return

    if (
        cached_etag
        and remote_etag
        and cached_etag == remote_etag
        and dest.is_file()
        and (remote_size == 0 or dest.stat().st_size == remote_size)
    ):
        size_str = _humanize(remote_size) if remote_size else f'{dest.stat().st_size:,} B'
        print(f'  [minerva] {dest.name} unchanged ({size_str}, etag matches), skipping.')
        return

    # Resume from the part file when available. If the canonical file
    # exists but the etag changed, restart from scratch.
    start = part_path.stat().st_size if part_path.is_file() else 0
    if remote_size and start >= remote_size:
        # Server's file shrank or the partial got bigger somehow; restart.
        start = 0
        try:
            part_path.unlink()
        except FileNotFoundError:
            pass

    if start:
        print(
            f'  [minerva] fetching {dest.name}'
            f' ({_humanize(remote_size)} total, resuming from {_humanize(start)})'
        )
    else:
        print(f'  [minerva] fetching {dest.name} ({_humanize(remote_size)})')

    try:
        _stream_download(url, part_path, start=start, total=remote_size)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
        print(f'  [minerva] download interrupted: {e}')
        print(f'  [minerva] partial copy retained at {part_path.name}; re-run to resume.')
        return

    final_size = part_path.stat().st_size
    if remote_size and final_size != remote_size:
        print(
            f'  [minerva] download finished short '
            f'({_humanize(final_size)} of {_humanize(remote_size)}); '
            f'leaving {part_path.name} in place to resume.'
        )
        return

    os.replace(part_path, dest)
    if remote_etag:
        etag_path.write_text(remote_etag, encoding='utf-8')
    print(f'  [minerva] {dest.name} done.')


def _stream_download(url: str, part_path: Path, *, start: int, total: int) -> None:
    headers = {'User-Agent': _USER_AGENT}
    mode = 'wb'
    if start > 0:
        headers['Range'] = f'bytes={start}-'
        mode = 'ab'

    req = urllib.request.Request(url, headers=headers, method='GET')
    with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp, part_path.open(mode) as f:
        downloaded = start
        chunk_size = 1 << 20  # 1 MiB
        last_print = 0.0
        while True:
            chunk = resp.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)
            downloaded += len(chunk)
            now = time.monotonic()
            if total and now - last_print >= 1.0:
                pct = downloaded / total * 100
                sys.stdout.write(
                    f'\r    {_humanize(downloaded)} / {_humanize(total)}  ({pct:5.1f}%)'
                )
                sys.stdout.flush()
                last_print = now
        if total:
            sys.stdout.write('\r' + ' ' * 60 + '\r')
            sys.stdout.flush()


def _request(url: str, *, method: str = 'GET') -> http.client.HTTPResponse:
    req = urllib.request.Request(
        url, headers={'User-Agent': _USER_AGENT}, method=method,
    )
    return urllib.request.urlopen(req, timeout=_TIMEOUT)


def _humanize(n: int) -> str:
    if n <= 0:
        return '0 B'
    size = float(n)
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if size < 1024:
            return f'{size:.1f} {unit}' if unit != 'B' else f'{size:.0f} {unit}'
        size /= 1024
    return f'{size:.1f} PB'


if __name__ == '__main__':
    download_minerva_artefacts()
