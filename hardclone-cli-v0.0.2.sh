#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Dawid Bielecki

set -euo pipefail

TMP_DIR="/tmp"
DEFAULT_OUTDIR="$TMP_DIR"
COMPRESSION=""
ENCRYPTION=""
SPLIT=""
VERIFY=""
HASH=""

separator() {
  echo
  echo "--------------------------------------------------------------------------------------------"
  echo
}

# Get list of disks excluding loop devices
mapfile -t DISKS < <(lsblk -dn -o NAME,SIZE,MODEL | grep -v '^loop' | awk '{print NR"\t"$0}')

separator
echo "Available disks:"
printf '%s\n' "${DISKS[@]}"
separator
read -rp "Select disk number: " disk_index

DISK_LINE="${DISKS[$((disk_index - 1))]}"
DISK_NAME=$(awk '{print $2}' <<< "$DISK_LINE")
DISK="/dev/$DISK_NAME"

separator
echo "Selected disk: $DISK"

# Get list of partitions on selected disk
mapfile -t PARTS < <(lsblk -ln -o NAME,SIZE -x NAME "$DISK" | grep -v "^$DISK_NAME " | awk '{print NR")\t/dev/"$1"\t"$2}')

if [ ${#PARTS[@]} -eq 0 ]; then
    separator
    echo "No partitions found on selected disk."
    exit 1
fi

separator
echo "Available partitions on $DISK:"
printf '%s\n' "${PARTS[@]}"
separator
read -rp "Select partition number: " part_index

PART_LINE="${PARTS[$((part_index - 1))]}"
PART_DEV=$(awk '{print $2}' <<< "$PART_LINE")

separator
echo "Selected partition: ${PART_DEV#/dev/}"

read -rp "Enter filename for the image: " IMAGE_NAME
OUTFILE="$DEFAULT_OUTDIR/$IMAGE_NAME"

# Encryption
separator
echo "Enable encryption with GPG?"
select opt in "Yes" "No"; do
    case $opt in
        Yes ) ENCRYPTION="gpg"; break ;;
        No ) break ;;
    esac
done

# Compression
separator
echo "Select compression method:"
echo "1) none"
echo "2) gzip"
echo "3) zstd"
echo "4) bzip2"
echo "5) xz"
read -rp "#? " comp_choice
case $comp_choice in
    1) COMPRESSION="" && ext=".img" ;;
    2) COMPRESSION="gzip" && ext=".gz" ;;
    3) COMPRESSION="zstd" && ext=".zst" ;;
    4) COMPRESSION="bzip2" && ext=".bz2" ;;
    5) COMPRESSION="xz" && ext=".xz" ;;
    *) echo "Invalid compression option." && exit 1 ;;
esac

# Split
separator
echo "Do you want to split the image after creation?"
select opt in "Yes" "No"; do
    case $opt in
        Yes ) SPLIT="yes"; break ;;
        No ) break ;;
    esac
done

# Verify
separator
echo "Do you want to verify the image after creation?"
select opt in "Yes" "No"; do
    case $opt in
        Yes ) VERIFY="yes"; break ;;
        No ) break ;;
    esac
done

# Hash
separator
echo "Do you want to create checksum hashes (SHA256, MD5)?"
select opt in "Yes" "No"; do
    case $opt in
        Yes ) HASH="yes"; break ;;
        No ) break ;;
    esac
done

separator
echo "Creating image of ${PART_DEV#/dev/}..."
CMD="dd if=$PART_DEV bs=4M status=progress"

if [[ -n "$COMPRESSION" ]]; then
    CMD+=" | $COMPRESSION"
fi

if [[ "$ENCRYPTION" == "gpg" ]]; then
    CMD+=" | gpg --symmetric --cipher-algo AES256"
    OUTFILE="$OUTFILE.gpg"
fi

CMD+=" > \"$OUTFILE$ext\""
separator
echo "Executing: $CMD"
eval "$CMD"

# Split
if [[ "$SPLIT" == "yes" ]]; then
    separator
    echo "Splitting image into 2G chunks..."
    split -b 2000M "$OUTFILE$ext" "$OUTFILE$ext.part_"
fi

# Verify
if [[ "$VERIFY" == "yes" ]]; then
    separator
    echo "Verifying image..."
    cmp "$PART_DEV" <(dd if="$OUTFILE$ext" bs=4M status=none)
    echo "Verification completed."
fi

# Hash
if [[ "$HASH" == "yes" ]]; then
    separator
    echo "Generating checksums..."
    sha256sum "$OUTFILE$ext" > "$OUTFILE$ext.sha256"
    md5sum    "$OUTFILE$ext" > "$OUTFILE$ext.md5"
    echo "Checksums saved to:"
    echo "$OUTFILE$ext.sha256"
    echo "$OUTFILE$ext.md5"
fi

separator
echo "Done."
