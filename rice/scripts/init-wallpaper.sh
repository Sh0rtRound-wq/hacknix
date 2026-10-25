#!/usr/bin/env bash

# Ensure HOME is set — niri spawn-at-startup may not inherit it
HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"

MATUGEN=matugen
WALLPAPER_FILE="$HOME/.config/hypr/wallpaper"

# If no wallpaper has been picked yet, fall back to the first image in WALLPAPER_DIR
if [ ! -f "$WALLPAPER_FILE" ] || [ ! -s "$WALLPAPER_FILE" ] || [ ! -f "$(cat "$WALLPAPER_FILE" 2>/dev/null)" ]; then
    # Try session var first, then derive from HOME
    WDIR="${WALLPAPER_DIR:-$HOME/hacknix/wallpapers}"
    if [ -d "$WDIR" ]; then
        FIRST=$(find "$WDIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort | head -n1)
        if [ -n "$FIRST" ]; then
            echo "$FIRST" > "$WALLPAPER_FILE"
        fi
    fi
fi

WALLPAPER="$(cat "$WALLPAPER_FILE" 2>/dev/null)"

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    echo "init-wallpaper: no valid wallpaper found, aborting" >&2
    exit 1
fi

# Set wallpaper (swaybg: no daemon needed, kill any existing instance and respawn)
pkill swaybg 2>/dev/null
swaybg -i "$WALLPAPER" -m fill &

# Generate color theme from wallpaper — always runs
$MATUGEN image --type scheme-vibrant --contrast 1.0 --source-color-index 0 "$WALLPAPER"
