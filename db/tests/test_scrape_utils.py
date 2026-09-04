"""Tests for utils/scrape_utils.py."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import utils.scrape_utils as scrape_utils
from utils.scrape_utils import (
    _needs_playwright,
    close_browser,
    create_scraper_session,
    fetch_url,
    BROWSER_HEADERS,
    PLAYWRIGHT_REQUIRED_HOSTS,
)


# -- _needs_playwright -------------------------------------------------------

def test_needs_playwright_matching():
    for host in PLAYWRIGHT_REQUIRED_HOSTS:
        assert _needs_playwright(f'https://{host}/page') is True


def test_needs_playwright_no_match():
    assert _needs_playwright('https://example.com/page') is False


# -- create_scraper_session --------------------------------------------------

def test_create_session_default_headers():
    session = create_scraper_session()
    for key in BROWSER_HEADERS:
        assert key in session.headers


def test_create_session_custom_headers():
    session = create_scraper_session({'Custom-Header': 'value'})
    assert session.headers.get('Custom-Header') == 'value'


# -- fetch_url ---------------------------------------------------------------

def test_fetch_url_success(tmp_cache_dir):
    with patch('utils.scrape_utils.create_scraper_session') as mock_session_factory:
        mock_session = MagicMock()
        mock_response = MagicMock()
        mock_response.ok = True
        mock_response.text = '<html>content</html>'
        mock_session.get.return_value = mock_response
        mock_session_factory.return_value = mock_session

        result = fetch_url('https://example.com/page')
        assert result == '<html>content</html>'


def test_fetch_url_http_error(tmp_cache_dir):
    with patch('utils.scrape_utils.create_scraper_session') as mock_session_factory:
        mock_session = MagicMock()
        mock_response = MagicMock()
        mock_response.ok = False
        mock_response.status_code = 403
        mock_session.get.return_value = mock_response
        mock_session_factory.return_value = mock_session

        result = fetch_url('https://example.com/blocked')
        assert result is None


def test_fetch_url_exception(tmp_cache_dir):
    with patch('utils.scrape_utils.create_scraper_session') as mock_session_factory:
        mock_session = MagicMock()
        mock_session.get.side_effect = Exception('timeout')
        mock_session_factory.return_value = mock_session

        result = fetch_url('https://example.com/timeout')
        assert result is None


def test_fetch_url_with_existing_session(tmp_cache_dir):
    mock_session = MagicMock()
    mock_response = MagicMock()
    mock_response.ok = True
    mock_response.text = 'data'
    mock_session.get.return_value = mock_response

    result = fetch_url('https://example.com/page', session=mock_session)
    assert result == 'data'
    mock_session.get.assert_called_once()


def test_fetch_url_playwright_route(tmp_cache_dir):
    url = 'https://pw-only.example.com/page'
    with patch.object(scrape_utils, 'PLAYWRIGHT_REQUIRED_HOSTS', ['pw-only.example.com']), \
            patch('utils.scrape_utils._fetch_with_playwright', return_value='<html>pw</html>') as mock_pw:
        result = fetch_url(url)
        assert result == '<html>pw</html>'
        mock_pw.assert_called_once_with(url)


# -- close_browser (smoke test) ---------------------------------------------

def test_close_browser_no_crash():
    close_browser()
