#!/usr/bin/env bash

animations=("outer" "center" "any" "wipe")
random_animation=${animations[RANDOM % ${#animations[@]}]}

echo "$1" > "$HOME/.config/hypr/wallpaper"

if [[ "$random_animation" == "wipe" ]]; then
    awww img --transition-type="wipe" --transition-angle=135 "$1" &
else
    awww img --transition-type="$random_animation" "$1" &
fi

matugen image --source-color-index 0 "$1"
bash "$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"
