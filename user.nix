{ config, pkgs, lib, wallpaperDir, homeUser, inputSensitivity, ... }:

let
  cava-dynamic = pkgs.writeShellScriptBin "cava" ''
    mkdir -p ~/.config/cava
    cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null
    exec ${pkgs.cava}/bin/cava "$@"
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
      safe.directory = "/home/${homeUser}/RSFT";
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

  home.pointerCursor =
    let
      getFrom = url: hash: name: {
        gtk.enable = true;
        x11.enable = true;
        name = name;
        size = 24;
        package = pkgs.runCommand "moveUp" {} ''
          mkdir -p $out/share/icons
          ln -s ${pkgs.fetchzip { url = url; hash = hash; }}/dist $out/share/icons/${name}
        '';
      };
    in
      getFrom
        "https://github.com/yeyushengfan258/ArcMidnight-Cursors/archive/refs/heads/main.zip"
        "sha256-VgOpt0rukW0+rSkLFoF9O0xO/qgwieAchAev1vjaqPE="
        "ArcMidnight-Cursors";

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
  services.easyeffects.enable = true;

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
        on-click-right = "hyprctl dispatch exec '[float; center; size 950 650] kitty --override font_size=14 --title float_kitty btop'";
      };
      memory = {
        format   = "<span foreground='#00CC33'>󰟜 </span>{}%";
        interval = 2;
        on-click-right = "hyprctl dispatch exec '[float; center; size 950 650] kitty --override font_size=14 --title float_kitty btop'";
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
  # rules.conf and variables.conf are static — deployed as read-only symlinks.
  # settings.conf, autostart.conf, keybindings.conf, monitors.conf, env.conf
  # are generated at runtime by settings_watcher.sh from templates/.
  # colors.conf is generated at runtime by matugen.
  xdg.configFile."hypr/config/rules.conf".source     = ./rice/hypr/config/rules.conf;
  xdg.configFile."hypr/config/variables.conf".source = ./rice/hypr/config/variables.conf;
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
    package       = null;
    portalPackage = null;
    xwayland.enable = true;
    systemd.enable  = true;
    extraConfig = ''
      source = ~/.config/hypr/colors.conf

      submap = passthru
      bind = SUPER SHIFT CTRL ALT, F35, exec, true
      submap = reset

      source = ~/.config/hypr/config/monitors.conf
      source = ~/.config/hypr/config/env.conf
      source = ~/.config/hypr/config/autostart.conf
      source = ~/.config/hypr/config/variables.conf
      source = ~/.config/hypr/config/settings.conf
      source = ~/.config/hypr/config/rules.conf
      source = ~/.config/hypr/config/keybindings.conf
    '';
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

  # ── Wallpapers + Scripts ───────────────────────────────────────────────
  home.activation.setupRice = lib.hm.dag.entryAfter ["linkGeneration"] ''
    mkdir -p "$HOME/.config/hypr/config"

    if [ ! -f "$HOME/.config/hypr/colors.conf" ]; then
      echo '$active_border = rgba(00FF41ee)' > "$HOME/.config/hypr/colors.conf"
      echo '$inactive_border = rgba(33333388)' >> "$HOME/.config/hypr/colors.conf"
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

d["inputSensitivity"] = "${inputSensitivity}"

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

    bash "$HOME/.config/hypr/scripts/settings_watcher.sh" --compile 2>/dev/null || true

    mkdir -p "$HOME/.local/bin"
    for f in ${./rice/scripts}/*.sh; do
      name=$(basename "$f" .sh)
      cp -f "$f" "$HOME/.local/bin/$name"
      chmod +x "$HOME/.local/bin/$name"
    done
  '';
}
