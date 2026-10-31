#!/usr/bin/env bash

# Deepen colours + push them into the running compositor.
# Delegated to the border-colors unit so the logic lives in exactly one place
# and runs with absolute binary paths rather than whatever PATH exec-once
# happened to inherit. The systemd path unit on colors_raw.conf also fires
# this on its own, so this call is belt-and-braces.
systemctl --user start --no-block border-colors.service 2>/dev/null || \
  python3 "${HOME}/.config/hypr/scripts/deepen-colors.py" || true

# Boost terminal colors to neon/vivid variants (kitty only)
bash "${HOME}/.config/hypr/scripts/quickshell-minimalist/wallpaper/boost-kitty-colors.sh"

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
