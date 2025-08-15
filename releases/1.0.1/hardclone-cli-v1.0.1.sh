#!/bin/bash

#######################################################################
# Hardclone CLI - Partition Backup Creator with Dialog Interface
#######################################################################
#
# A comprehensive script for creating partition backups with encryption,
# compression, and file splitting capabilities using a user-friendly
# dialog interface.
#
# Author: Dawid Bielecki "dawciobiel"
# Project: https://github.com/hardclone-cli
# Created: August 14, 2025
# Version: 1.0.1
# License: GPL-3.0
#
# Description:
#   This script provides an interactive interface for creating partition
#   backups with various options including encryption (AES-256-CBC),
#   gzip compression, and file splitting. It's designed to work with
#   System Rescue Linux but should be compatible with most Linux
#   distributions.
#
# Requirements:
#   - dialog (for user interface)
#   - root privileges
#   - dd, gzip, openssl, split (standard Linux utilities)
#
# Usage:
#   sudo ./hardclone-cli
#
# or
#   sudo ./hardclone-cli-v1.0.1.sh
#
# Features:
#   - Interactive device and partition selection
#   - AES-256-CBC encryption support
#   - Gzip compression
#   - File splitting into custom-sized chunks
#   - Space availability checking
#   - Progress monitoring
#
#######################################################################

# Check if dialog is available
if ! command -v dialog &> /dev/null; then
    echo "ERROR: 'dialog' program is not installed!"
    echo "Install it with: apt-get install dialog (Debian/Ubuntu) or pacman -S dialog (Arch)"
    exit 1
fi

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   dialog --msgbox "This script must be run as root!" 8 50
   exit 1
fi

# Cleanup function for exit
cleanup() {
    clear
    exit 0
}

trap cleanup EXIT

# Global variables
VERSION="1.0.1"
DEVICE=""
PARTITION=""
OUTPUT_PATH=""
ENCRYPT="false"
ENCRYPT_PASSWORD=""
COMPRESS="false"
SPLIT="false"
SPLIT_SIZE=""

# Function to format size in human readable format
format_size() {
    local bytes=$1
    local size=""

    if [[ $bytes -ge 1099511627776 ]]; then  # >= 1TB
        size=$(echo "scale=1; $bytes / 1099511627776" | bc -l 2>/dev/null || echo "$((bytes / 1099511627776))")
        echo "${size}TB"
    elif [[ $bytes -ge 1073741824 ]]; then  # >= 1GB
        size=$(echo "scale=1; $bytes / 1073741824" | bc -l 2>/dev/null || echo "$((bytes / 1073741824))")
        echo "${size}GB"
    elif [[ $bytes -ge 1048576 ]]; then  # >= 1MB
        size=$(echo "scale=0; $bytes / 1048576" | bc -l 2>/dev/null || echo "$((bytes / 1048576))")
        echo "${size}MB"
    else
        size=$(echo "scale=0; $bytes / 1024" | bc -l 2>/dev/null || echo "$((bytes / 1024))")
        echo "${size}KB"
    fi
}

