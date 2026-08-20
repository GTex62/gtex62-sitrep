---@diagnostic disable: undefined-global
-- Chassis-level drawing only: background, frame shadow/lights FX, panel
-- box + title. No SitRep-specific panel content lives here — that is
-- future work once real panel geometry and data sources are decided.
-- Structural mirror of gtex62-osa/lua/ui/frame.lua, trimmed to the pieces
-- this scaffold actually needs.

local M = {}

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
  cairo_rectangle(cr, frame.x + stroke, frame.y + stroke, math.max(0, frame.width - (stroke * 2)), math.max(0, frame.height - (stroke * 2)))
  cairo_clip(cr)

  for _, light in ipairs(lights) do
    local radius = (tonumber(light.radius) or 20) * radius_scale
    local radius_y = (tonumber(light.radius_y) or radius) * radius_y_scale
    local alpha = clamp01((tonumber(light.alpha) or 1) * alpha_scale)
    local color = frame_light_color(cfg, theme, light.color or { 1.0, 0.72, 0.28 })
    local cy = light.y == "top_frame" and (frame.y + stroke + top_frame_y_offset) or (frame.y + (tonumber(light.y) or stroke))
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
  return sides[index] == true or sides[index] == 1 or sides[index] == "1" or sides[index] == "on" or sides[index] == "true"
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

local function draw_panel_title(cr, panel, theme)
  local title = panel.title
  if not title or title == "" then return end

  local title_font = theme.fonts.title
  local title_pt = theme.text.panel_title_pt
  local pad_x = theme.spacing.title_pad_x
  local clearance = theme.spacing.title_clearance
  local x = panel.x + pad_x
  local y = panel.y

  cairo_select_font_face(cr, title_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
  cairo_set_font_size(cr, title_pt)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, title, ext)

  -- Mask the frame stroke behind the title so it reads inline, same
  -- convention as OSA's chassis titles.
  set_rgb(cr, theme.colors.bg)
  cairo_rectangle(cr, x - clearance, y - (title_pt * 0.55), ext.width + clearance * 2, title_pt + clearance)
  cairo_fill(cr)

  set_rgb(cr, theme.colors.fg)
  cairo_move_to(cr, x, y + (title_pt * 0.35))
  cairo_show_text(cr, title)
end

local function draw_panel_boxes(cr, panel, theme)
  local boxes = panel.boxes
  if type(boxes) ~= "table" then return end

  for _, box in pairs(boxes) do
    draw_rect(cr, panel.x + box.x, panel.y + box.y, box.width, box.height, theme.strokes.line, theme.colors.fg)
  end
end

-- Draws the SitRep chassis: background fill, panel frame(s), panel
-- title(s), frame shadow/light FX. `widgets` is accepted for future parity
-- with OSA's per-panel data-provider table but is unused here — no panel
-- content exists yet.
function M.draw(cr, theme, layout, panels, widgets)
  if type(theme) ~= "table" or type(layout) ~= "table" then return end
  widgets = widgets or {}

  local frame = layout.frame or { x = 0, y = 0, width = 900, height = 1200 }
  local scale = resolve_scale(layout)

  cairo_save(cr)
  cairo_scale(cr, scale, scale)

  fill_rect(cr, frame.x, frame.y, frame.width, frame.height, theme.colors.bg)

  local resolved_panels = resolve_panels(panels or {}, layout)
  for _, panel in pairs(resolved_panels) do
    draw_rect(cr, panel.x, panel.y, panel.width, panel.height, theme.strokes.line, theme.colors.fg)
    draw_panel_title(cr, panel, theme)
    draw_panel_boxes(cr, panel, theme)
  end

  draw_frame_shadow(cr, frame, theme)
  draw_frame_lights(cr, frame, theme)

  cairo_restore(cr)
end

return M
