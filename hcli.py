#!/usr/bin/env python3
"""
Hardclone CLI - Partition Backup Creator with Dialog Interface (Python)
Author: Dawid Bielecki "dawciobiel"
Version: {VERSION}
License: GPL-3.0
Description:
    Interactive Python script for creating partition backups with encryption,
    compression, and file splitting.
"""

import os
import subprocess
import shutil
import sys
from pathlib import Path
import tempfile

try:
    import dialog  # python3-dialog
except ImportError:
    print("ERROR: python3-dialog module not installed!")
    print("Install it with: pip3 install pythondialog")
    sys.exit(1)


# Load version from external file
def get_version():
    version_file = Path(__file__).parent / "VERSION"

    # Try to get version from Git tag
    try:
        git_version = subprocess.check_output(
            ["git", "describe", "--tags", "--abbrev=0"],
            cwd=Path(__file__).parent,
            text=True
        ).strip()
        if git_version:
            # Update VERSION file if it differs
            if not version_file.exists() or version_file.read_text(encoding="utf-8").strip() != git_version:
                version_file.write_text(git_version + "\n", encoding="utf-8")
            return git_version
    except subprocess.CalledProcessError:
        pass  # Not a git repo or no tags

    # Fallback: read from VERSION file
    if version_file.exists():
        return version_file.read_text(encoding="utf-8").strip()

    return "unknown"



VERSION = get_version()

d = dialog.Dialog(dialog="dialog")

# Global variables
DEVICE = ""
PARTITION = ""
OUTPUT_PATH = ""
ENCRYPT = False
ENCRYPT_PASSWORD = ""
COMPRESS = False
SPLIT = False
SPLIT_SIZE = ""


def format_size(bytes_size):
    """Format bytes into human-readable size."""
    try:
        bytes_size = int(bytes_size)
    except Exception:
        return "Unknown size"

    if bytes_size >= 1 << 40:
        return f"{bytes_size / (1 << 40):.1f} TB"
    elif bytes_size >= 1 << 30:
        return f"{bytes_size / (1 << 30):.1f} GB"
    elif bytes_size >= 1 << 20:
        return f"{bytes_size // (1 << 20)} MB"
    else:
        return f"{bytes_size // (1 << 10)} KB"


def list_devices():
    """Return list of available storage devices."""
    devices = []
    try:
        output = subprocess.check_output(
            "lsblk -d -o NAME,SIZE,MODEL,TYPE --noheadings", shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None, 3)
            if len(parts) < 4:
                continue
            name, size, model, typ = parts
            if typ == "disk" or typ == "":
                devices.append((name, f"{size} | {model.strip()}"))
    except Exception:
        pass

    # fallback: /dev/sd* and /dev/nvme* if no devices detected
    if not devices:
        for dev in sorted(list(shutil.glob("/dev/sd[a-z]")) + list(shutil.glob("/dev/nvme*n*"))):
            if os.path.exists(dev):
                try:
                    size_bytes = int(subprocess.check_output(f"blockdev --getsize64 {dev}", shell=True, text=True))
                    size_str = format_size(size_bytes)
                except Exception:
                    size_str = "Unknown size"
                devices.append((os.path.basename(dev), f"{size_str} | Unknown model"))
    return devices


def select_device():
    """Prompt user to select a storage device."""
    global DEVICE
    devices = list_devices()
    if not devices:
        d.msgbox("No storage devices found!", width=60)
        sys.exit(1)
    choices = [(name, desc) for name, desc in devices]
    code, tag = d.menu("Select storage device:", choices=choices, width=60, height=15)
    if code != d.DIALOG_OK:
        sys.exit(0)
    DEVICE = "/dev/" + tag if not tag.startswith("/dev/") else tag


def list_partitions(device):
    """Return list of partitions for a given device."""
    partitions = []
    try:
        output = subprocess.check_output(
            f"lsblk -n -r {device} -o NAME,SIZE,FSTYPE,MOUNTPOINT", shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None, 3)
            if len(parts) < 2:
                continue
            name = parts[0]
            size = parts[1]
            fstype = parts[2] if len(parts) > 2 else "unknown"
            mount = parts[3] if len(parts) > 3 else "not mounted"
            if os.path.basename(device) != os.path.basename(name):
                partitions.append((os.path.basename(name), f"{size} | {fstype} | {mount}"))
    except Exception:
        pass

    # fallback: direct /dev scanning
    if not partitions:
        base = os.path.basename(device)
        for part_file in sorted(list(shutil.glob(f"/dev/{base}[0-9]*")) + list(shutil.glob(f"/dev/{base}p[0-9]*"))):
            if os.path.exists(part_file):
                try:
                    size_bytes = int(subprocess.check_output(f"blockdev --getsize64 {part_file}", shell=True, text=True))
                    size_str = format_size(size_bytes)
                except Exception:
                    size_str = "Unknown size"
                fstype = subprocess.getoutput(f"blkid -o value -s TYPE {part_file}") or "unknown"
                mount = subprocess.getoutput(f"findmnt -n -o TARGET {part_file}") or "not mounted"
                partitions.append((os.path.basename(part_file), f"{size_str} | {fstype} | {mount}"))
    return partitions


