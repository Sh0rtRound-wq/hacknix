#!/usr/bin/env python3
"""
niri-smart-width — pair-based tiling daemon.

Behaviour per workspace:
  - Window opens solo → stays 100% (waiting for its pair)
  - Next window opens with a solo left neighbor → both snap to 50% (a "pair")
  - Next window after that → solo again (scrolls right at 100%)
  - Pattern repeats: solo, pair, solo, pair...

  i.e. odd-positioned columns = solo, even-positioned = pairs with previous

Resize strategy:
  niri's horizontal-view-movement animation is disabled in config.kdl, so
  focus-column-left/right are instant — no visible viewport pan. Both windows
  are resized immediately on open.

Socket auto-discovery handles systemd user service (no NIRI_SOCKET inherited).
"""

import subprocess
import json
import time
import sys
import os
import glob

# Auto-discover NIRI_SOCKET if not set (needed when running as a systemd user service)
if not os.environ.get("NIRI_SOCKET"):
    socks = glob.glob("/run/user/1000/niri.wayland-*.sock")
    if socks:
        os.environ["NIRI_SOCKET"] = socks[0]
    else:
        try:
            import pwd
            uid = pwd.getpwnam("liam").pw_uid
            socks = glob.glob(f"/run/user/{uid}/niri.wayland-*.sock")
            if socks:
                os.environ["NIRI_SOCKET"] = socks[0]
        except Exception:
            pass

# Track which window IDs are part of a pair (both windows in a pair get added)
paired_ids: set[int] = set()
# Track seen IDs to filter WindowOpenedOrChanged spam
seen_ids: set[int] = set()


def niri_json(cmd: list[str]) -> object:
    try:
        r = subprocess.run(
            ["niri", "msg", "-j"] + cmd,
            capture_output=True, text=True, timeout=2
        )
        return json.loads(r.stdout)
    except Exception:
        return None


def niri_action(*args: str) -> None:
    subprocess.run(
        ["niri", "msg", "action"] + list(args),
        capture_output=True, timeout=2
    )


def handle_new_window(win_id: int) -> None:
    # Poll until the new window is focused AND has a layout position.
    # Niri places the window before focusing it — if we act before focus
    # lands on win_id, focus-column-left fires from the wrong column.
    # Max 20 × 5ms = 100ms fallback.
    target = None
    pos = None
    windows = None
    for _ in range(20):
        windows = niri_json(["windows"])
        if windows:
            target = next((w for w in windows if w.get("id") == win_id), None)
            if target:
                pos = target.get("layout", {}).get("pos_in_scrolling_layout")
                if pos and target.get("is_focused", False):
                    break
        time.sleep(0.005)

    if not target or not pos:
        return

    # Skip floating windows
    if target.get("is_floating", False):
        return

    ws_id = target.get("workspace_id")
    if ws_id is None:
        return

    new_col = round(pos[0])

    # All non-floating windows on this workspace
    ws_windows = [
        w for w in (windows or [])
        if w.get("workspace_id") == ws_id and not w.get("is_floating", False)
    ]

    # Build col_x → window_id map
    col_to_id: dict[int, int] = {}
    for w in ws_windows:
        p = w.get("layout", {}).get("pos_in_scrolling_layout")
        if p:
            col = round(p[0])
            col_to_id[col] = w["id"]

    # Find the immediately left column
    left_cols = [k for k in col_to_id if k < new_col]
    if not left_cols:
        return  # first window on workspace — solo

    left_col = max(left_cols)
    left_id = col_to_id[left_col]

    # If left neighbor is already paired, new window stays solo
    if left_id in paired_ids:
        return

    # Left neighbor is solo → pair them.
    # horizontal-view-movement is disabled in niri config so focus changes
    # are instant — no visible viewport pan.
    niri_action("focus-column-left")
    niri_action("set-column-width", "50%")
    niri_action("focus-column-right")
    niri_action("set-column-width", "50%")
    niri_action("center-visible-columns")

    paired_ids.add(win_id)
    paired_ids.add(left_id)


def main() -> None:
    proc = subprocess.Popen(
        ["niri", "msg", "-j", "event-stream"],
        stdout=subprocess.PIPE,
        text=True,
    )

    for raw in proc.stdout:
        raw = raw.strip()
        if not raw:
            continue
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue

        if "WindowOpenedOrChanged" in event:
            win = event["WindowOpenedOrChanged"]["window"]
            win_id = win["id"]
            if win_id not in seen_ids:
                seen_ids.add(win_id)
                handle_new_window(win_id)

        elif "WindowClosed" in event:
            closed_id = event["WindowClosed"]["id"]
            seen_ids.discard(closed_id)
            paired_ids.discard(closed_id)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
