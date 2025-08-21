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
    """Ensure the script runs as root. Restart with sudo if needed."""
    if os.geteuid() != 0:
        print("Restarting with sudo...")
        try:
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
    print("or with package manager: python3-dialog")
    sys.exit(1)

# Load version from external file
def get_version():
    version_file = Path(__file__).parent / "VERSION"
    if version_file.exists():
        return version_file.read_text(encoding="utf-8").strip()
    return "unknown"

VERSION = get_version()

# Replace docstring dynamically with VERSION
__doc__ = f"""
Hardclone CLI - Partition Backup Creator/Restorer with Dialog Interface (Python)
Author: Dawid Bielecki "dawciobiel"
Version: {VERSION}
License: GPL-3.0
Description:
    Interactive Python script for creating and restoring partition backups with encryption,
    compression, and file splitting.
"""

d = dialog.Dialog(dialog="dialog")

# ===============================
# Global variables
# ===============================
DEVICE = ""
PARTITION = ""
OUTPUT_PATH = ""
ENCRYPT = False
ENCRYPT_PASSWORD = ""
COMPRESS = False
SPLIT = False
SPLIT_SIZE = ""

RESTORE_FILE = ""
RESTORE_DEVICE = ""
RESTORE_PARTITION = ""
IS_ENCRYPTED = False
IS_COMPRESSED = False
IS_SPLIT = False
RESTORE_PASSWORD = ""

# ===============================
# Helper functions
# ===============================
def format_size(bytes_size):
    """Convert bytes to human-readable format."""
    try:
        bytes_size = int(bytes_size)
    except Exception:
        return "Unknown size"
    if bytes_size >= 1 << 40:
        return f"{bytes_size / (1 << 40):.1f} TB"
    elif bytes_size >= 1 << 30:
        return f"{bytes_size / (1 << 30):.1f} GB"
    elif bytes_size >= 1 << 20:
        return f"{bytes_size / (1 << 20):.1f} MB"
    else:
        return f"{bytes_size // (1 << 10)} KB"

def list_devices():
    """List all real storage devices."""
    devices = []
    found_devices = set()
    # Method 1: lsblk -d
    try:
        output = subprocess.check_output(
            "lsblk -d -o NAME,SIZE,MODEL,TYPE --noheadings",
            shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None, 3)
            if len(parts) >= 3:
                name, size = parts[0], parts[1]
                if name.startswith(('loop','ram','rom','dm-','sr')):
                    continue
                model = parts[2] if parts[2] != '-' else "Unknown model"
                typ = parts[3] if len(parts) == 4 else "disk"
                if typ == "disk" and name not in found_devices:
                    devices.append((name, f"{size} | {model.strip()}"))
                    found_devices.add(name)
    except (subprocess.CalledProcessError, OSError):
        pass
    # Method 2: lsblk full
    try:
        output = subprocess.check_output(
            "lsblk -o NAME,SIZE,MODEL,TYPE,PKNAME --noheadings",
            shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None, 4)
            if len(parts) >= 4:
                name = parts[0].lstrip('├─└─│ ')
                size = parts[1]
                model = parts[2] if parts[2] != '-' else "Unknown model"
                typ = parts[3]
                pkname = parts[4] if len(parts) > 4 else ""
                if typ == "disk" and not pkname and name not in found_devices:
                    devices.append((name, f"{size} | {model.strip()}"))
                    found_devices.add(name)
    except (subprocess.CalledProcessError, OSError):
        pass
    # Method 3: /proc/partitions
    try:
        with open('/proc/partitions','r') as f:
            for line in f:
                parts = line.split()
                if len(parts) >=4 and parts[3] and not any(c.isdigit() for c in parts[3][-1]):
                    name = parts[3]
                    if name not in found_devices and name.startswith(('sd','nvme','vd','hd')):
                        try:
                            dev_path = f"/dev/{name}"
                            size_bytes = int(subprocess.check_output(
                                f"blockdev --getsize64 {dev_path}", shell=True, text=True
                            ))
                            size_str = format_size(size_bytes)
                            try:
                                model_output = subprocess.check_output(
                                    f"lsblk -d -n -o MODEL {dev_path}", shell=True, text=True
                                ).strip()
                                model = model_output if model_output and model_output != '-' else "Unknown model"
                            except:
                                model = "Unknown model"
                            devices.append((name, f"{size_str} | {model}"))
                            found_devices.add(name)
                        except:
                            continue
    except Exception:
        pass
    # Fallback: scan /dev
    if not devices:
        for pattern in ["/dev/sd[a-z]","/dev/nvme*n*","/dev/vd[a-z]","/dev/hd[a-z]"]:
            for dev_path in sorted(Path("/").glob(pattern.lstrip("/"))):
                if dev_path.exists() and dev_path.name not in found_devices:
                    try:
                        size_bytes = int(subprocess.check_output(
                            f"blockdev --getsize64 {dev_path}", shell=True, text=True
                        ))
                        size_str = format_size(size_bytes)
                        devices.append((dev_path.name, f"{size_str} | Unknown model"))
                    except:
                        continue
    return devices

