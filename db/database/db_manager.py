"""
This module provides functionality for managing a SQLite database used to store information about ROMs, platforms, regions, and associated metadata. 
It includes methods for initializing the database, inserting or updating entries, and closing the database connection.
"""
import sqlite3
import os
from utils.parse_utils import create_slug, create_search_key

DB_NAME = 'romdb.db'
DB_TEMP_NAME = 'romdb_temp.db'
DB_OLD_NAME = 'romdb_old.db'

con = None
cur = None

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


def init_database():
    """Initialize the database by creating tables, indexes, and populating initial data."""
    global con, cur

    if os.path.exists(DB_TEMP_NAME):
        os.remove(DB_TEMP_NAME)

    con = sqlite3.connect(DB_TEMP_NAME)
    cur = con.cursor()

    # Enable FTS5
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
            FOREIGN KEY (platform) REFERENCES platforms (id)
        )
    ''')

    cur.execute('''
        CREATE VIRTUAL TABLE entries_fts USING fts5(
            search_key,
            content='entries',
            content_rowid='rowid',
            tokenize='trigram'
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
        CREATE TABLE links (
            entry TEXT,
            name TEXT,
            type TEXT,
            format TEXT,
            url TEXT,
            filename TEXT,
            host TEXT,
            size INTEGER,
            size_str TEXT,
            source_url TEXT,
            FOREIGN KEY (entry) REFERENCES entries (slug)
        )
    ''')

    cur.execute('CREATE INDEX idx_entries_platform ON entries (platform);')
    cur.execute(
        'CREATE INDEX idx_regions_entries_entry ON regions_entries (entry);')
    cur.execute(
        'CREATE INDEX idx_regions_entries_region ON regions_entries (region);')
    cur.execute('CREATE INDEX idx_links_entry ON links (entry);')

    for id, info in PLATFORMS.items():
        cur.execute('INSERT INTO platforms (id, brand, name) VALUES (?, ?, ?)',
                    (id, info['brand'], info['name']))

    for id, name in REGIONS.items():
        cur.execute('INSERT INTO regions (id, name) VALUES (?, ?)', (id, name))


def insert_entry(entry: dict):
    """Insert a new entry into the database or update it if it exists."""
    entry['slug'] = create_slug(entry)
    entry['search_key'] = create_search_key(entry['title'])

    # Check if an entry with the same slug exists
    cur.execute("SELECT slug FROM entries WHERE slug = ?", (entry['slug'],))
    existing_entry = cur.fetchone()

    if existing_entry:
        # Update fields where they are NULL
        cur.execute('''
            UPDATE entries
            SET rom_id = COALESCE(rom_id, ?),
                search_key = COALESCE(search_key, ?),
                title = COALESCE(title, ?),
                platform = COALESCE(platform, ?),
                boxart_url = COALESCE(boxart_url, ?)
            WHERE slug = ?
        ''', (
            entry.get('rom_id'),
            entry.get('search_key'),
            entry.get('title'),
            entry.get('platform'),
            entry.get('boxart_url'),
            entry['slug']
        ))

        # Add new links
        for link in entry.get('links', []):
            cur.execute('''
                INSERT OR IGNORE INTO links (entry, name, type, format, url, filename, host, size, size_str, source_url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                entry.get('slug'),
                link.get('name'),
                link.get('type'),
                link.get('format'),
                link.get('url'),
                link.get('filename'),
                link.get('host'),
                link.get('size'),
                link.get('size_str'),
                link.get('source_url')
            ))
    else:
        # Insert the new entry into the entries table
        cur.execute('''
            INSERT INTO entries (slug, rom_id, search_key, title, platform, boxart_url)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (
            entry.get('slug'),
            entry.get('rom_id'),
            entry.get('search_key'),
            entry.get('title'),
            entry.get('platform'),
            entry.get('boxart_url')
        ))

        # Insert into the FTS5 table
        cur.execute('''
            INSERT INTO entries_fts (rowid, search_key)
            VALUES (last_insert_rowid(), ?)
        ''', (entry['search_key'],))

        # Insert regions into the regions_entries table
        for region in entry.get('regions', []):
            cur.execute('''
                INSERT OR IGNORE INTO regions_entries (entry, region)
                VALUES (?, ?)
            ''', (entry.get('slug'), region))

        # Insert links into the links table
        for link in entry.get('links', []):
            cur.execute('''
                INSERT INTO links (entry, name, type, format, url, filename, host, size, size_str, source_url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                entry.get('slug'),
                link.get('name'),
                link.get('type'),
                link.get('format'),
                link.get('url'),
                link.get('filename'),
                link.get('host'),
                link.get('size'),
                link.get('size_str'),
                link.get('source_url')
            ))


def close_database():
    """Close the database connection and finalize changes."""
    con.commit()

    cur.close()
    con.close()

    if os.path.exists(DB_NAME):
        if os.path.exists(DB_OLD_NAME):
            os.remove(DB_OLD_NAME)
        os.rename(DB_NAME, DB_OLD_NAME)
    os.rename(DB_TEMP_NAME, DB_NAME)
