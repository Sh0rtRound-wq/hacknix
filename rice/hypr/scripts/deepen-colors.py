#!/usr/bin/env python3
# deepen-colors.py — post-process matugen output to make accent colors deeper/more saturated
# Applies: normalize hue → power curve → scale down (jewel tone, not pastel)
# Leaves backgrounds (base/mantle/crust/surface/overlay) and text untouched

import json, re, math, os, sys

ACCENT_KEYS = ['blue', 'sapphire', 'peach', 'green', 'red', 'mauve',
               'pink', 'yellow', 'maroon', 'teal']

POWER = 3.0   # higher = more saturated
SCALE = 0.65  # lower = darker/deeper (0.65 = rich jewel tone)

def hex_to_rgb(h):
    h = h.lstrip('#')
    return (int(h[0:2],16)/255.0, int(h[2:4],16)/255.0, int(h[4:6],16)/255.0)

def rgb_to_hex(r, g, b):
    return '#{:02x}{:02x}{:02x}'.format(
        min(255,int(r*255)), min(255,int(g*255)), min(255,int(b*255)))

def deepen(hex_color):
    r, g, b = hex_to_rgb(hex_color)
    mx = max(r, g, b)
    if mx < 0.05: return hex_color  # skip near-black
    r, g, b = r/mx, g/mx, b/mx
    r = math.pow(r, POWER) * SCALE
    g = math.pow(g, POWER) * SCALE
    b = math.pow(b, POWER) * SCALE
    return rgb_to_hex(r, g, b)

# ── qs_colors.json ────────────────────────────────────────────────────────────
qs_path = '/tmp/qs_colors.json'
try:
    with open(qs_path) as f:
        colors = json.load(f)
    for k in ACCENT_KEYS:
        if k in colors:
            colors[k] = deepen(colors[k])
    with open(qs_path, 'w') as f:
        json.dump(colors, f, indent=4)
    print(f"qs_colors: deepened {[k for k in ACCENT_KEYS if k in colors]}")
except Exception as e:
    print(f"qs_colors error: {e}", file=sys.stderr)

# ── colors.conf (Hyprland border) ────────────────────────────────────────────
# Read from colors_raw.conf (fresh matugen output) → write to colors.conf (deepened)
# This keeps deepen idempotent: always processes raw values, never re-deepens
raw_path  = os.path.expanduser('~/.config/hypr/colors_raw.conf')
conf_path = os.path.expanduser('~/.config/hypr/colors.conf')
# Fall back to reading colors.conf if raw doesn't exist yet (legacy compat)
src_path = raw_path if os.path.exists(raw_path) else conf_path
try:
    with open(src_path) as f:
        content = f.read()

    def replace_hex(m):
        return m.group(0).replace(m.group(1), deepen('#'+m.group(1)).lstrip('#'))

    # deepen active_border hex only (leave inactive border alone)
    content = re.sub(
        r'(active_border\s*=\s*rgba\()([0-9a-fA-F]{6})',
        lambda m: m.group(1) + deepen('#'+m.group(2)).lstrip('#'),
        content
    )
    with open(conf_path, 'w') as f:
        f.write(content)
    print(f"colors.conf: deepened active_border")
except Exception as e:
    print(f"colors.conf error: {e}", file=sys.stderr)
