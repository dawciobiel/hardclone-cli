#!/bin/bash

list=()
while read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    desc=$(echo "$line" | cut -d' ' -f2-)
    list+=("$name" "$desc")
done < <(lsblk -dpno NAME,SIZE,MODEL | grep -v "loop")

device=$(whiptail --title "Wybierz napęd" --menu "Dostępne urządzenia:" 20 60 10 "${list[@]}" 3>&1 1>&2 2>&3)

clear
if [[ -n "$device" ]]; then
    echo "Wybrano: $device"
else
    echo "Nic nie wybrano."
fi

