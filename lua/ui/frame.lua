---@diagnostic disable: undefined-global
-- Chassis-level drawing only: background, frame shadow/lights FX, panel
-- box + title. No SitRep-specific panel content lives here — that is
-- future work once real panel geometry and data sources are decided.
-- Structural mirror of gtex62-osa/lua/ui/frame.lua, trimmed to the pieces
-- this scaffold actually needs.

local M = {}
local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-sitrep")
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")

local FOOTER_VERSION_CACHE = {
  tick = nil,
  label = nil,
}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Reads a single top-level `key = value` out of a TOML file (no section
-- handling needed here — version = "..." lives above any [section] in
-- both core.toml and suite.toml). Mirrors gtex62-osa/lua/ui/frame.lua's
-- simple_toml_value().
local function simple_toml_value(path, key)
  local s = read_file(path)
  if not s then return nil end

  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local parsed_key, value = line:match("^([%w_%-]+)%s*=%s*(.+)$")
    if parsed_key == key then
      return value:gsub('^"', ""):gsub('"$', "")
    end
  end

  return nil
end

-- Builds the chassis footer's version-identity string from the real
-- CORE and STRP versions, cached per-tick (os.time()) since draw_chassis_footer
-- runs every conky refresh. CORE comes from the deployed runtime's
-- core.toml (RUNTIME_ROOT), not this repo — gtex62-core has no in-repo
-- version file, only the runtime copy written by
-- gtex62-core-bootstrap-runtime. STRP comes from this repo's own
-- suite.toml. Mirrors gtex62-osa/lua/ui/frame.lua's version_identity_label().
local function version_identity_label()
  local tick = os.time()
  if FOOTER_VERSION_CACHE.tick == tick and FOOTER_VERSION_CACHE.label then
    return FOOTER_VERSION_CACHE.label
  end

  local core_version = simple_toml_value(RUNTIME_ROOT .. "/core.toml", "version")
    or simple_toml_value(RUNTIME_ROOT .. "/engine.toml", "version")
    or "UNKNOWN"
  local suite_version = simple_toml_value(SUITE_DIR .. "/suite.toml", "version")
    or simple_toml_value(RUNTIME_ROOT .. "/suites/sitrep.toml", "version")
    or "UNKNOWN"

  FOOTER_VERSION_CACHE.tick = tick
  FOOTER_VERSION_CACHE.label = string.format(
    "CORE %s // STRP %s",
    string.upper(core_version),
    string.upper(suite_version)
  )

  return FOOTER_VERSION_CACHE.label
end

local function set_rgb(cr, color)
  cairo_set_source_rgb(cr, color[1], color[2], color[3])
end

local function set_rgba(cr, color, alpha)
  cairo_set_source_rgba(cr, color[1], color[2], color[3], alpha)
end

local function draw_rect(cr, x, y, w, h, line_width, color)
  cairo_set_line_width(cr, line_width)
  set_rgb(cr, color)
  cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1, h - 1)
  cairo_stroke(cr)
end

local function fill_rect(cr, x, y, w, h, color)
  set_rgb(cr, color)
  cairo_rectangle(cr, x, y, w, h)
  cairo_fill(cr)
end

local function draw_vline(cr, x, y0, y1, line_width, color)
  cairo_set_line_width(cr, line_width)
  set_rgb(cr, color)
  cairo_move_to(cr, x + 0.5, y0)
  cairo_line_to(cr, x + 0.5, y1)
  cairo_stroke(cr)
end

local function draw_hline(cr, x0, x1, y, line_width, color)
  cairo_set_line_width(cr, line_width)
  set_rgb(cr, color)
  cairo_move_to(cr, x0, y + 0.5)
  cairo_line_to(cr, x1, y + 0.5)
  cairo_stroke(cr)
end

local function draw_text_left(cr, x, y, text, font_face, font_pt, color)
  if not text or text == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_pt)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, text)
end

-- Same "-TITLE-" text-metrics convention as draw_inline_title, but plain
-- (no bg cutout) and centered on (x, y) — used for table cell content.
local function draw_text_center_mid(cr, x, y, text, font_face, font_pt, color, weight)
  if not text or text == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_pt)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, text, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + (ext.height / 2))
  cairo_show_text(cr, text)
end

-- Vertically-centered-on-y left-aligned text — same text-metrics
-- convention as draw_text_center_mid, anchored left instead of center.
local function draw_text_left_mid(cr, x, y, text, font_face, font_pt, color, weight)
  if not text or text == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_pt)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, text, ext)
  cairo_move_to(cr, x, y + (ext.height / 2))
  cairo_show_text(cr, text)
end

-- Vertically-centered-on-y right-aligned text — used for kv-table
-- values (right-aligned data, same convention as OSA's table rows).
local function draw_text_right_mid(cr, x, y, text, font_face, font_pt, color, weight)
  if not text or text == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, font_face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, font_pt)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, text, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y + (ext.height / 2))
  cairo_show_text(cr, text)
end

-- Filled table-cell header: fg-filled rect with the label centered in
-- ink color — same look as OSA's meter/table headers (osa/lua/ui/frame.lua
-- draw_table_header).
local function draw_table_header(cr, x, y, w, h, label, font_pt, theme)
  fill_rect(cr, x, y, w, h, theme.colors.fg)
  draw_text_center_mid(cr, x + (w / 2), y + (h / 2), label, theme.fonts.data, font_pt, theme.colors.ink,
    CAIRO_FONT_WEIGHT_NORMAL)
end

