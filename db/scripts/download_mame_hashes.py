#!/usr/bin/env python
"""
This script downloads the MAME hash files from the official MAME GitHub repository 
using a sparse Git checkout. It ensures that only the necessary `hash` directory 
is downloaded, minimizing the data transfer. The downloaded files are saved in 
the `data/mame/hash` directory.
"""
import os
import sys
import subprocess
import shutil
import tempfile


def download_mame_hashes():
    """Download the MAME hash files from the official MAME GitHub repository."""
    print("Downloading MAME hash files...")

    # Check if Git is installed and available in PATH
    if not shutil.which('git'):
        print("Git is not installed or not found in PATH. Please install Git to proceed.")
        sys.exit(1)

    # Destination directory for the hash files
    destination = 'data/mame/hash'
    os.makedirs(destination, exist_ok=True)

    # URL of the MAME GitHub repository
    repo_url = 'https://github.com/mamedev/mame.git'

    # Directory to be sparsely checked out from the repository
    dir_path = 'hash'

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
        # Set the sparse-checkout to only include the `hash` directory
        subprocess.run(
            ['git', '-C', temp_dir, 'sparse-checkout', 'set', dir_path],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        # Path to the `hash` directory in the cloned repository
        hash_dir = os.path.join(temp_dir, dir_path)
        if os.path.exists(hash_dir):
            # Copy all files and subdirectories from the `hash` directory to the destination
            for item in os.listdir(hash_dir):
                s = os.path.join(hash_dir, item)
                d = os.path.join(destination, item)
                if os.path.isdir(s):
                    # Copy directories recursively
                    shutil.copytree(s, d, dirs_exist_ok=True)
                else:
                    # Copy individual files
                    shutil.copy2(s, d)

    print(f"Successfully downloaded MAME hash files to {destination}")


if __name__ == '__main__':
    # Change the working directory to main db repository location
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
    os.chdir('../')

    download_mame_hashes()
