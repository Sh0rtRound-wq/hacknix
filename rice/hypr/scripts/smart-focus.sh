#!/usr/bin/env python3
# smart-focus: focus the nearest window strictly in the given direction.
# Falls back to searching across monitors if no window found on current workspace.
# Usage: smart-focus.sh <l|r|u|d>

import json, subprocess, sys

direction = sys.argv[1]

focused_raw = subprocess.check_output(["niri", "msg", "-j", "focused-window"], stderr=subprocess.DEVNULL)
windows_raw = subprocess.check_output(["niri", "msg", "-j", "windows"], stderr=subprocess.DEVNULL)
workspaces_raw = subprocess.check_output(["niri", "msg", "-j", "workspaces"], stderr=subprocess.DEVNULL)

active   = json.loads(focused_raw)
clients  = json.loads(windows_raw)
wspaces  = json.loads(workspaces_raw)

if not active or not active.get("geometry"):
    sys.exit(0)

geo     = active["geometry"]
ax, ay  = geo["x"], geo["y"]
aw, ah  = geo["width"], geo["height"]
acx     = ax + aw / 2
acy     = ay + ah / 2
ws_id   = active["workspace_id"]
my_id   = active["id"]

def filter_direction(windows):
    if direction == "r":
        return [w for w in windows if w["geometry"]["x"] + w["geometry"]["width"] / 2 > ax + aw]
    elif direction == "l":
        return [w for w in windows if w["geometry"]["x"] + w["geometry"]["width"] / 2 < ax]
    elif direction == "d":
        return [w for w in windows if w["geometry"]["y"] + w["geometry"]["height"] / 2 > ay + ah]
    elif direction == "u":
        return [w for w in windows if w["geometry"]["y"] + w["geometry"]["height"] / 2 < ay]
    return []

def has_geometry(w):
    return w.get("geometry") is not None

# First: same-workspace candidates
candidates = filter_direction([
    w for w in clients
    if w.get("workspace_id") == ws_id and w["id"] != my_id and has_geometry(w)
])

# Fallback: windows on other outputs' focused workspaces
if not candidates:
    focused_ws_ids = {ws["id"] for ws in wspaces if ws.get("is_focused") and ws["id"] != ws_id}
    candidates = filter_direction([
        w for w in clients
        if w.get("workspace_id") in focused_ws_ids and w["id"] != my_id and has_geometry(w)
    ])

if not candidates:
    sys.exit(0)

def score(w):
    wcx = w["geometry"]["x"] + w["geometry"]["width"] / 2
    wcy = w["geometry"]["y"] + w["geometry"]["height"] / 2
    if direction in ("r", "l"):
        return (abs(wcy - acy), abs(wcx - acx))
    else:
        return (abs(wcx - acx), abs(wcy - acy))

best = min(candidates, key=score)
subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(best["id"])])
