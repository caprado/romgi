"""
This module provides functionality to scrape data from Internet Archive indexes. 
It includes methods for logging into the Internet Archive, fetching responses, 
extracting entries from HTML content, and creating structured data entries.
"""
import re
import cloudscraper
import html
import json
import sys
from utils import cache_manager
from utils.scrape_utils import fetch_url
from utils.parse_utils import size_bytes_to_str, size_str_to_bytes, join_urls

HOST_NAME = 'Internet Archive'

LOGIN_URL = 'https://archive.org/account/login'

session = None


def get_login_session(creds_path='scrapers/internet_archive_creds.json'):
    """Create and return a session logged into the Internet Archive."""
    try:
        # Load credentials
        with open(creds_path, 'r') as f:
            creds = json.load(f)

        session = cloudscraper.create_scraper()

        # Initial GET request to establish session cookies
        session.get(LOGIN_URL)

        r = session.post(LOGIN_URL, data={
            'username': creds['username'],
            'password': creds['password']
        })

        if not r.ok:
            raise Exception("Wrong or invalid credentials")

        return session
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Warning: Internet Archive credentials not found: {e}")
        return None
    except Exception as e:
        print(f"Warning: Failed to log into Internet Archive: {e}")
        return None


def extract_entries(response, source, platform, base_url, debug=False):
    """Extract entries from the HTML response using regex."""
    entries = []

    # Try multiple patterns for different IA HTML formats
    patterns = [
        # Format 1: Standard table with 3 columns (link, date, size)
        r'<tr[^>]*>\s*<td[^>]*><a href="([^"]+)"[^>]*>([^<]+)</a>.*?</td>\s*<td[^>]*>[^<]*</td>\s*<td[^>]*>([^<]+)</td>',
        # Format 2: With possible nested spans/divs
        r'<tr[^>]*>.*?<a href="([^"]+)"[^>]*>([^<]+)</a>.*?</td>.*?</td>.*?<td[^>]*>\s*([0-9][^<]*)</td>',
        # Format 3: Directory listing format
        r'href="([^"]+)"[^>]*>([^<]+)</a>\s*</td>\s*<td[^>]*>[^<]*</td>\s*<td[^>]*>([0-9][^<]*[KMGT]?i?B?)</td>',
    ]

    matches = []
    for i, pattern in enumerate(patterns):
        matches = re.findall(pattern, response, re.DOTALL | re.IGNORECASE)
        if matches:
            if debug:
                print(f"      Pattern {i+1} matched {len(matches)} entries")
            break

    if not matches and debug:
        # Save a snippet of the response for debugging
        print(f"      DEBUG: No pattern matched. Response snippet:")
        # Find table content
        table_match = re.search(r'<table[^>]*class="[^"]*directory[^"]*"[^>]*>(.*?)</table>', response, re.DOTALL | re.IGNORECASE)
        if table_match:
            print(f"      {table_match.group(0)[:500]}...")
        else:
            # Just show first few tr elements
            tr_matches = re.findall(r'<tr[^>]*>.*?</tr>', response[:5000], re.DOTALL)
            for tr in tr_matches[:2]:
                print(f"      {tr[:300]}...")

    for link, filename, size_str in matches:
        filename = filename.strip()
        size_str = size_str.strip()

        # Skip non-file entries (parent directory link, etc.)
        if not filename or 'parent directory' in filename.lower() or '.' not in filename:
            continue

        # Apply the filter from the source configuration
        match = re.match(source['filter'], filename)
        if not match:
            continue

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


def fetch_response(url, session, use_cached):
    """Fetch the response from a URL, optionally using a cached version."""
    short_url = url.split('/')[-1][:50] if '/' in url else url[:50]

    if use_cached:
        response = cache_manager.get_cached_response(url)
        if response:
            print(f"      {short_url}... cached")
            return response

    # Fetch the URL using the provided session
    return fetch_url(url, session)


def scrape(source, platform, use_cached=False):
    """Scrapes entries from the Internet Archive based on the source configuration."""
    global session

    entries = []

    # First attempt: scrape without login session
    for url in source['urls']:
        response = fetch_response(url, session, use_cached)
        if not response:
            print(f"Warning: Failed to get response from {url}, skipping...")
            continue

        parsed_entries = extract_entries(response, source, platform, url)
        if parsed_entries:
            entries.extend(parsed_entries)
        else:
            # Initialize the session if not already done
            if not session:
                session = get_login_session()
                if not session:
                    print("Warning: Unable to create Internet Archive session, skipping login-required content...")
                    # Try debug mode to see what HTML we got
                    extract_entries(response, source, platform, url, debug=True)
                    continue

            # Retry with login session (bypass cache to get authenticated response)
            response = fetch_response(url, session, use_cached=False)
            if not response:
                print(f"Warning: Failed to get response from {url} with login, skipping...")
                continue

            parsed_entries = extract_entries(response, source, platform, url)
            if parsed_entries:
                for entry in parsed_entries:
                    for link in entry['links']:
                        link['type'] += " (Requires Internet Archive Log in)"
                entries.extend(parsed_entries)
            else:
                # Show debug info when parsing fails
                print(f"Warning: No entries parsed from {url}, skipping...")
                extract_entries(response, source, platform, url, debug=True)

    return entries
