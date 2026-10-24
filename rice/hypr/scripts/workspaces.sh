#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# CACHING & MIGRATION
# -----------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/caching.sh"
qs_ensure_cache "workspaces"

# ============================================================================
# 1. ZOMBIE PREVENTION
# ============================================================================
for pid in $(pgrep -f "workspaces.sh"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

cleanup() {
    pkill -P $$ 2>/dev/null
}
trap cleanup EXIT SIGTERM SIGINT

# --- Special Cleanup for Network/Bluetooth ---
BT_PID_FILE="$QS_RUN_WORKSPACES/bt_scan_pid"
if [ -f "$BT_PID_FILE" ]; then
    kill $(cat "$BT_PID_FILE") 2>/dev/null
    rm -f "$BT_PID_FILE"
fi
(timeout 2 bluetoothctl scan off > /dev/null 2>&1) &

# Configuration: parse from settings.json, fallback to 8
SETTINGS_FILE="$HOME/.config/hypr/settings.json"
SEQ_END=$(jq -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null)
if ! [[ "$SEQ_END" =~ ^[0-9]+$ ]]; then
    SEQ_END=8
fi

print_workspaces() {
    WORKSPACES=$(timeout 2 niri msg -j workspaces 2>/dev/null)
    WINDOWS=$(timeout 2 niri msg -j windows 2>/dev/null)

    if [ -z "$WORKSPACES" ]; then return; fi

    jq -n \
        --argjson ws "$WORKSPACES" \
        --argjson wins "${WINDOWS:-[]}" \
        --arg end "$SEQ_END" -c '
        # Find the focused output
        ([$ws[] | select(.is_focused)] | .[0] | .output // "") as $focused_output |

        # Workspaces on focused output (fall back to all if nothing focused)
        (if $focused_output != "" then [$ws[] | select(.output == $focused_output)]
         else $ws end) as $out_ws |

        # Focused workspace idx on focused output
        ([$out_ws[] | select(.is_focused)] | .[0] | .idx // 1) as $active_idx |

        # Map workspace id -> window count
        ($wins | group_by(.workspace_id) |
            map({(.[0].workspace_id | tostring): length}) | add // {}) as $win_count |

        # Map workspace idx -> workspace id (for focused output)
        ($out_ws | map({((.idx // 0) | tostring): .id}) | add // {}) as $ws_id_map |

        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            ($ws_id_map[$i|tostring]) as $ws_id |
            (if $ws_id then ($win_count[$ws_id|tostring] // 0) else 0 end) as $cnt |
            (if $i == $active_idx then "active"
             elif $cnt > 0 then "occupied"
             else "empty" end) as $state |
            {id: $i, state: $state, tooltip: ("Workspace " + ($i|tostring))}
        )
    ' > "$QS_RUN_WORKSPACES/workspaces.tmp" 2>/dev/null

    [ -f "$QS_RUN_WORKSPACES/workspaces.tmp" ] && \
        mv "$QS_RUN_WORKSPACES/workspaces.tmp" "$QS_RUN_WORKSPACES/workspaces.json"
}

# Print initial state
print_workspaces

# ============================================================================
# 2. THE EVENT LISTENER
# Listen to niri event stream — debounce workspace/window events
# ============================================================================
while true; do
    niri msg event-stream 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *WorkspacesChanged*|*WindowFocusChanged*|*WindowOpenedOrChanged*|*WindowClosed*)
                # Debounce: discard events arriving within 50ms to prevent CPU storms
                while IFS= read -t 0.05 -r _; do continue; done
                print_workspaces
                ;;
        esac
    done
    sleep 1
done
