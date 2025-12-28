#!/usr/bin/env bash

# Options
declare -A OPTIONS
OPTIONS[shutdown]="⏻ Shutdown"
OPTIONS[reboot]="󰑓 Reboot"
OPTIONS[logout]="󰍃 Logout"

# Show menu using wofi (top right, compact, no search)
selected=$(printf "%s\n" "${OPTIONS[@]}" | wofi --dmenu --prompt "" --insensitive --location 3 --width 110 --height 80 --cache-file=/dev/null --hide-search)

# Execute action
case "$selected" in
    *"Shutdown"*)
        systemctl poweroff
        ;;
    *"Reboot"*)
        systemctl reboot
        ;;
    *"Logout"*)
        hyprctl dispatch exit
        ;;
esac
