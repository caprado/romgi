#!/usr/bin/env python
"""
This script automates the workflow for generating the ROM database.

Usage:
    python workflow.py              # Fresh download of everything
    python workflow.py --use-cached # Use cached HTTP responses (faster rebuilds)
"""
import os
import sys
from make import make
from scripts.download_gametdb_xmls import download_gametdb_xmls
from scripts.download_libretro_dats import download_libretro_dats
from scripts.download_mame_hashes import download_mame_hashes

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.realpath(__file__)))

    use_cached = '--use-cached' in sys.argv

    if use_cached:
        print("Using cached HTTP responses where available.\n")

    download_gametdb_xmls()
    download_libretro_dats()
    download_mame_hashes()
    make(use_cached=use_cached)
