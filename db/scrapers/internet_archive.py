"""
This module provides functionality to scrape data from Internet Archive indexes.
It extracts entries from HTML content and creates structured data entries.
"""
import re
import urllib.parse
import html
import json
import cloudscraper
from utils import cache_manager
from utils.scrape_utils import fetch_url
from utils.parse_utils import size_bytes_to_str, size_str_to_bytes, join_urls

HOST_NAME = 'Internet Archive'
LOGIN_URL = 'https://archive.org/account/login'

session = None


def get_login_session(creds_path='scrapers/internet_archive_creds.json'):
    """Create and return a session logged into the Internet Archive."""
    try:
        with open(creds_path, 'r') as f:
            creds = json.load(f)

        session = cloudscraper.create_scraper()
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
    matches = []
    # Common ROM file extensions
    file_ext = r'(zip|chd|iso|7z|rar|nsp|xci|wbfs|rvz|cso|pbp|pkg|bin|nds|3ds|cia|gba|gbc|gb|n64|z64|v64|nes|sfc|smc|gen|md|sms|gg|pce|vpk|app|cue|wad|dol|gcm|wux|wua|lnx|lyx|a26|a78|col|int|jag|ngp|ngc|psx|ws|wsc|vb|vec)'

    # Strategy 1: Find linked files (public downloads)
    # Pattern: <a href="filename.ext">filename.ext</a>
    link_pattern = rf'<a\s*href="([^"]+\.{file_ext})"[^>]*>'
    for match in re.finditer(link_pattern, response, re.IGNORECASE):
        href = match.group(1)
        start_pos = match.end()
        chunk = response[start_pos:start_pos + 500]
        size_match = re.search(r'(\d+\.?\d*)\s*([KMGT])i?B?', chunk, re.IGNORECASE)
        size_str = f"{size_match.group(1)}{size_match.group(2)}" if size_match else ''
        filename = html.unescape(urllib.parse.unquote(href))
        matches.append((href, filename, size_str))

    if debug:
        print(f"      Found {len(matches)} linked files")

    # Strategy 2: Find restricted files (no links, just text in <td>)
    # These rows have class "__restricted-file" and plain text filenames
    # Pattern: <tr class="...__restricted-file"><td>filename.ext</td><td>date</td><td>size</td>
    restricted_pattern = rf'<tr[^>]*restricted-file[^>]*>\s*<td>([^<]+\.{file_ext})</td>\s*<td>[^<]*</td>\s*<td>([^<]*)</td>'
    for match in re.finditer(restricted_pattern, response, re.IGNORECASE | re.DOTALL):
        filename = html.unescape(match.group(1).strip())
        size_str = match.group(3).strip()
        size_match = re.search(r'(\d+\.?\d*)\s*([KMGT])', size_str, re.IGNORECASE)
        size_str = f"{size_match.group(1)}{size_match.group(2)}" if size_match else ''
        href = urllib.parse.quote(filename)
        matches.append((href, filename, size_str))

    if debug:
        print(f"      Found {len(matches)} total files (including restricted)")

    for link, filename, size_str in matches:
        filename = filename.strip()
        # Strip HTML tags from size (e.g., <span>2.5G</span> -> 2.5G)
        size_str = re.sub(r'<[^>]+>', '', size_str).strip()

        # Skip non-file entries (parent directory link, etc.)
        if not filename or 'parent directory' in filename.lower() or '.' not in filename:
            if debug:
                print(f"      Skipped (no file): link={link[:30]}, filename={filename[:30] if filename else 'empty'}")
            continue

        # Apply the filter from the source configuration
        match = re.match(source['filter'], filename)
        if not match:
            if debug:
                print(f"      Skipped (filter): {filename[:50]} didn't match {source['filter'][:50]}")
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
    url_stripped = url.rstrip('/')
    short_url = url_stripped.split('/')[-1][:50] if '/' in url_stripped else url_stripped[:50]

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
