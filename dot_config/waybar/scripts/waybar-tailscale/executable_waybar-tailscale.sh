#!/usr/bin/env bash

MENU_CMD="wofi --dmenu --normal-window --prompt 'Select Exit Node'"  # Change to rofi/fuzzel/dmenu as needed
PREFERRED_VPN="${PREFERRED_VPN:-}"

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

tailscale_running() {
    has_cmd tailscale || return 1
    tailscale status --json 2>/dev/null | jq -r '.BackendState == "Running"' | grep -q true
}

nm_active_vpns() {
    has_cmd nmcli || return 0
    nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
        | awk -F: '$2=="vpn" || $2=="wireguard" {print $1}'
}

nm_configured_vpns() {
    has_cmd nmcli || return 0
    nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | awk -F: '$2=="vpn" || $2=="wireguard" {print $1}'
}

vpn_is_active() {
    [ -n "$(nm_active_vpns)" ] && return 0
    tailscale_running && return 0
    return 1
}

connect_nm_vpn() {
    local target=""

    if [ -n "$PREFERRED_VPN" ]; then
        if nm_configured_vpns | grep -Fxq "$PREFERRED_VPN"; then
            target="$PREFERRED_VPN"
        fi
    fi

    if [ -z "$target" ]; then
        target="$(nm_configured_vpns | head -n1)"
    fi

    if [ -n "$target" ]; then
        if nmcli connection up id "$target" >/dev/null 2>&1; then
            notify-send "VPN" "Enabled: $target"
            return 0
        fi
    fi

    return 1
}

nm_vpn_is_active() {
    local name="$1"
    nm_active_vpns | grep -Fxq "$name"
}

toggle_tailscale() {
    if ! has_cmd tailscale; then
        notify-send "Tailscale" "Tailscale is not installed"
        return 1
    fi

    if tailscale_running; then
        tailscale down >/dev/null 2>&1
        notify-send "VPN" "Disabled: Tailscale"
    else
        tailscale up >/dev/null 2>&1
        notify-send "VPN" "Enabled: Tailscale"
    fi
}

toggle_nm_vpn() {
    local name="$1"
    [ -z "$name" ] && return 1

    if nm_vpn_is_active "$name"; then
        nmcli connection down id "$name" >/dev/null 2>&1
        notify-send "VPN" "Disabled: $name"
    else
        if nmcli connection up id "$name" >/dev/null 2>&1; then
            notify-send "VPN" "Enabled: $name"
        else
            notify-send "VPN" "Failed to enable: $name"
            return 1
        fi
    fi
}

open_menu() {
    local options selected name
    options="Tailscale"

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        options="${options}"$'\n'"System VPN: $name"
    done <<< "$(nm_configured_vpns)"

    selected="$(printf '%s\n' "$options" | $MENU_CMD)"
    [ -z "$selected" ] && return 0

    if [ "$selected" = "Tailscale" ]; then
        toggle_tailscale
    elif [[ "$selected" == "System VPN: "* ]]; then
        name="${selected#System VPN: }"
        toggle_nm_vpn "$name"
    fi
}

disconnect_all_vpn() {
    local active name
    active="$(nm_active_vpns)"
    if [ -n "$active" ]; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            nmcli connection down id "$name" >/dev/null 2>&1
        done <<< "$active"
    fi

    if tailscale_running; then
        tailscale down >/dev/null 2>&1
    fi

    notify-send "VPN" "Disabled"
}

toggle_status() {
    if vpn_is_active; then
        disconnect_all_vpn
    elif connect_nm_vpn; then
        :
    elif has_cmd tailscale; then
        tailscale up >/dev/null 2>&1
        notify-send "VPN" "Enabled: Tailscale"
    else
        notify-send "VPN" "No VPN profile found"
    fi

    sleep 1
}

select_exit_node() {
    if ! has_cmd tailscale; then
        notify-send "Tailscale" "Tailscale is not installed"
        return 1
    fi

    if ! tailscale_running; then
        notify-send "Tailscale" "VPN is not running"
        return 1
    fi

    # Get available exit nodes (devices that advertise as exit nodes)
    local nodes
    nodes=$(tailscale status --json | jq -r '
        .Peer[] | select(.ExitNodeOption == true) |
        .DNSName | split(".")[0]
    ')

    # Add option to disable exit node
    nodes="None (disable exit node)"$'\n'"$nodes"

    # Show menu and get selection
    local selected
    selected=$(echo "$nodes" | $MENU_CMD)

    [ -z "$selected" ] && return 0  # User cancelled

    if [[ "$selected" == "None"* ]]; then
        tailscale set --exit-node=
        notify-send "Tailscale" "Exit node disabled"
    else
        tailscale set --exit-node="$selected"
        notify-send "Tailscale" "Exit node set to: $selected"
    fi
}

case $1 in
    --status)
        active_nm="$(nm_active_vpns | paste -sd ', ' -)"
        ts_exitnode=""
        ts_peers=""

        if tailscale_running; then
            T=${2:-"green"}
            F=${3:-"red"}
            ts_peers=$(tailscale status --json | jq -r --arg T "'$T'" --arg F "'$F'" '.Peer[]? | ("<span color=" + (if .Online then $T else $F end) + ">" + (.DNSName | split(".")[0]) + "</span>")' | tr '\n' '\r')
            ts_exitnode=$(tailscale status --json | jq -r '.Peer[]? | select(.ExitNode == true).DNSName | split(".")[0]' | head -n1)
        fi

        if [ -n "$active_nm" ] || tailscale_running; then
            label_parts=()
            tooltip_parts=()

            if [ -n "$active_nm" ]; then
                label_parts+=("$active_nm")
                tooltip_parts+=("NetworkManager: $active_nm")
            fi

            if tailscale_running; then
                label_parts+=("tailscale:${ts_exitnode:-on}")
                tooltip_parts+=("Tailscale: ${ts_exitnode:-connected}")
                if [ -n "$ts_peers" ]; then
                    tooltip_parts+=("$ts_peers")
                fi
            fi

            text="$(IFS=' | '; echo "${label_parts[*]}")"
            tooltip="$(printf '%s\\r' "${tooltip_parts[@]}")"
            echo "{\"text\":\"vpn: ${text}\",\"class\":\"connected\",\"alt\":\"connected\",\"tooltip\":\"${tooltip}\"}"
        else
            echo "{\"text\":\"vpn: <span foreground=\\\"#666666\\\">off</span>\",\"class\":\"stopped\",\"alt\":\"stopped\",\"tooltip\":\"No active VPN.\"}"
        fi
    ;;
    --toggle)
        toggle_status
    ;;
    --menu)
        open_menu
    ;;
    --select-exit-node)
        select_exit_node
    ;;
esac