# ===============================
# Select functions
# ===============================
def select_device():
    global DEVICE
    devices = list_devices()
    if not devices:
        d.msgbox("No storage devices found!", width=70)
        sys.exit(1)
    choices = [(name, desc) for name, desc in devices]
    code, tag = d.menu("Select storage device:", choices=choices, width=70, height=15)
    if code != d.DIALOG_OK:
        sys.exit(0)
    DEVICE = "/dev/" + tag if not tag.startswith("/dev/") else tag

def select_restore_device():
    global RESTORE_DEVICE
    devices = list_devices()
    if not devices:
        d.msgbox("No storage devices found!", width=70)
        sys.exit(1)
    choices = [(name, desc) for name, desc in devices]
    code, tag = d.menu("Select destination device for restore:", choices=choices, width=70, height=15)
    if code != d.DIALOG_OK:
        sys.exit(0)
    RESTORE_DEVICE = "/dev/" + tag if not tag.startswith("/dev/") else tag

# ===============================
# Partition functions
# ===============================
def list_partitions(device):
    partitions = []
    try:
        output = subprocess.check_output(
            f"lsblk -n -r {device} -o NAME,SIZE,FSTYPE,MOUNTPOINT", shell=True, text=True
        )
        for line in output.strip().splitlines():
            parts = line.split(None,3)
            if len(parts)<2: continue
            name,size = parts[0], parts[1]
            fstype = parts[2] if len(parts)>2 else "unknown"
            mount = parts[3] if len(parts)>3 else "not mounted"
            if os.path.basename(device)!=os.path.basename(name):
                partitions.append((os.path.basename(name), f"{size} | {fstype} | {mount}"))
    except:
        pass
    if not partitions:
        base=os.path.basename(device)
        for part_file in sorted(list(glob.glob(f"/dev/{base}[0-9]*"))+list(glob.glob(f"/dev/{base}p[0-9]*"))):
            if os.path.exists(part_file):
                try:
                    size_bytes=int(subprocess.check_output(f"blockdev --getsize64 {part_file}", shell=True, text=True))
                    size_str=format_size(size_bytes)
                except:
                    size_str="Unknown size"
                fstype=subprocess.getoutput(f"blkid -o value -s TYPE {part_file}") or "unknown"
                mount=subprocess.getoutput(f"findmnt -n -o TARGET {part_file}") or "not mounted"
                partitions.append((os.path.basename(part_file), f"{size_str} | {fstype} | {mount}"))
    return partitions

def select_partition():
    global PARTITION
    partitions=list_partitions(DEVICE)
    if not partitions:
        d.msgbox(f"No partitions found on device {DEVICE}!", width=70)
        sys.exit(1)
    choices=[(name,desc) for name,desc in partitions]
    code, tag = d.menu(f"Select partition on {DEVICE}:", choices=choices, width=70, height=15)
    if code!=d.DIALOG_OK:
        sys.exit(0)
    PARTITION="/dev/"+tag if not tag.startswith("/dev/") else tag

def select_restore_partition():
    global RESTORE_PARTITION
    partitions=list_partitions(RESTORE_DEVICE)
    if not partitions:
        d.msgbox(f"No partitions found on device {RESTORE_DEVICE}!", width=70)
        sys.exit(1)
    choices=[(name,desc) for name,desc in partitions]
    code, tag = d.menu(f"Select partition on {RESTORE_DEVICE}:", choices=choices, width=70, height=15)
    if code!=d.DIALOG_OK:
        sys.exit(0)
    RESTORE_PARTITION="/dev/"+tag if not tag.startswith("/dev/") else tag

def select_output_path():
    global OUTPUT_PATH
    code, path = d.fselect("/", width=70, height=20)
    if code != d.DIALOG_OK:
        sys.exit(0)
    OUTPUT_PATH=path

