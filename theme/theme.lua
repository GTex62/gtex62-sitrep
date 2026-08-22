-- gtex62-sitrep Conky Theme

----------------------------------------------------------------
-- Shared Theme Core
----------------------------------------------------------------
local theme = {}
local HOME = os.getenv("HOME") or ""
local CORE_DIR = os.getenv("GTEX62_CORE_DIR")
    or os.getenv("GTEX62_CONKY_ENGINE_DIR")
    or (HOME .. "/.config/conky/gtex62-core")
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-sitrep")
local palette_catalog = dofile(SUITE_DIR .. "/theme/palettes.lua")

local function load_engine_runtime()
  local ok, runtime = pcall(dofile, CORE_DIR .. "/lua/runtime/window.lua")
  if ok and type(runtime) == "table" then
    return runtime
  end
  return nil
end

local engine_runtime = load_engine_runtime()

-- Monitor selection (0 = primary, 1 = secondary). Provisional — pending final
-- size/placement confirmation once SitRep is actually laid out on-screen.
theme.monitor_head = 1

-- Palette (own catalog — env override mirrors OSA's CONKY_OSA_PALETTE pattern)
theme.default_palette = palette_catalog.default or "amber"
theme.active_palette = os.getenv("CONKY_SITREP_PALETTE") or theme.default_palette
theme.palettes = palette_catalog.palettes or {}

theme.palette = theme.palettes[theme.active_palette] or theme.palettes[theme.default_palette]
theme.resolved_palette = theme.palette == theme.palettes[theme.active_palette]
    and theme.active_palette
    or theme.default_palette

theme.colors = {
  bg = theme.palette.bg,
  fg = theme.palette.fg,
  ink = theme.palette.ink,
}

theme.roles = {
  background = theme.colors.bg,
  foreground = theme.colors.fg,
  fill = theme.colors.fg,
  inverse_text = theme.colors.ink,
}

theme.strokes = {
  line = 1,
  frame = 8,
  frame_alpha = 0.99,
}

----------------------------------------------------------------
-- Theme FX
----------------------------------------------------------------
theme.frame_shadow = {
  enabled = true,
  color = { 0.0, 0.0, 0.0 },
  alpha_scale = 1.25,
  sides = { 1, 1, 1, 1 },                -- top, right, bottom, left
  side_alpha = { 1.0, 0.45, 0.45, 1.0 }, -- top, right, bottom, left
  bands = {
    { offset = 8.0,  width = 8.0, alpha = 0.40 },
    { offset = 10.0, width = 8.0, alpha = 0.30 },
    { offset = 12.0, width = 8.0, alpha = 0.20 },
    { offset = 16.0, width = 8.0, alpha = 0.10 },
  },
}

theme.frame_lights = {
  enabled = "auto",
  auto_bg_threshold = 0.70,
  color_mode = "auto",
  color_lift = 0.16,
  color_warmth = { 0.06, 0.03, 0.00 },
  radius_scale = 1.0,
  radius_y_scale = 1.0,
  alpha_scale = 1.0,
  top_frame_y_offset = 18,
  -- 2 fixtures at 290px apart (vs. OSA's 6, same 290px gap, across its
  -- ~2.3x wider frame) — same per-light spacing as OSA, just fewer of them
  -- to fit SitRep's narrower 750px frame. Each fixture reuses OSA's exact
  -- 6-layer glow stack below unchanged (same lit-panel look/identity
  -- across suites), only the count differs.
  light_count = 2,
  light_gap = 290,
  lights = {
    {
      x = "center",
      y = 10,
      radius = 11.451,
      radius_y = 6.972,
      color = { 1.0, 0.90, 0.90 },
      alpha = 0.7,
    },
    {
      x = "center",
      y = 22,
      radius = 22.37,
      radius_y = 7.465,
      color = { 1.0, 0.89, 0.86 },
      alpha = 0.12,
    },
    {
      x = "center",
      y = 24,
      radius = 20.248,
      radius_y = 9.704,
      color = { 1.0, 0.88, 0.82 },
      alpha = 0.22,
    },
    {
      x = "center",
      y = 26,
      radius = 28.087,
      radius_y = 12.69,
      color = { 1.0, 0.86, 0.78 },
      alpha = 0.20,
    },
    {
      x = "center",
      y = 28,
      radius = 39.192,
      radius_y = 16.423,
      color = { 1.0, 0.84, 0.74 },
      alpha = 0.16,
    },
    {
      x = "center",
      y = "top_frame",
      radius = 53.561,
      radius_y = 30.902,
      color = { 1.0, 0.82, 0.70 },
      alpha = 0.3,
    },
  },
}

----------------------------------------------------------------
-- Fonts
----------------------------------------------------------------
theme.fonts = {
  title = "Eurostile LT Std",
  data = "GTex62 OSA",
}

theme.text = {
  panel_title_pt = 21,
  body_pt = 18,
  body_sm_pt = 16,
  body_xs_pt = 14,
  micro_pt = 12,
}

theme.spacing = {
  grid = 8,
  title_pad_x = 32,
  title_clearance = 8,
  box_title_x = 20,
}

function theme.session_text_scale()
  if engine_runtime and engine_runtime.session_text_scale then
    return engine_runtime.session_text_scale()
  end
  return 1.0
end

function theme.window_size(frame)
  if engine_runtime and engine_runtime.window_size then
    return engine_runtime.window_size(frame)
  end
  frame = frame or {}
  local scale = theme.session_text_scale()
  return {
    width = math.floor(((frame.width or 900) / scale) + 0.5),
    height = math.floor(((frame.height or 1200) / scale) + 0.5),
  }
end

function theme.core_dir()
  return CORE_DIR
end

function theme.engine_dir()
  return CORE_DIR
end

function theme.using_engine_runtime()
  return engine_runtime ~= nil
end

return theme
