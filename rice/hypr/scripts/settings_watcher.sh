#!/usr/bin/env bash

# settings_watcher.sh — compile settings.json + templates into Hyprland Lua config.
# Emits ~/.config/hypr/config/{env,settings,autostart,keybindings,monitors}.lua
# Consumed by ~/.config/hypr/hyprland.lua via require().
#
# Runs from two very different environments:
#   * the session (start hook / settings UI)      — full user PATH
#   * home-manager activation (`--compile`)       — a minimal PATH with no awk,
#     no hyprctl, no inotifywait
# so every tool used here must be found explicitly, and every generated file must
# be written atomically. A missing tool used to truncate the target file to zero
# bytes (e.g. `awk: command not found` -> empty monitors.lua -> the whole monitor
# layout reset on every rebuild) and the activation's reload then applied it.
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:$PATH"

# File paths
SETTINGS_FILE="$HOME/.config/hypr/settings.json"
WEATHER_SCRIPT="$HOME/.config/hypr/scripts/weather.sh"
ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

# Target configuration files (Lua)
CONF_DIR="$HOME/.config/hypr/config"
TMPL_DIR="$HOME/.config/hypr/templates"
SETTINGS_LUA="$CONF_DIR/settings.lua"
AUTOSTART_LUA="$CONF_DIR/autostart.lua"
ENV_LUA="$CONF_DIR/env.lua"
KEYBINDS_LUA="$CONF_DIR/keybindings.lua"
MONITORS_LUA="$CONF_DIR/monitors.lua"
ZSH_RC="$HOME/.zshrc"

# Ensure the required files and directories exist
mkdir -p "$CONF_DIR" "$TMPL_DIR" "$(dirname "$SETTINGS_FILE")" "$(dirname "$ENV_FILE")"
[ ! -f "$SETTINGS_FILE" ] && echo "{}" > "$SETTINGS_FILE"

CACHE_DIR="$HOME/.cache/settings_watcher"
mkdir -p "$CACHE_DIR"

