#!/usr/bin/env python3
"""
Hardclone CLI - Partition Backup Creator/Restorer with Dialog Interface (Python)
Author: Dawid Bielecki "dawciobiel"
Version: {VERSION}
License: GPL-3.0
Description:
    Interactive Python script for creating and restoring partition backups with encryption,
    compression, and file splitting.
"""

import os
import subprocess
import shutil
import sys
import glob
from pathlib import Path
import tempfile

def ensure_root():
    # Check UID of process (0 = root)
    if os.geteuid() != 0:
        print("Restarting with sudo...")
        try:
            # Restart the same script by 'sudo'
            subprocess.check_call(["sudo", sys.executable] + sys.argv)
        except subprocess.CalledProcessError as e:
            sys.exit(e.returncode)
        sys.exit(0)

ensure_root()

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

# Global variables for backup
DEVICE = ""
PARTITION = ""
OUTPUT_PATH = ""
ENCRYPT = False
ENCRYPT_PASSWORD = ""
COMPRESS = False
SPLIT = False
SPLIT_SIZE = ""

# Global variables for restore
RESTORE_FILE = ""
RESTORE_DEVICE = ""
RESTORE_PARTITION = ""
IS_ENCRYPTED = False
IS_COMPRESSED = False
IS_SPLIT = False
RESTORE_PASSWORD = ""


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
    found_devices = set()

    # Method 1: Try lsblk -d first
    try:
        output = subprocess.check_output(
            "lsblk -d -o NAME,SIZE,MODEL,TYPE --noheadings", shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None, 3)
            if len(parts) >= 3:
                name = parts[0]
                size = parts[1]

                # Skip loop, ram, rom and other virtual devices by name
                if name.startswith(('loop', 'ram', 'rom', 'dm-', 'sr')):
                    continue

                if len(parts) == 3:
                    model = parts[2] if parts[2] != '-' else "Unknown model"
                    typ = "disk"
                elif len(parts) == 4:
                    model = parts[2] if parts[2] != '-' else "Unknown model"
                    typ = parts[3]
                else:
                    model = "Unknown model"
                    typ = "disk"

                # Only include disk type devices and exclude virtual devices
                if typ == "disk" and not name.startswith(('loop', 'ram', 'rom', 'dm-', 'sr')):
                    devices.append((name, f"{size} | {model.strip()}"))
                    found_devices.add(name)
    except Exception:
        pass

    # Method 2: Try lsblk without -d and filter for parent devices
    try:
        output = subprocess.check_output(
            "lsblk -o NAME,SIZE,MODEL,TYPE,PKNAME --noheadings", shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None, 4)
            if len(parts) >= 4:
                name = parts[0].lstrip('├─└─│ ')  # Remove tree characters
                size = parts[1]
                model = parts[2] if parts[2] != '-' else "Unknown model"
                typ = parts[3]
                pkname = parts[4] if len(parts) > 4 else ""

                # Include only disk type devices (exclude loop, rom, etc.) that are not already found and have no parent
                if (typ == "disk" and not pkname and name not in found_devices and
                    not name.startswith(('loop', 'ram', 'rom', 'dm-', 'sr'))):
                    devices.append((name, f"{size} | {model.strip()}"))
                    found_devices.add(name)
    except Exception:
        pass

    # Method 3: Direct /proc/partitions parsing as additional fallback
    try:
        with open('/proc/partitions', 'r') as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 4 and parts[3] and not any(char.isdigit() for char in parts[3][-1]):
                    # This is likely a whole disk (no partition number at the end)
                    name = parts[3]
                    # Only include real disk devices, exclude loop, ram, etc.
                    if (name not in found_devices and
                        name.startswith(('sd', 'nvme', 'vd', 'hd')) and
                        not name.startswith(('loop', 'ram', 'dm-'))):
                        try:
                            dev_path = f"/dev/{name}"
                            size_bytes = int(subprocess.check_output(f"blockdev --getsize64 {dev_path}", shell=True, text=True))
                            size_str = format_size(size_bytes)
                            # Try to get model info
                            try:
                                model_output = subprocess.check_output(f"lsblk -d -n -o MODEL {dev_path}", shell=True, text=True).strip()
                                model = model_output if model_output and model_output != '-' else "Unknown model"
                            except:
                                model = "Unknown model"
                            devices.append((name, f"{size_str} | {model}"))
                            found_devices.add(name)
                        except:
                            continue
    except Exception:
        pass

    # Final fallback: Direct device scanning
    if not devices:
        for pattern in ["/dev/sd[a-z]", "/dev/nvme*n*", "/dev/vd[a-z]", "/dev/hd[a-z]"]:
            for dev_path in sorted(Path("/").glob(pattern.lstrip("/"))):
                if dev_path.exists() and dev_path.name not in found_devices:
                    try:
                        size_bytes = int(subprocess.check_output(f"blockdev --getsize64 {dev_path}", shell=True, text=True))
                        size_str = format_size(size_bytes)
                        devices.append((dev_path.name, f"{size_str} | Unknown model"))
                    except:
                        continue

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


