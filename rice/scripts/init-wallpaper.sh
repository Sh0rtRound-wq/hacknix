#!/usr/bin/env bash

SWWW=awww
MATUGEN=matugen

# Start awww daemon if not running
if ! pgrep -x awww-daemon > /dev/null; then
    $SWWW-daemon --no-cache &

    # Wait until the daemon is ready
    while ! $SWWW query > /dev/null 2>&1; do
        sleep 0.1
    done
fi

WALLPAPER_FILE="$HOME/.config/hypr/wallpaper"

# If no wallpaper has been picked yet, fall back to the first image in WALLPAPER_DIR
if [ ! -f "$WALLPAPER_FILE" ] || [ ! -f "$(cat "$WALLPAPER_FILE" 2>/dev/null)" ]; then
    if [ -n "$WALLPAPER_DIR" ]; then
        FIRST=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort | head -n1)
        if [ -n "$FIRST" ]; then
            echo "$FIRST" > "$WALLPAPER_FILE"
        fi
    fi
fi

WALLPAPER="$(cat "$WALLPAPER_FILE")"

# Set wallpaper
$SWWW img --transition-type none "$WALLPAPER"

# Generate color theme from wallpaper
$MATUGEN image --source-color-index 0 "$WALLPAPER"
