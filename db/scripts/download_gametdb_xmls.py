#!/usr/bin/env python
"""
This script downloads and extracts GameTDB XML files.
Uses cloudscraper to bypass Cloudflare protection.
"""
import os
import sys
import zipfile

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cloudscraper

DOWNLOADS = [
    {'url': 'https://www.gametdb.com/dstdb.zip?LANG=EN', 'xml': 'dstdb.xml', 'referer': 'https://www.gametdb.com/DS/Downloads'},
    {'url': 'https://www.gametdb.com/wiitdb.zip?LANG=EN&WIIWARE=1&GAMECUBE=1', 'xml': 'wiitdb.xml', 'referer': 'https://www.gametdb.com/Wii/Downloads'},
    {'url': 'https://www.gametdb.com/3dstdb.zip?LANG=EN', 'xml': '3dstdb.xml', 'referer': 'https://www.gametdb.com/3DS/Downloads'},
    {'url': 'https://www.gametdb.com/wiiutdb.zip?LANG=EN', 'xml': 'wiiutdb.xml', 'referer': 'https://www.gametdb.com/WiiU/Downloads'},
    {'url': 'https://www.gametdb.com/ps3tdb.zip?LANG=EN', 'xml': 'ps3tdb.xml', 'referer': 'https://www.gametdb.com/PS3/Downloads'},
]


def download_gametdb_xmls():
    """Download and extract GameTDB XML files."""
    print("Downloading GameTDB XML files...")

    destination = 'data/gametdb'
    os.makedirs(destination, exist_ok=True)

    # Create cloudscraper session (bypasses Cloudflare)
    session = cloudscraper.create_scraper(
        browser={
            'browser': 'chrome',
            'platform': 'windows',
            'mobile': False
        }
    )

    success_count = 0

    for item in DOWNLOADS:
        xml_file = item['xml']
        xml_file_path = os.path.join(destination, xml_file)
        zip_file_name = item['url'].split('/')[-1].split('?')[0]
        zip_file_path = os.path.join(destination, zip_file_name)

        # Skip if already exists
        if os.path.exists(xml_file_path):
            print(f"  {xml_file}: cached")
            success_count += 1
            continue

        print(f"  {xml_file}: ", end='', flush=True)

        try:
            # Set referer header for this request
            response = session.get(
                item['url'],
                headers={'Referer': item['referer']},
                timeout=120
            )

            if response.ok and len(response.content) > 1000:
                # Save zip
                with open(zip_file_path, 'wb') as f:
                    f.write(response.content)

                # Extract
                with zipfile.ZipFile(zip_file_path, 'r') as zip_ref:
                    zip_ref.extractall(destination)
                os.remove(zip_file_path)
                print("OK")
                success_count += 1
            else:
                print(f"failed ({response.status_code})")

        except Exception as e:
            print(f"failed ({e})")
            if os.path.exists(zip_file_path):
                os.remove(zip_file_path)

    print(f"GameTDB: {success_count}/{len(DOWNLOADS)} files")


if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
    os.chdir('../')
    download_gametdb_xmls()
