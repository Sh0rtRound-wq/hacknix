#!/usr/bin/env python3
# smart-focus: focus the nearest window strictly in the given direction.
# Does nothing if no window exists there.
# Usage: smart-focus.sh <l|r|u|d>

import json, subprocess, sys

direction = sys.argv[1]

active  = json.loads(subprocess.check_output(["hyprctl", "activewindow", "-j"]))
clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"]))

ax, ay   = active["at"]
aw, ah   = active["size"]
acx      = ax + aw / 2
acy      = ay + ah / 2
ws_id    = active["workspace"]["id"]
my_addr  = active["address"]

candidates = [
    w for w in clients
    if w["workspace"]["id"] == ws_id and w["address"] != my_addr
]

# Keep only windows whose center is strictly past the active window's edge
# in the requested direction.
if direction == "r":
    candidates = [w for w in candidates if w["at"][0] + w["size"][0] / 2 > ax + aw]
elif direction == "l":
    candidates = [w for w in candidates if w["at"][0] + w["size"][0] / 2 < ax]
elif direction == "d":
    candidates = [w for w in candidates if w["at"][1] + w["size"][1] / 2 > ay + ah]
elif direction == "u":
    candidates = [w for w in candidates if w["at"][1] + w["size"][1] / 2 < ay]

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
