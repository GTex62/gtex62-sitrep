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
    width = 696,
    height = 872,
    boxes = {
      -- Header/alert block: SITREP title (drawn by the panel itself) sits
      -- above this; the 3-line status column (left) and alert banner
      -- (right) are future content. No border or title of its own in the
      -- previz — just reserved space, plus a vertical divider position for
      -- when that content lands.
      header = {
        x = 16,
        y = 0,
        width = 664,
        height = 104,
        divider_x = 295,
        divider_line_x = 328,
        border = false,
      },
      pfsense = {
        x = 16,
        y = 104,
        width = 664,
        height = 136,
        title = "PFSENSE",
      },
      wan = {
        x = 16,
        y = 272,
        width = 320,
        height = 144,
        title = "WAN",
      },
      vpn = {
        x = 368,
        y = 272,
        width = 312,
        height = 144,
        title = "VPN",
      },
      pihole = {
        x = 16,
        y = 448,
        width = 320,
        height = 104,
        title = "PI-HOLE",
      },
      pfblockerng = {
        x = 368,
        y = 448,
        width = 312,
        height = 104,
        title = "PFBLOCKERNG",
      },
      access_points = {
        x = 16,
        y = 584,
        width = 664,
        height = 272,
        title = "ACCESS POINTS",
      },
    },
  },
}

return panels
