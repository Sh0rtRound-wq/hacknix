#!/usr/bin/env python3
# deepen-colors.py — push matugen accents to NEON: full saturation, high
# lightness. Target look is high-contrast-dark: bright green / electric blue
# on black, not pastel and not jewel-tone.
#
# Transform is deliberately identical to boost_accent() in
# boost-kitty-colors.sh so the borders, quickshell accents and terminal all
# agree:
#     L = clamp(L, 0.50, 0.65)    neon sweet spot
#     S = clamp(S + 0.35, 0, 1)   push toward fully saturated
#
# HISTORY — do not reintroduce the old transform. It was:
#     normalise by max channel -> power curve (3.0) -> scale 0.65
# which DROPPED SATURATION from 100% to 52% and darkened to L43%, producing a
# muddy olive. That desaturation was the "grey border" bug, not a persistence
# problem. Matugen's own primary_container is S100% but only L44%, which reads
# as a dark colour (very obviously so for purple hues) — hence the lightness
# floor here.
#
# Pipeline (raw/final split is load-bearing):
#     matugen        -> colors_raw.lua       + /tmp/qs_colors_raw.json
#     this script    -> colors.lua           + /tmp/qs_colors.json
# Input is never its own output, so this is idempotent and a failed run leaves
# the last-good output intact rather than stranding a raw value where Hyprland
# will source it on every subsequent boot.
#
# Backgrounds and text are left untouched on purpose: the accent transform
# normalises by the max channel, which inverts near-black backgrounds into
# bright colours (base #0c0f09 -> #54a523) and collapses text contrast from
# 14.9:1 to 1.23:1.

import json, re, math, os, sys, colorsys, tempfile

ACCENT_KEYS = ['blue', 'sapphire', 'peach', 'green', 'red', 'mauve',
               'pink', 'yellow', 'maroon', 'teal']

# ── tuning knobs ─────────────────────────────────────────────────────────────
# L_MIN/L_MAX : lightness window. Raise for brighter, lower for deeper.
#               0.48-0.56 as of 2026-11-12 (was 0.50-0.65). The ceiling was the
#               "lighter wallpaper" bug: quickshell renders accents through
#               Qt.lighter(...,1.15), i.e. L*1.15, so a 0.65 value was displayed
#               at ~0.75 and looked washed. Anything matugen emits with raw
#               L>0.56 (secondary/tertiary/error and every scheme-tonal-spot
#               role) used to land on that ceiling.
# S_FLOOR     : minimum saturation. 1.0 = force every accent fully saturated,
#               which is what makes low-chroma roles read as neon rather than
#               pastel. matugen's secondary/tertiary come in as low as S27%,
#               and a mere additive boost left them around S62% — visibly not
#               neon. Drop toward ~0.8 if the palette feels too aggressive.
L_MIN, L_MAX = 0.48, 0.56
S_FLOOR      = 1.00
S_BOOST      = 0.35         # additive, applied before the floor

# Hue anchor: matugen's green family lands on yellow-green (H80-115 in HSL), which
# reads chartreuse next to a dark background. Pull that band toward true green,
# with a smooth ramp at both edges so genuine yellows (<=70) and cyans (>=140) are
# untouched. Tunables: raise PULL for more green (1.0 = clamp everything in the
# band to TARGET), widen BAND/HI if a wallpaper's yellows start drifting green.
HUE_GREEN_TARGET = 124.0          # degrees pulled toward (= pure green)
HUE_GREEN_BAND   = (68.0, 140.0)  # (lo, hi) region treated as "should be green"
HUE_GREEN_RAMP   = 10.0           # degrees of smooth ramp at each band edge
HUE_GREEN_PULL   = 0.90           # 0 = off, 1 = snap to target

def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)

