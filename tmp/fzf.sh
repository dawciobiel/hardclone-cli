#!/bin/bash

device=$(lsblk -dpno NAME,SIZE,MODEL | grep -v "loop" | fzf --layout=reverse-list --height=40% --layout=reverse --border --prompt="Wybierz napęd: ")



if [[ -n "$device" ]]; then
    echo "Wybrano: $device"
else
    echo "Nic nie wybrano."
fi

