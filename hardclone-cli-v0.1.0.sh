#!/usr/bin/env bash

# hardclone-cli v1.0.0
# Interactive CLI tool for creating and restoring disk/partition images
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Dawid Bielecki
#
# DESCRIPTION:
#   Interactive Bash-based tool for disk image management via terminal.
#   Supports both image creation from partitions and image restoration
#   to partitions with encryption, compression, and verification features.
#
# FEATURES:
#   • Dual mode operation (create/restore)
#   • Auto-detection of image formats from file extensions
#   • Encryption: AES-256-CBC, ChaCha20 (via OpenSSL)
#   • Compression: gzip, xz, zstandard
#   • Image verification and checksum generation (SHA256, MD5)
#   • Safety confirmations and warnings
#   • Optional image splitting for large files
#
# FILE FORMAT CONVENTION:
#   .himg                  - Raw image (uncompressed, unencrypted)
#   .himg.aes256           - AES-256 encrypted
#   .himg.chacha20         - ChaCha20 encrypted
#   .himg.gz               - Gzip compressed
#   .himg.xz               - XZ/LZMA compressed
#   .himg.zst              - Zstandard compressed
#   .himg.aes256.gz        - AES-256 encrypted, then gzip compressed
#   .himg.chacha20.xz      - ChaCha20 encrypted, then XZ compressed
#
# REQUIREMENTS:
#   • bash (4.0+)
#   • coreutils: dd, lsblk
#   • openssl (for encryption)
#   • Optional: gzip, xz, zstd, sha256sum, md5sum, split
#
# USAGE:
#   ./hardclone-cli.sh
#
#   Follow the interactive prompts to:
#   1. Choose operation mode (create/restore)
#   2. Select disk and partition
#   3. Configure encryption and compression
#   4. Set verification and splitting options
#
# EXAMPLES:
#   Create encrypted and compressed image:
#     Choose: Create → Select partition → AES-256 → gzip
#     Result: backup.himg.aes256.gz
#
#   Restore image with auto-detection:
#     Choose: Restore → Enter: backup.himg.chacha20.xz → Select target
#     Auto-detects: ChaCha20 encryption + XZ compression
#
# SECURITY NOTES:
#   • Uses OpenSSL with PBKDF2 key derivation
#   • Passwords are prompted securely (not visible in process list)
#   • Verification compares restored data with original partition
#   • Checksum files help verify image integrity
#
# WARNING:
#   This tool performs low-level disk operations. Incorrect usage can
#   result in data loss. Always verify partition selections and have
#   backups before restoring images.
#
# AUTHOR:
#   Dawid Bielecki <dawciobiel@gmail.com>
#   GitHub: https://github.com/dawciobiel/hardclone-cli
#
# VERSION HISTORY:
#   v1.0.0 - Initial release with create/restore functionality
#
# LICENSE:
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.

set -euo pipefail

TMP_DIR="/tmp"
DEFAULT_OUTDIR="$TMP_DIR"
COMPRESSION=""
ENCRYPTION=""
SPLIT=""
VERIFY=""
HASH=""
MODE=""

separator() {
  echo
  echo "--------------------------------------------------------------------------------------------"
  echo
}

# Function to detect image format from filename
detect_image_format() {
    local filepath="$1"
    local filename=$(basename "$filepath")

    # Reset format variables
    COMPRESSION=""
    ENCRYPTION=""

    # Check for compression extensions
    if [[ $filename == *.gz ]]; then
        COMPRESSION="gzip"
        filename="${filename%.gz}"
    elif [[ $filename == *.xz ]]; then
        COMPRESSION="xz"
        filename="${filename%.xz}"
    elif [[ $filename == *.zst ]]; then
        COMPRESSION="zstd"
        filename="${filename%.zst}"
    fi

    # Check for encryption extensions
    if [[ $filename == *.aes256 ]]; then
        ENCRYPTION="aes256"
        filename="${filename%.aes256}"
    elif [[ $filename == *.chacha20 ]]; then
        ENCRYPTION="chacha20"
        filename="${filename%.chacha20}"
    fi

    # Verify it's a hardclone image
    if [[ $filename != *.himg ]]; then
        echo "Error: Not a valid hardclone image file (missing .himg extension)"
        exit 1
    fi
}

