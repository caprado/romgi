"""
This module provides utility functions for parsing, normalizing, and manipulating strings, filenames, 
URLs, and file sizes. These functions are designed to handle common tasks such as sanitizing input, 
creating slugs, and converting between human-readable and byte-based file sizes.
"""
import os
import re
import urllib
from unidecode import unidecode


def replace_invalid_chars(title):
    """Replace invalid characters in a string with valid substitutes."""
    for value1, value2 in {
        '+': 'plus',
        '&': 'and',
        '™': '',
        '©': '',
        '®': ''
    }.items():
        title = title.replace(value1, f' {value2} ')
    return title


def remove_ext(filename):
    """Remove the file extension from a given filename."""
    basename = os.path.basename(filename)
    name, ext = os.path.splitext(basename)

    # If no extension exists, return the original filename
    if ext == '':
        return filename
    return name


def normalize_repeated_chars(text, char):
    """Replace consecutive occurrences of a character with a single instance."""
    escaped_char = re.escape(char)  # Escape special characters for regex
    return re.sub(f'{escaped_char}+', char, text).strip()


def create_slug(entry):
    """Create a URL-friendly slug from an entry dictionary."""
    title = entry['title']

    title = replace_invalid_chars(title)
    title = unidecode(title)
    platform = entry['platform']
    regions = '-'.join(entry['regions'])
    slug = f"{title}-{platform}-{regions}"
    
    slug = re.sub(r"[^a-zA-Z0-9-]", '-', slug).lower()
    slug = normalize_repeated_chars(slug, '-').strip('-')

    return slug


def create_search_key(title):
    """Generate a search-friendly key from the given title by normalizing and sanitizing it."""
    title = replace_invalid_chars(title)
    title = unidecode(title)
    title = title.lower()
    title = re.sub(r"[^a-z0-9]", '', title)
    title = title.strip()

    return title


def size_bytes_to_str(size):
    """Convert a size in bytes to a human-readable string with appropriate units."""
    suffixes = ['B', 'K', 'M', 'G', 'T', 'P']
    i = 0
    while size >= 1024 and i < len(suffixes) - 1:
        size /= 1024.0
        i += 1

    # Format the size to two decimal places and remove trailing zeros
    f = ('%.2f' % size).rstrip('0').rstrip('.')
    return '%s%s' % (f, suffixes[i])


def size_str_to_bytes(size_str):
    """Convert a human-readable size string to bytes."""
    # Extract the first alphabetic character as the unit
    for character in size_str:
        if not character.isalpha():
            continue
        unit = character
        break

    # Extract the numeric part of the size string
    size = float(re.sub(r'[^\d\.]', '', size_str))
    if unit == 'B':
        size = size
    elif unit == 'K':
        size = size * 1024
    elif unit == 'M':
        size = size * 1024 * 1024
    elif unit == 'G':
        size = size * 1024 * 1024 * 1024

    return int(size)


def join_urls(url, *links):
    """Join a base URL with one or more relative links."""
    for link in links:
        # Ensure proper joining of URLs by stripping and appending slashes
        url = urllib.parse.urljoin(url.rstrip('/') + '/', link.lstrip('/'))
    return url
