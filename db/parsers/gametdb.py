"""
This module provides functionality for parsing game data from GameTDB XML files,
retrieving box art URLs, and enriching game entries with additional metadata.
"""
import re
import xml.etree.ElementTree as ET
from utils.parse_utils import create_search_key

# List of XML filenames containing game data
XML_FILENAMES = [
    'dstdb.xml',
    'wiitdb.xml',
    '3dstdb.xml',
    'wiiutdb.xml',
    'ps3tdb.xml'
]

# Mapping of platforms to their respective XML files
PLATFORM_XML_MAP = {
    'nds': 'dstdb.xml',
    'dsi': 'dstdb.xml',
    'wii': 'wiitdb.xml',
    'gc': 'wiitdb.xml',
    '3ds': '3dstdb.xml',
    'n3ds': '3dstdb.xml',
    'wiiu': 'wiiutdb.xml',
    'ps3': 'ps3tdb.xml'
}

# Mapping of game types to platforms for each XML file
TYPE_PLATFORM_MAP = {
    'dstdb.xml': {
        'DS': 'nds',
        'DSi': 'dsi',
        'DSiWare': 'dsi',
        'CUSTOM': 'nds'
    },
    'wiitdb.xml': {
        'WiiWare': 'wii',
        'VC-NES': 'wii',
        'VC-SNES': 'wii',
        'VC-N64': 'wii',
        'VC-SMS': 'wii',
        'VC-MD': 'wii',
        'VC-PCE': 'wii',
        'VC-NEOGEO': 'wii',
        'VC-Arcade': 'wii',
        'VC-C64': 'wii',
        'VC-MSX': 'wii',
        'Channel': 'wii',
        'GameCube': 'gc',
        'Homebrew': 'wii',
        'CUSTOM': 'wii'
    },
    '3dstdb.xml': {
        '3DS': '3ds',
        'None': '3ds',
        '3DSWare': '3ds',
        'New3DS': 'n3ds',
        'New3DSWare': 'n3ds',
        'VC-NES': '3ds',
        'VC-GB': '3ds',
        'VC-GBC': '3ds',
        'VC-GBA': '3ds',
        'VC-GG': '3ds',
        'CUSTOM': '3ds',
        'Homebrew': '3ds'
    },
    'wiiutdb.xml': {
        'WiiU': 'wiiu',
        'eShop': 'wiiu',
        'VC-NES': 'wiiu',
        'VC-SNES': 'wiiu',
        'VC-N64': 'wiiu',
        'VC-GBA': 'wiiu',
        'VC-DS': 'wiiu',
        'VC-PCE': 'wiiu',
        'VC-MSX': 'wiiu',
        'Channel': 'wiiu',
        'CUSTOM': 'wiiu'
    },
    'ps3tdb.xml': {
        'PS3': 'ps3',
        'CUSTOM': 'ps3',
        'SEN': 'ps3',
        'Homebrew': 'ps3'
    }
}

# Mapping of regions to database region codes
REGION_REGION_MAP = {
    'NTSC-U': 'us',
    'NTSC-J': 'jp',
    'PAL': 'eu',
    'NTSC-K': 'other',
    'NTSC-T': 'other',
    'PAL-R': 'other',
    'NTSC-A': 'other'
}

# Patterns for capturing region codes in game IDs
ID_REGION_CODE_PATTERN_MAP = {
    'dstdb.xml': '.{3}(.)',
    'wiitdb.xml': '.{3}(.)',
    '3dstdb.xml': '.{3}(.)',
    'wiiutdb.xml': '.{3}(.)',
    'ps3tdb.xml': '([A-Z]{4})'
}

# List of supported countries for GameTDB artwork
GAMETDB_COUNTRIES = [
    'US', 'EN', 'JA', 'FR', 'DE', 'ES', 'IT', 'NL', 'PT', 'NO', 'FI', 'SE',
    'ZH', 'KO', 'RU', 'AU', 'DK', 'other'
]