# Function to select storage device
select_device() {
    local devices_list=""
    local device_info=""

    # Get list of block devices (try multiple methods for compatibility)
    # Method 1: Use lsblk with disk type filter
    while IFS= read -r line; do
        device=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $4}')
        type=$(echo "$line" | awk '{print $6}')

        # Filter only disks (not partitions) - check multiple possible values
        if [[ "$type" == "disk" ]] || [[ -z "$type" && ! "$device" =~ [0-9]$ ]]; then
            # Get additional device information
            model=$(lsblk -d -o MODEL "/dev/$device" 2>/dev/null | tail -n 1 | xargs)
            if [[ -z "$model" ]]; then
                model="Unknown Model"
            fi
            # Get precise size in bytes for better formatting
            size_bytes=$(blockdev --getsize64 "/dev/$device" 2>/dev/null)
            if [[ -n "$size_bytes" ]] && [[ $size_bytes -gt 0 ]]; then
                formatted_size=$(format_size $size_bytes)
                devices_list="$devices_list $device \"$formatted_size | $model\" "
            else
                devices_list="$devices_list $device \"$size | $model\" "
            fi
        fi
    done < <(lsblk -d -o NAME,SIZE,TYPE 2>/dev/null | tail -n +2)

    # Method 2: If no devices found, try alternative approach
    if [[ -z "$devices_list" ]]; then
        # Get devices from /proc/partitions and filter main devices
        while IFS= read -r major minor blocks name; do
            # Skip header and empty lines
            if [[ "$major" =~ ^[0-9]+$ ]] && [[ ! "$name" =~ [0-9]$ ]] && [[ -b "/dev/$name" ]]; then
                size_bytes=$((blocks * 1024))
                if [[ $size_bytes -gt 104857600 ]]; then  # Only devices larger than 100MB
                    model=$(lsblk -d -o MODEL "/dev/$name" 2>/dev/null | tail -n 1 | xargs)
                    if [[ -z "$model" ]]; then
                        model="Unknown Model"
                    fi
                    formatted_size=$(format_size $size_bytes)
                    devices_list="$devices_list $name \"$formatted_size | $model\" "
                fi
            fi
        done < /proc/partitions
    fi

    # Method 3: If still no devices, try listing /dev/sd* and /dev/nvme*
    if [[ -z "$devices_list" ]]; then
        for device in /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/vd[a-z] /dev/hd[a-z]; do
            if [[ -b "$device" ]]; then
                name=$(basename "$device")
                size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null)
                if [[ -n "$size_bytes" ]] && [[ $size_bytes -gt 0 ]]; then
                    model=$(lsblk -d -o MODEL "$device" 2>/dev/null | tail -n 1 | xargs)
                    if [[ -z "$model" ]]; then
                        model="Unknown Model"
                    fi
                    formatted_size=$(format_size $size_bytes)
                    devices_list="$devices_list $name \"$formatted_size | $model\" "
                fi
            fi
        done
    fi

    if [[ -z "$devices_list" ]]; then
        dialog --msgbox "No block devices found!\n\nDebug info:\nlsblk output: $(lsblk -d 2>&1)\n/proc/partitions exists: $([[ -r /proc/partitions ]] && echo "yes" || echo "no")" 12 70
        exit 1
    fi

    # Display device selection menu
    eval "dialog --menu \"Select storage device:\" 18 80 10 $devices_list" 2>temp_device

    if [[ $? -ne 0 ]]; then
        exit 0
    fi

    DEVICE=$(cat temp_device)
    rm -f temp_device

    # Add /dev/ prefix if missing
    if [[ ! "$DEVICE" =~ ^/dev/ ]]; then
        DEVICE="/dev/$DEVICE"
    fi
}