# Lua string literal escaping: backslash, double-quote, newline.
lua_quote() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# hyprlang dispatcher name -> Lua dispatcher expression (best-effort; unknown => null)
dynamic_keybind_lua() {
    # stdin: one JSON object per line with keys: type, mods, key, dispatcher, command
    jq -r '
      def q: @json;
      def dir:  { "l":"left","r":"right","u":"up","d":"down","left":"left","right":"right","up":"up","down":"down" }[.];
      def dsp:
        if   .dispatcher == "exec"            then "hl.dsp.exec_cmd(" + ((.command // "")|q) + ")"
        elif .dispatcher == "killactive"      then "hl.dsp.window.close()"
        elif .dispatcher == "togglefloating"  then "hl.dsp.window.float({ action = \"toggle\" })"
        elif .dispatcher == "fullscreen"      then "hl.dsp.window.fullscreen()"
        elif .dispatcher == "centerwindow"    then "hl.dsp.window.center()"
        elif .dispatcher == "pseudo"          then "hl.dsp.window.pseudo()"
        elif .dispatcher == "pin"             then "hl.dsp.window.pin()"
        elif .dispatcher == "movefocus"       then "hl.dsp.focus({ direction = " + ((.command // "left")|dir|q) + " })"
        elif .dispatcher == "movewindow"      then "hl.dsp.window.move({ direction = " + ((.command // "left")|dir|q) + " })"
        elif .dispatcher == "workspace"       then "hl.dsp.focus({ workspace = " + ((.command // "1")|q) + " })"
        elif .dispatcher == "movetoworkspace" then "hl.dsp.window.move({ workspace = " + ((.command // "1")|q) + " })"
        elif .dispatcher == "submap"          then "hl.dsp.submap(" + ((.command // "reset")|q) + ")"
        else null end;
      def flags:
        ([ (if (.type // "bind") | test("l") then "locked = true" else empty end),
           (if (.type // "bind") | test("e") then "repeating = true" else empty end),
           (if (.type // "bind") | test("r") then "release = true" else empty end),
           (if (.type // "bind") | test("m") then "mouse = true" else empty end) ] | join(", "));
      def keyexpr:
        ( (.mods // "") | gsub("\\$mainMod"; "mainMod") ) as $m
        | (.key // "") as $k
        | ($m | split(" ") | map(select(length > 0))) as $toks
        | if ($toks | map(select(. == "mainMod")) | length) > 0
          then "mainMod .. \" + " + ([ $toks[] | if . == "mainMod" then empty else . end ] + [$k] | join(" + ")) + "\""
          else ([ $toks ] + [$k] | join(" + ")) | q end;
      select((.dispatcher // "") != "")
      | (dsp) as $d
      | if $d == null then
          "-- TODO: unmapped dispatcher \"" + (.dispatcher // "") + "\" for " + (.mods // "") + " " + (.key // "")
        else
          "hl.bind(" + (keyexpr) + ", " + $d + (if flags == "" then "" else ", { " + flags + " }" end) + ")"
        end
    '
}

# render_template <template> <placeholder> <replacement-file> <output>
# Substitutes a placeholder line with the contents of a file, then swaps the
# result in atomically. Refuses to install an empty result, so a failure can
# never wipe a working config (that is what reset the monitor layout).
render_template() {
    local tmpl="$1" ph="$2" body="$3" out="$4" tmp
    [ -f "$tmpl" ] || { echo "render_template: missing template $tmpl" >&2; return 1; }
    tmp="$(mktemp "${out}.XXXXXX")"
    if [ -s "$body" ]; then
        sed -e "/$ph/r $body" -e "/$ph/d" "$tmpl" > "$tmp" || { rm -f "$tmp"; return 1; }
    else
        sed -e "/$ph/d" "$tmpl" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    if [ ! -s "$tmp" ]; then
        echo "render_template: empty result for $out — keeping existing file" >&2
        rm -f "$tmp"; return 1
    fi
    mv -f "$tmp" "$out"
}

compile_settings() {
    # Hard requirement check: without these the compiler would silently emit
    # gutted configs (a missing jq meant monitors.lua was rewritten with only the
    # fallback rule, i.e. the monitor layout reset). Bail out before touching
    # anything instead.
    local _missing=""
    for _t in jq sed install mktemp md5sum find; do
        command -v "$_t" >/dev/null 2>&1 || _missing="$_missing $_t"
    done
    if [ -n "$_missing" ]; then
        echo "settings_watcher: missing required tool(s):$_missing — not regenerating" >&2
        return 1
    fi

    echo "Regenerating configurations from templates (lua)..."

    # Hash existing configs before any changes, split by monitor vs non-monitor.
    OLD_NONMON_HASH=$(md5sum "$SETTINGS_LUA" "$KEYBINDS_LUA" "$AUTOSTART_LUA" "$ENV_LUA" 2>/dev/null | md5sum)
    OLD_MON_HASH=$(md5sum "$MONITORS_LUA" 2>/dev/null | md5sum)

    LANG=$(jq -r '.language // "us"' "$SETTINGS_FILE")
    KB_OPT=$(jq -r '.kbOptions // "grp:alt_shift_toggle"' "$SETTINGS_FILE")
    MOUSE_SENSITIVITY=$(jq -r '.mouseSensitivity // "-0.1"' "$SETTINGS_FILE")
    TOUCHPAD_SENSITIVITY=$(jq -r '.touchpadSensitivity // "1.0"' "$SETTINGS_FILE")
    _TOUCHPAD_STORED=$(jq -r '.touchpadMouseDevice // "none"' "$SETTINGS_FILE")
    # Self-heal the touchpad device name. It is normally written by load_info.sh, which
    # only runs when setting up a machine — so a fresh/regenerated settings.json, or any
    # box where load_info.sh was never run, ends up with "none". With "none" both device
    # blocks below match no device, Hyprland silently ignores them, and the touchpad
    # inherits the global input:sensitivity (the *mouse* value) — i.e. mouse and touchpad
    # end up the same speed, with no error. Detect it here instead.
    if [ -z "$_TOUCHPAD_STORED" ] || [ "$_TOUCHPAD_STORED" = "none" ]; then
        _TD_DETECT=$(grep -iE '^N: Name=.*(touchpad|trackpad|clickpad)' /proc/bus/input/devices 2>/dev/null \
            | head -1 | sed 's/N: Name="//;s/"//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        if [ -n "$_TD_DETECT" ] && [ "$_TD_DETECT" != "none" ]; then
            _TOUCHPAD_STORED="$_TD_DETECT"
            _td_tmp="$(mktemp "$SETTINGS_FILE.XXXXXX")"
            if jq --arg td "$_TD_DETECT" '.touchpadMouseDevice = $td' "$SETTINGS_FILE" > "$_td_tmp" 2>/dev/null && [ -s "$_td_tmp" ]; then
                mv -f "$_td_tmp" "$SETTINGS_FILE"
            else
                rm -f "$_td_tmp"
            fi
        fi
    fi
    if [ "$_TOUCHPAD_STORED" = "none" ]; then
        TOUCHPAD_MOUSE_DEV="none"
        TOUCHPAD_DEV="none"
    else
        _TD_BASE=$(echo "$_TOUCHPAD_STORED" | sed 's/-mouse$//;s/-touchpad$//')
        TOUCHPAD_MOUSE_DEV="${_TD_BASE}-mouse"
        TOUCHPAD_DEV="${_TD_BASE}-touchpad"
    fi
    WP_DIR=$(jq -r '.wallpaperDir // empty' "$SETTINGS_FILE")
    GUIDE_STARTUP=$(jq -r 'if has("openGuideAtStartup") then .openGuideAtStartup else true end' "$SETTINGS_FILE")

    PIC_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
    VID_DIR="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"

    HW_ENV=$(jq -r '.hardwareEnvs[]? // empty' "$SETTINGS_FILE")
    WS_COUNT=$(jq -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null)
    [[ "$WS_COUNT" =~ ^[0-9]+$ ]] || WS_COUNT=8
    PER_MON_WS=$(jq -r 'if has("perMonitorWorkspaces") then .perMonitorWorkspaces else true end' "$SETTINGS_FILE" 2>/dev/null)

    # 1. env.lua — hardwareEnvs entries are "env = NAME,VALUE" lines.
    echo "Regenerating env.lua..."
    HW_ENV_LUA=$(printf '%s\n' "$HW_ENV" | sed -n 's/^[[:space:]]*env[a-z]*[[:space:]]*=[[:space:]]*//p' | while IFS= read -r line; do
        [ -n "$line" ] || continue
        name="${line%%,*}"
        value="${line#*,}"
        [ "$name" = "$line" ] && continue   # no comma => no name/value pair
        printf 'hl.env("%s", "%s")\n' "$name" "$(lua_quote "$value")"
    done)
    printf '%s\n' "$HW_ENV_LUA" > "$CACHE_DIR/env_body.lua"
    render_template "$TMPL_DIR/env.lua.template" "{{HARDWARE_ENV}}" "$CACHE_DIR/env_body.lua" "$ENV_LUA"

    # Sync ZSH_RC if Wallpaper Dir changed
    if [ -n "$WP_DIR" ] && [ -f "$ZSH_RC" ]; then
        sed -i "s|^export WALLPAPER_DIR=.*|export WALLPAPER_DIR=\"$WP_DIR\"|" "$ZSH_RC"
    fi

    # 2. settings.lua from template
    echo "Regenerating settings.lua..."
    _tmp="$(mktemp "$SETTINGS_LUA.XXXXXX")"
    if sed -e "s|{{KB_LAYOUT}}|$LANG|g" \
        -e "s|{{KB_OPTIONS}}|$KB_OPT|g" \
        -e "s|{{MOUSE_SENSITIVITY}}|$MOUSE_SENSITIVITY|g" \
        -e "s|{{TOUCHPAD_SENSITIVITY}}|$TOUCHPAD_SENSITIVITY|g" \
        -e "s|{{TOUCHPAD_MOUSE_DEV}}|$TOUCHPAD_MOUSE_DEV|g" \
        -e "s|{{TOUCHPAD_DEV}}|$TOUCHPAD_DEV|g" \
        "$TMPL_DIR/settings.lua.template" > "$_tmp" && [ -s "$_tmp" ]; then
        mv -f "$_tmp" "$SETTINGS_LUA"
    else
        echo "settings.lua generation failed — keeping existing file" >&2
        rm -f "$_tmp"
    fi

    # 3. autostart.lua
    echo "Regenerating autostart.lua..."
    DYNAMIC_STARTUP=$(jq -r '.startup[]? | "    hl.exec_cmd(\(.command|@json))"' "$SETTINGS_FILE")
    if [[ "$GUIDE_STARTUP" == "true" ]]; then
        DYNAMIC_STARTUP="${DYNAMIC_STARTUP}
    hl.exec_cmd(\"bash -c 'sleep 1 && ~/.config/hypr/scripts/qs_manager.sh toggle guide'\")"
    fi
    printf '%s\n' "$DYNAMIC_STARTUP" > "$CACHE_DIR/startup_body.lua"
    render_template "$TMPL_DIR/autostart.lua.template" "{{DYNAMIC_STARTUP}}" "$CACHE_DIR/startup_body.lua" "$AUTOSTART_LUA"

    # 4. keybindings.lua
    echo "Regenerating keybindings.lua..."
    _tmp="$(mktemp "$KEYBINDS_LUA.XXXXXX")"
    if install -m 644 "$TMPL_DIR/keybinds.lua.template" "$_tmp" && [ -s "$_tmp" ]; then
        { jq -c '.keybinds[]? | {type: (.type // "bind"), mods: (.mods // ""), key: (.key // ""), dispatcher: (.dispatcher // "exec"), command: (.command // "")}' "$SETTINGS_FILE" \
            | dynamic_keybind_lua; } >> "$_tmp" 2>/dev/null || true
        mv -f "$_tmp" "$KEYBINDS_LUA"
    else
        echo "keybindings.lua generation failed — keeping existing file" >&2
        rm -f "$_tmp"
    fi

    # 5. monitors.lua
    echo "Regenerating monitors.lua..."
    MONITOR_COUNT=$(jq '.monitors | length' "$SETTINGS_FILE" 2>/dev/null)
    {
        # Fallback first (matches any unrecognised output), then explicit monitors.
        echo 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })'
        if [[ "${MONITOR_COUNT:-0}" -gt 0 ]]; then
            jq -r '.monitors[]? | "hl.monitor({ output = \(.name|@json), mode = \(("\(.resW)x\(.resH)@\(.rate)")|@json), position = \(("\(.x)x\(.y)")|@json), scale = \(.scale)\(if .transform and .transform != 0 then ", transform = \(.transform)" else "" end) })"' "$SETTINGS_FILE"
        fi
        echo 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })'
        # ── Per-monitor workspaces ────────────────────────────────────────────
        # Each monitor owns its own slots 1..workspaceCount, mapped to disjoint
        # real workspace IDs (<monitor index> * 10 + slot) and pinned to that
        # monitor, so "send this to workspace 2" always means workspace 2 *of the
        # focused monitor*. Monitor index = left-to-right by live x position
        # (falls back to the settings.json order when hyprctl is unavailable).
        # Set "perMonitorWorkspaces": false in settings.json for one global set.
        if [[ "$PER_MON_WS" == "true" ]]; then
            MON_ORDER=$(hyprctl monitors -j 2>/dev/null | jq -r 'sort_by(.x) | .[].name' 2>/dev/null || true)
            [ -n "$MON_ORDER" ] || MON_ORDER=$(jq -r '(.monitors // []) | .[].name' "$SETTINGS_FILE" 2>/dev/null)
            _mi=0
            while IFS= read -r _mon; do
                [ -n "$_mon" ] || continue
                for _s in $(seq 1 "$WS_COUNT"); do
                    echo "hl.workspace_rule({ workspace = \"$((_mi * 10 + _s))\", monitor = \"$_mon\" })"
                done
                _mi=$((_mi + 1))
            done <<< "$MON_ORDER"
        fi
    } > "$CACHE_DIR/monitors_body.lua"
    render_template "$TMPL_DIR/monitors.lua.template" "{{MONITORS}}" "$CACHE_DIR/monitors_body.lua" "$MONITORS_LUA"

    # Hash after changes
    NEW_NONMON_HASH=$(md5sum "$SETTINGS_LUA" "$KEYBINDS_LUA" "$AUTOSTART_LUA" "$ENV_LUA" 2>/dev/null | md5sum)
    NEW_MON_HASH=$(md5sum "$MONITORS_LUA" 2>/dev/null | md5sum)

    if [ "$OLD_MON_HASH" != "$NEW_MON_HASH" ]; then
        echo "Monitor config changed, reloading Hyprland..."
        hyprctl reload
    elif [ "$OLD_NONMON_HASH" != "$NEW_NONMON_HASH" ]; then
        echo "Non-monitor config changed, reloading Hyprland..."
        hyprctl reload
    else
        echo "No Hyprland config changes detected, skipping reload."
    fi
}

# If called with --compile, execute once and exit (used by install.sh)
if [[ "$1" == "--compile" ]]; then
    compile_settings
    exit 0
fi

compile_settings

echo "Started watching settings directories for changes..."

inotifywait -m -q -e close_write,moved_to --format '%w%f' "$(dirname "$SETTINGS_FILE")" "$(dirname "$ENV_FILE")" | while read -r filepath; do

    if [[ "$filepath" == "$SETTINGS_FILE" ]]; then
        compile_settings
    fi

    if [[ "$filepath" == "$ENV_FILE" ]]; then
        echo ".env updated! Forcing weather cache refresh..."
        if [ -x "$WEATHER_SCRIPT" ]; then
            "$WEATHER_SCRIPT" --getdata &
        else
            bash "$WEATHER_SCRIPT" --getdata &
        fi
    fi
done