def select_restore_device():
    """Prompt user to select a storage device for restore."""
    global RESTORE_DEVICE
    devices = list_devices()
    if not devices:
        d.msgbox("No storage devices found!", width=60)
        sys.exit(1)
    choices = [(name, desc) for name, desc in devices]
    code, tag = d.menu("Select destination device for restore:", choices=choices, width=70, height=15)
    if code != d.DIALOG_OK:
        sys.exit(0)
    RESTORE_DEVICE = "/dev/" + tag if not tag.startswith("/dev/") else tag


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
        for part_file in sorted(list(glob.glob(f"/dev/{base}[0-9]*")) + list(glob.glob(f"/dev/{base}p[0-9]*"))):
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


def select_restore_partition():
    """Prompt user to select a partition for restore."""
    global RESTORE_PARTITION
    partitions = list_partitions(RESTORE_DEVICE)
    if not partitions:
        d.msgbox(f"No partitions found on device {RESTORE_DEVICE}!", width=70)
        sys.exit(1)
    choices = [(name, desc) for name, desc in partitions]
    code, tag = d.menu(f"Select destination partition on {RESTORE_DEVICE}:", choices=choices, width=80, height=15)
    if code != d.DIALOG_OK:
        sys.exit(0)
    RESTORE_PARTITION = "/dev/" + tag if not tag.startswith("/dev/") else tag
    if not os.path.exists(RESTORE_PARTITION):
        d.msgbox(f"Error: Partition {RESTORE_PARTITION} does not exist!", width=60)
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


def select_restore_file():
    """Prompt user to select restore image file."""
    global RESTORE_FILE
    code, path = d.inputbox("Enter path to backup image file:", width=70)
    if code != d.DIALOG_OK:
        sys.exit(0)
    RESTORE_FILE = path
    if not os.path.exists(RESTORE_FILE):
        d.msgbox(f"Error: File {RESTORE_FILE} does not exist!", width=60)
        sys.exit(1)


def detect_file_properties(file_path):
    """Detect if file is encrypted, compressed, or split."""
    global IS_ENCRYPTED, IS_COMPRESSED, IS_SPLIT

    # Check for split files
    base_dir = os.path.dirname(file_path)
    base_name = os.path.basename(file_path)

    # Look for split file patterns
    split_patterns = [
        f"{base_name}.*",  # file.ext.aa, file.ext.ab, etc.
        f"{base_name.rsplit('.', 1)[0]}.*" if '.' in base_name else f"{base_name}.*"  # file.aa, file.ab, etc.
    ]

    split_files = []
    for pattern in split_patterns:
        matches = glob.glob(os.path.join(base_dir, pattern))
        if len(matches) > 1:  # More than just the original file
            split_files.extend(matches)

    IS_SPLIT = len(split_files) > 1

    # Check file extension and content to detect compression and encryption
    IS_COMPRESSED = file_path.endswith('.gz') or file_path.endswith('.gz.enc')
    IS_ENCRYPTED = file_path.endswith('.enc') or file_path.endswith('.gz.enc')

    # If we can't determine from extension, try to detect from file content
    if not IS_COMPRESSED and not IS_ENCRYPTED:
        try:
            with open(file_path, 'rb') as f:
                header = f.read(16)
                # Check for gzip magic number
                if header.startswith(b'\x1f\x8b'):
                    IS_COMPRESSED = True
                # OpenSSL encrypted files start with "Salted__"
                elif header.startswith(b'Salted__'):
                    IS_ENCRYPTED = True
        except Exception:
            pass


def ask_restore_password():
    """Ask for decryption password if needed."""
    global RESTORE_PASSWORD
    if IS_ENCRYPTED:
        code, password = d.passwordbox("Enter decryption password:", width=50)
        if code != d.DIALOG_OK:
            sys.exit(0)
        RESTORE_PASSWORD = password


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


def show_backup_summary():
    """Display summary of backup operation."""
    summary = f"""
BACKUP OPERATION SUMMARY:

Device: {DEVICE}
Partition: {PARTITION}
Output file: {OUTPUT_PATH}
Encryption: {'YES' if ENCRYPT else 'NO'}
Compression: {'YES' if COMPRESS else 'NO'}
File splitting: {'YES (' + SPLIT_SIZE + ')' if SPLIT else 'NO'}

Continue with backup operation?
"""
    code = d.yesno(summary, width=70)
    return code == d.DIALOG_OK