def select_restore_file():
    global RESTORE_FILE
    code, path=d.fselect("/", width=70, height=20)
    if code!=d.DIALOG_OK:
        sys.exit(0)
    RESTORE_FILE=path

def select_encryption():
    global ENCRYPT, ENCRYPT_PASSWORD
    code = d.yesno("Do you want to encrypt the backup? (LUKS)", width=70)
    if code==d.DIALOG_OK:
        ENCRYPT=True
        code, pwd = d.passwordbox("Enter encryption password:", width=70)
        if code==d.DIALOG_OK:
            ENCRYPT_PASSWORD=pwd
        else:
            sys.exit(0)

def select_compression():
    global COMPRESS
    code=d.yesno("Do you want to compress the backup? (gzip)", width=70)
    if code==d.DIALOG_OK:
        COMPRESS=True

def show_backup_summary():
    summary=f"Device: {DEVICE}\nPartition: {PARTITION}\nOutput path: {OUTPUT_PATH}\n"
    summary+=f"Encryption: {'Yes' if ENCRYPT else 'No'}\nCompression: {'Yes' if COMPRESS else 'No'}\n"
    try:
        partition_size=int(subprocess.check_output(f"blockdev --getsize64 {PARTITION}", shell=True, text=True))
        available=shutil.disk_usage(os.path.dirname(OUTPUT_PATH)).free
        if partition_size>available:
            summary+="\nWARNING: Partition size exceeds available disk space!"
    except:
        pass
    d.msgbox(summary,width=70)

def show_restore_summary():
    summary=f"Restore file: {RESTORE_FILE}\nDevice: {RESTORE_DEVICE}\nPartition: {RESTORE_PARTITION}\n"
    summary+=f"Encrypted: {'Yes' if IS_ENCRYPTED else 'No'}\nCompressed: {'Yes' if IS_COMPRESSED else 'No'}\n"
    d.msgbox(summary,width=70)

# ===============================
# Backup & Restore functions
# ===============================
def create_image():
    cmd=["dd","if="+PARTITION,"of="+OUTPUT_PATH,"bs=4M","status=progress"]
    if COMPRESS:
        cmd=["bash","-c",f"dd if={PARTITION} bs=4M status=progress | gzip > {OUTPUT_PATH}"]
    if ENCRYPT:
        cmd=["bash","-c",f"dd if={PARTITION} bs=4M status=progress | cryptsetup luksFormat -q - {OUTPUT_PATH}.luks && dd if={PARTITION} bs=4M status=progress | cryptsetup luksOpen {OUTPUT_PATH}.luks backup && dd if={PARTITION} of=/dev/mapper/backup"]
    try:
        subprocess.check_call(cmd)
        d.msgbox("Backup finished successfully!",width=70)
    except subprocess.CalledProcessError:
        d.msgbox("ERROR: Backup failed!",width=70)
        sys.exit(1)

def restore_image():
    cmd=["dd","if="+RESTORE_FILE,"of="+RESTORE_PARTITION,"bs=4M","status=progress"]
    if IS_COMPRESSED:
        cmd=["bash","-c",f"gzip -dc {RESTORE_FILE} | dd of={RESTORE_PARTITION} bs=4M status=progress"]
    if IS_ENCRYPTED:
        cmd=["bash","-c",f"cryptsetup luksOpen {RESTORE_FILE} backup && dd if=/dev/mapper/backup of={RESTORE_PARTITION} bs=4M status=progress"]
    try:
        subprocess.check_call(cmd)
        d.msgbox("Restore finished successfully!",width=70)
    except subprocess.CalledProcessError:
        d.msgbox("ERROR: Restore failed!",width=70)
        sys.exit(1)

# ===============================
# Main workflow
# ===============================
def backup_workflow():
    select_device()
    select_partition()
    select_output_path()
    select_encryption()
    select_compression()
    show_backup_summary()
    create_image()

def restore_workflow():
    select_restore_file()
    select_restore_device()
    select_restore_partition()
    # Detect properties from file if needed
    show_restore_summary()
    restore_image()

def main():
    code, tag=d.menu("Select operation:", choices=[("backup","Create partition backup"),("restore","Restore from backup")], width=70, height=10)
    if code!=d.DIALOG_OK:
        sys.exit(0)
    if tag=="backup":
        backup_workflow()
    else:
        restore_workflow()

if __name__=="__main__":
    main()
