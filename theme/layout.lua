local layout = {}

-- SitRep is authored in one live coordinate space, same as OSA's chassis.
-- Conky window dimensions are derived at runtime from this frame.
--
-- Base dimensions are provisional — carried over from the sizing sketch in
-- gtex62-core/docs/sitrep-relocation-plan.md (wide enough for a stacked
-- pfSense/router/pfBlockerNG/Pi-hole/VPN/modem/AP/devices status column).
-- Real geometry is future panel-design work, not decided here.
layout.frame = {
  x = 0,
  y = 0,
  width = 900,
  height = 1200,
}

-- scale_mode: "manual" uses layout.scale directly.
-- scale_mode: "auto" computes scale from CONKY_SCREEN_W/H vs frame dimensions.
-- Frame dimensions are the base (scale=1.0) coordinate space.
layout.scale_mode = "manual"
layout.scale = 1.0

-- SitRep is single-panel, so there is only one column for now.
layout.columns = {
  main = { x = 24, width = 852 },
}

layout.rows = {
  top = 40,
  gap = 56,
}

-- scaled_frame: pre-computed for Conky window sizing at conf load time.
-- In auto mode this reads CONKY_SCREEN_W/H; export them before launching Conky.
local function _compute_scale()
  if layout.scale_mode == "auto" then
    local w = tonumber(os.getenv("CONKY_SCREEN_W"))
    local h = tonumber(os.getenv("CONKY_SCREEN_H"))
    local bw = layout.frame.width
    local bh = layout.frame.height
    if w and h and bw > 0 and bh > 0 then
      return math.min(w / bw, h / bh)
    end
  end
  return tonumber(layout.scale) or 1.0
end

local _s = _compute_scale()
layout.scaled_frame = {
  x      = math.floor(layout.frame.x * _s + 0.5),
  y      = math.floor(layout.frame.y * _s + 0.5),
  width  = math.floor(layout.frame.width * _s + 0.5),
  height = math.floor(layout.frame.height * _s + 0.5),
}

return layout
