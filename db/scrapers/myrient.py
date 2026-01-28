"""
This module provides functionality to scrape and parse entries from Myrient indexes.
It includes methods to fetch HTML responses, extract relevant data using regex, and
format the extracted data into structured entries.
"""
import re
import html
import sys
from utils import cache_manager
from utils.scrape_utils import fetch_url
from utils.parse_utils import size_bytes_to_str, size_str_to_bytes, join_urls

HOST_NAME = 'Myrient'


def extract_entries(response, source, platform, base_url):
    """Extract entries from the HTML response using regex."""
    entries = []
    # Regex pattern to extract link, title, and size from table rows
    pattern = (
        r"<tr><td class=\"link\"><a href=\"(.*?)\" title=\".*?\">(.*?)</a></td><td class=\"size\">(.*?)</td><td class=\"date\">.*?</td></tr>"
    )
    matches = re.findall(pattern, response)

    for link, title, size_str in matches:
        # Apply the filter from the source configuration
        match = re.match(source['filter'], title)
        if not match:
            continue

        filename = title  # Original filename
        title = match.group(1)  # Extract the filtered title

        # Create an entry and add it to the list
        entries.append(create_entry(
            link, filename, title, size_str, source, platform, base_url))

    return entries


def create_entry(link, filename, title, size_str, source, platform, base_url):
    """Create a dictionary representing a single entry."""
    name = html.unescape(title)
    size = size_str_to_bytes(size_str)
    size_str = size_bytes_to_str(size)
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


def fetch_response(url, use_cached):
    """Fetch the response from a URL, optionally using a cached version."""
    short_url = url.split('/')[-2] if url.endswith('/') else url.split('/')[-1]
    short_url = short_url[:50]

    if use_cached:
        response = cache_manager.get_cached_response(url)
        if response:
            age = cache_manager.get_cache_age_days(url)
            age_str = f" ({age:.0f}d old)" if age else ""
            print(f"      {short_url}... cached{age_str}")
            return response
        # Cache miss or expired - will fetch fresh
        print(f"      {short_url}... ", end='', flush=True)

    # Fetch the URL directly if no cached response is available
    return fetch_url(url)


def scrape(source, platform, use_cached=False):
    """Scrape entries from Myrient based on the source configuration."""
    entries = []

    for url in source['urls']:
        # Fetch the response for each URL
        response = fetch_response(url, use_cached)
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
