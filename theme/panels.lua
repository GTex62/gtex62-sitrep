-- SitRep is a single-panel widget, unlike OSA's six-panel grid — this file
-- still exists (rather than folding panel geometry into layout.lua) purely to
-- keep the same theme/layout/panels/palettes split OSA uses, so a future
-- multi-box layout inside this one panel has a conventional home to land in.
--
-- `boxes` is intentionally empty: real box geometry (pfSense / router /
-- pfBlockerNG / Pi-hole / VPN / modem / AP / devices sections) is future
-- panel-design work, not decided by this scaffold.
local panels = {
  main = {
    title = "SITREP",
    column = "main",
    x = 24,
    y = 40,
    width = 852,
    height = 1120,
    boxes = {},
  },
}

return panels
