"""
This module provides utilities for parsing and processing game titles, 
primarily following the No-Intro naming convention. It includes functions 
to extract regions, clean up titles, and normalize their structure.
"""
import re
from utils.parse_utils import normalize_repeated_chars

# Mapping of regions to their respective database region
REGIONS_MAP = {
    'USA': 'us',
    'Canada': 'us',
    'Mexico': 'us',
    'Europe': 'eu',
    'Australia': 'eu',
    'Italy': 'eu',
    'Germany': 'eu',
    'France': 'eu',
    'Spain': 'eu',
    'United Kingdom': 'eu',
    'UK': 'eu',
    'Netherlands': 'eu',
    'Austria': 'eu',
    'Belgium': 'eu',
    'Croatia': 'eu',
    'Denmark': 'eu',
    'Finland': 'eu',
    'Greece': 'eu',
    'Ireland': 'eu',
    'Poland': 'eu',
    'Portugal': 'eu',
    'Sweden': 'eu',
    'Turkey': 'eu',
    'Japan': 'jp',
    'Argentina': 'other',
    'Brazil': 'other',
    'China': 'other',
    'Hong Kong': 'other',
    'India': 'other',
    'Israel': 'other',
    'Korea': 'other',
    'Latin America': 'other',
    'New Zealand': 'other',
    'Norway': 'other',
    'Russia': 'other',
    'Scandinavia': 'other',
    'South Africa': 'other',
    'Switzerland': 'other',
    'Taiwan': 'other',
    'United Arab Emirates': 'other',
    'Asia': 'other',
    'Unknown': 'other'
}

# List of possible languages described in a title
LANGUAGES = [
    'En', 'Ja', 'Fr', 'De', 'Es', 'It', 'Nl', 'Pt', 'Sv', 'No', 'Da', 'Fi',
    'Zh', 'Ko', 'Pl', 'Ru', 'Cs', 'Hu', 'Zh-Hant', 'Zh-Hans', 'El', 'Es-XL',
    'Pt-BR', 'Tr', 'En-GB', 'Ar', 'En+En', 'It+En', 'Ro', 'Af'
]

# List of contents that are in parentheses to remove from titles
TITLE_REMOVE_LIST = [
    'Europe', 'USA', 'Japan', 'World'
] + LANGUAGES

# List of articles to handle in titles
WORD_ARTICLES = [
    'the', 'die', 'la', 'des', 'das', 'le', 'l\'', 'ein', 'der', 'het', 'el',
    'il', 'i', 'los', 'os'
]


def parse_regions(title):
    """Parse the regions from a title."""
    # Extract all groups of parentheses from the title
    matches = re.findall(r"\((.*?)\)", title)

    # Split the contents of each parentheses group into subgroups
    groups = [group.split(',') for group in matches]

    regions = []
    for group in groups:
        for content in group:
            content = content.strip()
            region = REGIONS_MAP.get(content)
            if region and region not in regions:
                regions.append(region)
        # Stop processing further groups if regions are found
        if regions:
            break

    return regions


def remove_groups_with_contents(title, contents_to_remove):
    """Remove parentheses groups containing specific contents."""

    # Construct a regex pattern to match parentheses groups containing any of the specified contents
    contents_pattern = '|'.join(contents_to_remove)
    pattern = rf"\((?:{contents_pattern})(?:,(?:{contents_pattern}))*\)"

    return re.sub(pattern, '', title)


def move_article(title):
    """Move the article in a title to the beginning."""
    # Match the title structure: main name, article, and optional extra info
    match = re.match(r"^(.*?),\s*(\S+)(?:\s+(.*))?$", title)

    if match:
        name = match.group(1)

        # Avoid changes if the main name contains parentheses (to prevent false positives)
        if '(' in name:
            return title

        article = match.group(2)
        other = match.group(3)

        # Construct the final title
        if other:
            if article.endswith("'"):
                return f'{article}{name} {other}'
            return f'{article} {name} {other}'
        else:
            if article.endswith("'"):
                return f'{article}{name}'
            return f'{article} {name}'

    return title


def get_clean_title(title):
    """Clean the title by removing unnecessary groups and normalizing it."""
    clean_title = title

    # Extract all groups of parentheses from the title
    matches = re.findall(r"\((.*?)\)", title)

    # Split the contents of each parentheses group into subgroups
    groups = [group.split(',') for group in matches]

    # Remove parentheses groups if they match specific criteria
    for group in groups:
        remove_group = True
        for content in group:
            content = content.strip()
            if content not in REGIONS_MAP and content not in LANGUAGES and content not in TITLE_REMOVE_LIST:
                remove_group = False
                break
            if content in REGIONS_MAP and content not in TITLE_REMOVE_LIST:
                remove_group = False
                break
        if remove_group:
            clean_title = remove_groups_with_contents(clean_title, group)

    # Normalize repeated spaces and move articles
    clean_title = normalize_repeated_chars(clean_title, ' ')

    return clean_title


def process_entry(entry, parse_title_regions, clean_title_contents, move_title_article):
    """Process a single entry by applying various transformations."""
    if parse_title_regions:
        if not entry.get('regions'):
            entry['regions'] = parse_regions(entry['title'])

    if clean_title_contents:
        entry['title'] = get_clean_title(entry['title'])

    if move_title_article:
        entry['title'] = move_article(entry['title'])


def parse(entries, flags):
    """Parse a list of entries and process each one."""
    parse_title_regions = flags.get('parse_title_regions', True)
    clean_title_contents = flags.get('clean_title_contents', True)
    move_title_article = flags.get('move_title_article', True)

    for entry in entries:
        process_entry(entry, parse_title_regions,
                      clean_title_contents, move_title_article)

    return entries