def select_partition():
    """Prompt user to select a partition from DEVICE."""
    global PARTITION
    partitions = list_partitions(DEVICE)
    if not partitions:
        d.msgbox(f"No partitions found on device {DEVICE}!", width=70)
        sys.exit(1)
    choices = [(name, desc) for name, desc in partitions]
    code, tag = d.menu(f"Select partition on {DEVICE}:", choices=choices, width=70, height=15)
    if code != d.DIALOG_OK:
        sys.exit(0)
    PARTITION = "/dev/" + tag if not tag.startswith("/dev/") else tag
    if not os.path.exists(PARTITION):
        d.msgbox(f"Error: Partition {PARTITION} does not exist!", width=60)
        sys.exit(1)


def select_output_path():
    """Prompt user to select output path for image file."""
    global OUTPUT_PATH
    default_path = f"/tmp/backup_{os.path.basename(PARTITION)}.img"
    code, path = d.inputbox("Enter destination path for partition image:", init=default_path, width=70)
    if code != d.DIALOG_OK:
        sys.exit(0)
    OUTPUT_PATH = path
    output_dir = os.path.dirname(OUTPUT_PATH)
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    # Check available space
    available_space = shutil.disk_usage(output_dir).free
    partition_size = int(subprocess.check_output(f"blockdev --getsize64 {PARTITION}", shell=True, text=True))
    if partition_size > available_space:
        d.msgbox(f"Warning: Partition size ({format_size(partition_size)}) may exceed available space ({format_size(available_space)})!", width=70)


def select_encryption():
    """Ask if the user wants to encrypt the image."""
    global ENCRYPT, ENCRYPT_PASSWORD
    code = d.yesno("Encrypt the image file?", width=50)
    if code == d.DIALOG_OK:
        ENCRYPT = True
        code, pw1 = d.passwordbox("Enter encryption password:", width=50)
        if code != d.DIALOG_OK or not pw1:
            sys.exit(0)
        code, pw2 = d.passwordbox("Confirm encryption password:", width=50)
        if code != d.DIALOG_OK or pw1 != pw2:
            d.msgbox("Passwords do not match!", width=50)
            sys.exit(1)
        ENCRYPT_PASSWORD = pw1


def select_compression():
    """Ask if the user wants to compress the image."""
    global COMPRESS
    code = d.yesno("Compress the image file?", width=50)
    if code == d.DIALOG_OK:
        COMPRESS = True


def select_split():
    """Ask if the user wants to split the file."""
    global SPLIT, SPLIT_SIZE
    code = d.yesno("Split file into smaller parts?", width=50)
    if code == d.DIALOG_OK:
        SPLIT = True
        code, size = d.inputbox("Enter maximum size for each part (e.g. 1G, 500M, 2048K):", init="1G", width=50)
        if code != d.DIALOG_OK:
            sys.exit(0)
        if not size or not size.upper()[0].isdigit():
            d.msgbox("Invalid size format!", width=50)
            sys.exit(1)
        SPLIT_SIZE = size


def show_summary():
    """Display summary of operation."""
    summary = f"""
OPERATION SUMMARY:

Device: {DEVICE}
Partition: {PARTITION}
Output file: {OUTPUT_PATH}
Encryption: {'YES' if ENCRYPT else 'NO'}
Compression: {'YES' if COMPRESS else 'NO'}
File splitting: {'YES (' + SPLIT_SIZE + ')' if SPLIT else 'NO'}

Continue with operation?
"""
    code = d.yesno(summary, width=70)
    return code == d.DIALOG_OK


def create_image():
    """Execute the partition backup."""
    cmd = f"dd if={PARTITION} bs=1M"

    out_file = OUTPUT_PATH
    pipeline = ""
    if COMPRESS and ENCRYPT:
        if SPLIT:
            pipeline = f"gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:{ENCRYPT_PASSWORD} | split -b {SPLIT_SIZE} - {out_file}."
        else:
            pipeline = f"gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:{ENCRYPT_PASSWORD} -out {out_file}.gz.enc"
    elif COMPRESS:
        if SPLIT:
            pipeline = f"gzip | split -b {SPLIT_SIZE} - {out_file}.gz."
        else:
            pipeline = f"gzip > {out_file}.gz"
    elif ENCRYPT:
        if SPLIT:
            pipeline = f"openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:{ENCRYPT_PASSWORD} | split -b {SPLIT_SIZE} - {out_file}.enc."
        else:
            pipeline = f"openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:{ENCRYPT_PASSWORD} -out {out_file}.enc"
    elif SPLIT:
        pipeline = f"split -b {SPLIT_SIZE} - {out_file}"
    else:
        cmd += f" of={out_file}"

    full_cmd = f"{cmd} | {pipeline}" if pipeline else cmd

    d.infobox("Starting partition image creation...\nThis may take a long time.", width=50)
    try:
        subprocess.run(full_cmd, shell=True, check=True)
        msg = f"Partition image created successfully!\nLocation: {OUTPUT_PATH}"
        if SPLIT:
            msg += f"\nFile was split into parts of size {SPLIT_SIZE}"
        if COMPRESS:
            msg += "\nFile was compressed (gzip)"
        if ENCRYPT:
            msg += "\nFile was encrypted (AES-256-CBC)"
        d.msgbox(msg, width=70)
    except subprocess.CalledProcessError:
        d.msgbox("ERROR: Failed to create partition image!", width=50)
        sys.exit(1)


def main():
    """Main program flow."""
    d.msgbox(f"Welcome to Hardclone CLI v{VERSION} - Partition Backup Creator!", width=60)
    select_device()
    select_partition()
    select_output_path()
    select_encryption()
    select_compression()
    select_split()

    if show_summary():
        create_image()
    else:
        d.msgbox("Operation cancelled by user.", width=50)


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("ERROR: This script must be run as root!")
        sys.exit(1)
    main()
