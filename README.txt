# hacknix

Portable NixOS flake with Hyprland rice, matugen theming, and pentest/gaming profiles.

## First Time Setup

**1. Clone and copy your hardware config**
```bash
git clone https://github.com/YOUR_USERNAME/hacknix ~/hacknix
cp /etc/nixos/hardware-configuration.nix ~/hacknix/
```

**2. Auto-detect machine settings**
```bash
cd ~/hacknix
bash load_info.sh
```
This fills `config.nix` with your hostname, username, GPU, CPU vendor, and power profile. Review it after and adjust anything it got wrong.

**3. Rebuild**
```bash
# Pentest profile (offensive security tools, CTF tooling)
sudo nixos-rebuild switch --flake ~/hacknix#pentest

# Gaming profile (gaming packages, performance tuning)
sudo nixos-rebuild switch --flake ~/hacknix#gaming
```

That's it. The rice, keybinds, and theming are all declarative — no manual setup needed after the rebuild.

---

## Profiles

| Profile | Use case |
|---------|----------|
| `pentest` | Offensive security tools, CTF tooling |
| `gaming` | Gaming packages, performance tuning |

## Per-machine config

`config.nix` is the only file that changes between machines. It is gitignored — do not commit it. Use `config.nix.example` as a reference.

`hardware-configuration.nix` is also gitignored — generate it fresh per machine with:
```bash
nixos-generate-config --show-hardware-config > ~/hacknix/hardware-configuration.nix
```

## Monitor / display config

Monitor layout and resolution live in `~/.config/hypr/settings.json` — per-device state, not in the flake. Sensible defaults are set on first rebuild. Edit directly to change resolution or monitor arrangement.