def show_restore_summary():
    """Display summary of restore operation."""
    summary = f"""
RESTORE OPERATION SUMMARY:

Source file: {RESTORE_FILE}
Destination device: {RESTORE_DEVICE}
Destination partition: {RESTORE_PARTITION}
File is encrypted: {'YES' if IS_ENCRYPTED else 'NO'}
File is compressed: {'YES' if IS_COMPRESSED else 'NO'}
File is split: {'YES' if IS_SPLIT else 'NO'}

WARNING: This will OVERWRITE all data on {RESTORE_PARTITION}!
Are you sure you want to continue?
"""
    code = d.yesno(summary, width=80)
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
        pipeline = f"split -b {SPLIT_SIZE} - {out_file}."
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


def restore_image():
    """Execute the partition restore."""
    # Build the command pipeline for reading the file
    input_cmd = ""

    if IS_SPLIT:
        # Find all split files
        base_dir = os.path.dirname(RESTORE_FILE)
        base_name = os.path.basename(RESTORE_FILE)

        # Try different split file patterns
        split_files = []
        patterns = [
            f"{RESTORE_FILE}.*",
            f"{RESTORE_FILE.rsplit('.', 1)[0]}.*" if '.' in base_name else f"{RESTORE_FILE}.*"
        ]

        for pattern in patterns:
            matches = sorted(glob.glob(pattern))
            if len(matches) > 1:
                split_files = matches
                break

        if not split_files:
            d.msgbox("ERROR: Could not find split files!", width=50)
            sys.exit(1)

        # Use cat to join split files
        split_files_str = " ".join(f'"{f}"' for f in split_files)
        input_cmd = f"cat {split_files_str}"
    else:
        input_cmd = f"cat {RESTORE_FILE}"

    # Build the pipeline for processing the data
    pipeline_parts = []

    # First handle decryption if needed
    if IS_ENCRYPTED:
        pipeline_parts.append(f"openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:{RESTORE_PASSWORD}")

    # Then handle decompression if needed
    if IS_COMPRESSED:
        pipeline_parts.append("gunzip")

    # Finally write to partition
    pipeline_parts.append(f"dd of={RESTORE_PARTITION} bs=1M")

    # Combine all parts
    if pipeline_parts:
        full_cmd = f"{input_cmd} | " + " | ".join(pipeline_parts)
    else:
        full_cmd = f"{input_cmd} | dd of={RESTORE_PARTITION} bs=1M"

    d.infobox("Starting partition restore...\nThis may take a long time.", width=50)
    try:
        subprocess.run(full_cmd, shell=True, check=True)
        msg = f"Partition restored successfully!\nDestination: {RESTORE_PARTITION}"
        if IS_SPLIT:
            msg += "\nJoined split files"
        if IS_COMPRESSED:
            msg += "\nDecompressed file"
        if IS_ENCRYPTED:
            msg += "\nDecrypted file"
        d.msgbox(msg, width=70)
    except subprocess.CalledProcessError as e:
        error_msg = "ERROR: Failed to restore partition image!"
        if IS_ENCRYPTED:
            error_msg += "\nPossible causes:\n- Wrong password\n- Corrupted file"
        d.msgbox(error_msg, width=60)
        sys.exit(1)


def select_operation():
    """Ask user to select backup or restore operation."""
    choices = [
        ("backup", "Create backup image from partition"),
        ("restore", "Restore partition from backup image")
    ]
    code, tag = d.menu("Select operation:", choices=choices, width=60, height=10)
    if code != d.DIALOG_OK:
        sys.exit(0)
    return tag


def backup_workflow():
    """Execute backup workflow."""
    select_device()
    select_partition()
    select_output_path()
    select_encryption()
    select_compression()
    select_split()

    if show_backup_summary():
        create_image()
    else:
        d.msgbox("Backup operation cancelled by user.", width=50)


def restore_workflow():
    """Execute restore workflow."""
    select_restore_file()
    detect_file_properties(RESTORE_FILE)
    ask_restore_password()
    select_restore_device()
    select_restore_partition()

    if show_restore_summary():
        restore_image()
    else:
        d.msgbox("Restore operation cancelled by user.", width=50)


def main():
    """Main program flow."""
    d.msgbox(f"Welcome to Hardclone CLI {VERSION} - Partition Backup Creator/Restorer!", width=70)

    operation = select_operation()

    if operation == "backup":
        backup_workflow()
    elif operation == "restore":
        restore_workflow()


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("ERROR: This script must be run as root!")
        sys.exit(1)
    main()