-- Generic label/value table: a draw_table_header cell followed by N
-- rows, label left-aligned and value right-aligned per row (same
-- right-aligned-data convention as OSA's table rows). `rows` is a
-- list of { label = "...", value = "..." } — an empty label is valid
-- (a value-only row, e.g. PI-HOLE's "38%" line under BLOCKED). Shared
-- by PI-HOLE's TOTALS column and both of PFBLOCKERNG's columns —
-- anywhere content is genuinely tabular key/value pairs, as opposed
-- to WAN/VPN's mixed meter+free-text layouts.
local function draw_kv_table(cr, x, y, w, cfg, theme, header_label, rows)
  local header_h = tonumber(cfg.header_h) or 16
  local header_font_pt = tonumber(cfg.header_font_pt) or theme.text.body_sm_pt
  local row_gap = tonumber(cfg.row_gap) or 2
  local row_h = tonumber(cfg.row_h) or 16
  local row_font_pt = tonumber(cfg.row_font_pt) or theme.text.body_xs_pt
  local label_x_pad = tonumber(cfg.label_x_pad) or 0
  local value_x_pad = tonumber(cfg.value_x_pad) or 0

  draw_table_header(cr, x, y, w, header_h, header_label, header_font_pt, theme)

  local row_y = y + header_h + row_gap
  for i, row in ipairs(rows or {}) do
    local mid_y = row_y + ((i - 1) * row_h) + (row_h / 2)
    draw_text_left_mid(cr, x + label_x_pad, mid_y, row.label or "", theme.fonts.data, row_font_pt, theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL)
    draw_text_right_mid(cr, x + w - value_x_pad, mid_y, row.value or "", theme.fonts.data, row_font_pt,
      theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
  end
end

-- Even-odd-fill hollow rectangle, exact stroke width regardless of line
-- position (unlike draw_rect's centered cairo_stroke). Used for the outer
-- chassis border, same technique as OSA's frame.lua.
local function draw_frame_rect(cr, x, y, w, h, line_width, color, alpha)
  local stroke = tonumber(line_width) or 1
  local inner_w = math.max(0, w - (stroke * 2))
  local inner_h = math.max(0, h - (stroke * 2))
  set_rgba(cr, color, tonumber(alpha) or 1.0)
  cairo_save(cr)
  cairo_new_path(cr)
  cairo_rectangle(cr, x, y, w, h)
  cairo_rectangle(cr, x + stroke, y + stroke, inner_w, inner_h)
  cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
  cairo_fill(cr)
  cairo_restore(cr)
end

local function resolve_scale(layout)
  local mode = layout and layout.scale_mode or "manual"
  if mode == "auto" then
    local w = tonumber(os.getenv("CONKY_SCREEN_W"))
    local h = tonumber(os.getenv("CONKY_SCREEN_H"))
    local bw = layout.frame and tonumber(layout.frame.width)
    local bh = layout.frame and tonumber(layout.frame.height)
    if w and h and bw and bh and bw > 0 and bh > 0 then
      return math.min(w / bw, h / bh)
    end
  end
  return tonumber(layout and layout.scale) or 1.0
end

local function panel_col_x(panel, layout)
  local cols = layout and layout.columns
  local col = panel and panel.column
  if col and cols and cols[col] then
    return tonumber(cols[col].x) or (tonumber(panel.x) or 0)
  end
  return tonumber(panel.x) or 0
end

local function resolve_panels(panels_tbl, layout)
  local resolved = {}
  for name, panel in pairs(panels_tbl) do
    if type(panel) == "table" then
      local rp = {}
      for k, v in pairs(panel) do rp[k] = v end
      rp.x = panel_col_x(panel, layout)
      resolved[name] = rp
    else
      resolved[name] = panel
    end
  end
  return resolved
end

local function clamp01(value)
  return math.max(0, math.min(1, tonumber(value) or 0))
end

local function color_luma(color)
  color = color or { 0, 0, 0 }
  return ((tonumber(color[1]) or 0) * 0.2126)
      + ((tonumber(color[2]) or 0) * 0.7152)
      + ((tonumber(color[3]) or 0) * 0.0722)
end

local function draw_soft_circle(cr, cx, cy, radius_x, radius_y, color, alpha)
  alpha = tonumber(alpha) or 1.0
  radius_y = tonumber(radius_y) or radius_x

  if cairo_pattern_create_radial and cairo_pattern_add_color_stop_rgba and cairo_set_source and cairo_pattern_destroy then
    local pattern = cairo_pattern_create_radial(cx, cy, 0, cx, cy, radius_x)
    cairo_pattern_add_color_stop_rgba(pattern, 0.00, color[1], color[2], color[3], alpha)
    cairo_pattern_add_color_stop_rgba(pattern, 0.68, color[1], color[2], color[3], alpha * 0.82)
    cairo_pattern_add_color_stop_rgba(pattern, 1.00, color[1], color[2], color[3], alpha * 0.20)
    cairo_save(cr)
    cairo_translate(cr, cx, cy)
    cairo_scale(cr, 1, radius_y / radius_x)
    cairo_translate(cr, -cx, -cy)
    cairo_set_source(cr, pattern)
    cairo_arc(cr, cx, cy, radius_x, 0, 2 * math.pi)
    cairo_fill(cr)
    cairo_restore(cr)
    cairo_pattern_destroy(pattern)
    return
  end

  cairo_save(cr)
  cairo_translate(cr, cx, cy)
  cairo_scale(cr, 1, radius_y / radius_x)
  cairo_translate(cr, -cx, -cy)
  set_rgba(cr, color, alpha)
  cairo_arc(cr, cx, cy, radius_x, 0, 2 * math.pi)
  cairo_fill(cr)
  cairo_restore(cr)
end

local function frame_lights_enabled(cfg, theme)
  local enabled = cfg.enabled
  if enabled == nil or enabled == true or enabled == "on" or enabled == "true" then
    return true
  end
  if enabled == false or enabled == "off" or enabled == "false" then
    return false
  end

  local threshold = tonumber(cfg.auto_bg_threshold) or 0.70
  return color_luma(theme.colors and theme.colors.bg) >= threshold
end

local function frame_light_color(cfg, theme, fallback)
  if cfg.color_mode ~= "auto" then
    return fallback
  end

  local bg = (theme.colors and theme.colors.bg) or { 0, 0, 0 }
  local lift = tonumber(cfg.color_lift) or 0
  local warmth = cfg.color_warmth or {}
  return {
    clamp01((bg[1] or 0) + lift + (tonumber(warmth[1]) or 0)),
    clamp01((bg[2] or 0) + lift + (tonumber(warmth[2]) or 0)),
    clamp01((bg[3] or 0) + lift + (tonumber(warmth[3]) or 0)),
  }
end

local function draw_frame_lights(cr, frame, theme)
  local cfg = theme.frame_lights or {}
  if not frame_lights_enabled(cfg, theme) then
    return
  end

  local lights = cfg.lights or {}
  if #lights == 0 then
    return
  end

  local stroke = tonumber(theme.strokes and (theme.strokes.frame or theme.strokes.line)) or 1
  local top_frame_y_offset = tonumber(cfg.top_frame_y_offset) or 0
  local light_count = math.max(1, math.floor(tonumber(cfg.light_count) or 1))
  local light_gap = tonumber(cfg.light_gap) or 0
  local radius_scale = tonumber(cfg.radius_scale) or 1
  local radius_y_scale = tonumber(cfg.radius_y_scale) or 1
  local alpha_scale = tonumber(cfg.alpha_scale) or 1
  local row_center_x = frame.x + (frame.width / 2)

  cairo_save(cr)
  cairo_rectangle(cr, frame.x + stroke, frame.y + stroke, math.max(0, frame.width - (stroke * 2)),
    math.max(0, frame.height - (stroke * 2)))
  cairo_clip(cr)

  for _, light in ipairs(lights) do
    local radius = (tonumber(light.radius) or 20) * radius_scale
    local radius_y = (tonumber(light.radius_y) or radius) * radius_y_scale
    local alpha = clamp01((tonumber(light.alpha) or 1) * alpha_scale)
    local color = frame_light_color(cfg, theme, light.color or { 1.0, 0.72, 0.28 })
    local cy = light.y == "top_frame" and (frame.y + stroke + top_frame_y_offset) or
    (frame.y + (tonumber(light.y) or stroke))
    if light.x == "center" then
      for light_index = 1, light_count do
        local cx = row_center_x + ((light_index - ((light_count + 1) / 2)) * light_gap)
        draw_soft_circle(cr, cx, cy, radius, radius_y, color, alpha)
      end
    else
      local cx = frame.x + (tonumber(light.x) or 0)
      draw_soft_circle(cr, cx, cy, radius, radius_y, color, alpha)
    end
  end

  cairo_restore(cr)
end

local function side_enabled(sides, index)
  if type(sides) ~= "table" or sides[index] == nil then
    return true
  end
  return sides[index] == true or sides[index] == 1 or sides[index] == "1" or sides[index] == "on" or
  sides[index] == "true"
end

local function side_alpha(side_alpha_values, index)
  if type(side_alpha_values) ~= "table" or side_alpha_values[index] == nil then
    return 1.0
  end
  return clamp01(side_alpha_values[index])
end

local function draw_frame_shadow(cr, frame, theme)
  local cfg = theme.frame_shadow or {}
  if cfg.enabled == false then
    return
  end

  local color = cfg.color or { 0.0, 0.0, 0.0 }
  local alpha_scale = tonumber(cfg.alpha_scale) or 1
  local sides = cfg.sides or {}
  local side_alpha_values = cfg.side_alpha or {}
  local bands = cfg.bands or {}
  if #bands == 0 then
    return
  end

  local x = frame.x
  local y = frame.y
  local w = frame.width
  local h = frame.height
  local draw_top = side_enabled(sides, 1)
  local draw_right = side_enabled(sides, 2)
  local draw_bottom = side_enabled(sides, 3)
  local draw_left = side_enabled(sides, 4)
  local top_alpha = side_alpha(side_alpha_values, 1)
  local right_alpha = side_alpha(side_alpha_values, 2)
  local bottom_alpha = side_alpha(side_alpha_values, 3)
  local left_alpha = side_alpha(side_alpha_values, 4)

  if not (draw_top or draw_right or draw_bottom or draw_left) then
    return
  end

  cairo_save(cr)
  cairo_rectangle(cr, x, y, w, h)
  cairo_clip(cr)

  for _, band in ipairs(bands) do
    local offset = tonumber(band.offset) or 0
    local width = tonumber(band.width) or 1
    local alpha = clamp01((tonumber(band.alpha) or 0) * alpha_scale)
    if width > 0 and alpha > 0 then
      local outer = math.max(0, offset - (width / 2))
      local inner = math.max(outer, offset + (width / 2))
      local outer_w = math.max(0, w - (outer * 2))
      local outer_h = math.max(0, h - (outer * 2))
      local thickness = math.max(0, inner - outer)
      local vertical_y = y + outer + (draw_top and thickness or 0)
      local vertical_h = math.max(0, outer_h - (draw_top and thickness or 0) - (draw_bottom and thickness or 0))

      if draw_top then
        set_rgba(cr, color, alpha * top_alpha)
        cairo_new_path(cr)
        cairo_rectangle(cr, x + outer, y + outer, outer_w, thickness)
        cairo_fill(cr)
      end
      if draw_bottom then
        set_rgba(cr, color, alpha * bottom_alpha)
        cairo_new_path(cr)
        cairo_rectangle(cr, x + outer, y + h - inner, outer_w, thickness)
        cairo_fill(cr)
      end
      if draw_left then
        set_rgba(cr, color, alpha * left_alpha)
        cairo_new_path(cr)
        cairo_rectangle(cr, x + outer, vertical_y, thickness, vertical_h)
        cairo_fill(cr)
      end
      if draw_right then
        set_rgba(cr, color, alpha * right_alpha)
        cairo_new_path(cr)
        cairo_rectangle(cr, x + w - inner, vertical_y, thickness, vertical_h)
        cairo_fill(cr)
      end
    end
  end

  cairo_restore(cr)
end

-- Masks the border stroke behind (x,y) with a bg-colored patch and draws
-- `title` inline on top of it, same "-TITLE-" cutout convention for both
-- panel titles and box titles — only the font size and x/y anchor differ.
local function draw_inline_title(cr, x, y, title, theme, font_pt)
  if not title or title == "" then return end

  local title_font = theme.fonts.title
  local clearance = theme.spacing.title_clearance

  cairo_select_font_face(cr, title_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
  cairo_set_font_size(cr, font_pt)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, title, ext)

  set_rgb(cr, theme.colors.bg)
  cairo_rectangle(cr, x - clearance, y - (font_pt * 0.55), ext.width + clearance * 2, font_pt + clearance)
  cairo_fill(cr)

  set_rgb(cr, theme.colors.fg)
  cairo_move_to(cr, x, y + (font_pt * 0.35))
  cairo_show_text(cr, title)
end

local function draw_panel_title(cr, panel, theme)
  local pad_x = theme.spacing.title_pad_x
  draw_inline_title(cr, panel.x + pad_x, panel.y, panel.title, theme, theme.text.panel_title_pt)
end

-- Box border + inline title only — no data/table content. A box with
-- `border = false` (e.g. the header block, which has no border of its own
-- in the previz) skips the rectangle; a box with no `title` skips the label.
local function draw_panel_boxes(cr, panel, theme)
  local boxes = panel.boxes
  if type(boxes) ~= "table" then return end

  local pad_x = theme.spacing.box_title_x or theme.spacing.title_pad_x

  for _, box in pairs(boxes) do
    local box_x = panel.x + box.x
    local box_y = panel.y + box.y
    if box.border ~= false then
      draw_rect(cr, box_x, box_y, box.width, box.height, theme.strokes.line, theme.colors.fg)
    end
    draw_inline_title(cr, box_x + pad_x, box_y, box.title, theme, theme.text.body_sm_pt)
  end
end

-- Header block's 2-line status column (DOCSIS / PFSENSE, left side of the
-- header box; the alert banner on the right and the divider between them
-- are still future work). `widgets.pf.header_status_lines()` returns the
-- ready-to-draw lines — this function only positions and draws them.
-- Convention (font, offsets-from-panel, line step) matches OSA's SYS panel
-- status stack — see theme.header.status / osa-theme.lua's theme.sys.status.
local function draw_header_status(cr, panel, theme, widgets)
  if not (panel.boxes and panel.boxes.header) then return end
  local pf = widgets and widgets.pf
  if not pf or type(pf.header_status_lines) ~= "function" then return end

  local ok, lines = pcall(pf.header_status_lines)
  if not ok or type(lines) ~= "table" then return end

  local status_cfg = (theme.header or {}).status or {}
  local x = panel.x + (tonumber(status_cfg.x) or 16)
  local y = panel.y + (tonumber(status_cfg.y) or 26)
  local line_step = tonumber(status_cfg.line_step) or 22

  for i, line in ipairs(lines) do
    draw_text_left(cr, x, y + ((i - 1) * line_step), line, theme.fonts.data, theme.text.body_pt, theme.colors.fg)
  end
end

-- Header block's alert-banner column (right side, divided from the status
-- column by a vertical rule at header.divider_x). Real banner.json-driven
-- content — see pf.lua's header_alert_lines() (severity-sorted,
-- parent/child-flattened, up to 3 lines, scrolling one line at a time
-- when more are queued). Geometry only here: reuses theme.header.status's
-- x/y/line_step, same as the alert column always has.
local function draw_header_alert_banner(cr, panel, theme, widgets)
  local header = panel.boxes and panel.boxes.header
  if not (header and header.divider_x) then return end
  local pf = widgets and widgets.pf
  if not pf or type(pf.header_alert_lines) ~= "function" then return end

  local ok, lines = pcall(pf.header_alert_lines)
  if not ok or type(lines) ~= "table" or #lines == 0 then return end

  local status_cfg = (theme.header or {}).status or {}
  local inset = tonumber(status_cfg.x) or 16 -- same left-padding convention the status column uses past its own box edge
  local x = panel.x + header.divider_x + inset
  local y = panel.y + (tonumber(status_cfg.y) or 26)
  local line_step = tonumber(status_cfg.line_step) or 22

  for i, line in ipairs(lines) do
    draw_text_left(cr, x, y + ((i - 1) * line_step), line, theme.fonts.data, theme.text.body_pt, theme.colors.fg)
  end

  local top = y - 14
  local bottom = y + ((#lines - 1) * line_step) + 6
  -- divider_line_x lets the rule move independently of divider_x (which
  -- also anchors the alert text's x position) — defaults to divider_x when
  -- not set, so the two stay together unless a box explicitly splits them.
  local divider_line_x = tonumber(header.divider_line_x) or header.divider_x
  draw_vline(cr, panel.x + divider_line_x, top, bottom, theme.strokes.line, theme.colors.fg)
end

-- WAN panel, CM1000 detail table: the Boot State and MTR (PI5) rows are
-- conditionally visible, not always-shown (see lua/suite/pf.lua's
-- wan_boot_state_line/wan_mtr_line — both return nil when the row should
-- be absent). Only these two rows exist here; the rest of the WAN/CM1000
-- detail table (gateway loss, T3/SNR/power readouts) is separate, not-yet-
-- built content.
local function draw_wan_conditional_rows(cr, panel, theme, widgets)
  local wan = panel.boxes and panel.boxes.wan
  if not wan then return end
  local pf = widgets and widgets.pf
  if not pf then return end

  local rows = {}
  local boot_ok, boot_line = pcall(pf.wan_boot_state_line or function() return nil end)
  if boot_ok and boot_line then rows[#rows + 1] = boot_line end
  local mtr_ok, mtr_line = pcall(pf.wan_mtr_line or function() return nil end)
  if mtr_ok and mtr_line then rows[#rows + 1] = mtr_line end
  if #rows == 0 then return end

  local x = panel.x + wan.x + (theme.spacing.box_title_x or 16)
  local y = panel.y + wan.y + 40
  local line_step = 22

  for i, line in ipairs(rows) do
    draw_text_left(cr, x, y + ((i - 1) * line_step), line, theme.fonts.data, theme.text.body_sm_pt, theme.colors.fg)
  end
end

-- PFSENSE box content: system-info row (HARDWARE/VERSION/CPU/BIOS + a
-- right-aligned LOAD cell) over an interface-throughput row (one column
-- per interface, rx value over tx value). Values come from
-- widgets.pf.pfsense_panel_data(), which reads three independent
-- collectors — router.json, status.json, vpn.json (see pf.lua) — this
-- function only lays out whatever it's handed. Geometry from
-- theme.pfsense (theme.lua).
local function draw_pfsense_content(cr, panel, theme, widgets)
  local box = panel.boxes and panel.boxes.pfsense
  if not box then return end
  local pf = widgets and widgets.pf
  if not pf or type(pf.pfsense_panel_data) ~= "function" then return end

  local ok, data = pcall(pf.pfsense_panel_data)
  if not ok or type(data) ~= "table" then return end

  local cfg = theme.pfsense or {}
  local sys_cfg = cfg.system_table or {}
  local iface_cfg = cfg.iface_table or {}

  local box_x = panel.x + box.x
  local box_y = panel.y + box.y
  local content_x_offset = tonumber(sys_cfg.x) or 16
  local content_x = box_x + content_x_offset
  local content_w = box.width - (content_x_offset * 2)

  -- System-info row: HARDWARE / VERSION / CPU / BIOS, then LOAD
  -- right-aligned within the same content width, separated by whatever
  -- space is left over (matches the previz's wide gap before LOAD).
  local sys_y = box_y + (tonumber(sys_cfg.y) or 20)
  local header_h = tonumber(sys_cfg.header_h) or 16
  local value_h = tonumber(sys_cfg.value_h) or 20
  local row_gap = tonumber(sys_cfg.row_gap) or 2
  local col_gap = tonumber(sys_cfg.col_gap) or 1
  local col_widths = sys_cfg.col_widths or { 84, 84, 64, 84 }
  local header_font_pt = tonumber(sys_cfg.header_font_pt) or theme.text.body_xs_pt
  local value_font_pt = tonumber(sys_cfg.value_font_pt) or theme.text.body_pt
  local value_mid_y = sys_y + header_h + row_gap + (value_h / 2)

  local sys_labels = { "HARDWARE", "VERSION", "CPU", "BIOS" }
  local sys_values = { data.hardware, data.version, data.cpu, data.bios }

  local cx = content_x
  for i, w in ipairs(col_widths) do
    draw_table_header(cr, cx, sys_y, w, header_h, sys_labels[i] or "", header_font_pt, theme)
    draw_text_center_mid(cr, cx + (w / 2), value_mid_y, sys_values[i] or "/", theme.fonts.data, value_font_pt,
      theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    cx = cx + w + col_gap
  end

  local load_cfg = sys_cfg.load or {}
  local load_w = tonumber(load_cfg.w) or 150
  local load_x = content_x + content_w - load_w
  local load_header_pt = tonumber(load_cfg.header_font_pt) or header_font_pt
  local load_value_pt = tonumber(load_cfg.value_font_pt) or value_font_pt
  draw_table_header(cr, load_x, sys_y, load_w, header_h, "LOAD", load_header_pt, theme)
  draw_text_center_mid(cr, load_x + (load_w / 2), value_mid_y, data.load or "/", theme.fonts.data, load_value_pt,
    theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)

  -- Interface-throughput row: one equal-width column per interface,
  -- rx value stacked over tx value.
  local iface_y = sys_y + header_h + row_gap + value_h + (tonumber(iface_cfg.y_gap) or 8)
  local iface_header_h = tonumber(iface_cfg.header_h) or 16
  local iface_row_h = tonumber(iface_cfg.row_h) or 18
  local iface_row_gap = tonumber(iface_cfg.row_gap) or 2
  local iface_col_gap = tonumber(iface_cfg.col_gap) or 1
  local iface_header_font_pt = tonumber(iface_cfg.header_font_pt) or theme.text.body_xs_pt
  local iface_value_font_pt = tonumber(iface_cfg.value_font_pt) or theme.text.micro_pt

  local ifaces = data.interfaces or {}
  local n = math.max(1, #ifaces)
  local iface_col_w = (content_w - ((n - 1) * iface_col_gap)) / n
  local iface_rx_mid_y = iface_y + iface_header_h + iface_row_gap + (iface_row_h / 2)
  local iface_tx_mid_y = iface_rx_mid_y + iface_row_h

  local ix = content_x
  for _, iface in ipairs(ifaces) do
    draw_table_header(cr, ix, iface_y, iface_col_w, iface_header_h, iface.label or "", iface_header_font_pt, theme)
    local col_cx = ix + (iface_col_w / 2)
    draw_text_center_mid(cr, col_cx, iface_rx_mid_y, iface.rx or "/", theme.fonts.data, iface_value_font_pt,
      theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    draw_text_center_mid(cr, col_cx, iface_tx_mid_y, iface.tx or "/", theme.fonts.data, iface_value_font_pt,
      theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    ix = ix + iface_col_w + iface_col_gap
  end
end

-- WAN box content: GATEWAY loss/avg-latency two-bar meter (left column)
-- beside a CM1000 modem detail text block (right column, 4 fixed
-- lines). Values come from widgets.pf.wan_panel_data(), currently a
-- static placeholder (see pf.lua's WAN_PANEL_PLACEHOLDER) — this
-- function only lays out whatever it's handed. Geometry from
-- theme.wan (theme.lua). Bar-meter styling (fg-stroked frame, bottom-
-- anchored fg fill, split footer header) follows the same idiom as
-- OSA's meter/table widgets (osa/lua/ui/frame.lua's draw_meter_bar,
-- draw_table_header), trimmed to WAN's two-bar case.
local function draw_wan_content(cr, panel, theme, widgets)
  local box = panel.boxes and panel.boxes.wan
  if not box then return end
  local pf = widgets and widgets.pf
  if not pf or type(pf.wan_panel_data) ~= "function" then return end

  local ok, data = pcall(pf.wan_panel_data)
  if not ok or type(data) ~= "table" then return end

  local cfg = theme.wan or {}
  local box_x = panel.x + box.x
  local box_y = panel.y + box.y
  local content_x_offset = tonumber(cfg.content_x) or 16
  local content_x = box_x + content_x_offset
  local content_y = box_y + (tonumber(cfg.content_y) or 20)

  -- GATEWAY meter: header, LOSS%/AVG-ms values, twin bottom-anchored
  -- bars with a shared placeholder scale, split LOSS/AVG footer.
  local gw_cfg = cfg.gateway_meter or {}
  local gw_w = tonumber(gw_cfg.w) or 100
  local header_h = tonumber(gw_cfg.header_h) or 16
  local value_row_h = tonumber(gw_cfg.value_row_h) or 20
  local row_gap = tonumber(gw_cfg.row_gap) or 2
  local body_h = tonumber(gw_cfg.body_h) or 48
  local footer_h = tonumber(gw_cfg.footer_h) or 16
  local footer_row_gap = tonumber(gw_cfg.footer_row_gap) or 2
  local footer_col_gap = tonumber(gw_cfg.footer_col_gap) or 2
  local bar_w = tonumber(gw_cfg.bar_w) or 10
  local bar_gap = tonumber(gw_cfg.bar_gap) or 24
  local bar_max = tonumber(gw_cfg.bar_max) or 100
  local value_font_pt = tonumber(gw_cfg.value_font_pt) or theme.text.body_sm_pt
  local footer_font_pt = tonumber(gw_cfg.footer_font_pt) or theme.text.body_xs_pt
  local header_font_pt = tonumber(gw_cfg.header_font_pt) or footer_font_pt

  draw_table_header(cr, content_x, content_y, gw_w, header_h, "GATEWAY", header_font_pt, theme)

  -- No-data case (nil, not a numeric placeholder — see pf.lua's
  -- gateway_meter_fields()) renders as an explicit "XXX"/"XXX%" label,
  -- same digit width as a real reading, rather than formatting a fake
  -- number that could pass for a real one. The bar itself still falls
  -- back to 0 below (tonumber(nil) or 0), so a no-data bar draws at
  -- zero height alongside the XXX label.
  local function bar_label(value, suffix)
    local n = tonumber(value)
    if not n then return "XXX" .. suffix end
    return string.format("%03d%s", math.floor(n + 0.5), suffix)
  end

  local bars = {
    { value = data.loss_pct, label = bar_label(data.loss_pct, "%") },
    { value = data.avg_ms,   label = bar_label(data.avg_ms, "") },
  }
  local total_bars_w = (#bars * bar_w) + ((#bars - 1) * bar_gap)
  local first_bar_x = content_x + ((gw_w - total_bars_w) / 2)
  local value_y = content_y + header_h + row_gap + (value_row_h / 2)
  local body_top = content_y + header_h + row_gap + value_row_h + row_gap
  local body_bottom = body_top + body_h
  local footer_y = body_bottom + footer_row_gap

  -- Center-line tick marks, between the header and footer — same
  -- short/medium/long convention as OSA's draw_env_meter (osa/lua/ui/
  -- frame.lua), driven by theme.wan.gateway_meter.meter_marks.
  local center_x = content_x + (gw_w / 2)
  local marks = gw_cfg.meter_marks or {}
  local mark_short = tonumber(marks.short) or 5
  local mark_medium = tonumber(marks.medium) or 8
  local mark_long = tonumber(marks.long) or 11

  local line_top = content_y + header_h
  local line_h = body_bottom - line_top

  draw_vline(cr, center_x, line_top, body_bottom, theme.strokes.line, theme.colors.fg)
  for i = 1, 11 do
    local len = mark_short
    if i == 6 then
      len = mark_long
    elseif i == 3 or i == 9 then
      len = mark_medium
    end
    local tick_y = line_top + math.floor((line_h * (i / 12)) + 0.5)
    draw_hline(cr, center_x - (len / 2), center_x + (len / 2), tick_y, theme.strokes.line, theme.colors.fg)
  end

  local value_spread = tonumber(gw_cfg.value_spread) or 0

  for i, bar in ipairs(bars) do
    local bx = first_bar_x + ((i - 1) * (bar_w + bar_gap))
    local bar_center_x = bx + (bar_w / 2)
    local spread_sign = (bar_center_x < center_x) and -1 or 1
    draw_text_center_mid(cr, bar_center_x + (spread_sign * value_spread), value_y, bar.label, theme.fonts.data,
      value_font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    local ratio = math.max(0, math.min(1, (tonumber(bar.value) or 0) / bar_max))
    local fill_h = math.floor((line_h * ratio) + 0.5)
    if fill_h > 0 then
      fill_rect(cr, bx, body_bottom - fill_h, bar_w, fill_h, theme.colors.fg)
    end
  end

  local footer_cell_w = (gw_w - footer_col_gap) / 2
  draw_table_header(cr, content_x, footer_y, footer_cell_w, footer_h, "LOSS", footer_font_pt, theme)
  draw_table_header(cr, content_x + footer_cell_w + footer_col_gap, footer_y, footer_cell_w, footer_h, "AVG",
    footer_font_pt, theme)

  -- CM1000 column: header + 4 fixed detail lines.
  local cm_cfg = cfg.cm1000 or {}
  local cm_gap = tonumber(cm_cfg.gap) or 24
  local cm_x = content_x + gw_w + cm_gap
  local right_edge = box_x + box.width - content_x_offset
  local cm_w = right_edge - cm_x
  local cm_header_h = tonumber(cm_cfg.header_h) or 16
  local cm_header_font_pt = tonumber(cm_cfg.header_font_pt) or footer_font_pt

  draw_table_header(cr, cm_x, content_y, cm_w, cm_header_h, "CM1000", cm_header_font_pt, theme)

  local text_x = cm_x + (tonumber(cm_cfg.text_x_pad) or 8)
  local text_y = box_y + (tonumber(cm_cfg.first_line_y) or 40)
  local line_step = tonumber(cm_cfg.line_step) or 18
  local font_pt = tonumber(cm_cfg.font_pt) or theme.text.body_xs_pt

  for i, line in ipairs(data.cm1000 or {}) do
    draw_text_left(cr, text_x, text_y + ((i - 1) * line_step), line, theme.fonts.data, font_pt, theme.colors.fg)
  end
end

-- LTNCY meter: single vertical bar-meter with tick marks along the
-- right edge and the value shown to the left — same build as OSA's
-- theme.sys.meters.cpu (osa/lua/ui/frame.lua's draw_meter_header /
-- draw_meter_value / draw_meter_bar), just shorter (vertical_h) to fit
-- the VPN box instead of OSA's 128px-tall sys meters. (x, y) is the
-- meter's own top-left corner, already resolved by the caller.
local function draw_vpn_ltncy_meter(cr, x, y, cfg, theme, value)
  local w = tonumber(cfg.width) or 64
  local header_h = tonumber(cfg.header_h) or 16
  local header_font_pt = tonumber(cfg.header_font_pt) or theme.text.body_sm_pt
  local vertical_h = tonumber(cfg.vertical_h) or 90
  local bar_x = tonumber(cfg.bar_x) or 44
  local bar_width = tonumber(cfg.bar_width) or 8
  local value_x = tonumber(cfg.value_x) or 0
  local value_y = tonumber(cfg.value_y) or 58
  local value_font_pt = tonumber(cfg.value_font_pt) or theme.text.body_pt
  local bar_max = tonumber(cfg.bar_max) or 100
  local marks = cfg.marks or {}
  local mark_short = tonumber(marks.short) or 4
  local mark_medium = tonumber(marks.medium) or 6
  local mark_long = tonumber(marks.long) or 8

  draw_table_header(cr, x, y, w, header_h, "LTNCY", header_font_pt, theme)

  local tick_x = x + w - 1
  local tick_top = y + header_h + 2
  local tick_bottom = tick_top + vertical_h
  draw_hline(cr, x, x + w, y + header_h + 1, theme.strokes.line, theme.colors.fg)
  draw_vline(cr, tick_x, tick_top, tick_bottom, theme.strokes.line, theme.colors.fg)
  draw_hline(cr, x, x + w, tick_bottom + 1, theme.strokes.line, theme.colors.fg)

  for i = 1, 7 do
    local len = mark_short
    if i == 4 then
      len = mark_long
    elseif i == 2 or i == 6 then
      len = mark_medium
    end
    local tick_y = tick_top + math.floor((vertical_h * (i / 8)) + 0.5)
    draw_hline(cr, tick_x - len + 1, tick_x, tick_y, theme.strokes.line, theme.colors.fg)
  end

  -- No-data case (nil, not a numeric placeholder — see vpn.lua's
  -- ltncy_meter_fields()) renders as an explicit "XXX" label, same
  -- digit width as a real reading, rather than a plausible-looking
  -- fake number. The bar itself still falls back to 0 below, so a
  -- no-data reading draws at zero height alongside the XXX label —
  -- same convention as the WAN GATEWAY meter's own no-data case.
  local numeric = tonumber(value)
  local label = numeric and string.format("%03d", math.floor(numeric + 0.5)) or "XXX"
  draw_text_left(cr, x + value_x, y + value_y, label, theme.fonts.data, value_font_pt, theme.colors.fg)

  local ratio = math.max(0, math.min(1, (numeric or 0) / bar_max))
  local fill_h = math.floor((vertical_h * ratio) + 0.5)
  if fill_h > 0 then
    fill_rect(cr, x + bar_x, tick_bottom - fill_h, bar_width, fill_h, theme.colors.fg)
  end
end

-- VPN box content: the LTNCY meter (left column) beside a STATUS text
-- block (right column, 5 fixed lines) — same header+text-column shape
-- as draw_wan_content's CM1000 column. Values come from
-- widgets.vpn.vpn_panel_data() (see vpn.lua) — this function only lays
-- out whatever it's handed. Geometry from theme.vpn (theme.lua).
local function draw_vpn_content(cr, panel, theme, widgets)
  local box = panel.boxes and panel.boxes.vpn
  if not box then return end
  local vpn = widgets and widgets.vpn
  if not vpn or type(vpn.vpn_panel_data) ~= "function" then return end

  local ok, data = pcall(vpn.vpn_panel_data)
  if not ok or type(data) ~= "table" then return end

  local cfg = theme.vpn or {}
  local box_x = panel.x + box.x
  local box_y = panel.y + box.y
  local content_x_offset = tonumber(cfg.content_x) or 16
  local content_x = box_x + content_x_offset
  local content_y = box_y + (tonumber(cfg.content_y) or 20)

  local ltncy_cfg = cfg.ltncy_meter or {}
  draw_vpn_ltncy_meter(cr, content_x, content_y, ltncy_cfg, theme, data.ltncy_ms)

  local status_cfg = cfg.status or {}
  local ltncy_w = tonumber(ltncy_cfg.width) or 64
  local status_gap = tonumber(status_cfg.gap) or 24
  local status_x = content_x + ltncy_w + status_gap
  local right_edge = box_x + box.width - content_x_offset
  local status_w = right_edge - status_x
  local status_header_h = tonumber(status_cfg.header_h) or 16
  local status_header_font_pt = tonumber(status_cfg.header_font_pt) or ltncy_cfg.header_font_pt or theme.text.body_sm_pt

  draw_table_header(cr, status_x, content_y, status_w, status_header_h, "STATUS", status_header_font_pt, theme)

  local text_x = status_x + (tonumber(status_cfg.text_x_pad) or 8)
  local text_y = box_y + (tonumber(status_cfg.first_line_y) or 52)
  local line_step = tonumber(status_cfg.line_step) or 18
  local font_pt = tonumber(status_cfg.font_pt) or theme.text.body_xs_pt

  for i, line in ipairs(data.status_lines or {}) do
    draw_text_left(cr, text_x, text_y + ((i - 1) * line_step), line, theme.fonts.data, font_pt, theme.colors.fg)
  end
end

-- PI-HOLE box content: a plain 2-line SYSTEM status readout (left
-- column) beside a TOTALS label/value table (right column, via the
-- shared draw_kv_table). Values come from
-- widgets.pihole.pihole_panel_data(), currently a static placeholder
-- (see pihole.lua) — this function only lays out whatever it's
-- handed. Geometry from theme.pihole (theme.lua).
local function draw_pihole_content(cr, panel, theme, widgets)
  local box = panel.boxes and panel.boxes.pihole
  if not box then return end
  local pihole = widgets and widgets.pihole
  if not pihole or type(pihole.pihole_panel_data) ~= "function" then return end

  local ok, data = pcall(pihole.pihole_panel_data)
  if not ok or type(data) ~= "table" then return end

  local cfg = theme.pihole or {}
  local box_x = panel.x + box.x
  local box_y = panel.y + box.y
  local content_x_offset = tonumber(cfg.content_x) or 16
  local content_x = box_x + content_x_offset
  local content_y = box_y + (tonumber(cfg.content_y) or 18)
  local right_edge = box_x + box.width - content_x_offset

  -- SYSTEM column: header + 2 fixed lines, no table (not tabular
  -- content — see theme.lua's comment on this section).
  local sys_cfg = cfg.system or {}
  local sys_w = tonumber(sys_cfg.w) or 104
  local sys_header_h = tonumber(sys_cfg.header_h) or 16
  local sys_header_font_pt = tonumber(sys_cfg.header_font_pt) or theme.text.body_sm_pt

  draw_table_header(cr, content_x, content_y, sys_w, sys_header_h, "SYSTEM", sys_header_font_pt, theme)

  local sys_text_x = content_x + (tonumber(sys_cfg.text_x_pad) or 0)
  local sys_text_y = box_y + (tonumber(sys_cfg.first_line_y) or 44)
  local sys_line_step = tonumber(sys_cfg.line_step) or 16
  local sys_font_pt = tonumber(sys_cfg.font_pt) or theme.text.body_xs_pt

  for i, line in ipairs(data.system_lines or {}) do
    draw_text_left(cr, sys_text_x, sys_text_y + ((i - 1) * sys_line_step), line, theme.fonts.data, sys_font_pt,
      theme.colors.fg)
  end

  -- TOTALS column: label/value table.
  local totals_cfg = cfg.totals or {}
  local totals_gap = tonumber(totals_cfg.gap) or 16
  local totals_x = content_x + sys_w + totals_gap
  local totals_w = right_edge - totals_x

  draw_kv_table(cr, totals_x, content_y, totals_w, totals_cfg, theme, "TOTALS", data.totals_rows)
end

-- PFBLOCKERNG box content: two side-by-side label/value tables (IP
-- BLOCK, DNSBL), both via the shared draw_kv_table. Values come from
-- widgets.pfblockerng.pfblockerng_panel_data(), wired to pfblockerng.json
-- (see pfblockerng.lua) — this function only lays out whatever it's
-- handed, so IP BLOCK's real 1-row/DNSBL's 3-row split just renders as
-- an uneven pair of columns. Geometry from theme.pfblockerng (theme.lua).
local function draw_pfblockerng_content(cr, panel, theme, widgets)
  local box = panel.boxes and panel.boxes.pfblockerng
  if not box then return end
  local pfb = widgets and widgets.pfblockerng
  if not pfb or type(pfb.pfblockerng_panel_data) ~= "function" then return end

  local ok, data = pcall(pfb.pfblockerng_panel_data)
  if not ok or type(data) ~= "table" then return end

  local cfg = theme.pfblockerng or {}
  local box_x = panel.x + box.x
  local box_y = panel.y + box.y
  local content_x_offset = tonumber(cfg.content_x) or 16
  local content_x = box_x + content_x_offset
  local content_y = box_y + (tonumber(cfg.content_y) or 18)
  local right_edge = box_x + box.width - content_x_offset

  local col_cfg = cfg.columns or {}
  local col_gap = tonumber(col_cfg.gap) or 24
  -- col_widths lets IP BLOCK and DNSBL be sized independently (DNSBL's
  -- "QUERIES: 11,983,368" needs more room than IP BLOCK's short
  -- values) — falls back to an equal split if left unset.
  local col_widths = col_cfg.col_widths or {}
  local even_w = ((right_edge - content_x) - col_gap) / 2
  local col1_w = tonumber(col_widths[1]) or even_w
  local col2_w = tonumber(col_widths[2]) or even_w
  local col2_x = content_x + col1_w + col_gap

  draw_kv_table(cr, content_x, content_y, col1_w, col_cfg, theme, "IP BLOCK", data.ip_block_rows)
  draw_kv_table(cr, col2_x, content_y, col2_w, col_cfg, theme, "DNSBL", data.dnsbl_rows)
end

-- ACCESS POINTS box content: one repeating block per AP — a 5-cell
-- stat header (name + MSMTCH/CPU/CONN/UNKWN, via draw_table_header)
-- followed by a fixed number of client-list lines. Lines are already
-- wrapped by widgets.ap.access_points_panel_data() (see ap.lua) —
-- this function only draws whatever rows exist and always advances by
-- the same ap_row_step, so a short client list just leaves blank rows
-- rather than compressing the block. Geometry from theme.access_points
-- (theme.lua).
local function draw_access_points_content(cr, panel, theme, widgets)
  local box = panel.boxes and panel.boxes.access_points
  if not box then return end
  local ap = widgets and widgets.ap
  if not ap or type(ap.access_points_panel_data) ~= "function" then return end

  local ok, aps = pcall(ap.access_points_panel_data)
  if not ok or type(aps) ~= "table" then return end

  local cfg = theme.access_points or {}
  local box_x = panel.x + box.x
  local box_y = panel.y + box.y
  local content_x_offset = tonumber(cfg.content_x) or 16
  local content_x = box_x + content_x_offset
  local content_w = box.width - (content_x_offset * 2)
  local content_y = box_y + (tonumber(cfg.content_y) or 20)

  local header_h = tonumber(cfg.header_h) or 16
  local header_font_pt = tonumber(cfg.header_font_pt) or theme.text.body_sm_pt
  local name_w = tonumber(cfg.name_w) or 200
  local name_text_pad_x = tonumber(cfg.name_text_pad_x) or 10
  local col_gap = tonumber(cfg.col_gap) or 1
  local ap_row_step = tonumber(cfg.ap_row_step) or 86

  local clients_cfg = cfg.clients or {}
  local clients_lines = math.max(1, math.floor(tonumber(clients_cfg.lines) or 3))
  local clients_first_line_y = tonumber(clients_cfg.first_line_y) or 32
  local clients_line_step = tonumber(clients_cfg.line_step) or 15
  local clients_text_x_pad = tonumber(clients_cfg.text_x_pad) or 0
  local clients_font_pt = tonumber(clients_cfg.font_pt) or theme.text.body_xs_pt

  local stat_total_w = content_w - name_w - (4 * col_gap)
  local stat_w = stat_total_w / 4

  local y = content_y
  for _, entry in ipairs(aps) do
    local x = content_x
    -- Name cell is left-aligned (device group names read left-to-
    -- right), unlike the centered stat cells below — fill + a
    -- vertically-centered, left-aligned label instead of draw_table_header.
    fill_rect(cr, x, y, name_w, header_h, theme.colors.fg)
    draw_text_left_mid(cr, x + name_text_pad_x, y + (header_h / 2), entry.name or "", theme.fonts.data,
      header_font_pt, theme.colors.ink, CAIRO_FONT_WEIGHT_NORMAL)
    x = x + name_w + col_gap

    local stat_cells = {
      string.format("MSMTCH %02d", math.floor((tonumber(entry.msmtch) or 0) + 0.5)),
      string.format("CPU %02d%%", math.floor((tonumber(entry.cpu) or 0) + 0.5)),
      string.format("CONN %02d", math.floor((tonumber(entry.conn) or 0) + 0.5)),
      string.format("UNKWN %02d", math.floor((tonumber(entry.unkwn) or 0) + 0.5)),
    }
    for i = 1, 4 do
      draw_table_header(cr, x, y, stat_w, header_h, stat_cells[i], header_font_pt, theme)
      x = x + stat_w + col_gap
    end

    local text_x = content_x + clients_text_x_pad
    local lines = entry.client_lines or {}
    for i = 1, clients_lines do
      local line = lines[i]
      if line then
        draw_text_left(cr, text_x, y + clients_first_line_y + ((i - 1) * clients_line_step), line, theme.fonts.data,
          clients_font_pt, theme.colors.fg)
      end
    end

    y = y + ap_row_step
  end
end

-- Draws the SitRep chassis: background fill, outer chassis border, panel
-- frame(s), panel/box titles, frame shadow/light FX. `widgets` is accepted
-- for future parity with OSA's per-panel data-provider table but is unused
-- here — no panel content exists yet. Draw order mirrors OSA's frame.lua:
-- bg -> shadow -> panels/boxes/titles -> lights -> outer border (on top,
-- so it isn't dimmed by the shadow bands or covered by light bleed).
-- Chassis footer: a single centered version-identity line near the
-- bottom of the outer frame, not tied to any panel — matches the
-- previz. Text comes from version_identity_label() above (live
-- CORE/STRP versions from core.toml/suite.toml), not a static string.
local function draw_chassis_footer(cr, theme, frame)
  local cfg = theme.footer or {}
  local label = version_identity_label()
  if not label or label == "" then return end

  local font_pt = tonumber(cfg.font_pt) or 14
  local bottom_inset = tonumber(cfg.bottom_inset) or 24
  local center_x = frame.x + (frame.width / 2)
  local y = frame.y + frame.height - bottom_inset

  draw_text_center_mid(cr, center_x, y, label, theme.fonts.title, font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_BOLD)
end

function M.draw(cr, theme, layout, panels, widgets)
  if type(theme) ~= "table" or type(layout) ~= "table" then return end
  widgets = widgets or {}

  local frame = layout.frame or { x = 0, y = 0, width = 750, height = 990 }
  local scale = resolve_scale(layout)

  cairo_save(cr)
  cairo_scale(cr, scale, scale)

  fill_rect(cr, frame.x, frame.y, frame.width, frame.height, theme.colors.bg)
  draw_frame_shadow(cr, frame, theme)

  local resolved_panels = resolve_panels(panels or {}, layout)
  for _, panel in pairs(resolved_panels) do
    draw_rect(cr, panel.x, panel.y, panel.width, panel.height, theme.strokes.line, theme.colors.fg)
    draw_panel_title(cr, panel, theme)
    draw_panel_boxes(cr, panel, theme)
    draw_header_status(cr, panel, theme, widgets)
    draw_header_alert_banner(cr, panel, theme, widgets)
    draw_pfsense_content(cr, panel, theme, widgets)
    draw_wan_content(cr, panel, theme, widgets)
    draw_vpn_content(cr, panel, theme, widgets)
    draw_pihole_content(cr, panel, theme, widgets)
    draw_pfblockerng_content(cr, panel, theme, widgets)
    draw_access_points_content(cr, panel, theme, widgets)
    draw_wan_conditional_rows(cr, panel, theme, widgets)
  end

  draw_chassis_footer(cr, theme, frame)

  draw_frame_lights(cr, frame, theme)

  draw_frame_rect(
    cr,
    frame.x,
    frame.y,
    frame.width,
    frame.height,
    theme.strokes.frame or theme.strokes.line,
    theme.colors.fg,
    theme.strokes.frame_alpha
  )

  cairo_restore(cr)
end

return M