# Function to show image information
show_image_info() {
    local filepath="$1"
    echo "Image file: $filepath"
    echo "File size: $(du -h "$filepath" | cut -f1)"

    if [[ -n "$ENCRYPTION" ]]; then
        echo "Encryption: $ENCRYPTION"
    else
        echo "Encryption: none"
    fi

    if [[ -n "$COMPRESSION" ]]; then
        echo "Compression: $COMPRESSION"
    else
        echo "Compression: none"
    fi

    # Check for hash files
    if [[ -f "$filepath.sha256" ]]; then
        echo "SHA256 checksum available"
    fi
    if [[ -f "$filepath.md5" ]]; then
        echo "MD5 checksum available"
    fi
}

# Get list of disks excluding loop devices
mapfile -t DISKS < <(lsblk -dn -o NAME,SIZE,MODEL | grep -v '^loop' | awk '{print NR"\t"$0}')

separator
echo "Select operation mode:"
echo "1) Create image from partition"
echo "2) Restore image to partition"
read -rp "#? " mode_choice

case $mode_choice in
    1) MODE="create" ;;
    2) MODE="restore" ;;
    *) echo "Invalid mode selection." && exit 1 ;;
esac

if [[ "$MODE" == "restore" ]]; then
    # RESTORE MODE
    separator
    read -rp "Enter full path to image file: " IMAGE_FILE

    if [[ ! -f "$IMAGE_FILE" ]]; then
        echo "Error: Image file does not exist: $IMAGE_FILE"
        exit 1
    fi

    # Detect and display image format
    detect_image_format "$IMAGE_FILE"
    separator
    echo "Image information:"
    show_image_info "$IMAGE_FILE"
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
    echo "WARNING: This will OVERWRITE all data on ${PART_DEV#/dev/}!"
    echo "Selected partition: ${PART_DEV#/dev/}"
    echo "Image file: $IMAGE_FILE"
    separator
    read -rp "Are you sure you want to continue? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "Operation cancelled."
        exit 0
    fi

    # Verify checksums if available
    if [[ -f "$IMAGE_FILE.sha256" ]]; then
        separator
        echo "Verifying SHA256 checksum..."
        if sha256sum -c "$IMAGE_FILE.sha256"; then
            echo "SHA256 checksum verification passed."
        else
            echo "SHA256 checksum verification failed!"
            read -rp "Continue anyway? (yes/no): " continue_anyway
            if [[ "$continue_anyway" != "yes" ]]; then
                exit 1
            fi
        fi
    fi

    # Build restore command
    separator
    echo "Restoring image to ${PART_DEV#/dev/}..."

    RESTORE_CMD="cat \"$IMAGE_FILE\""

    # Add decompression if needed
    if [[ -n "$COMPRESSION" ]]; then
        case $COMPRESSION in
            gzip)
                RESTORE_CMD+=" | gunzip"
                ;;
            xz)
                RESTORE_CMD+=" | unxz"
                ;;
            zstd)
                RESTORE_CMD+=" | unzstd"
                ;;
        esac
    fi

    # Add decryption if needed
    if [[ -n "$ENCRYPTION" ]]; then
        case $ENCRYPTION in
            aes256)
                RESTORE_CMD+=" | openssl enc -aes-256-cbc -d -salt -pbkdf2"
                ;;
            chacha20)
                RESTORE_CMD+=" | openssl enc -chacha20 -d -salt -pbkdf2"
                ;;
        esac
    fi

    RESTORE_CMD+=" | dd of=$PART_DEV bs=4M status=progress"

    separator
    echo "Executing: $RESTORE_CMD"
    eval "$RESTORE_CMD"

    separator
    echo "Image successfully restored to ${PART_DEV#/dev/}"
    echo "Done."

