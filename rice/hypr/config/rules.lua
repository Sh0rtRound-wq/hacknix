-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ WINDOW & LAYER RULES
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- ─────────────────────────────
-- Layer rules (OSD / overlays)
-- ─────────────────────────────
hl.layer_rule({ name = "volume-osd",     match = { namespace = "volume_osd" },     no_anim = true })
hl.layer_rule({ name = "brightness-osd", match = { namespace = "brightness_osd" }, no_anim = true })
hl.layer_rule({ name = "hyprpicker",     match = { namespace = "hyprpicker" },     no_anim = true })
hl.layer_rule({ name = "qsdock",         match = { namespace = "qsdock" },         no_anim = true })

hl.layer_rule({
  name         = "session-lock",
  match        = { namespace = "ext-session-lock" },
  blur         = true,
  ignore_alpha = 0.2,
})

-- ─────────────────────────────
-- Window rules
-- ─────────────────────────────

-- ───────── App Launcher ─────────
hl.window_rule({
  name      = "app-launcher-rules",
  match     = { title = "^(app-launcher)$" },
  float     = true,
  center    = true,
  size      = "1200 600",
  animation = "slide",
})

-- ───────── MASTER QUICKSHELL CONTAINER ─────────
-- All widgets now live inside this single, shape-shifting window.
-- (the previous windowrulev2 rules for qs-master remain disabled)
