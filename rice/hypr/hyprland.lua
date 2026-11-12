-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ HYPRLAND — ROOT LUA CONFIG
--  Loaded instead of hyprland.conf (Hyprland 0.55+). The require order mirrors the
--  previous hyprlang `source` order exactly, so rule precedence and bind order are
--  preserved.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Runtime-generated modules (colors, config/*.lua) may not exist yet — e.g. on a fresh
-- install before settings_watcher/matugen have run. A missing module would otherwise kill
-- execution of *this* file, so every require is pcall-guarded.
local function load(name)
  local ok, mod = pcall(require, name)
  if not ok then
    hl.print("[hyprland.lua] require '" .. name .. "' failed: " .. tostring(mod))
    return nil
  end
  return mod
end

load("colors")
load("config.monitors")
load("config.env")
load("config.autostart")
load("config.variables")
load("config.settings")
load("config.rules")
load("config.keybindings")

-- ───────── passthru submap ─────────
-- Sentinel bind only; the submap is entered/exited from quickshell via
-- `hyprctl dispatch 'hl.dsp.submap("passthru"|"reset")'`.
hl.define_submap("passthru", function()
  hl.bind("SUPER + SHIFT + CTRL + ALT + F35", hl.dsp.exec_cmd("true"))
end)
