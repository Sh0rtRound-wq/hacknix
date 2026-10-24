#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"

PIPE="$QS_RUN_DIR/qs_kb_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

# Listen to niri event stream for keyboard layout changes
niri msg event-stream 2>/dev/null | grep --line-buffered "KeyboardLayoutsChanged" > "$PIPE" &

read -r _ < "$PIPE"
sleep 0.05
