require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-sitrep")

local runtime     ---@type any
local frame       ---@type any
local pf          ---@type any
local vpn         ---@type any
local pihole      ---@type any
local pfblockerng ---@type any
local ap          ---@type any

local function ensure_loaded()
  if runtime ~= nil then
    return
  end

  runtime = dofile(SUITE_DIR .. "/lua/suite/runtime.lua")
  frame = dofile(SUITE_DIR .. "/lua/ui/frame.lua")
  pf = dofile(SUITE_DIR .. "/lua/suite/pf.lua")
  vpn = dofile(SUITE_DIR .. "/lua/suite/vpn.lua")
  pihole = dofile(SUITE_DIR .. "/lua/suite/pihole.lua")
  pfblockerng = dofile(SUITE_DIR .. "/lua/suite/pfblockerng.lua")
  ap = dofile(SUITE_DIR .. "/lua/suite/ap.lua")
end

function conky_draw_sitrep()
  if conky_window == nil then return end
  ensure_loaded()

  local w = conky_window.width
  local h = conky_window.height
  local surface = cairo_xlib_surface_create(
    conky_window.display,
    conky_window.drawable,
    conky_window.visual,
    w,
    h
  )
  local cr = cairo_create(surface)
  local state = runtime.get_state()

  if type(frame.draw) == "function" then
    frame.draw(cr, state.theme, state.layout, state.panels,
      { pf = pf, vpn = vpn, pihole = pihole, pfblockerng = pfblockerng, ap = ap })
  end

  cairo_destroy(cr)
  cairo_surface_destroy(surface)
end