# Function to select partition
select_partition() {
    local partitions_list=""

    # Get list of partitions for selected device
    while IFS= read -r line; do
        # Clean partition name from lsblk tree characters
        part=$(echo "$line" | awk '{print $1}' | sed 's/[├└│─ ]//g')
        size=$(echo "$line" | awk '{print $4}')
        fstype=$(echo "$line" | awk '{print $2}')
        mountpoint=$(echo "$line" | awk '{print $7}')

        # Skip main device entry and process only partitions
        if [[ "$part" != "${DEVICE##*/}" ]] && [[ "$part" =~ [0-9]$ ]] && [[ -n "$part" ]]; then
            if [[ -z "$fstype" ]]; then
                fstype="unknown"
            fi
            if [[ -z "$mountpoint" ]]; then
                mountpoint="not mounted"
            fi

            # Get precise size in bytes for better formatting
            part_device="/dev/$part"
            if [[ -b "$part_device" ]]; then
                size_bytes=$(blockdev --getsize64 "$part_device" 2>/dev/null)
                if [[ -n "$size_bytes" ]] && [[ $size_bytes -gt 0 ]]; then
                    formatted_size=$(format_size $size_bytes)
                    partitions_list="$partitions_list $part \"$formatted_size | $fstype | $mountpoint\" "
                else
                    partitions_list="$partitions_list $part \"$size | $fstype | $mountpoint\" "
                fi
            else
                partitions_list="$partitions_list $part \"$size | $fstype | $mountpoint\" "
            fi
        fi
    done < <(lsblk "$DEVICE" -o NAME,FSTYPE,SIZE,MOUNTPOINT | tail -n +2)

    # If no partitions found with lsblk, try alternative method using plain list format
    if [[ -z "$partitions_list" ]]; then
        # Use lsblk without tree formatting
        while IFS= read -r line; do
            part=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $4}')
            fstype=$(echo "$line" | awk '{print $2}')
            mountpoint=$(echo "$line" | awk '{print $7}')

            # Skip main device and process only partitions
            if [[ "$part" != "${DEVICE##*/}" ]] && [[ "$part" =~ [0-9]$ ]] && [[ -n "$part" ]]; then
                if [[ -z "$fstype" ]]; then
                    fstype="unknown"
                fi
                if [[ -z "$mountpoint" ]]; then
                    mountpoint="not mounted"
                fi

                part_device="/dev/$part"
                if [[ -b "$part_device" ]]; then
                    size_bytes=$(blockdev --getsize64 "$part_device" 2>/dev/null)
                    if [[ -n "$size_bytes" ]] && [[ $size_bytes -gt 0 ]]; then
                        formatted_size=$(format_size $size_bytes)
                        partitions_list="$partitions_list $part \"$formatted_size | $fstype | $mountpoint\" "
                    else
                        partitions_list="$partitions_list $part \"$size | $fstype | $mountpoint\" "
                    fi
                fi
            fi
        done < <(lsblk "$DEVICE" --list -o NAME,FSTYPE,SIZE,MOUNTPOINT | tail -n +2)
    fi

    # If still no partitions found, try direct device file detection
    if [[ -z "$partitions_list" ]]; then
        # Try to find partitions by checking device files directly
        device_base="${DEVICE##*/}"
        for part_file in /dev/${device_base}[0-9]* /dev/${device_base}p[0-9]*; do
            if [[ -b "$part_file" ]]; then
                part_name=$(basename "$part_file")
                size_bytes=$(blockdev --getsize64 "$part_file" 2>/dev/null)
                if [[ -n "$size_bytes" ]] && [[ $size_bytes -gt 0 ]]; then
                    formatted_size=$(format_size $size_bytes)
                    fstype=$(blkid -o value -s TYPE "$part_file" 2>/dev/null || echo "unknown")
                    mountpoint=$(findmnt -n -o TARGET "$part_file" 2>/dev/null || echo "not mounted")
                    partitions_list="$partitions_list $part_name \"$formatted_size | $fstype | $mountpoint\" "
                fi
            fi
        done
    fi

    if [[ -z "$partitions_list" ]]; then
        dialog --msgbox "No partitions found on device $DEVICE!\n\nDebug info:\nDevice: $DEVICE\nAvailable files: $(ls -la /dev/${DEVICE##*/}* 2>/dev/null | head -5)" 15 80
        exit 1
    fi

    # Display partition selection menu
    eval "dialog --menu \"Select partition on $DEVICE:\" 18 90 10 $partitions_list" 2>temp_partition

    if [[ $? -ne 0 ]]; then
        exit 0
    fi

    PARTITION=$(cat temp_partition)
    rm -f temp_partition

    # Construct full device path - ensure clean partition name
    PARTITION=$(echo "$PARTITION" | sed 's/[├└│─ ]//g')  # Clean any remaining tree characters
    if [[ ! "$PARTITION" =~ ^/dev/ ]]; then
        PARTITION="/dev/$PARTITION"
    fi

    # Verify the partition exists
    if [[ ! -b "$PARTITION" ]]; then
        dialog --msgbox "Error: Partition $PARTITION does not exist or is not a block device!\n\nDebug info:\nRequested: $PARTITION\nAvailable partitions:\n$(ls -la /dev/${DEVICE##*/}* 2>/dev/null)" 15 80
        exit 1
    fi
}