# Mapping of region codes to countries for each XML file
REGION_CODE_COUNTRY_MAP = {
    'dstdb.xml': {
        r"E": 'US',
        r"J": 'JA',
        r"K": 'KO',
        r"D": 'DE',
        r"F": 'FR',
        r"H": 'NL',
        r"I": 'IT',
        r"S": 'ES',
        r"Z": 'SE',
        r"N": 'NO',
        r"Q": 'DK',
        r"M": 'SE',
        r"G": 'GR',
        r"T": 'US',
        r"": 'EN'
    },
    'wiitdb.xml': {
        r"E": 'US',
        r"J": 'JA',
        r"D": 'DE',
        r"F": 'FR',
        r"S": 'ES',
        r"M": 'SE',
        r"Y": 'DE',
        r"K": 'KO',
        r"H": 'NL',
        r"I": 'IT',
        r"Z": 'ES',
        r"": 'EN'
    },
    '3dstdb.xml': {
        r"J": 'JA',
        r"E": 'US',
        r"K": 'KO',
        r"D": 'DE',
        r"W": 'ZH',
        r"I": 'IT',
        r"H": 'NL',
        r"V": 'IT',
        r"": 'EN'
    },
    'wiiutdb.xml': {
        r"E": 'US',
        r"J": 'JA',
        r"R": 'RU',
        r"A": 'JA',
        r"": 'EN'
    },
    'ps3tdb.xml': {
        r"BCAS": 'ZH',
        r"BCAX": 'JA',
        r"BCJB": 'JA',
        r"BCJN": 'JA',
        r"BCJS": 'JA',
        r"BCJX": 'JA',
        r"BCKS": 'KO',
        r"BCUS": 'US',
        r"BLAS": 'ZH',
        r"BLJB": 'JA',
        r"BLJM": 'JA',
        r"BLJS": 'JA',
        r"BLKS": 'KO',
        r"BLMJ": 'JA',
        r"BLUS": 'US',
        r"CPCS": 'JA',
        r"HOP3": 'JA',
        r"KTGS": 'JA',
        r"XCUS": 'US',
        r"..J.": 'JA',
        r"..U.": 'US',
        r"..H.": 'US',
        r"": 'EN'
    }
}

# Patterns for capturing GameTDB IDs in game serials
SERIAL_GAMETDB_ID_PATTERN_MAP = {
    'nds': r"(\w{4})",
    'dsi': r"(\w{4})",
    'wii': r"(\w{4})",
    'gc': r"(\w{4})",
    '3ds': r"(\w{4})",
    'n3ds': r"(\w{4})",
    'wiiu': r"(\w{6}|\w{4})",
    'ps3': r"(\w{4}).*(\w{5})"
}

# Mapping of platform paths for building box art URLs
BOXART_URL_PLATFORM_PATHS_MAP = {
    'nds': 'ds/coverS',
    'dsi': 'ds/coverS',
    'wii': 'wii/cover',
    'gc': 'wii/cover',
    '3ds': '3ds/coverM',
    'n3ds': '3ds/coverM',
    'wiiu': 'wiiu/coverM',
    'ps3': 'ps3/cover'
}

# Base URL for GameTDB artwork
GAMETDB_ARTWORK_BASE_URL = 'https://art.gametdb.com'

# Global variable to store parsed TDB data
tdbs = None

def load_tdbs():
    """Load TDB data from XML files into memory."""
    global tdbs
    tdbs = {}

    for xml_filename in XML_FILENAMES:
        try:
            tree = ET.parse(f'data/gametdb/{xml_filename}')
            root = tree.getroot()

            tdbs[xml_filename] = []

            for game in root.findall('game'):
                tdbs[xml_filename].append(
                    {
                        'name': game.get('name'),
                        'id': game.find('id').text,
                        'type': game.find('type').text,
                        'region': game.find('region').text
                    }
                )
        except FileNotFoundError:
            print(f"Warning: {xml_filename} not found, skipping GameTDB enrichment for related platforms...")
            tdbs[xml_filename] = []


