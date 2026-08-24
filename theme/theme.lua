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
theme.monitor_head = 0

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

----------------------------------------------------------------
-- Header
----------------------------------------------------------------
-- Same convention as OSA's SYS panel 3-line status stack
-- (osa-theme.lua theme.sys.status, read in frame.lua's draw_sys_content):
-- offsets from panel.x/panel.y directly, not from a sub-box.
theme.header = {
  status = {
    x = 46,
    y = 36,
    line_step = 22,
  },
}

----------------------------------------------------------------
-- Alert Banner Section
----------------------------------------------------------------
-- Header box's alert-banner column (right side) — timing only. Geometry
-- (x/y/line_step) is inherited from theme.header.status above, same as
-- the pre-Aug-24-2026 placeholder draw already did — this column shares
-- the header box, it isn't a box of its own in panels.lua. Values come
-- from widgets.pf.header_alert_lines(), which reads
-- shared/alerts/{profile}/banner.json (see pf.lua).
theme.alert_banner = {
  -- How often the up-to-3-line display window advances by one line when
  -- more than 3 lines are queued (sitrep-design-notes.md § Alert banner
  -- / outage detection, "Scroll behavior" — the design left pace
  -- undefined; 3s chosen here as a readable default). Same
  -- config-drives-the-look convention as every other panel.
  scroll_interval_sec = 3,
}

----------------------------------------------------------------
-- pfSense Section
----------------------------------------------------------------
-- PFSENSE box content: a system-info row (HARDWARE/VERSION/CPU/BIOS +
-- L01/L05/L15) over an interface-throughput row (one column per
-- interface, rx value over tx value). Geometry only — values come
-- from widgets.pf.pfsense_panel_data(), which reads
-- router.json/status.json/vpn.json live (see pf.lua). Coordinates are
-- relative to the pfsense box (panels.lua's boxes.pfsense), not the
-- panel or frame.
--
-- col_widths' last 3 entries (L01/L05/L15) are sized so the whole row
-- fills content_w exactly: 96+88+64+84+98+98+98 = 626, +6 col_gaps(1px)
-- = 632 = box.width(664) - 2*x(16). Measured against the real
-- "GTex62 OSA" render font (cairo text_extents, not estimated): a
-- worst-case healthy value "0.38/4C" is 77px wide in a 98px cell (21px
-- padding — more generous than the CPU column's shipped 64px cell
-- holding a 55px value). On a non-healthy word (frame.lua's load_word
-- branch), the word is drawn spanning the merged L01-L15 region (296px)
-- instead of one 98px cell — words like "STALE - 14M AGO" (165px) don't
-- fit a single narrow cell, matching the space the old single LOAD cell
-- used to occupy. No load sub-table needed any more — L01/L05/L15 reuse
-- this table's own header_font_pt/value_font_pt like every other column.
theme.pfsense = {
  system_table = {
    x = 16,
    y = 20,
    header_h = 16,
    value_h = 20,
    row_gap = 2,
    col_gap = 1,
    col_widths = { 96, 88, 64, 84, 98, 98, 98 },
    header_font_pt = 18,
    value_font_pt = 18,
  },
  iface_table = {
    y_gap = 8, -- gap below the system-info row before this one starts
    header_h = 16,
    row_h = 18,
    row_gap = 2,
    col_gap = 1,
    header_font_pt = 18,
    value_font_pt = 16,
  },
}

----------------------------------------------------------------
-- WAN Section
----------------------------------------------------------------
-- WAN box content: a GATEWAY loss/avg-latency two-bar meter (left
-- column) beside a CM1000 modem detail text block (right column, 4
-- fixed lines). Geometry only — values come from
-- widgets.pf.wan_panel_data(), currently a static placeholder (see
-- pf.lua). Coordinates are relative to the wan box (panels.lua's
-- boxes.wan), not the panel or frame.
theme.wan = {
  content_x = 16,
  content_y = 20,
  gateway_meter = {
    w = 100,
    header_h = 16,
    header_font_pt = 18,
    value_row_h = 20,
    row_gap = 2,
    body_h = 52,
    bar_w = 8,
    bar_gap = 24,
    bar_max = 100, -- shared placeholder scale for both LOSS% and AVG ms bars
    -- Center-line tick marks between header and footer, same
    -- short/medium/long convention as OSA's theme.env.atmos.meter_marks
    -- (osa-theme.lua) — defaults copied from there.
    meter_marks = {
      short = 2,
      medium = 8,
      long = 11,
    },
    footer_h = 16,
    footer_row_gap = 2,
    footer_col_gap = 2,
    value_font_pt = 16,
    value_spread = 10, -- pushes each bar's value label away from center_x, like OSA's aqi_value_spread/solar_value_spread
    footer_font_pt = 16,
  },
  cm1000 = {
    gap = 24, -- horizontal gap between the GATEWAY meter and this column
    header_h = 16,
    header_font_pt = 18,
    text_x_pad = 0,
    first_line_y = 52, -- baseline of the first line, offset from box top
    line_step = 18,
    font_pt = 16,
  },
}

----------------------------------------------------------------
-- VPN Section
----------------------------------------------------------------
-- VPN box content: an LTNCY meter (single vertical bar, tick marks
-- along the right edge, value to the left — same build as OSA's
-- theme.sys.meters.cpu, osa-theme.lua) beside a STATUS text block
-- (header + 5 fixed lines, same shape as theme.wan.cm1000). Geometry
-- only — values come from widgets.vpn.vpn_panel_data(), currently a
-- static placeholder (see vpn.lua). Coordinates are relative to the
-- vpn box (panels.lua's boxes.vpn), not the panel or frame.
theme.vpn = {
  content_x = 16,
  content_y = 20,
  ltncy_meter = {
    width = 64, -- same meter width as OSA's cpu meter
    header_h = 16,
    header_font_pt = 18,
    vertical_h = 90, -- OSA's cpu meter uses 128; shortened to fit the VPN box
    bar_x = 44,
    bar_width = 8,
    value_x = 0,
    value_y = 58,  -- scaled down from OSA's value_y=82 at the same 90/128 ratio
    value_font_pt = 20,
    bar_max = 100, -- placeholder scale; no real latency provider yet (see vpn.lua)
    marks = {
      short = 4,
      medium = 6,
      long = 8,
    },
  },
  status = {
    gap = 24, -- horizontal gap between the LTNCY meter and this column
    header_h = 16,
    header_font_pt = 18,
    text_x_pad = 0,
    first_line_y = 52, -- baseline of the first line, offset from box top
    line_step = 18,
    font_pt = 16,
  },
}

----------------------------------------------------------------
-- Pi-Hole Section
----------------------------------------------------------------
-- PI-HOLE box content: a plain 2-line SYSTEM status readout (left
-- column) beside a TOTALS label/value table (right column, right-
-- aligned values via the shared draw_kv_table primitive — same
-- right-aligned-data convention as OSA's table rows). Geometry only —
-- values come from widgets.pihole.pihole_panel_data(), currently a
-- static placeholder (see pihole.lua). Coordinates are relative to
-- the pihole box (panels.lua's boxes.pihole), not the panel or frame.
theme.pihole = {
  content_x = 16,
  content_y = 18,
  system = {
    w = 88, -- shrunk so TOTALS (which auto-expands to fill the rest) gets more room
    header_h = 16,
    header_font_pt = 18,
    text_x_pad = 0,
    first_line_y = 50, -- baseline of the first line, offset from box top
    line_step = 15,
    font_pt = 16,
  },
  totals = {
    gap = 16, -- horizontal gap between the SYSTEM and TOTALS columns
    header_h = 16,
    header_font_pt = 18,
    row_gap = 2,
    row_h = 15,
    row_font_pt = 16,
    label_x_pad = 0,
    value_x_pad = 0,
  },
}

----------------------------------------------------------------
-- pfBlockingNG Section
----------------------------------------------------------------
-- PFBLOCKERNG box content: two side-by-side label/value tables (IP
-- BLOCK, DNSBL), both drawn with the same shared draw_kv_table
-- primitive as PI-HOLE's TOTALS column. Geometry only — values come
-- from widgets.pfblockerng.pfblockerng_panel_data(), currently a
-- static placeholder (see pfblockerng.lua). Coordinates are relative
-- to the pfblockerng box (panels.lua's boxes.pfblockerng), not the
-- panel or frame.
theme.pfblockerng = {
  content_x = 16,
  content_y = 18,
  columns = {
    gap = 16, -- horizontal gap between the IP BLOCK and DNSBL columns
    -- IP BLOCK, DNSBL — asymmetric: DNSBL's "QUERIES: 11,983,368" row
    -- needs more room than IP BLOCK's short IP/HITS values. Falls back
    -- to an equal split if left unset.
    col_widths = { 98, 166 }, -- DNSBL trimmed 2px to fit the 8px-grid-snapped box (was 314 wide, now 312)
    header_h = 16,
    header_font_pt = 18,
    row_gap = 2,
    row_h = 18,
    row_font_pt = 15,
    label_x_pad = 0,
    value_x_pad = 0,
  },
}


----------------------------------------------------------------
-- Access Points Section
----------------------------------------------------------------
-- ACCESS POINTS box content: one repeating block per AP — a 5-cell
-- stat header (name + MSMTCH/CPU/CONN/UNKWN) over a fixed-height
-- client-list area. clients.lines is a fixed row count, not a cap on
-- what fits — every AP block reserves the same vertical space
-- (ap_row_step) regardless of how many lines its client list actually
-- wraps to, so AP blocks stay evenly spaced no matter the client
-- count. ap.lua reads clients.wrap_col/lines directly (same
-- suite-module-reads-its-own-theme-config convention as OSA's
-- wxr.lua), so this is the single source of truth for both wrapping
-- and layout. Geometry only — values come from
-- widgets.ap.access_points_panel_data(), currently a static
-- placeholder (see ap.lua). Coordinates are relative to the
-- access_points box (panels.lua's boxes.access_points), not the
-- panel or frame.
theme.access_points = {
  content_x = 16,
  content_y = 20,
  header_h = 16,
  header_font_pt = 18,
  name_w = 200,
  name_text_pad_x = 10, -- left-aligned inset for the AP name cell (unlike the centered stat cells)
  col_gap = 1,
  ap_row_step = 80,     -- vertical distance from one AP block's header to the next
  clients = {
    lines = 3,          -- fixed row count per AP, regardless of how many lines actually wrap
    wrap_col = 64,      -- character-column wrap width, same convention as OSA's theme.wxr.current.metar_wrap_col
    text_x_pad = 0,
    first_line_y = 32,  -- baseline of the first client line, offset from this AP block's own top (not the box top)
    line_step = 18,
    font_pt = 16,
  },
}

----------------------------------------------------------------
-- Footer
----------------------------------------------------------------
-- Chassis-level version-identity line, centered near the bottom of the
-- outer frame (not tied to any panel) — matches the previz. Text itself
-- is built live by version_identity_label() in lua/ui/frame.lua from
-- core.toml/suite.toml ("CORE %s // STRP %s"); this table only holds
-- sizing/placement.
theme.footer = {
  bottom_inset = 30, -- distance from the frame's bottom edge up to this label's baseline
  font_pt = 10,
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
