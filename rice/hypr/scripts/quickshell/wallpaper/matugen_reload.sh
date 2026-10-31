#!/usr/bin/env bash

# Deepen accent colors post-matugen
# Reads colors_raw.conf (fresh matugen output) → writes colors.conf (deepened, idempotent)
python3 "${HOME}/.config/hypr/scripts/deepen-colors.py"

# Apply border colors directly via hyprctl keyword — no reload needed, no race condition
# Anchor to ^ so inactive_border line doesn't pollute _active match
_active=$(grep -oP   '(?<=^\$active_border = )rgba\([^)]+\)'   "${HOME}/.config/hypr/colors.conf")
_inactive=$(grep -oP '(?<=^\$inactive_border = )rgba\([^)]+\)' "${HOME}/.config/hypr/colors.conf")
[ -n "$_active"   ] && hyprctl keyword general:col.active_border   "$_active"   2>/dev/null || true
[ -n "$_inactive" ] && hyprctl keyword general:col.inactive_border "$_inactive" 2>/dev/null || true

# Boost terminal colors to neon/vivid variants (kitty only)
bash "${HOME}/.config/hypr/scripts/quickshell/wallpaper/boost-kitty-colors.sh"

# Reload Kitty instances
killall -USR1 .kitty-wrapped 2>/dev/null || true

# Reload CAVA
if pgrep -x "cava" > /dev/null; then
    cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null
    killall -USR1 cava
fi

# Reload SwayNC CSS styling dynamically without killing the daemon
if command -v swaync-client &> /dev/null; then
    swaync-client -rs
fi

# Restarting swayosd.service is currently the ONLY way to reload its CSS.
if systemctl --user is-active --quiet swayosd.service; then
    systemctl --user restart swayosd.service &
fi

# GTK Live-Reload Hack
if command -v gsettings &> /dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    sleep 0.05
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    sleep 0.05
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi

wait
