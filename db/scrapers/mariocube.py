"""
This module provides functionality to scrape and parse entries from MarioCube indexes.
It detects the plain-text directory listings returned to curl-style clients, extracts file
metadata, and formats the data into structured entries ready for downstream processing.
"""
import html
import re
import sys
import urllib.parse

from utils import cache_manager
from utils.scrape_utils import fetch_url, create_scraper_session
from utils.parse_utils import size_str_to_bytes, join_urls

HOST_NAME = 'MarioCube'

# Curl-like headers to get plain-text directory listing instead of HTML
CURL_HEADERS = {
    'User-Agent': 'curl/8.0',
    'Accept': '*/*'
}


def extract_entries(response, source, platform, base_url):
    """Extract entries from the ANSI-colored directory listing response."""
    entries = []

    for filename, size_str in parse_listing_lines(response):
        match = re.match(source['filter'], filename)
        if not match:
            continue

        title = match.group(1)
        encoded_link = urllib.parse.quote(filename)
        entries.append(create_entry(
            encoded_link, filename, title, size_str, source, platform, base_url))

    return entries


def create_entry(link, filename, title, size_str, source, platform, base_url):
    """Create a dictionary representing a single entry."""
    name = html.unescape(title)
    size = size_str_to_bytes(size_str)
    url = join_urls(base_url, link)

    return {
        'title': name,
        'platform': platform,
        'regions': source['regions'],
        'links': [
            {
                'name': name,
                'type': source['type'],
                'format': source['format'],
                'url': url,
                'filename': filename,
                'host': HOST_NAME,
                'size': size,
                'size_str': size_str,
                'source_url': base_url
            }
        ]
    }


def parse_listing_lines(response):
    """Yield filename and size pairs from the raw listing response."""
    for raw_line in response.splitlines():
        line = re.compile(r'\x1B\[[0-?]*[ -/]*[@-~]').sub('', raw_line).strip()
        if not line or line.startswith('#'):
            continue

        parts = line.split(maxsplit=2)
        if len(parts) < 3:
            continue

        _, size_str, filename = parts
        yield filename, size_str


def fetch_response(url, use_cached, session=None):
    """Fetch the response from a URL, optionally using a cached version."""
    url_stripped = url.rstrip('/')
    short_url = url_stripped.split('/')[-1][:50] if '/' in url_stripped else url_stripped[:50]

    if use_cached:
        response = cache_manager.get_cached_response(url)
        if response:
            print(f"      {short_url}... cached")
            return response

    # Fetch the URL directly if no cached response is available
    return fetch_url(url, session=session)


def scrape(source, platform, use_cached=False):
    """Scrape entries from MarioCube based on the source configuration."""
    entries = []
    session = create_scraper_session(CURL_HEADERS)

    for url in source['urls']:
        # Fetch the response for each URL
        response = fetch_response(url, use_cached, session=session)
        if not response:
            print(f"Warning: Failed to get response from {url}, skipping...")
            continue

        # Extract entries from the response
        parsed_entries = extract_entries(response, source, platform, url)
        if not parsed_entries:
            print(f"Warning: No entries parsed from {url}, skipping...")
            continue

        entries.extend(parsed_entries)

    return entries
