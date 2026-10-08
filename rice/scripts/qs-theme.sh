#!/usr/bin/env bash
# qs-theme.sh — switch quickshell theme (modern | minimalist)
# Usage: qs-theme.sh <modern|minimalist>

THEME="${1:-}"
SCRIPTS_DIR="$HOME/.config/hypr/scripts"
CURRENT_FILE="$HOME/.config/hypr/.qs_theme"

if [[ -z "$THEME" ]]; then
    current=$(cat "$CURRENT_FILE" 2>/dev/null || echo "modern")
    echo "Current theme: $current"
    echo "Usage: qs-theme.sh <modern|minimalist>"
    exit 0
fi

if [[ "$THEME" != "modern" && "$THEME" != "minimalist" ]]; then
    echo "Unknown theme: $THEME. Valid: modern, minimalist"
    exit 1
fi

THEME_DIR="$SCRIPTS_DIR/quickshell-${THEME}"

if [[ ! -d "$THEME_DIR" ]]; then
    echo "Theme dir not found: $THEME_DIR"
    exit 1
fi

# Write theme + kill (systemd Restart=always relaunches with new theme)
echo "$THEME" > "$CURRENT_FILE"
pkill -f "quickshell.*Shell.qml" 2>/dev/null || true
echo "Switched to: $THEME"
