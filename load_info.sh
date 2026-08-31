#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
# load_info.sh — auto-detect hardware and write config.nix
# Run as your normal user (not sudo) — no root needed.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# Ensure NixOS system binaries are on PATH (lspci lives here)
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:$PATH"

if ! command -v lspci &>/dev/null; then
  echo "error: lspci not found — install pciutils or run: nix-shell -p pciutils --run './load_info.sh'"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.nix"

# ── Helpers ───────────────────────────────────────────────────────────────────

hex2dec() { printf '%d' "0x${1}"; }

# Convert lspci short address (e.g. "c4:00.0") to NixOS format ("PCI:196:0:0")
pci_nixos() {
  local bus dev func
  bus=$(echo "$1"  | cut -d: -f1)
  dev=$(echo "$1"  | cut -d: -f2 | cut -d. -f1)
  func=$(echo "$1" | cut -d: -f2 | cut -d. -f2)
  printf "PCI:%d:%d:%d" "$(hex2dec "$bus")" "$(hex2dec "$dev")" "$(hex2dec "$func")"
}

# Extract a string value from an existing config.nix
nix_str() {
  grep "$1" "$2" 2>/dev/null | grep -oP '"\K[^"]+(?=")' | head -1 || true
}

# Extract the first PCI address from an lspci line
get_addr() { echo "$1" | grep -oE '^[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' || true; }

# ── Preserve values from existing config.nix ─────────────────────────────────

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  CURRENT_USER="$SUDO_USER"
else
  CURRENT_USER="$(whoami)"
fi
CURRENT_POWER="balanced"

if [ -f "$CONFIG" ]; then
  u=$(nix_str "user"         "$CONFIG"); [ -n "$u" ] && CURRENT_USER="$u"
  p=$(nix_str "powerProfile" "$CONFIG"); [ -n "$p" ] && CURRENT_POWER="$p"
fi

# ── Detect hardware ───────────────────────────────────────────────────────────

HOSTNAME_VAL=$(hostname)

if grep -qm1 "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
  CPU_VENDOR="amd"
else
  CPU_VENDOR="intel"
fi

# Match by human-readable names (when pciids db is present) OR raw class codes
# 0300=VGA, 0301=XGA, 0302=3D controller
GPU_LIST=$(lspci | grep -E "VGA compatible controller|3D controller|Display controller|Class 030[012]" || true)

# Match NVIDIA by name or vendor ID 10de
NVIDIA_LINE=$(echo "$GPU_LIST" | grep -iE "(nvidia|10de)" | head -1 || true)
# Match AMD/ATI by name or vendor ID 1002
AMD_LINE=$(  echo "$GPU_LIST" | grep -iE "(amd|ati|1002)" | head -1 || true)
# Match Intel display by name or vendor ID 8086 (already filtered to display class)
INTEL_LINE=$(echo "$GPU_LIST" | grep -iE "(intel|8086)"   | head -1 || true)

NVIDIA_BUS="" AMD_BUS="" INTEL_BUS=""

if [ -n "$NVIDIA_LINE" ] && [ -n "$AMD_LINE" ]; then
  GPU_MODE="prime-nvidia-amd"
  NVIDIA_BUS=$(pci_nixos "$(get_addr "$NVIDIA_LINE")")
  AMD_BUS=$(  pci_nixos "$(get_addr "$AMD_LINE")")
elif [ -n "$NVIDIA_LINE" ] && [ -n "$INTEL_LINE" ]; then
  GPU_MODE="prime-nvidia-intel"
  NVIDIA_BUS=$(pci_nixos "$(get_addr "$NVIDIA_LINE")")
  INTEL_BUS=$( pci_nixos "$(get_addr "$INTEL_LINE")")
elif [ -n "$NVIDIA_LINE" ]; then
  GPU_MODE="nvidia"
  NVIDIA_BUS=$(pci_nixos "$(get_addr "$NVIDIA_LINE")")
elif [ -n "$AMD_LINE" ]; then
  GPU_MODE="amd"
elif [ -n "$INTEL_LINE" ]; then
  GPU_MODE="intel"
else
  echo "warning: no GPU detected — check 'lspci' manually and set gpu in config.nix yourself."
  echo "  Defaulting to 'amd' (safe fallback — open source driver, no config needed)."
  GPU_MODE="amd"
fi

# ── Detect input device type ──────────────────────────────────────────────────

if grep -qi 'touchpad\|trackpad\|clickpad' /proc/bus/input/devices 2>/dev/null; then
  INPUT_DEVICE="touchpad"
  INPUT_SENSITIVITY="0.8"
else
  INPUT_DEVICE="mouse"
  INPUT_SENSITIVITY="-0.1"
