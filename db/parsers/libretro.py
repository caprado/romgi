"""
This module provides functionality for parsing and enriching game metadata 
from libretro DAT files. It includes platform-specific configurations, 
functions to load and parse DAT files, and methods to enhance game entries 
with ROM IDs and box art URLs.
"""
import requests
import re
from urllib.parse import quote, unquote
from utils.parse_utils import remove_ext

# Platform-specific metadata definitions
PLATFORMS = {
    'nes': {
        'system': 'Nintendo - Nintendo Entertainment System',
        'dats': [
            'metadat/no-intro/Nintendo - Nintendo Entertainment System.dat',
            'dat/Nintendo - Nintendo Entertainment System.dat'
        ]
    },
    'fds': {
        'system': 'Nintendo - Family Computer Disk System',
        'dats': [
            'metadat/no-intro/Nintendo - Family Computer Disk System.dat'
        ]
    },
    'snes': {
        'system': 'Nintendo - Super Nintendo Entertainment System',
        'dats': [
            'metadat/no-intro/Nintendo - Super Nintendo Entertainment System.dat',
            'dat/Nintendo - Super Nintendo Entertainment System.dat'
        ]
    },
    'gb': {
        'system': 'Nintendo - Game Boy',
        'dats': [
            'metadat/no-intro/Nintendo - Game Boy.dat'
        ]
    },
    'gbc': {
        'system': 'Nintendo - Game Boy Color',
        'dats': [
            'metadat/no-intro/Nintendo - Game Boy Color.dat'
        ]
    },
    'gba': {
        'system': 'Nintendo - Game Boy Advance',
        'dats': [
            'metadat/no-intro/Nintendo - Game Boy Advance.dat'
        ]
    },
    'min': {
        'system': 'Nintendo - Pokemon Mini',
        'dats': [
            'metadat/no-intro/Nintendo - Pokemon Mini.dat'
        ]
    },
    'vb': {
        'system': 'Nintendo - Virtual Boy',
        'dats': [
            'metadat/no-intro/Nintendo - Virtual Boy.dat'
        ]
    },
    'n64': {
        'system': 'Nintendo - Nintendo 64',
        'dats': [
            'metadat/no-intro/Nintendo - Nintendo 64.dat'
        ]
    },
    'ndd': {
        'system': 'Nintendo - Nintendo 64DD',
        'dats': [
            'metadat/no-intro/Nintendo - Nintendo 64DD.dat'
        ]
    },
    'gc': {
        'system': 'Nintendo - GameCube',
        'dats': [
            'metadat/redump/Nintendo - GameCube.dat',
            'dat/Nintendo - GameCube.dat'
        ]
    },
    'nds': {
        'system': 'Nintendo - Nintendo DS',
        'dats': [
            'metadat/no-intro/Nintendo - Nintendo DS.dat',
            'metadat/no-intro/Nintendo - Nintendo DS (Download Play).dat'
        ]
    },
    'dsi': {
        'system': 'Nintendo - Nintendo DSi',
        'dats': [
            'metadat/no-intro/Nintendo - Nintendo DSi.dat'
        ]
    },
    'wii': {
        'system': 'Nintendo - Wii',
        'dats': [
            'metadat/redump/Nintendo - Wii.dat',
            'dat/Nintendo - Wii.dat',
        ]
    },
    '3ds': {
        'system': 'Nintendo - Nintendo 3DS',
        'dats': [
            'metadat/no-intro/Nintendo - Nintendo 3DS.dat',
            'metadat/no-intro/Nintendo - Nintendo 3DS (Digital).dat'
        ]
    },
    'n3ds': {
        'system': 'Nintendo - Nintendo 3DS',
        'dats': [
            'metadat/no-intro/Nintendo - New Nintendo 3DS.dat',
            'metadat/no-intro/Nintendo - New Nintendo 3DS (Digital).dat'
        ]
    },
    'wiiu': {
        'system': 'Nintendo - Wii U',
        'dats': [
            'dat/Nintendo - Wii U.dat'
        ]
    },
    'ps1': {
        'system': 'Sony - PlayStation',
        'dats': [
            'metadat/redump/Sony - PlayStation.dat'
        ]
    },
    'ps2': {
        'system': 'Sony - PlayStation 2',
        'dats': [
            'metadat/redump/Sony - PlayStation 2.dat'
        ]
    },
    'psp': {
        'system': 'Sony - PlayStation Portable',
        'dats': [
            'metadat/redump/Sony - PlayStation Portable.dat',
            'metadat/no-intro/Sony - PlayStation Portable.dat',
            'metadat/no-intro/Sony - PlayStation Portable (PSN).dat',
            'metadat/no-intro/Sony - PlayStation Portable (PSX2PSP).dat',
            'metadat/no-intro/Sony - PlayStation Portable (UMD Music).dat',
            'metadat/no-intro/Sony - PlayStation Portable (UMD Video).dat',
            'dat/Sony - PlayStation Minis.dat'
        ]
    },
    'ps3': {
        'system': 'Sony - PlayStation 3',
        'dats': [
            'metadat/no-intro/Sony - PlayStation 3 (PSN).dat',
            'dat/Sony - PlayStation 3.dat'
        ]
    },
    'psv': {
        'system': 'Sony - PlayStation Vita',
        'dats': [
            'metadat/no-intro/Sony - PlayStation Vita.dat',
            'metadat/no-intro/Sony - PlayStation Vita (PSN).dat'
        ]
    },
    'xbox': {
        'system': 'Microsoft - Xbox',
        'dats': [
            'metadat/redump/Microsoft - Xbox.dat'
        ]
    },
    'x360': {
        'system': 'Microsoft - Xbox 360',
        'dats': [
            'metadat/redump/Microsoft - Xbox 360.dat',
            'metadat/no-intro/Microsoft - Xbox 360.dat',
            'metadat/no-intro/Microsoft - Xbox 360 (Digital).dat'
        ]
    },
    'sms': {
        'system': 'Sega - Master System - Mark III',
        'dats': [
            'metadat/no-intro/Sega - Master System - Mark III.dat'
        ]
    },
    'gg': {
        'system': 'Sega - Game Gear',
        'dats': [
            'metadat/no-intro/Sega - Game Gear.dat'
        ]
    },
    'smd': {
        'system': 'Sega - Mega Drive - Genesis',
        'dats': [
            'metadat/no-intro/Sega - Mega Drive - Genesis.dat'
        ]
    },
    'scd': {
        'system': 'Sega - Mega-CD - Sega CD',
        'dats': [
            'metadat/redump/Sega - Mega-CD - Sega CD.dat'
        ]
    },
    '32x': {
        'system': 'Sega - 32X',
        'dats': [
            'metadat/no-intro/Sega - 32X.dat'
        ]
    },
    'sat': {
        'system': 'Sega - Saturn',
        'dats': [
            'metadat/redump/Sega - Saturn.dat',
            'dat/Sega - Saturn.dat'
        ]
    },
    'dc': {
        'system': 'Sega - Dreamcast',
        'dats': [
            'metadat/redump/Sega - Dreamcast.dat'
        ]
    },
    'mame': {
        'system': 'MAME',
        'dats': []
    },
    'a26': {
        'system': 'Atari - 2600',
        'dats': [
            'metadat/no-intro/Atari - 2600.dat'
        ]
    },
    'a52': {
        'system': 'Atari - 5200',
        'dats': [
            'metadat/no-intro/Atari - 5200.dat'
        ]
    },
    'a78': {
        'system': 'Atari - 7800',
        'dats': [
            'metadat/no-intro/Atari - 7800.dat'
        ]
    },
    'lynx': {
        'system': 'Atari - Lynx',
        'dats': [
            'metadat/no-intro/Atari - Lynx.dat'
        ]
    },
    'jag': {
        'system': 'Atari - Jaguar',
        'dats': [
            'metadat/no-intro/Atari - Jaguar.dat'
        ]
    },
    'jcd': {
        'system': 'Atari - Jaguar CD',
        'dats': [
            'metadat/redump/Atari - Jaguar CD.dat'
        ]
    },
    'tg16': {
        'system': 'NEC - PC Engine - TurboGrafx 16',
        'dats': [
            'metadat/no-intro/NEC - PC Engine - TurboGrafx 16.dat'
        ]
    },
    'tgcd': {
        'system': 'NEC - PC Engine CD - TurboGrafx-CD',
        'dats': [
            'metadat/redump/NEC - PC Engine CD - TurboGrafx-CD.dat'
        ]
    },
    'pcfx': {
        'system': 'NEC - PC-FX',
        'dats': [
            'metadat/redump/NEC - PC-FX.dat'
        ]
    },
    'pc98': {
        'system': 'NEC - PC-98',
        'dats': [
            'metadat/redump/NEC - PC-98.dat',
            'dat/NEC - PC-98.dat'
        ]
    },
    'intv': {
        'system': 'Mattel - Intellivision',
        'dats': [
            'metadat/no-intro/Mattel - Intellivision.dat'
        ]
    },
    'cv': {
        'system': 'Coleco - ColecoVision',
        'dats': [
            'metadat/no-intro/Coleco - ColecoVision.dat'
        ]
    },
    '3do': {
        'system': 'The 3DO Company - 3DO',
        'dats': [
            'metadat/redump/The 3DO Company - 3DO.dat'
        ]
    },
    'cdi': {
        'system': 'Philips - CD-i',
        'dats': [
            'metadat/redump/Philips - CD-i.dat'
        ]
    },
    'ngcd': {
        'system': 'SNK - Neo Geo CD',
        'dats': [
            'metadat/redump/SNK - Neo Geo CD.dat'
        ]
    }
}