# Function to select output path
select_output_path() {
    dialog --inputbox "Enter destination path for partition image:" 10 70 "/tmp/backup_$(basename "$PARTITION").img" 2>temp_path

    if [[ $? -ne 0 ]]; then
        exit 0
    fi

    OUTPUT_PATH=$(cat temp_path)
    rm -f temp_path

    # Check if destination directory exists
    output_dir=$(dirname "$OUTPUT_PATH")
    if [[ ! -d "$output_dir" ]]; then
        dialog --yesno "Directory $output_dir does not exist. Create it?" 8 60
        if [[ $? -eq 0 ]]; then
            mkdir -p "$output_dir"
            if [[ $? -ne 0 ]]; then
                dialog --msgbox "Cannot create directory $output_dir!" 8 50
                exit 1
            fi
        else
            exit 0
        fi
    fi

    # Check available space
    available_space=$(df "$output_dir" | tail -n 1 | awk '{print $4}')
    partition_size=$(blockdev --getsize64 "$PARTITION")
    partition_size_kb=$((partition_size / 1024))

    if [[ $partition_size_kb -gt $available_space ]]; then
        dialog --msgbox "Warning: Partition size ($((partition_size_kb / 1024)) MB) may exceed available space ($((available_space / 1024)) MB)!" 10 70
    fi
}

# Function to select encryption option
select_encryption() {
    dialog --yesno "Encrypt the image file?" 8 40
    if [[ $? -eq 0 ]]; then
        ENCRYPT="true"

        # Get encryption password
        dialog --passwordbox "Enter encryption password:" 10 50 2>temp_password
        if [[ $? -ne 0 ]]; then
            exit 0
        fi

        ENCRYPT_PASSWORD=$(cat temp_password)
        rm -f temp_password

        if [[ -z "$ENCRYPT_PASSWORD" ]]; then
            dialog --msgbox "Empty password not allowed!" 8 40
            exit 1
        fi

        # Confirm password
        dialog --passwordbox "Confirm encryption password:" 10 50 2>temp_password2
        if [[ $? -ne 0 ]]; then
            exit 0
        fi

        ENCRYPT_PASSWORD2=$(cat temp_password2)
        rm -f temp_password2

        if [[ "$ENCRYPT_PASSWORD" != "$ENCRYPT_PASSWORD2" ]]; then
            dialog --msgbox "Passwords do not match!" 8 40
            exit 1
        fi
    fi
}

# Function to select compression option
select_compression() {
    dialog --yesno "Compress the image file?" 8 40
    if [[ $? -eq 0 ]]; then
        COMPRESS="true"
    fi
}

# Function to select file splitting option
select_split() {
    dialog --yesno "Split file into smaller parts?" 8 50
    if [[ $? -eq 0 ]]; then
        SPLIT="true"

        dialog --inputbox "Enter maximum size for each part (e.g. 1G, 500M, 2048K):" 10 60 "1G" 2>temp_size

        if [[ $? -ne 0 ]]; then
            exit 0
        fi

        SPLIT_SIZE=$(cat temp_size)
        rm -f temp_size

        # Validate size format
        if [[ ! "$SPLIT_SIZE" =~ ^[0-9]+[KMGT]?$ ]]; then
            dialog --msgbox "Invalid size format! Use e.g.: 1G, 500M, 2048K" 8 60
            exit 1
        fi
    fi
}

# Function to display operation summary
show_summary() {
    local summary="OPERATION SUMMARY:\n\n"
    summary+="Device: $DEVICE\n"
    summary+="Partition: $PARTITION\n"
    summary+="Output file: $OUTPUT_PATH\n"
    summary+="Encryption: $([ "$ENCRYPT" = "true" ] && echo "YES" || echo "NO")\n"
    summary+="Compression: $([ "$COMPRESS" = "true" ] && echo "YES" || echo "NO")\n"
    summary+="File splitting: $([ "$SPLIT" = "true" ] && echo "YES ($SPLIT_SIZE)" || echo "NO")\n\n"
    summary+="Continue with operation?"

    dialog --yesno "$summary" 15 70
    return $?
}

