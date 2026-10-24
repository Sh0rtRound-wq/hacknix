#!/usr/bin/env bash
# Toggle laptop display (eDP-1) on/off via niri
# In niri, monitor enable/disable requires config change + reload.
# This script adds/removes eDP-1 from the settings.json monitors list.

SETTINGS_JSON="$HOME/.config/hypr/settings.json"
OUTPUT="eDP-1"

if [ ! -f "$SETTINGS_JSON" ]; then
    echo "settings.json not found" >&2
    exit 1
fi

# Check if output is currently listed as disabled in settings
is_disabled=$(jq --arg o "$OUTPUT" '
    (.monitors // []) | map(select(.name == $o and .off == true)) | length > 0
' "$SETTINGS_JSON")

if [ "$is_disabled" = "true" ]; then
    # Re-enable: remove the off flag
    TMP=$(mktemp)
    jq --arg o "$OUTPUT" '
        .monitors = [(.monitors // []) | .[] | if .name == $o then del(.off) else . end]
    ' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
    echo "Display $OUTPUT enabled"
else
    # Disable: add off flag
    TMP=$(mktemp)
    jq --arg o "$OUTPUT" '
        if [(.monitors // []) | .[] | select(.name == $o)] | length > 0
        then .monitors = [(.monitors // []) | .[] | if .name == $o then . + {"off": true} else . end]
        else .
        end
    ' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
    echo "Display $OUTPUT disabled"
fi

# Trigger niri config regeneration and reload
bash "$HOME/.config/hypr/scripts/settings_watcher.sh" --compile
