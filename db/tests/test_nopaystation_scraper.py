"""Tests for sources/nopaystation/scraper.py."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import pytest
from sources.nopaystation import scraper as nps
from sources.nopaystation.scraper import (
    add_ps3_links,
    add_psv_links,
    create_entry,
    create_rap_file,
    create_zrif_file,
    parse_links,
    parse_response,
)

MOCK_TSV = (
    "Title ID\tRegion\tName\tPKG direct link\tContent ID\tRAP\tFile Size\n"
    "BLUS12345\tUS\tTest Game\thttps://example.com/BLUS12345.pkg\t"
    "UP1234-BLUS12345_00\t0123456789abcdef0123456789abcdef\t1073741824\n"
    "BLES67890\tEU\tAnother Game\thttps://example.com/BLES67890.pkg\t"
    "EP5678-BLES67890_00\t\t524288000\n"
)


def _source() -> dict[str, Any]:
    return {
        'filter': None,
        'regions': [],
        'type': 'Game',
        'format': 'pkg',
        'urls': ['https://nopaystation.com/tsv/PS3_GAMES.tsv'],
    }


def _result(
    title_id: str = 'BLUS12345',
    region: str = 'US',
    name: str = 'Test Game',
    url: str = 'https://example.com/test.pkg',
    content_id: str = 'UP1234-BLUS12345_00',
    rap: str = '',
    size: str = '1073741824',
) -> dict[str, str]:
    return {
        'Title ID': title_id,
        'Region': region,
        'Name': name,
        'PKG direct link': url,
        'Content ID': content_id,
        'RAP': rap,
        'File Size': size,
    }


# -- create_entry ------------------------------------------------------------

def test_create_entry_basic():
    entry = create_entry(_result(), _source(), 'ps3', 'https://nps.com')
    assert entry['rom_id'] == 'BLUS12345'
    assert entry['title'] == 'Test Game'
    assert entry['platform'] == 'ps3'
    assert entry['regions'] == ['us']


def test_create_entry_unknown_region():
    entry = create_entry(_result(region='XX'), _source(), 'ps3', 'https://nps.com')
    assert entry['regions'] == ['other']


def test_create_entry_invalid_url_no_links():
    entry = create_entry(_result(url='MISSING'), _source(), 'ps3', 'https://nps.com')
    assert entry['links'] == []


# -- parse_links -------------------------------------------------------------

def test_parse_links_direct_url():
    links = parse_links(_result(), _source(), 'ps3', 'https://nps.com')
    assert len(links) >= 1
    assert links[0]['url'] == 'https://example.com/test.pkg'


def test_parse_links_names_file_after_title():
    links = parse_links(
        _result(url='https://cdn.example.com/fSndUWIDQSWRWhQnmRat.pkg'),
        _source(), 'ps3', 'https://nps.com',
    )
    assert links[0]['filename'] == 'Test Game.pkg'


def test_parse_links_sanitizes_title_and_defaults_extension():
    links = parse_links(
        _result(name='Game: Redux?', url='https://cdn.example.com/tokenwithoutext'),
        _source(), 'ps3', 'https://nps.com',
    )
    assert links[0]['filename'] == 'Game Redux.pkg'


def test_parse_links_zero_size():
    links = parse_links(_result(size=''), _source(), 'ps3', 'https://nps.com')
    assert links[0]['size'] == 0


def test_parse_links_missing_url():
    links = parse_links(_result(url=''), _source(), 'ps3', 'https://nps.com')
    assert len(links) == 0


# -- parse_response ----------------------------------------------------------

def test_parse_response_basic(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(nps, 'PS3_RAPS_DIR', str(tmp_path / 'raps'))
    monkeypatch.setattr(nps, 'PSV_ZRIFS_DIR', str(tmp_path / 'zrifs'))
    (tmp_path / 'raps').mkdir()
    (tmp_path / 'zrifs').mkdir()
    entries = parse_response(MOCK_TSV, _source(), 'ps3', 'https://nps.com')
    assert len(entries) == 2
    assert entries[0]['rom_id'] == 'BLUS12345'
    assert entries[1]['rom_id'] == 'BLES67890'


def test_parse_response_empty():
    assert parse_response('', _source(), 'ps3', 'https://nps.com') == []


def test_parse_response_header_only():
    header = "Title ID\tRegion\tName\tPKG direct link\tContent ID\tRAP\tFile Size\n"
    assert parse_response(header, _source(), 'ps3', 'https://nps.com') == []


# -- create_rap_file / create_zrif_file --------------------------------------

def test_create_rap_file(tmp_path: Path):
    filepath = str(tmp_path / 'test.rap')
    create_rap_file('0123456789abcdef0123456789abcdef', filepath)
    assert os.path.exists(filepath)
    with open(filepath, 'rb') as f:
        assert len(f.read()) == 16


def test_create_zrif_file(tmp_path: Path):
    filepath = str(tmp_path / 'test.zrif')
    create_zrif_file('KO5ifR1dQ+eHBw==', filepath)
    assert os.path.exists(filepath)
    with open(filepath, 'r') as f:
        assert f.read() == 'KO5ifR1dQ+eHBw=='


# -- add_ps3_links -----------------------------------------------------------

def test_add_ps3_links_creates_rap(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(nps, 'PS3_RAPS_DIR', str(tmp_path))
    result = {
        'Name': 'Test Game',
        'RAP': '0123456789abcdef0123456789abcdef',
        'Content ID': 'UP1234-BLUS12345_00',
    }
    links: list[dict[str, Any]] = []
    add_ps3_links(result, links, 'https://nps.com')
    assert len(links) == 1
    assert links[0]['format'] == 'rap'
    assert os.path.exists(tmp_path / 'UP1234-BLUS12345_00.rap')


def test_add_ps3_links_skips_short_rap(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(nps, 'PS3_RAPS_DIR', str(tmp_path))
    result = {'Name': 'Test', 'RAP': 'tooshort', 'Content ID': 'XX'}
    links: list[dict[str, Any]] = []
    add_ps3_links(result, links, 'https://nps.com')
    assert len(links) == 0


def test_add_ps3_links_skips_empty_content_id(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(nps, 'PS3_RAPS_DIR', str(tmp_path))
    result = {'Name': 'Test', 'RAP': '0123456789abcdef0123456789abcdef', 'Content ID': ''}
    links: list[dict[str, Any]] = []
    add_ps3_links(result, links, 'https://nps.com')
    assert len(links) == 0


# -- add_psv_links -----------------------------------------------------------

def test_add_psv_links_creates_zrif(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(nps, 'PSV_ZRIFS_DIR', str(tmp_path))
    result = {
        'Name': 'Vita Game',
        'zRIF': 'KO5ifR1dQ+eHBw==',
        'Content ID': 'PCSE12345',
    }
    links: list[dict[str, Any]] = []
    add_psv_links(result, links, 'https://nps.com')
    assert len(links) == 1
    assert links[0]['format'] == 'string'
    assert os.path.exists(tmp_path / 'PCSE12345')


def test_add_psv_links_skips_empty_zrif(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(nps, 'PSV_ZRIFS_DIR', str(tmp_path))
    result = {'Name': 'Test', 'zRIF': '', 'Content ID': 'PCSE12345'}
    links: list[dict[str, Any]] = []
    add_psv_links(result, links, 'https://nps.com')
    assert len(links) == 0
