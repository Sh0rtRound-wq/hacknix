#!/usr/bin/env python3
# smart-focus: focus the nearest window strictly in the given direction.
# Falls back to searching across monitors if no window found on current workspace.
# Usage: smart-focus.sh <l|r|u|d>

import json, subprocess, sys

direction = sys.argv[1]

active  = json.loads(subprocess.check_output(["hyprctl", "activewindow", "-j"]))
clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"]))
monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]))

ax, ay   = active["at"]
aw, ah   = active["size"]
acx      = ax + aw / 2
acy      = ay + ah / 2
ws_id    = active["workspace"]["id"]
my_addr  = active["address"]

def filter_direction(windows):
    if direction == "r":
        return [w for w in windows if w["at"][0] + w["size"][0] / 2 > ax + aw]
    elif direction == "l":
        return [w for w in windows if w["at"][0] + w["size"][0] / 2 < ax]
    elif direction == "d":
        return [w for w in windows if w["at"][1] + w["size"][1] / 2 > ay + ah]
    elif direction == "u":
        return [w for w in windows if w["at"][1] + w["size"][1] / 2 < ay]
    return []

# First: same-workspace candidates
candidates = filter_direction([
    w for w in clients
    if w["workspace"]["id"] == ws_id and w["address"] != my_addr
])

# Fallback: windows on other monitors' active workspaces
if not candidates:
    active_ws_ids = {m["activeWorkspace"]["id"] for m in monitors}
    active_ws_ids.discard(ws_id)
    cross_monitor = filter_direction([
        w for w in clients
        if w["workspace"]["id"] in active_ws_ids and w["address"] != my_addr
    ])
    candidates = cross_monitor

if not candidates:
    sys.exit(0)

def score(w):
    wcx = w["at"][0] + w["size"][0] / 2
    wcy = w["at"][1] + w["size"][1] / 2
    if direction in ("r", "l"):
        return (abs(wcy - acy), abs(wcx - acx))   # minimize vertical gap first
    else:
        return (abs(wcx - acx), abs(wcy - acy))   # minimize horizontal gap first

best = min(candidates, key=score)
subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{best['address']}"])