# Global variable to store parsed DATs
dbs = None


def load_dbs():
    """Load and parse the libretro DAT files for each platform."""
    global dbs
    dbs = {}

    for platform, data in PLATFORMS.items():
        dbs[platform] = {}

        for dat_filename in data['dats']:
            # Open and read the .dat file
            with open(f'data/libretro/{dat_filename}', encoding='utf-8') as f:
                lines = f.readlines()

            game = None
            in_rom_section = False
            for line in lines:
                line = line.strip()
                if line.startswith('game ('):
                    # Start of a new game entry
                    game = {}
                    in_rom_section = False
                elif line.startswith('rom ('):
                    # Start of a ROM section
                    in_rom_section = True
                    if line.endswith(')'):
                        # End of ROM section
                        in_rom_section = False
                elif line == ')':
                    # End of a game entry
                    if in_rom_section:
                        in_rom_section = False
                    elif game is not None:
                        # Save game data if both name and serial are present
                        if 'name' in game and 'serial' in game:
                            # Do not overwrite if present
                            if not game['name'] in dbs[platform]:
                                dbs[platform][game['name']] = game['serial']
                        game = None
                elif not in_rom_section:
                    # Parse game name and serial
                    if line.startswith('name') and game is not None:
                        game['name'] = line.split('"', 1)[1].rsplit('"', 1)[0]
                    elif line.startswith('serial') and game is not None:
                        game['serial'] = line.split(
                            '"', 1)[1].rsplit('"', 1)[0]


def parse(entries, flags):
    """Parse a list of entries and enrich them with ROM IDs and box art URLs."""
    if not dbs:
        load_dbs()

    for entry in entries:
        # Retrieve the database for the platform
        db = dbs.get(entry['platform'])
        entry['rom_id'] = db.get(entry['title'])

        # Construct the URL for box art thumbnails
        index_url = f"https://thumbnails.libretro.com/{quote(PLATFORMS[entry['platform']]['system'])}/Named_Boxarts/"

        # If box art list is not cached, fetch it from the server
        if not 'available_boxarts' in PLATFORMS[entry['platform']]:
            PLATFORMS[entry['platform']]['available_boxarts'] = []
            r = requests.get(index_url)

            # Extract box art filenames from the HTML response
            results = re.findall(
                r"<tr>.*alt=\"\[IMG\]\".*?href=\"(.*?)\".*?>.*?</tr>", r.text)
            for result in results:
                PLATFORMS[entry['platform']]['available_boxarts'].append(
                    remove_ext(unquote(result)))

        # Add box art URL if available
        if entry['title'] in PLATFORMS[entry['platform']]['available_boxarts']:
            entry['boxart_url'] = f"{index_url}{quote(entry['title'])}.png"

    return entries
