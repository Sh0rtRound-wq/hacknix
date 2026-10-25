#!/usr/bin/env bash
# Auto-manage monitors when external displays connect/disconnect via niri

restart-apps() {
    pkill swaybg 2>/dev/null
    init-wallpaper &

    pkill .waybar-wrapped 2>/dev/null
    waybar &

    pkill .swayosd-server 2>/dev/null
    swayosd-server &
}

handle-monitor-state() {
    # Check for external monitors (HDMI-* or DP-*)
    external_present=$(niri msg -j outputs 2>/dev/null | jq -r '.[].name' | grep -E "^(HDMI-|DP-)" | head -1)
    enabled_count=$(niri msg -j outputs 2>/dev/null | jq 'length')

    if [ -n "$external_present" ]; then
        if [ "${enabled_count:-0}" -gt 1 ]; then
            # External connected: disable laptop screen
            bash "$HOME/.config/hypr/scripts/../../../scripts/toggle-display.sh" 2>/dev/null || true
        fi
    else
        # No external: ensure laptop screen is enabled
        SETTINGS_JSON="$HOME/.config/hypr/settings.json"
        if [ -f "$SETTINGS_JSON" ]; then
            TMP=$(mktemp)
            jq '.monitors = [(.monitors // []) | .[] | del(.off)]' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
            bash "$HOME/.config/hypr/scripts/settings_watcher.sh" --compile
        fi
    fi
}

# Startup check
sleep 1
handle-monitor-state
restart-apps

# Listen to niri event stream for output changes
niri msg event-stream 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -qE "OutputConnected|OutputDisconnected"; then
        handle-monitor-state
        restart-apps
    fi
done
