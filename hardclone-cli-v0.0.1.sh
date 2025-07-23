#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2025 Dawid Bielecki

set -e

# Check for required tools
for tool in fzf dialog pv dd lsblk /usr/sbin/blockdev gzip gpg; do
    if ! command -v "$tool" >/dev/null; then
        echo "Missing tool: $tool. Please install it." >&2
        exit 1
    fi
done

# 1. Select disk
disk=$(lsblk -dpno NAME,SIZE,MODEL | grep -v loop | fzf --prompt="Select disk: " --height=40% --layout=reverse)
[[ -z "$disk" ]] && { echo "No disk selected."; exit 1; }
disk_base=$(echo "$disk" | awk '{print $1}' | xargs basename)

# 2. Select partition
partition=$(lsblk -rno NAME,SIZE,TYPE | \
    awk -v disk="$disk_base" '$3 == "part" && $1 ~ "^"disk { print "/dev/"$1, $2 }' | \
    fzf --prompt="Select partition: " --height=40% --layout=reverse)
[[ -z "$partition" ]] && { echo "No partition selected."; exit 1; }
partition_device=$(echo "$partition" | awk '{print $1}')

# 3. Output file path (without extension)
outfile=$(dialog --inputbox "Enter output image path (without extension):" 10 60 "~/image" 3>&1 1>&2 2>&3)
[[ -z "$outfile" ]] && { echo "No output path given."; exit 1; }
outfile=$(eval echo "$outfile")

# 4. Select compression
compression=$(dialog --menu "Choose compression:" 10 50 4 \
    1 "None" \
    2 "gzip" \
    3 "xz" \
    4 "zstd" 3>&1 1>&2 2>&3)
[[ -z "$compression" ]] && { echo "No compression selected."; exit 1; }

# 5. Select encryption
encryption=$(dialog --menu "Choose encryption:" 10 50 3 \
    1 "None" \
    2 "gpg (symmetric)" 3>&1 1>&2 2>&3)
[[ -z "$encryption" ]] && { echo "No encryption selected."; exit 1; }

# 6. Get partition size in bytes
size=$(/usr/sbin/blockdev --getsize64 "$partition_device")

# 7. Create image with progress bar and optional compression/encryption
(
    dd if="$partition_device" bs=4M status=none | pv -n -s "$size" | {
        case $compression in
            1) cat ;; # no compression
            2) gzip ;;
            3) xz ;;
            4) zstd ;;
        esac
    } | {
        case $encryption in
            1) cat > "${outfile}.img" ;; # no encryption
            2)
                gpg --symmetric --cipher-algo AES256 --batch --passphrase-fd 0 > "${outfile}.img.gpg"
                exit 0
                ;;
        esac
    }
) 2>&1 | dialog --gauge "Creating partition image..." 10 60 0

# 8. Final message
if [[ "$encryption" -eq 2 ]]; then
    dialog --msgbox "Encryption completed.\nFile saved as:\n${outfile}.img.gpg" 8 60
else
    dialog --msgbox "Image created successfully.\nFile saved as:\n${outfile}.img" 8 60
fi

clear
