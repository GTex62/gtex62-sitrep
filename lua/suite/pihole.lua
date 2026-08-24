-- PI-HOLE box content: a 2-line SYSTEM status readout + a TOTALS
-- label/value table.
--
-- Real data source (once wired up) is fetch_pihole.sh's
-- shared/pihole/{profile}/pihole.json (gtex62-core/providers/pfsense/
-- fetch_pihole.sh): active, load.l15, blocked, total, domains,
-- blocked_pct — every field below already has a real counterpart
-- there, unlike some of the other panels' placeholders. Static
-- placeholder only, mirroring the previz (design/gtex62-sitrep-02.png).
local M = {}

local PIHOLE_PANEL_PLACEHOLDER = {
  system_lines = {
    "ACTIVE",
    "L15: 0.07",
  },
  totals_rows = {
    { label = "BLOCKED:", value = "10,478,313" },
    { label = "",         value = "38%" },
    { label = "DOMAINS:", value = "282,947" },
    { label = "TOTAL:",   value = "27,506,946" },
  },
}

function M.pihole_panel_data()
  return PIHOLE_PANEL_PLACEHOLDER
end

return M
