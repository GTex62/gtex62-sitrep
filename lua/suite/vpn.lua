-- VPN box content: LTNCY meter + STATUS text block.
--
-- Real data source (once wired up) is fetch_vpn.sh's shared/vpn/{profile}/
-- vpn.json (gtex62-core/providers/vpn/fetch_vpn.sh): connectionstate,
-- region, protocol, latest_handshake_seconds, killswitch. That script
-- doesn't collect a latency sample — LTNCY's placeholder value has no
-- real provider yet. Static placeholder only, mirroring the previz
-- (design/gtex62-sitrep-02.png).
local M = {}

local VPN_PANEL_PLACEHOLDER = {
  ltncy_ms = 25,
  status_lines = {
    "NOMINAL",
    "REGION: US-TEXAS",
    "PROTOCOL: WG",
    "HANDSHAKE 0:55",
    "KS ON",
  },
}

function M.vpn_panel_data()
  return VPN_PANEL_PLACEHOLDER
end

return M
