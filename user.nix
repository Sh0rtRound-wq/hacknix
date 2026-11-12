{ config, pkgs, lib, wallpaperDir, homeUser, mouseSensitivity, touchpadSensitivity, qsTheme, ... }:

let
  cava-dynamic = pkgs.writeShellScriptBin "cava" ''
    mkdir -p ~/.config/cava
    cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null
    exec ${pkgs.cava}/bin/cava "$@"
  '';

  # ── Border colour: push colors.lua into the running compositor ────────
  # matugen is the SOLE writer of colors.lua, and its template pulls
  # primary_container, which Material You already supplies at S100% L44%.
  # There is deliberately no transform step here.
  #
  # History: colors.lua used to be post-processed by deepen-colors.py, which
  # read and wrote the same file. That gave two permanent failure states —
  # a failed run left the raw washed-out value in place (grey border on every
  # subsequent boot, never self-recovering), and a repeat run double-deepened.
  # It also *desaturated* (100% -> 52%), which was the grey itself.
  #
  # All binaries are absolute nix store paths; the old script called bare
  # `python3`/`grep`/`hyprctl` and silently no-op'd whenever the Hyprland
  # exec-once environment lacked them.
  apply-border-colors = pkgs.writeShellScript "apply-border-colors" ''
    set -uo pipefail

    RAW="$HOME/.config/hypr/colors_raw.lua"
    OUT="$HOME/.config/hypr/colors.lua"
    QS_RAW="/tmp/qs_colors_raw.json"

    # The quickshell accents live in /tmp and are ONLY ever produced by
    # matugen, so if init-wallpaper died (bad wallpaper path, matugen crash)
    # or /tmp was cleaned, quickshell would fall back to its hardcoded
    # catppuccin defaults. Regenerate the raw files ourselves so this unit is
    # fully self-sufficient and does not depend on init-wallpaper at all.
    # The border itself is safe regardless: colors.lua is under ~/.config and
    # persists across reboots.
    if [ ! -f "$RAW" ] || [ ! -f "$QS_RAW" ]; then
      _wall=$(${pkgs.coreutils}/bin/cat "$HOME/.config/hypr/wallpaper" 2>/dev/null || true)
      if [ -n "$_wall" ] && [ -f "$_wall" ]; then
        ${pkgs.matugen}/bin/matugen image --type scheme-vibrant --contrast 1.0 --mode dark \
          --source-color-index 0 "$_wall" >/dev/null 2>&1 || \
          echo "apply-border-colors: matugen failed on $_wall" >&2
      else
        echo "apply-border-colors: no usable wallpaper at $_wall" >&2
      fi
    fi

    # Apply the neon transform (S->100%, L->0.50-0.65). matugen's raw output is
    # washed (L84%) and even primary_container is only L44%. Reads the _raw
    # files, writes the files consumers read, so repeat runs are idempotent and
    # a failure leaves the last-good output in place.
    ${pkgs.python3}/bin/python3 "$HOME/.config/hypr/scripts/deepen-colors.py" || \
      echo "apply-border-colors: transform failed, keeping existing colors.lua" >&2

    [ -f "$OUT" ] || exit 0

    # colors.lua is only read by Hyprland at startup/reload, so a live session
    # needs an explicit set. Under the Lua config provider `hyprctl keyword` is a
    # no-op (man page), so the values are pushed with `hyprctl eval`. Worst case
    # this fails and the next boot still reads the correct colors.lua — no
    # persistent bad state.
    _active=$(${pkgs.gnugrep}/bin/grep -oP '^\s*active_border\s*=\s*"rgba\([^)]+\)"' "$OUT" | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed 's/.*"\(.*\)"/\1/' || true)
    _inactive=$(${pkgs.gnugrep}/bin/grep -oP '^\s*inactive_border\s*=\s*"rgba\([^)]+\)"' "$OUT" | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gnused}/bin/sed 's/.*"\(.*\)"/\1/' || true)

    [ -n "$_active" ] || exit 0

    _code=$(printf 'hl.config({ general = { col = { active_border = "%%s", inactive_border = "%%s" } } })' "$_active" "$_inactive")

    # Resolve the live instance ourselves — exec-once and systemd user units
    # do not always inherit HYPRLAND_INSTANCE_SIGNATURE.
    _sockdir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/hypr"
    _apply() {
      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        hyprctl eval "$_code" >/dev/null 2>&1 && return 0
      fi
      for _d in "$_sockdir"/*/; do
        [ -S "$_d/.socket.sock" ] || continue
        HYPRLAND_INSTANCE_SIGNATURE="$(${pkgs.coreutils}/bin/basename "$_d")" \
          hyprctl eval "$_code" >/dev/null 2>&1 && return 0
      done
      return 0
    }
    _apply
  '';
in
{
  home.username      = homeUser;
  home.homeDirectory = "/home/${homeUser}";
  home.stateVersion  = "24.11";
  programs.home-manager.enable = true;

  # ── Shell ──────────────────────────────────────────────────────────────
  programs.zsh = {
    enable               = true;
    dotDir               = config.home.homeDirectory;
    enableCompletion     = true;
    autosuggestion.enable = false;
    syntaxHighlighting.enable = true;
    history = {
      size          = 10000;
      path          = "$HOME/.zsh_history";
      ignoreAllDups = true;
    };
    oh-my-zsh = {
      enable  = true;
      plugins = [];
      theme   = "minimal";
    };
    shellAliases = {};
    loginExtra = ''
      if [ "$(tty)" = "/dev/tty1" ]; then
        exec uwsm start hyprland-uwsm.desktop
      fi
    '';
    initContent = builtins.readFile ./rice/zsh/zsh-init.sh;
  };

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      [ -f /etc/bashrc ] && . /etc/bashrc
    '';
    initExtra = ''
      PS1='\[\033[0;32m\]\u@\h\[\033[0m\]:\[\033[0;34m\]\w\[\033[0m\] \[\033[0;32m\]❯\[\033[0m\] '
    '';
  };

  home.sessionVariables.FLAKE        = "$HOME/hacknix";
  home.sessionVariables.WALLPAPER_DIR = wallpaperDir;

  # ── Git ────────────────────────────────────────────────────────────────
  programs.git = {
    enable   = true;
    settings = {
      user.name      = "HackTFTP";
      user.email     = "liamtftp@gmail.com";
      safe.directory = "/home/${homeUser}/hacknix";
    };
  };

  # ── Neovim ────────────────────────────────────────────────────────────
  programs.neovim = {
    enable        = true;
    defaultEditor = true;
    viAlias       = true;
    vimAlias      = true;
    withRuby      = true;
    withPython3   = true;
    extraPackages = with pkgs; [
      ripgrep fd lua-language-server pyright nil nixpkgs-fmt gopls
    ];
    plugins = with pkgs.vimPlugins; [
      catppuccin-nvim nvim-web-devicons nvim-treesitter.withAllGrammars
      lualine-nvim bufferline-nvim indent-blankline-nvim gitsigns-nvim
      which-key-nvim nvim-tree-lua plenary-nvim telescope-nvim telescope-ui-select-nvim
      nvim-autopairs comment-nvim nvim-lspconfig nvim-cmp cmp-nvim-lsp
      cmp-buffer cmp-path cmp-cmdline luasnip cmp_luasnip friendly-snippets
    ];
  };
  xdg.configFile."nvim/init.lua".source = ./rice/neovim/init.lua;

  # ── Theming ───────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    adwaita-icon-theme adw-gtk3
    libsForQt5.qt5ct qt6Packages.qt6ct
    (lib.hiPrio cava-dynamic)
    swayosd
  ];

  home.pointerCursor = {
    enable     = true;
    gtk.enable = true;
    x11.enable = true;
    size       = 24;
    name       = "oreo_spark_black_bordered_cursors";
    package    = pkgs.oreo-cursors-plus;
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme    = "adw-gtk3-dark";
  };

  gtk = {
    enable = true;
    gtk3.extraCss = ''@import url("file://${config.home.homeDirectory}/.cache/matugen/colors-gtk.css");'';
    gtk4.extraCss = ''@import url("file://${config.home.homeDirectory}/.cache/matugen/colors-gtk.css");'';
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
      gtk-theme-name = "adw-gtk3-dark";
    };
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
  };

  fonts.fontconfig.enable = true;

  services.swayosd = {
    enable    = true;
    topMargin = 0.9;
    stylePath = "${config.home.homeDirectory}/.config/swayosd/style.css";
  };

  # ── Matugen ───────────────────────────────────────────────────────────
  xdg.configFile."matugen" = {
    source    = ./rice/matugen;
    recursive = true;
  };

  # ── Cava ──────────────────────────────────────────────────────────────
  xdg.configFile."cava/config_base".source = ./rice/cava/config_base;

  # ── XDG / session ─────────────────────────────────────────────────────
  xdg.enable = true;
  home.sessionPath = [ "$HOME/.local/bin" ];

  # ── Rofi ──────────────────────────────────────────────────────────────
  xdg.configFile."rofi/config.rasi".source          = ./rice/rofi/config.rasi;
  xdg.configFile."rofi/theme.rasi".source           = ./rice/rofi/theme.rasi;
  xdg.configFile."rofi/powermenu-theme.rasi".source = ./rice/rofi/powermenu-theme.rasi;

  # ── Swaync ────────────────────────────────────────────────────────────
  xdg.configFile."swaync/config.json".source = ./rice/swaync/config.json;
  xdg.configFile."swaync/style.css".source   = ./rice/swaync/style.css;

  # ── Waybar ────────────────────────────────────────────────────────────
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      position      = "top";
      layer         = "top";
      height        = 28;
      margin-top    = 0;
      margin-bottom = 0;
      margin-left   = 0;
      margin-right  = 0;
      modules-left   = [ "custom/launcher" "hyprland/workspaces" "tray" ];
      modules-center = [ "clock" ];
      modules-right  = [
        "cpu" "memory" "pulseaudio" "network" "battery"
        "custom/notification" "custom/power-menu"
      ];
      clock = {
        format         = "{:%H:%M}";
        tooltip        = "true";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        format-alt     = "{:%d/%m}";
        calendar.format.today = "<span color='#00FF41'><b>{}</b></span>";
      };
      "hyprland/workspaces" = {
        active-only    = false;
        disable-scroll = true;
        format         = "{icon}";
        on-click       = "activate";
        format-icons = {
          "1" = "I"; "2" = "II"; "3" = "III"; "4" = "IV"; "5" = "V";
          "6" = "VI"; "7" = "VII"; "8" = "VIII"; "9" = "IX"; "10" = "X";
          sort-by-number = true;
        };
        persistent-workspaces = {
          "1" = []; "2" = []; "3" = []; "4" = []; "5" = [];
        };
      };
      cpu = {
        format   = "<span foreground='#00FF41'> </span> {usage}%";
        interval = 2;
        on-click-right = "hyprctl dispatch 'hl.dsp.exec_cmd(\"kitty --override font_size=14 --title float_kitty btop\", { float = true, center = true, size = \"950 650\" })'";
      };
      memory = {
        format   = "<span foreground='#00CC33'>󰟜 </span>{}%";
        interval = 2;
        on-click-right = "hyprctl dispatch 'hl.dsp.exec_cmd(\"kitty --override font_size=14 --title float_kitty btop\", { float = true, center = true, size = \"950 650\" })'";
      };
      network = {
        format-wifi         = "<span foreground='#00FF41'> </span> {signalStrength}%";
        format-ethernet     = "<span foreground='#00FF41'>󰀂 </span>";
        tooltip-format      = "Connected to {essid} {ifname} via {gwaddr}";
        format-linked       = "{ifname} (No IP)";
        format-disconnected = "<span foreground='#00FF41'>󰖪 </span>";
      };
      tray = { icon-size = 20; spacing = 8; };
      pulseaudio = {
        format         = "{icon} {volume}%";
        format-muted   = "<span foreground='#00AA2B'> </span> {volume}%";
        format-icons.default = [ "<span foreground='#00AA2B'> </span>" ];
        scroll-step    = 2;
        on-click       = "pamixer -t";
        on-click-right = "pavucontrol";
      };
      battery = {
        format          = "<span foreground='#00FF41'>{icon}</span> {capacity}%";
        format-icons    = [ " " " " " " " " " " ];
        format-charging = "<span foreground='#00FF41'> </span>{capacity}%";
        format-full     = "<span foreground='#00FF41'> </span>{capacity}%";
        interval        = 5;
        states.warning  = 20;
        tooltip         = true;
        tooltip-format  = "{time}";
        format-time     = "{H}h{M}m";
      };
      "custom/launcher" = {
        format         = "";
        on-click       = "random-wallpaper";
        on-click-right = "rofi -show drun";
        tooltip        = "true";
        tooltip-format = "Left: Random Wallpaper | Right: App Launcher";
      };
      "custom/notification" = {
        tooltip        = true;
        tooltip-format = "Notifications";
        format         = "{icon}";
        format-icons = {
          notification     = "<span foreground='red'><sup></sup></span>";
          none             = "";
          dnd-notification = "<span foreground='red'><sup></sup></span>";
          dnd-none         = "";
        };
        return-type    = "json";
        exec-if        = "which swaync-client";
        exec           = "swaync-client -swb";
        on-click       = "swaync-client -t -sw";
        on-click-right = "swaync-client -d -sw";
        escape         = true;
      };
      "custom/power-menu" = {
        tooltip        = true;
        tooltip-format = "Power menu";
        format         = "<span foreground='#FF3333'> </span>";
        on-click       = "power-menu";
      };
    };
    style = ''
      * {
        border: none;
        border-radius: 0px;
        padding: 0;
        margin: 0;
        font-family: JetBrainsMono Nerd Font;
        font-weight: bold;
        opacity: 1;
        font-size: 16px;
      }
      window#waybar {
        background: #0D0D0D;
        border-bottom: 1px solid #00FF41;
      }
      tooltip {
        background: #0D0D0D;
        border: 1px solid #00FF41;
      }
      tooltip label {
        margin: 5px;
        color: #00FF41;
      }
      #workspaces { padding-left: 15px; }
      #workspaces button {
        color: #00AA2B;
        padding-left: 5px;
        padding-right: 5px;
        margin-right: 10px;
      }
      #workspaces button.empty { color: #005500; }
      #workspaces button.active { color: #00FF41; }
      #clock { color: #00FF41; }
      #tray { margin-left: 10px; color: #00FF41; }
      #tray menu {
        background: #0D0D0D;
        border: 1px solid #00FF41;
        padding: 8px;
      }
      #tray menuitem { padding: 1px; }
      #pulseaudio, #network, #cpu, #memory, #battery,
      #custom-notification, #custom-power-menu {
        padding-left: 5px;
        padding-right: 5px;
        margin-right: 10px;
        color: #00FF41;
      }
      #pulseaudio, #custom-notification { margin-left: 15px; }
      #custom-power-menu { padding-right: 2px; margin-right: 5px; }
      #custom-launcher {
        font-size: 20px;
        color: #00FF41;
        font-weight: bold;
        margin-left: 15px;
        padding-right: 10px;
      }
    '';
  };

  # ── Hyprland ──────────────────────────────────────────────────────────
  # rules.lua and variables.lua are static — deployed as read-only symlinks.
  # settings.lua, autostart.lua, keybindings.lua, monitors.lua, env.lua are
  # generated at runtime by settings_watcher.sh from templates/.
  # colors.lua is generated at runtime by matugen.
  xdg.configFile."hypr/config/rules.lua".source     = ./rice/hypr/config/rules.lua;
  xdg.configFile."hypr/config/variables.lua".source = ./rice/hypr/config/variables.lua;
  xdg.configFile."hypr/templates" = {
    source    = ./rice/hypr/templates;
    recursive = true;
  };
  xdg.configFile."hypr/scripts" = {
    source    = ./rice/hypr/scripts;
    recursive = true;
  };
  wayland.windowManager.hyprland = {
    enable        = true;
    configType    = "lua";
    package       = null;
    portalPackage = null;
    xwayland.enable = true;
    systemd.enable  = false;  # uwsm manages the session; HM integration stops graphical-session.target and kills uwsm
    # Root Lua config (require order preserved from the previous hyprlang sources).
    extraConfig = builtins.readFile ./rice/hypr/hyprland.lua;
  };

  # ── Hyprlock ──────────────────────────────────────────────────────────
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor        = true;
        ignore_empty_input = true;
      };
      background = [{
        path        = "${wallpaperDir}/halo.jpg";
        blur_passes = 2;
      }];
      label = [
        {
          text        = ''cmd[update:1000] echo "$(date +'%k:%M')"'';
          font_size   = 115;
          font_family = "JetBrainsMono Nerd Font Bold";
          color       = "rgba(0, 255, 65, 0.9)";
          position    = "0, -150";
          halign      = "center";
          valign      = "top";
        }
        {
          text        = ''cmd[update:1000] echo "$(date +'%A, %B %d')"'';
          font_size   = 18;
          font_family = "JetBrainsMono Nerd Font";
          color       = "rgba(0, 255, 65, 0.9)";
          position    = "0, -350";
          halign      = "center";
          valign      = "top";
        }
      ];
      input-field = [{
        size             = "300, 50";
        position         = "0, 200";
        halign           = "center";
        valign           = "bottom";
        outer_color      = "rgba(0, 255, 65, 0.95)";
        inner_color      = "rgba(0, 30, 0, 0.5)";
        font_color       = "rgba(0, 255, 65, 0.9)";
        placeholder_text = "Enter Password";
        fade_on_empty    = false;
      }];
    };
  };

  # ── Hypridle ──────────────────────────────────────────────────────────
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd         = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
      };
      listener = [];
    };
  };

  # ── Quickshell systemd user service ───────────────────────────────────
  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell compositor shell";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type        = "simple";
      Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
      ExecStart   = "${pkgs.bash}/bin/bash -c 'exec quickshell -p %h/.config/hypr/scripts/quickshell-$(cat %h/.config/hypr/.qs_theme 2>/dev/null || printf modern)/Shell.qml'";
      Restart     = "always";
      RestartSec  = "1";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # ── Wallpaper daemon ───────────────────────────────────────────────────
  # Single owner of the awww daemon for the whole session, so the wallpaper
  # survives every reboot. Previously init-wallpaper, the quickshell monitor
  # popup and wall-change each spawned/killed their own daemon: two of those
  # racing (kill + immediate respawn, or the broken `pgrep -x awww-daemon`
  # guard, which never matches because the Nix wrapper renames the comm to
  # `.awww-daemon-wr`) make the newcomer panic with "already running on this
  # socket" — which can leave the session with no daemon and no wallpaper.
  systemd.user.services.awww-daemon = {
    Unit = {
      Description          = "awww wallpaper daemon";
      After                = [ "graphical-session.target" ];
      PartOf               = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      # Best effort: clear a stray non-service daemon holding the socket.
      ExecStartPre = "-${pkgs.awww}/bin/awww kill";
      ExecStart    = "${pkgs.awww}/bin/awww-daemon --no-cache";
      Restart      = "always";
      RestartSec   = "1";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # ── Border colour: self-heal at session start ─────────────────────────
  # Runs independently of init-wallpaper. If that script dies (bad wallpaper
  # path, matugen failure, missing PATH entry) the border still gets the
  # deepened colour instead of silently falling back to raw/default grey.
  systemd.user.services.border-colors = {
    Unit = {
      Description = "Apply deepened matugen border colours to Hyprland";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type      = "oneshot";
      ExecStart = "${apply-border-colors}";
      # Hyprland's IPC socket may not exist the instant the target is up.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Re-apply whenever matugen rewrites colors_raw.lua (wallpaper change).
  # Decouples applying the colour from whichever script invoked matugen.
  systemd.user.paths.border-colors = {
    Unit = {
      Description = "Watch matugen raw colours for changes";
      PartOf      = [ "graphical-session.target" ];
    };
    Path = {
      PathChanged = "%h/.config/hypr/colors_raw.lua";
      Unit        = "border-colors.service";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # ── Wallpapers + Scripts ───────────────────────────────────────────────
  home.activation.setupRice = lib.hm.dag.entryAfter ["linkGeneration"] ''
    mkdir -p "$HOME/.config/hypr/config"

    # colors.lua is owned by matugen. Seed it only so hyprland.lua has something
    # to require before matugen has ever run. inactive_border matches the
    # matugen template (rgba(00000000)).
    if [ ! -f "$HOME/.config/hypr/colors.lua" ]; then
      {
        echo 'return {'
        echo '  active_border   = "rgba(00FF41ee)",'
        echo '  inactive_border = "rgba(00000000)",'
        echo '}'
      } > "$HOME/.config/hypr/colors.lua"
    fi

    # Seed raw too, so the transform has an input on a brand-new install.
    if [ ! -f "$HOME/.config/hypr/colors_raw.lua" ]; then
      {
        echo 'return {'
        echo '  active_border   = "rgba(00FF41ee)",'
        echo '  inactive_border = "rgba(00000000)",'
        echo '}'
      } > "$HOME/.config/hypr/colors_raw.lua"
    fi

    chmod -R +x "$HOME/.config/hypr/scripts/" 2>/dev/null || true

    ${pkgs.python3}/bin/python3 - <<'PYEOF'
import json, os

f = os.path.expanduser("~/.config/hypr/settings.json")
try:
    with open(f) as fh:
        d = json.load(fh)
except Exception:
    d = {}

d["mouseSensitivity"]    = "${mouseSensitivity}"
d["touchpadSensitivity"] = "${touchpadSensitivity}"
# touchpadMouseDevice is written by load_info.sh — only set default if missing
if "touchpadMouseDevice" not in d:
    d["touchpadMouseDevice"] = "none"

defaults = {
    "wallpaperDir":       "${wallpaperDir}",
    "uiScale":            1,
    "openGuideAtStartup": False,
    "topbarHelpIcon":     False,
    "language":           "",
    "kbOptions":          "grp:alt_shift_toggle",
    "workspaceCount":     8,
}
for k, v in defaults.items():
    if k not in d:
        d[k] = v

os.makedirs(os.path.dirname(f), exist_ok=True)
with open(f, "w") as fh:
    json.dump(d, fh, indent=2)
PYEOF

    bash "$HOME/.config/hypr/scripts/settings_watcher.sh" --compile || true

    # Force Hyprland reload — HYPRLAND_INSTANCE_SIGNATURE isn't set in activation context
    # so hyprctl inside settings_watcher silently fails. Enumerate the socket dir instead.
    _hypr_sock_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
    if [ -d "$_hypr_sock_dir" ]; then
      for _inst_dir in "$_hypr_sock_dir"/*/; do
        [ -d "$_inst_dir" ] || continue
        _inst=$(basename "$_inst_dir")
        HYPRLAND_INSTANCE_SIGNATURE="$_inst" hyprctl reload 2>/dev/null && break
      done
    fi

    mkdir -p "$HOME/.local/bin"
    for f in ${./rice/scripts}/*.sh; do
      name=$(basename "$f" .sh)
      cp -f "$f" "$HOME/.local/bin/$name"
      chmod +x "$HOME/.local/bin/$name"
    done

    # Write QS theme file — only on first install; runtime switches via qs-theme.sh persist
    mkdir -p "$HOME/.config/hypr"
    [ ! -f "$HOME/.config/hypr/.qs_theme" ] && echo "${qsTheme}" > "$HOME/.config/hypr/.qs_theme"
  '';
}
