"""
This module provides utility functions for caching HTTP responses to a local directory.
It includes functionality to sanitize URLs into valid filenames, save responses to cache,
and retrieve cached responses with optional expiration.
"""
import os
import re
import time

# Directory name where cached responses will be stored
CACHE_DIRNAME = 'cache'

# Cache expiration in days (0 = never expire)
CACHE_MAX_AGE_DAYS = 7

# Ensure the cache directory exists
if not os.path.exists(CACHE_DIRNAME):
    os.mkdir(CACHE_DIRNAME)


def get_cached_response_filename(url):
    """Generate a safe filename for caching a response based on the given URL."""
    return re.sub(r"[\\/:\*\?\"<>|]", '_', url)


def cache_response(url, response):
    """Cache the response content for a given URL."""
    filename = get_cached_response_filename(url)
    with open(f'{CACHE_DIRNAME}/{filename}', 'w', encoding='utf-8') as f:
        f.write(response)


def get_cached_response(url, max_age_days=CACHE_MAX_AGE_DAYS):
    """Retrieve the cached response if it exists and is not expired.

    Args:
        url: The URL to look up in cache
        max_age_days: Maximum age in days (0 = never expire)

    Returns:
        Cached response string or None if not found/expired
    """
    filename = get_cached_response_filename(url)
    filepath = f'{CACHE_DIRNAME}/{filename}'

    if not os.path.exists(filepath):
        return None

    # Check cache age if expiration is enabled
    if max_age_days > 0:
        file_age_days = (time.time() - os.path.getmtime(filepath)) / 86400
        if file_age_days > max_age_days:
            return None  # Cache expired

    with open(filepath, encoding='utf-8') as f:
        return f.read()


def get_cache_age_days(url):
    """Get the age of a cached response in days, or None if not cached."""
    filename = get_cached_response_filename(url)
    filepath = f'{CACHE_DIRNAME}/{filename}'

    if not os.path.exists(filepath):
        return None

    return (time.time() - os.path.getmtime(filepath)) / 86400
