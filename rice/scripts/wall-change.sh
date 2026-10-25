#!/usr/bin/env bash

echo "$1" > "$HOME/.config/hypr/wallpaper"

pkill swaybg 2>/dev/null
swaybg -i "$1" -m fill &

matugen image --type scheme-vibrant --contrast 1.0 --source-color-index 0 "$1"
bash "$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"