def anchor_green(hue_deg):
    lo, hi = HUE_GREEN_BAND
    if not (lo <= hue_deg < hi):
        return hue_deg
    weight = min(1.0, (hue_deg - lo) / HUE_GREEN_RAMP, (hi - hue_deg) / HUE_GREEN_RAMP)
    if weight <= 0.0:
        return hue_deg
    return hue_deg + (HUE_GREEN_TARGET - hue_deg) * weight * HUE_GREEN_PULL

def neon(hex_color):
    """Full-saturation, high-lightness. Hue is preserved exactly."""
    h = hex_color.lstrip('#')
    if len(h) != 6:
        return hex_color
    r, g, b = (int(h[0:2],16)/255.0, int(h[2:4],16)/255.0, int(h[4:6],16)/255.0)
    hh, l, s = colorsys.rgb_to_hls(r, g, b)
    # Achromatic input has no hue to make neon — leave it be rather than
    # inventing a colour.
    if s < 0.01:
        return '#' + h
    hh = anchor_green(hh * 360.0) / 360.0
    l = clamp(l, L_MIN, L_MAX)
    s = clamp(max(s + S_BOOST, S_FLOOR), 0.0, 1.0)
    r, g, b = colorsys.hls_to_rgb(hh, l, s)
    return '#{:02x}{:02x}{:02x}'.format(
        int(r*255 + 0.5), int(g*255 + 0.5), int(b*255 + 0.5))

def write_atomic(path, content):
    """Temp file + rename, so a crash mid-write can never leave a truncated
    file for Hyprland or quickshell to read."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.tmp-', text=True)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(content)
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise

# ── quickshell accents ───────────────────────────────────────────────────────
qs_raw, qs_out = '/tmp/qs_colors_raw.json', '/tmp/qs_colors.json'
# Persistent mirror. /tmp is disk-backed here, but tmpfiles.d ages it out after
# ~10 days, and a missing /tmp/qs_colors.json makes quickshell fall back to its
# hardcoded palette (a light catppuccin-ish look) until the next wallpaper
# switch. MatugenColors.qml reads /tmp first, then this mirror.
qs_cache = os.path.expanduser('~/.cache/hypr/qs_colors.json')
qs_src = qs_raw if os.path.exists(qs_raw) else qs_out
try:
    with open(qs_src) as f:
        colors = json.load(f)
    for k in ACCENT_KEYS:
        if k in colors:
            colors[k] = neon(colors[k])
    payload = json.dumps(colors, indent=4)
    write_atomic(qs_out, payload)
    os.makedirs(os.path.dirname(qs_cache), exist_ok=True)
    write_atomic(qs_cache, payload)
    print(f"qs_colors: neon {[k for k in ACCENT_KEYS if k in colors]} (+ cache mirror)")
except Exception as e:
    print(f"qs_colors error: {e}", file=sys.stderr)

# ── Hyprland border ─────────────────────────────────────────────────────────
# Lua module consumed by ~/.config/hypr/config/settings.lua via require("colors").
raw_path  = os.path.expanduser('~/.config/hypr/colors_raw.lua')
conf_path = os.path.expanduser('~/.config/hypr/colors.lua')
src_path  = raw_path if os.path.exists(raw_path) else conf_path
try:
    with open(src_path) as f:
        content = f.read()

    # active_border only. Anchored to line start because "inactive_border" also
    # contains the substring "active_border"; an unanchored match would feed
    # Hyprland two rgba values (parsed as a gradient whose second stop is
    # rgba(00000000) — an invisible border).
    content, n = re.subn(
        r'(?m)^(\s*active_border\s*=\s*"rgba\()([0-9a-fA-F]{6})',
        lambda m: m.group(1) + neon('#'+m.group(2)).lstrip('#'),
        content
    )
    if n == 0:
        print(f"colors.lua: no active_border in {src_path}, leaving as-is",
              file=sys.stderr)
        sys.exit(1)

    write_atomic(conf_path, content)
    print(f"colors.lua: neon active_border from {os.path.basename(src_path)}")
except Exception as e:
    print(f"colors.lua error: {e}", file=sys.stderr)
    sys.exit(1)
