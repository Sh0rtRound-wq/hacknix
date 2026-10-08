#!/usr/bin/env python3
"""
restyle_code_theme.py — mass restyle quickshell-minimalist widgets for minimalist theme aesthetic
- Semi-transparent main bg
- Mauve accent borders
- Theme-aware slider track colors
"""

import os
import re
import sys

QML_DIR = os.path.expanduser("~/hacknix/rice/hypr/scripts/quickshell-minimalist")

# Files to skip (infrastructure, not visual widgets)
SKIP = {"Shell.qml", "Main.qml", "MatugenColors.qml", "Scaler.qml",
        "Caching.qml", "Config.qml", "SysData.qml", "Lock.qml", "TopBar.qml"}

REPLACEMENTS = [
    # ── Main container variants: solid base → semi-transparent
    # window.base / window.surface0
    (
        "color: window.base\n            border.color: window.surface0",
        "color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.88)\n            border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.35)"
    ),
    # root.base / root.surface0 (GuidePopup, SettingsPopup style)
    (
        "color: root.base\n            border.color: root.surface0",
        "color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.88)\n            border.color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.35)"
    ),
    # _theme.base / _theme.surface1 (NotificationPopups style)
    (
        "color: _theme.base\n                    border.color: _theme.surface1",
        "color: Qt.rgba(_theme.base.r, _theme.base.g, _theme.base.b, 0.88)\n                    border.color: Qt.rgba(_theme.mauve.r, _theme.mauve.g, _theme.mauve.b, 0.35)"
    ),
    # SettingsPopup inner bg (root.base without border on same line)
    (
        "            color: root.base\n            radius: 0\n\n            // FIX: This forces the entire background",
        "            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.88)\n            radius: 0\n\n            // FIX: This forces the entire background"
    ),
    # CalendarPopup uses Qt.alpha style
    (
        "color: window.base\n            border.color: window.surface0\n            border.width: 1\n            clip: true",
        "color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.88)\n            border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.35)\n            border.width: 1\n            clip: true"
    ),
    # Slider tracks: hardcoded near-transparent white → overlay-based
    (
        'color: "#0dffffff"; border.color: "#1affffff"; border.width: 1',
        'color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.08); border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2); border.width: 1'
    ),
    (
        'color: "#0dffffff"\n                    border.color: "#1affffff"\n                    border.width: 1',
        'color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.08)\n                    border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2)\n                    border.width: 1'
    ),
    # Tab container in VolumePopup
    (
        'color: "#0dffffff" \n                    border.color: "#1affffff"',
        'color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.08)\n                    border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2)'
    ),
    # Delegate rows: near-transparent white hover states
    (
        'color: isActiveNode ? window.tabColor : (isHovered ? "#0affffff" : "#05ffffff")',
        'color: isActiveNode ? window.tabColor : (isHovered ? Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.12) : Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.05))'
    ),
    (
        'border.color: isActiveNode ? window.tabColor : "#1affffff"',
        'border.color: isActiveNode ? window.tabColor : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2)'
    ),
    # Calendar glass panel: Qt.alpha(window.surface0, 0.2) → darker
    (
        "color: Qt.alpha(window.surface0, 0.2) \n                radius: 0\n                border.color: Qt.alpha(window.surface1, 0.4)",
        "color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.75)\n                radius: 0\n                border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)"
    ),
    # Mute button border
    (
        'border.color: muteMa.containsMouse ? (model.mute ? window.overlay0 : window.tabColor) : "transparent"',
        'border.color: muteMa.containsMouse ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.5) : "transparent"'
    ),
]

def restyle(path: str) -> bool:
    with open(path) as f:
        orig = f.read()

    content = orig
    for old, new in REPLACEMENTS:
        content = content.replace(old, new)

    if content == orig:
        return False

    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, 0o775)
    return True


def main():
    changed = []
    skipped = []

    for root, dirs, files in os.walk(QML_DIR):
        for fname in files:
            if not fname.endswith(".qml"):
                continue
            if fname in SKIP:
                skipped.append(fname)
                continue
            fpath = os.path.join(root, fname)
            if restyle(fpath):
                rel = os.path.relpath(fpath, QML_DIR)
                changed.append(rel)

    print(f"Modified ({len(changed)}):")
    for f in sorted(changed):
        print(f"  {f}")
    print(f"\nSkipped ({len(skipped)}): {', '.join(sorted(skipped))}")

if __name__ == "__main__":
    main()
