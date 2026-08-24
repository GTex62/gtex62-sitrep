-- PFBLOCKERNG box content: two side-by-side label/value tables, IP
-- BLOCK and DNSBL.
--
-- Real data source (once wired up) is fetch_pfblockerng.sh's
-- shared/pfblockerng/{profile}/pfblockerng.json (gtex62-core/providers/
-- pfsense/fetch_pfblockerng.sh): pfb_ip_total, pfb_dnsbl_total,
-- pfb_dnsbl_pct, resolver_total. That script doesn't compute an IP-list
-- hit rate yet — IP BLOCK's HITS value has no real counterpart there.
-- Static placeholder only, mirroring the previz
-- (design/gtex62-sitrep-02.png).
local M = {}

local PFBLOCKERNG_PANEL_PLACEHOLDER = {
  ip_block_rows = {
    { label = "IP:",    value = "7,786" },
    { label = "HITS:",  value = "0.14%" },
  },
  dnsbl_rows = {
    { label = "DNSBL:",    value = "16,352" },
    { label = "QUERIES:",  value = "11,983,368" },
  },
}

function M.pfblockerng_panel_data()
  return PFBLOCKERNG_PANEL_PLACEHOLDER
end

return M
