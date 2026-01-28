"""
This module provides utilities for scraping web content and caching responses.
"""
import time
import cloudscraper
from playwright.sync_api import sync_playwright

from utils import cache_manager

# Use browser-like headers instead of curl
BROWSER_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate, br',
    'DNT': '1',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1'
}

# Sites that require Playwright (real browser) due to TLS fingerprinting
PLAYWRIGHT_REQUIRED_HOSTS = ['myrient.erista.me']

# Rate limiting settings
MAX_RETRIES = 5
RETRY_DELAY = 3  # seconds between retries
REQUEST_DELAY = 1  # seconds between requests to avoid rate limiting

# Global Playwright browser instance for efficiency
_playwright = None
_browser = None
_last_request_time = 0


def _get_browser():
    """Get or create the Playwright browser instance."""
    global _playwright, _browser
    if _browser is None:
        _playwright = sync_playwright().start()
        _browser = _playwright.chromium.launch(headless=True)
    return _browser


def close_browser():
    """Close the Playwright browser when done."""
    global _playwright, _browser
    if _browser:
        _browser.close()
        _browser = None
    if _playwright:
        _playwright.stop()
        _playwright = None


def _needs_playwright(url):
    """Check if a URL requires Playwright for TLS fingerprinting bypass."""
    return any(host in url for host in PLAYWRIGHT_REQUIRED_HOSTS)


def _rate_limit():
    """Enforce rate limiting between requests."""
    global _last_request_time
    elapsed = time.time() - _last_request_time
    if elapsed < REQUEST_DELAY:
        time.sleep(REQUEST_DELAY - elapsed)
    _last_request_time = time.time()


def _fetch_with_playwright(url):
    """Fetch URL using Playwright (real browser) with retry logic."""
    browser = _get_browser()

    # Show progress for slow Playwright fetches
    short_url = url.split('/')[-2] if url.endswith('/') else url.split('/')[-1]
    print(f"      Fetching {short_url[:50]}... ", end='', flush=True)

    for attempt in range(MAX_RETRIES):
        _rate_limit()
        page = browser.new_page()
        try:
            response = page.goto(url, wait_until='domcontentloaded', timeout=60000)
            if response and response.ok:
                content = page.content()
                page.close()
                print("OK")
                return content
            page.close()
            print("failed")
            return None
        except Exception as e:
            page.close()
            if attempt < MAX_RETRIES - 1:
                wait_time = RETRY_DELAY * (attempt + 1)  # Exponential backoff
                print(f"retry {attempt + 1}... ", end='', flush=True)
                time.sleep(wait_time)
            else:
                print(f"failed ({e})")
                return None
    return None


def create_scraper_session(headers=None):
    """Create a scraper session and optionally apply custom headers."""
    session = cloudscraper.create_scraper(
        browser={
            'browser': 'chrome',
            'platform': 'windows',
            'mobile': False
        }
    )
    applied_headers = headers or BROWSER_HEADERS
    if applied_headers:
        session.headers.update(applied_headers)
    return session


def fetch_url(url, session=None):
    """Fetch the content of a URL and cache the response."""
    # Get short URL for display (handle trailing slashes)
    url_stripped = url.rstrip('/')
    short_url = url_stripped.split('/')[-1][:50] if '/' in url_stripped else url_stripped[:50]

    # Use Playwright for sites with strict TLS fingerprinting
    if _needs_playwright(url):
        response = _fetch_with_playwright(url)
        if response:
            cache_manager.cache_response(url, response)
        return response

    # Use cloudscraper for other sites
    if not session:
        session = create_scraper_session(BROWSER_HEADERS)

    try:
        r = session.get(url, timeout=60)

        if not r.ok:
            print(f"      {short_url}... HTTP {r.status_code}")
            return None

        response = r.text
        cache_manager.cache_response(url, response)
        print(f"      {short_url}... OK")

        return response
    except Exception as e:
        print(f"      {short_url}... error: {e}")
        return None
