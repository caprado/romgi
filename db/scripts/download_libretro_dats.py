#!/usr/bin/env python
"""
This script downloads Libretro DAT files from the official Libretro GitHub repository.
It uses a sparse Git checkout to efficiently clone only the required directories and
copies the files to a specified destination directory.
"""
import os
import sys
import subprocess
import shutil
import tempfile


def download_libretro_dats():
    """Download Libretro DAT files from the official GitHub repository."""
    print("Downloading Libretro DAT files...")

    # Check if Git is installed and available in PATH
    if not shutil.which('git'):
        print("Git is not installed or not found in PATH. Please install Git to proceed.")
        sys.exit(1)

    # Base destination directory for the downloaded files
    base_destination = 'data/libretro'

    # URL of the Libretro database repository
    repo_url = 'https://github.com/libretro/libretro-database.git'

    # Directories to clone from the repository
    directories_to_clone = ['dat', 'metadat']

    # Ensure the destination directories exist
    for dir_name in directories_to_clone:
        destination = os.path.join(base_destination, dir_name)
        os.makedirs(destination, exist_ok=True)

    # Use a temporary directory for cloning the repository
    with tempfile.TemporaryDirectory() as temp_dir:
        # Clone the repository with sparse checkout enabled
        subprocess.run(
            ['git', 'clone', '--depth', '1', '--filter=blob:none',
             '--sparse', repo_url, temp_dir],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        # Sparse checkout for each required directory
        for dir_name in directories_to_clone:
            subprocess.run(
                ['git', '-C', temp_dir, 'sparse-checkout', 'set', dir_name],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            # Source and destination paths for copying files
            source_dir = os.path.join(temp_dir, dir_name)
            destination = os.path.join(base_destination, dir_name)

            # Copy files from the sparse-checked-out directory to the destination
            if os.path.exists(source_dir):
                for item in os.listdir(source_dir):
                    s = os.path.join(source_dir, item)
                    d = os.path.join(destination, item)
                    if os.path.isdir(s):
                        # Copy directories recursively
                        shutil.copytree(s, d, dirs_exist_ok=True)
                    else:
                        # Copy individual files
                        shutil.copy2(s, d)

    print(f"Successfully downloaded Libretro DAT files to {base_destination}")


if __name__ == '__main__':
    # Change the working directory to main db repository location
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
    os.chdir('../')

    download_libretro_dats()
