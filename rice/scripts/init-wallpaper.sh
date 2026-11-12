#!/usr/bin/env bash
# init-wallpaper — start/verify the wallpaper daemon, then apply the saved wallpaper
# and regenerate the matugen colour theme.
#
# Two things changed vs. the original versions of this script:
#   1. Liveness of the daemon is probed with `awww query`, never with
#      `pgrep -x awww-daemon`. The Nix wrapper renames the daemon's comm to
#      `.awww-daemon-wr` (15-char truncation), so `pgrep -x awww-daemon` never
#      matches a running daemon — the old guard started a *second* daemon on
#      every call, which panics with "There is an awww-daemon instance already
#      running on this socket!" and can leave the session with no daemon.
#   2. The daemon is owned by the `awww-daemon.service` systemd user unit
#      (Restart=always). This script asks that unit to start it instead of
#      spawning an unsupervised child, and only falls back to a bare spawn if
#      the unit is not usable.
#
# Diagnostics are appended to ~/.cache/hypr/init-wallpaper.log so a boot-time
# failure is no longer silent.

SWWW=awww
MATUGEN=matugen

LOG_DIR="$HOME/.cache/hypr"
LOG="$LOG_DIR/init-wallpaper.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null || true; }

query_ok() { $SWWW query > /dev/null 2>&1; }

log "start (WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}, pid=$$)"

wait_for_daemon() {
    local i
    for i in $(seq 1 100); do
        query_ok && return 0
        sleep 0.1
    done
    return 1
}

if query_ok; then
    log "daemon already up (${SWWW} query ok)"
else
    log "no daemon responding; starting awww-daemon.service"
    systemctl --user start awww-daemon.service > /dev/null 2>&1 || true
    if ! wait_for_daemon; then
        log "service unavailable after 10s; spawning unsupervised fallback daemon"
        $SWWW-daemon --no-cache > /dev/null 2>&1 &
        if ! wait_for_daemon; then
            log "FATAL: no wallpaper daemon — skipping wallpaper + theme"
            exit 1
        fi
    fi
    log "daemon up after start"
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

WALLPAPER="$(cat "$WALLPAPER_FILE" 2>/dev/null)"

# Set wallpaper (retry: the daemon may still be settling right after a monitor change)
i=0
while [ $i -lt 3 ]; do
    if $SWWW img --transition-type none "$WALLPAPER" > /dev/null 2>&1; then
        log "wallpaper applied: $WALLPAPER"
        break
    fi
    i=$((i + 1))
    sleep 0.5
done
[ $i -ge 3 ] && log "WARN: 'awww img' failed 3x for '$WALLPAPER'"

# Generate color theme from wallpaper
$MATUGEN image --type scheme-vibrant --contrast 1.0 --mode dark --source-color-index 0 "$WALLPAPER" > /dev/null 2>&1 || log "WARN: matugen failed"

# Post-process: deepen accent colors + reload Hyprland borders + boost kitty colors
# Same pipeline that wall-change.sh runs — ensures deepened colors survive reboots
bash "$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"

log "done"
