#!/usr/bin/env python
"""
This script initializes a database and processes sources for scraping and parsing.
It integrates various scrapers and parsers to handle data from multiple platforms and formats.
"""
import json
import sys
import os
from parsers import no_intro
from scrapers import myrient, internet_archive, nopaystation, mariocube
from parsers import libretro, gametdb, mame, wii_rom_set_by_ghostware
from database import db_manager

SCRAPERS = {
    'myrient': myrient,
    'internet_archive': internet_archive,
    'nopaystation': nopaystation,
    'mariocube': mariocube
}

PARSERS = {
    'no_intro': no_intro,
    'libretro': libretro,
    'gametdb': gametdb,
    'mame': mame,
    'wii_rom_set_by_ghostware': wii_rom_set_by_ghostware
}


def load_sources(file_path='sources.json'):
    """Load sources from a JSON file."""
    with open(file_path, 'r') as file:
        return json.load(file)


def get_scraper(name):
    """Retrieve a scraper by its name."""
    return SCRAPERS.get(name)


def get_parser(name):
    """Retrieve a parser by its name."""
    return PARSERS.get(name)


def process_sources(sources, use_cached, scraper_filter=None):
    """Process the sources to scrape, parse, and insert data into the database."""
    for platform, source_list in sources.items():
        # Filter sources by scraper if specified
        if scraper_filter:
            source_list = [s for s in source_list if s['scraper'] in scraper_filter]
            if not source_list:
                continue

        print(f"\n{platform}:")
        for i, source in enumerate(source_list, start=1):
            print(f"  {i}) ", end='')
            print(f"[{source['format']}] ", end='')
            if source['regions']:
                print(f"[{', '.join(source['regions'])}] ", end='')
            print(f"[{source['scraper']}] ", end='')
            print(f"[{source['type']}]")

            scraper = get_scraper(source['scraper'])
            if not scraper:
                print(f"Scraper '{source['scraper']}' not found.")
                sys.exit(1)

            entries = scraper.scrape(source, platform, use_cached)

            for parser_name, parser_flags in source['parsers'].items():
                parser = get_parser(parser_name)
                if not parser:
                    print(f"Parser '{parser_name}' not found.")
                    sys.exit(1)

                entries = parser.parse(entries, parser_flags)

            for entry in entries:
                db_manager.insert_entry(entry)


def make(use_cached=False, sources_file='sources.json', scraper_filter=None):
    """Main function to initialize the database, process sources, and close the database."""
    sources = load_sources(sources_file)
    db_manager.init_database()

    if scraper_filter:
        print(f"Filtering to scrapers: {', '.join(scraper_filter)}")

    process_sources(sources, use_cached, scraper_filter)

    db_manager.close_database()
    print("Database created successfully.")


if __name__ == '__main__':
    # Change directory to script location
    os.chdir(os.path.dirname(os.path.realpath(__file__)))

    args = sys.argv[1:] if len(sys.argv) > 1 else []
    use_cached = '--use-cached' in args

    # Check for --sources argument
    sources_file = 'sources.json'
    scraper_filter = None
    for i, arg in enumerate(args):
        if arg == '--sources' and i + 1 < len(args):
            sources_file = args[i + 1]
        elif arg == '--scrapers' and i + 1 < len(args):
            # Comma-separated list of scrapers to run
            scraper_filter = [s.strip() for s in args[i + 1].split(',')]

    make(use_cached, sources_file, scraper_filter)
