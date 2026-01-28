"""
This module provides functionality to scrape and process data from the NoPayStation database.
It includes methods for handling PS3 RAP files, PSV ZRIF strings, and parsing links and entries
from the source data. The module also supports caching and fetching responses from URLs.
"""
import os
import requests
import csv
import io
import xml.etree.ElementTree as ET
import sys
from utils import cache_manager
from utils.scrape_utils import fetch_url
from utils.parse_utils import size_bytes_to_str, join_urls

HOST_NAME = 'NoPayStation'

REGIONS_MAP = {
    'US': 'us',
    'EU': 'eu',
    'JP': 'jp'
}

# Base URL for static content hosted in the repository
MAIN_SITE = 'https://raw.githubusercontent.com/caprado/romgi/main/db'

# Directories and base URLs for PS3 RAP files and PSV ZRIF files
PS3_RAPS_DIR = 'static/content/ps3/raps'
PS3_RAPS_BASE_URL = f'{MAIN_SITE}/static/content/ps3/raps'

PSV_ZRIFS_DIR = 'static/content/psv/zrifs'
PSV_ZRIFS_BASE_URL = f'{MAIN_SITE}/static/content/psv/zrifs'


def create_rap_file(rap, filepath):
    """Create a RAP file from a hex string."""
    with open(filepath, 'wb') as f:
        f.write(bytes.fromhex(rap))


def create_zrif_file(zrif, filepath):
    """Create a ZRIF file from a string."""
    with open(filepath, 'w') as f:
        f.write(zrif)


def add_ps3_links(result, links, base_url):
    """Add PS3-specific links (e.g., RAP files) to the links list."""
    name = result['Name']
    rap = result['RAP']
    content_id = result['Content ID']

    if len(rap) == 32 and content_id:
        filename = f'{content_id}.rap'
        filepath = os.path.join(PS3_RAPS_DIR, filename)
        create_rap_file(rap, filepath)

        links.append({
            'name': name,
            'type': 'RAP file',
            'format': 'rap',
            'url': join_urls(PS3_RAPS_BASE_URL, filename),
            'filename': filename,
            'host': HOST_NAME,
            'size': 16,
            'size_str': size_bytes_to_str(16),
            'source_url': base_url
        })


def add_psv_links(result, links, base_url):
    """Add PSV-specific links (e.g., ZRIF strings) to the links list."""
    name = result['Name']
    zrif = result['zRIF']
    content_id = result['Content ID']

    if zrif and content_id:
        filename = content_id
        filepath = os.path.join(PSV_ZRIFS_DIR, filename)
        create_zrif_file(zrif, filepath)

        links.append({
            'name': name,
            'type': 'ZRIF string',
            'format': 'string',
            'url': join_urls(PSV_ZRIFS_BASE_URL, filename),
            'filename': filename,
            'host': HOST_NAME,
            'size': len(zrif),
            'size_str': size_bytes_to_str(len(zrif)),
            'source_url': base_url
        })


def parse_links(result, source, platform, base_url):
    """Parse links from the result and generate metadata for each link."""
    links = []
    url = result['PKG direct link']
    if not url.startswith('http'):
        return links

    name = result['Name']
    filename = url.rstrip('/').split('/')[-1]
    size = round(float(result['File Size'])) if result['File Size'].isdigit() else 0
    size_str = size_bytes_to_str(size) if size else 0

    if url.endswith('.xml'):
        # Handle XML files containing multiple URLs
        r = requests.get(url)
        if r.ok:
            root = ET.fromstring(r.text)
            urls = [piece.attrib['url'] for piece in root.findall('pieces')]
            for i, url in enumerate(urls):
                filename = url.rstrip('/').split('/')[-1]

                links.append({
                    'name': name,
                    'type': f"{source['type']} #{i}",
                    'format': source['format'],
                    'url': url,
                    'filename': filename,
                    'host': HOST_NAME,
                    'size': size,
                    'size_str': size_str,
                    'source_url': base_url
                })
    else:
        # Handle direct links
        links.append({
            'name': name,
            'type': source['type'],
            'format': source['format'],
            'url': url,
            'filename': filename,
            'host': HOST_NAME,
            'size': size,
            'size_str': size_str,
            'source_url': base_url
        })

    # Add platform-specific links
    if platform == 'ps3':
        add_ps3_links(result, links, base_url)
    elif platform == 'psv':
        add_psv_links(result, links, base_url)

    return links


def create_entry(result, source, platform, base_url):
    """Create an entry for a ROM based on the result data."""
    rom_id = result['Title ID']
    name = result['Name']
    region = REGIONS_MAP.get(result['Region'], 'other')
    links = parse_links(result, source, platform, base_url)

    return {
        'rom_id': rom_id,
        'title': name,
        'platform': platform,
        'regions': [region],
        'links': links
    }


def parse_response(response, source, platform, base_url):
    """Parse the response and extract entries."""
    entries = []
    results = csv.DictReader(io.StringIO(response), delimiter='\t')

    for result in results:
        entry = create_entry(result, source, platform, base_url)
        if entry and entry['links']:
            entries.append(entry)

    return entries


def fetch_response(url, use_cached):
    """Fetch the response from a URL, optionally using a cached version."""
    short_url = url.split('/')[-1][:50] if '/' in url else url[:50]

    if use_cached:
        response = cache_manager.get_cached_response(url)
        if response:
            print(f"      {short_url}... cached")
            return response

    return fetch_url(url)


def scrape(source, platform, use_cached=False):
    """Scrape data from the source and extract entries."""
    # Ensure directories exist
    for path in (PS3_RAPS_DIR, PSV_ZRIFS_DIR):
        os.makedirs(path, exist_ok=True)

    entries = []

    for url in source['urls']:
        response = fetch_response(url, use_cached)
        if not response:
            print(f"Warning: Failed to get response from {url}, skipping...")
            continue

        parsed_entries = parse_response(response, source, platform, url)
        if not parsed_entries:
            print(f"Warning: No entries parsed from {url}, skipping...")
            continue

        entries.extend(parsed_entries)

    return entries