def build_boxart_url(platform, country, id):
    """Build a boxart URL for a specific platform, country, and game ID."""
    file_extension = 'jpg' if platform in (
        '3ds', 'n3ds', 'wiiu', 'ps3') else 'png'

    base_path = BOXART_URL_PLATFORM_PATHS_MAP[platform]

    return f'{GAMETDB_ARTWORK_BASE_URL}/{base_path}/{country}/{id}.{file_extension}'


def find_full_id(id, platform):
    """Retrieve the first game ID that contains a the given ID as a substring"""
    xml_filename = PLATFORM_XML_MAP[platform]
    for game in tdbs[xml_filename]:
        if game['id'].startswith(id):
            return game['id']
    return None


def get_boxart_url_by_id(id, platform):
    """Retrieve the boxart URL for a game by its ID and platform."""
    xml_filename = PLATFORM_XML_MAP[platform]
    region_code_pattern = ID_REGION_CODE_PATTERN_MAP[xml_filename]
    valid_id_pattern = SERIAL_GAMETDB_ID_PATTERN_MAP[platform]

    match = re.search(valid_id_pattern, id)
    if not match:
        return None
    valid_id = ''.join(match.groups())
    full_valid_id = find_full_id(valid_id, platform)
    if not full_valid_id:
        return None

    match = re.match(region_code_pattern, full_valid_id)
    if not match:
        return None
    region_code = match.group(1)

    boxart_url = None
    for pattern, country in REGION_CODE_COUNTRY_MAP[xml_filename].items():
        if not re.match(pattern, region_code):
            continue

        boxart_url = build_boxart_url(platform, country, full_valid_id)
        break
    return boxart_url


def parse(entries, flags):
    """Parse game entries and enrich them with additional data."""
    if not tdbs:
        load_tdbs()

    parse_boxart = flags.get('parse_boxart', True)
    parse_name = flags.get('parse_name', False)

    total = len(entries)
    progress_interval = max(1, total // 10)  # Report every 10%

    for i, entry in enumerate(entries):
        # Print progress every 10%
        if i > 0 and i % progress_interval == 0:
            percent = (i * 100) // total
            print(f"      Enriching entries... {percent}% ({i}/{total})")
        xml_filename = PLATFORM_XML_MAP[entry['platform']]

        # If a rom ID is set already, parse the box art URL or name directly
        if entry.get('rom_id'):
            if parse_boxart:
                entry['boxart_url'] = get_boxart_url_by_id(
                    entry['rom_id'], entry['platform'])
            if parse_name:
                for game in tdbs[xml_filename]:
                    if game['id'] != entry['rom_id']:
                        continue

                    entry['title'] = game['name']
                    break

            continue

        # We do not have a rom ID, use the logic to find the best matching game in TDB

        # Get a simple to compare value from the entry title
        title_compare_value = create_search_key(
            re.sub(r"\(.*", '', entry['title']))

        regions = entry['regions']
        platform = entry['platform']

        best_match = None
        best_match_name = None

        for game in tdbs[xml_filename]:
            # Skip if platform does not match
            if platform != TYPE_PLATFORM_MAP[xml_filename].get(game['type'], platform):
                continue

            # Skip if game region does not match any of the entry regions
            game_region = REGION_REGION_MAP.get(game['region'])
            if regions and game_region not in regions:
                continue

            # Get a simple to compare value from the game name
            name_compare_value = create_search_key(
                re.sub(r"\(.*", '', game['name']))

            # Skip if entry title is not a substring of game name
            if title_compare_value not in name_compare_value:
                continue

            # Update best match
            if not best_match_name or len(name_compare_value) < len(best_match_name):
                best_match = game
                best_match_name = game['name']

        if best_match:
            if parse_boxart:
                entry['boxart_url'] = get_boxart_url_by_id(
                    best_match['id'], platform)
            if parse_name:
                entry['title'] = best_match['name']

    if total > 0:
        print(f"      Enriching entries... done ({total} entries)")

    return entries
