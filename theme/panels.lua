-- SitRep is a single-panel widget, unlike OSA's six-panel grid — this file
-- still exists (rather than folding panel geometry into layout.lua) purely to
-- keep the same theme/layout/panels/palettes split OSA uses.
--
-- Box geometry below is pixel-measured against the annotated previz
-- (design/gtex62-sitrep-02.png, design/gtex62-sitrep-measured-02.png) via
-- border-run detection, then snapped to an 8px rhythm where the previz
-- itself didn't land on one. This is a geometry-only pass — box borders
-- and static titles only, no data/tables/text content yet. Expect fine
-- adjustment once frames are actually visible on screen.
local panels = {
  main = {
    title = "SITREP",
    column = "main",
    x = 24,
    y = 40,
    width = 698,
    height = 912,
    boxes = {
      -- Header/alert block: SITREP title (drawn by the panel itself) sits
      -- above this; the 3-line status column (left) and alert banner
      -- (right) are future content. No border or title of its own in the
      -- previz — just reserved space, plus a vertical divider position for
      -- when that content lands.
      header = {
        x = 16,
        y = 0,
        width = 666,
        height = 96,
        divider_x = 320,
        border = false,
      },
      pfsense = {
        x = 16,
        y = 96,
        width = 666,
        height = 142,
        title = "PFSENSE",
      },
      wan = {
        x = 16,
        y = 270,
        width = 320,
        height = 146,
        title = "WAN",
      },
      vpn = {
        x = 368,
        y = 270,
        width = 314,
        height = 146,
        title = "VPN",
      },
      pihole = {
        x = 16,
        y = 448,
        width = 320,
        height = 103,
        title = "PI-HOLE",
      },
      pfblockerng = {
        x = 368,
        y = 448,
        width = 314,
        height = 103,
        title = "PFBLOCKERNG",
      },
      access_points = {
        x = 16,
        y = 583,
        width = 666,
        height = 301,
        title = "ACCESS POINTS",
      },
    },
  },
}

return panels