else
    # CREATE MODE (original functionality)

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
    separator
    read -rp "Enter base filename for the image (without extension): " IMAGE_NAME
    BASE_OUTFILE="$DEFAULT_OUTDIR/$IMAGE_NAME"

    # Encryption selection
    separator
    echo "Select encryption method:"
    echo "1) none"
    echo "2) AES-256"
    echo "3) ChaCha20"
    read -rp "#? " enc_choice
    case $enc_choice in
        1) ENCRYPTION="" ;;
        2) ENCRYPTION="aes256" ;;
        3) ENCRYPTION="chacha20" ;;
        *) echo "Invalid encryption option." && exit 1 ;;
    esac

    # Compression selection
    separator
    echo "Select compression method:"
    echo "1) none"
    echo "2) gzip"
    echo "3) xz"
    echo "4) zstd"
    read -rp "#? " comp_choice
    case $comp_choice in
        1) COMPRESSION="" ;;
        2) COMPRESSION="gzip" ;;
        3) COMPRESSION="xz" ;;
        4) COMPRESSION="zstd" ;;
        *) echo "Invalid compression option." && exit 1 ;;
    esac

    # Build filename according to convention
    OUTFILE="$BASE_OUTFILE.himg"

    # Add encryption extension if selected
    if [[ -n "$ENCRYPTION" ]]; then
        OUTFILE="$OUTFILE.$ENCRYPTION"
    fi

    # Add compression extension if selected
    if [[ -n "$COMPRESSION" ]]; then
        case $COMPRESSION in
            gzip) OUTFILE="$OUTFILE.gz" ;;
            xz) OUTFILE="$OUTFILE.xz" ;;
            zstd) OUTFILE="$OUTFILE.zst" ;;
        esac
    fi

    # Split option
    separator
    echo "Do you want to split the image after creation?"
    select opt in "Yes" "No"; do
        case $opt in
            Yes ) SPLIT="yes"; break ;;
            No ) break ;;
        esac
    done

    # Verify option
    separator
    echo "Do you want to verify the image after creation?"
    select opt in "Yes" "No"; do
        case $opt in
            Yes ) VERIFY="yes"; break ;;
            No ) break ;;
        esac
    done

    # Hash option
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
    echo "Output file: $OUTFILE"

    # Build command pipeline
    CMD="dd if=$PART_DEV bs=4M status=progress"

    # Add encryption if selected
    if [[ -n "$ENCRYPTION" ]]; then
        case $ENCRYPTION in
            aes256)
                CMD+=" | openssl enc -aes-256-cbc -salt -pbkdf2"
                ;;
            chacha20)
                CMD+=" | openssl enc -chacha20 -salt -pbkdf2"
                ;;
        esac
    fi

    # Add compression if selected
    if [[ -n "$COMPRESSION" ]]; then
        case $COMPRESSION in
            gzip)
                CMD+=" | gzip"
                ;;
            xz)
                CMD+=" | xz -6"
                ;;
            zstd)
                CMD+=" | zstd -6"
                ;;
        esac
    fi

    CMD+=" > \"$OUTFILE\""

    separator
    echo "Executing: $CMD"
    eval "$CMD"

    # Split
    if [[ "$SPLIT" == "yes" ]]; then
        separator
        echo "Splitting image into 2G chunks..."
        split -b 2000M "$OUTFILE" "$OUTFILE.part_"
    fi

    # Verify (Note: verification with encrypted/compressed images requires reverse pipeline)
    if [[ "$VERIFY" == "yes" ]]; then
        separator
        echo "Verifying image..."

        # Build reverse pipeline for verification
        VERIFY_CMD="cat \"$OUTFILE\""

        # Reverse compression if applied
        if [[ -n "$COMPRESSION" ]]; then
            case $COMPRESSION in
                gzip)
                    VERIFY_CMD+=" | gunzip"
                    ;;
                xz)
                    VERIFY_CMD+=" | unxz"
                    ;;
                zstd)
                    VERIFY_CMD+=" | unzstd"
                    ;;
            esac
        fi

        # Reverse encryption if applied
        if [[ -n "$ENCRYPTION" ]]; then
            case $ENCRYPTION in
                aes256)
                    VERIFY_CMD+=" | openssl enc -aes-256-cbc -d -salt -pbkdf2"
                    ;;
                chacha20)
                    VERIFY_CMD+=" | openssl enc -chacha20 -d -salt -pbkdf2"
                    ;;
            esac
        fi

        echo "Verification command: cmp \"$PART_DEV\" <($VERIFY_CMD)"
        if eval "cmp \"$PART_DEV\" <($VERIFY_CMD)"; then
            echo "Verification completed successfully."
        else
            echo "Verification failed!"
            exit 1
        fi
    fi

    # Hash
    if [[ "$HASH" == "yes" ]]; then
        separator
        echo "Generating checksums..."
        sha256sum "$OUTFILE" > "$OUTFILE.sha256"
        md5sum "$OUTFILE" > "$OUTFILE.md5"
        echo "Checksums saved to:"
        echo "$OUTFILE.sha256"
        echo "$OUTFILE.md5"
    fi

    separator
    echo "Image created: $OUTFILE"
    echo "Done."
fi