# Function to create the partition image
create_image() {
    local cmd="dd if=$PARTITION"
    local output_file="$OUTPUT_PATH"

    # Prepare command pipeline based on selected options
    if [[ "$COMPRESS" = "true" && "$ENCRYPT" = "true" ]]; then
        if [[ "$SPLIT" = "true" ]]; then
            cmd+=" bs=1M | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:\"$ENCRYPT_PASSWORD\" | split -b $SPLIT_SIZE - \"${output_file}.\""
        else
            cmd+=" bs=1M | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:\"$ENCRYPT_PASSWORD\" -out \"${output_file}.gz.enc\""
        fi
    elif [[ "$COMPRESS" = "true" ]]; then
        if [[ "$SPLIT" = "true" ]]; then
            cmd+=" bs=1M | gzip | split -b $SPLIT_SIZE - \"${output_file}.gz.\""
        else
            cmd+=" bs=1M | gzip > \"${output_file}.gz\""
        fi
    elif [[ "$ENCRYPT" = "true" ]]; then
        if [[ "$SPLIT" = "true" ]]; then
            cmd+=" bs=1M | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:\"$ENCRYPT_PASSWORD\" | split -b $SPLIT_SIZE - \"${output_file}.enc.\""
        else
            cmd+=" bs=1M | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:\"$ENCRYPT_PASSWORD\" -out \"${output_file}.enc\""
        fi
    elif [[ "$SPLIT" = "true" ]]; then
        cmd+=" bs=1M | split -b $SPLIT_SIZE - \"${output_file}.\""
    else
        cmd+=" of=\"$output_file\" bs=1M"
    fi

    # Display operation start information
    dialog --infobox "Starting partition image creation...\n\nPartition: $PARTITION\nThis may take a long time depending on partition size." 10 60
    sleep 2

    # Clear screen and show progress info
    clear
    echo "========================================"
    echo "Creating partition image..."
    echo "========================================"
    echo "Source: $PARTITION"
    echo "Output: $OUTPUT_PATH"
    echo "Options: $([ "$COMPRESS" = "true" ] && echo -n "Compression ")$([ "$ENCRYPT" = "true" ] && echo -n "Encryption ")$([ "$SPLIT" = "true" ] && echo -n "Split($SPLIT_SIZE) ")"
    echo "========================================"
    echo ""
    echo "Progress will be shown below:"
    echo "Press Ctrl+C to cancel"
    echo ""

    # Execute command and show progress
    if eval "$cmd"; then
        echo ""
        echo "========================================"
        echo "SUCCESS: Partition image created!"
        echo "========================================"

        local result_msg="Partition image created successfully!\n\n"
        result_msg+="Location: $OUTPUT_PATH"

        if [[ "$SPLIT" = "true" ]]; then
            result_msg+="\n\nFile was split into parts of size $SPLIT_SIZE"
            echo "File was split into parts of size $SPLIT_SIZE"
        fi

        if [[ "$COMPRESS" = "true" ]]; then
            result_msg+="\nFile was compressed"
            echo "File was compressed (gzip)"
        fi

        if [[ "$ENCRYPT" = "true" ]]; then
            result_msg+="\nFile was encrypted"
            echo "File was encrypted (AES-256-CBC)"
        fi

        echo "========================================"
        echo "Press any key to continue..."
        read -n 1

        dialog --msgbox "$result_msg" 15 70
    else
        echo ""
        echo "========================================"
        echo "ERROR: Failed to create partition image!"
        echo "========================================"
        echo "Press any key to continue..."
        read -n 1

        dialog --msgbox "An error occurred while creating the partition image!" 8 50
        exit 1
    fi

    # Clear password from memory
    ENCRYPT_PASSWORD=""
}

# Main function
main() {
    dialog --msgbox "Welcome to the Hardclone CLI v$VERSION - Partition Backup Creator!\n\nThis script will help you create a backup copy of a selected partition." 10 60

    select_device
    select_partition
    select_output_path
    select_encryption
    select_compression
    select_split

    if show_summary; then
        create_image
    else
        dialog --msgbox "Operation cancelled by user." 8 40
    fi
}

# Execute main function
main

# Clear screen on exit
clear