fi

# ── Preview & confirm ─────────────────────────────────────────────────────────

echo ""
echo "Detected:"
echo "  hostname:    $HOSTNAME_VAL"
echo "  user:        $CURRENT_USER"
echo "  power:       $CURRENT_POWER"
echo "  cpu:         $CPU_VENDOR"
echo "  gpu mode:    $GPU_MODE"
[ -n "$NVIDIA_BUS" ] && echo "  nvidia bus:  $NVIDIA_BUS"
[ -n "$AMD_BUS"    ] && echo "  amd bus:     $AMD_BUS"
[ -n "$INTEL_BUS"  ] && echo "  intel bus:   $INTEL_BUS"
echo "  input:       $INPUT_DEVICE (sensitivity: $INPUT_SENSITIVITY)"
echo ""
printf "Write to config.nix? [Y/n] "
read -r CONFIRM
CONFIRM="${CONFIRM:-Y}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Write config.nix ──────────────────────────────────────────────────────────

cat > "$CONFIG" <<NIXEOF
# ════════════════════════════════════════════════════════════════════════════
# USER CONFIG — edit this file when setting up on a new machine
# Run ./load_info.sh to auto-detect and fill all fields from hardware
# ════════════════════════════════════════════════════════════════════════════
{
  hostname         = "$HOSTNAME_VAL";    # your machine's hostname
  user             = "$CURRENT_USER";    # your Linux username
  powerProfile     = "$CURRENT_POWER";   # "performance", "balanced", or "power-saver"
  cpuVendor        = "$CPU_VENDOR";      # "amd" or "intel"
  gpu              = "$GPU_MODE";        # "amd", "intel", "nvidia", "prime-nvidia-amd", "prime-nvidia-intel"
  nvidiaBusId      = "$NVIDIA_BUS";      # only for prime modes, e.g. "PCI:196:0:0"
  amdBusId         = "$AMD_BUS";         # only for prime-nvidia-amd, e.g. "PCI:197:0:0"
  intelBusId       = "$INTEL_BUS";       # only for prime-nvidia-intel, e.g. "PCI:0:2:0"
  inputSensitivity = "$INPUT_SENSITIVITY"; # "0.8" for touchpad, "-0.1" for mouse
}
NIXEOF

echo "Done. config.nix written."

# ── Symlink hardware-configuration.nix ───────────────────────────────────────
HW_SRC="/etc/nixos/hardware-configuration.nix"
HW_DST="$SCRIPT_DIR/hardware-configuration.nix"
if [ -f "$HW_SRC" ]; then
  ln -sf "$HW_SRC" "$HW_DST"
  echo "Symlinked hardware-configuration.nix → $HW_SRC"
else
  echo "warning: $HW_SRC not found — run 'nixos-generate-config' first"
fi

# ── Write hardware env vars to settings.json ──────────────────────────────────
# Populates the {{HARDWARE_ENV}} placeholder used by settings_watcher.sh
# so the Hyprland env.conf gets the right GPU-specific vars on this machine.
SETTINGS_JSON="$HOME/.config/hypr/settings.json"
mkdir -p "$(dirname "$SETTINGS_JSON")"
[ ! -f "$SETTINGS_JSON" ] && echo "{}" > "$SETTINGS_JSON"

if [[ "$GPU_MODE" == nvidia || "$GPU_MODE" == prime-nvidia-amd || "$GPU_MODE" == prime-nvidia-intel ]]; then
  HW_ENVS='["env = GBM_BACKEND,nvidia-drm","env = __GLX_VENDOR_LIBRARY_NAME,nvidia","env = WLR_NO_HARDWARE_CURSORS,1","env = LIBVA_DRIVER_NAME,nvidia"]'
elif [[ "$GPU_MODE" == amd ]]; then
  HW_ENVS='["env = LIBVA_DRIVER_NAME,radeonsi"]'
else
  HW_ENVS='[]'
fi

TMP=$(mktemp)
jq --argjson envs "$HW_ENVS" \
  '.hardwareEnvs = $envs' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
chown "$CURRENT_USER:" "$SETTINGS_JSON"
chmod 644 "$SETTINGS_JSON"
echo "Hardware env vars written to $SETTINGS_JSON (gpu: $GPU_MODE)"

# ── Fix nvim state ownership ──────────────────────────────────────────────────
USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
NVIM_STATE="$USER_HOME/.local/state/nvim"
if [ -d "$NVIM_STATE" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$CURRENT_USER:users" "$NVIM_STATE"
  else
    sudo chown -R "$CURRENT_USER:users" "$NVIM_STATE"
  fi
  echo "Fixed ownership of $NVIM_STATE → $CURRENT_USER:users"
fi
