-- ACCESS POINTS box content: one repeating block per AP — a 5-cell
-- stat header (name + MSMTCH/CPU/CONN/UNKWN) followed by a wrapped,
-- comma-separated client list, capped at a fixed row count
-- (theme.access_points.clients.lines) regardless of how many lines
-- actually wrap, so every AP block takes the same vertical space.
--
-- Real data source (once wired up) is fetch_ap.sh's shared/ap/{profile}/
-- ap_status.json + ap_clients.json (gtex62-core/providers/ap/
-- fetch_ap.sh) — see docs/ap-provider-status.md for the schema. MSMTCH
-- (mismatches[] length) and UNKWN (unknown[] length) are already
-- core-computed per the design notes (design/sitrep-design-notes.md §
-- Access Points panel); CPU/CONN come from ap_status.json. Static
-- placeholder only, mirroring the previz (design/gtex62-sitrep-02.png).
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-sitrep")

-- Same greedy word-wrap as OSA's wxr.lua wrap_lines() (osa/lua/suite/
-- wxr.lua): split on the last space at or before wrap_col, hard-split
-- mid-word only if no space is found in range. Truncates to max_lines
-- with a trailing "..." on overflow, same as OSA.
local function wrap_lines(text, wrap_col, max_lines)
  local lines = {}
  wrap_col = math.max(8, tonumber(wrap_col) or 42)
  local limit = math.max(1, tonumber(max_lines) or 7)
  local s = text or ""
  while s ~= "" do
    if #s <= wrap_col then
      lines[#lines + 1] = s
      break
    end

    local split = wrap_col
    for i = wrap_col, 2, -1 do
      if s:sub(i, i) == " " then
        split = i - 1
        break
      end
    end

    lines[#lines + 1] = s:sub(1, split)
    s = s:sub(split + 1):gsub("^%s+", "")
  end

  if #lines > limit then
    lines[limit] = (lines[limit] or "") .. "..."
    while #lines > limit do
      table.remove(lines)
    end
  end

  return lines
end

-- Reads wrap_col/lines from theme.access_points.clients directly
-- (rather than hardcoding a copy here) — same suite-module-reads-its-
-- own-theme-config convention as OSA's wxr.lua, so the two stay in
-- sync automatically instead of by comment.
local function clients_cfg()
  local ok, theme = pcall(dofile, SUITE_DIR .. "/theme/theme.lua")
  if ok and type(theme) == "table" then
    return (theme.access_points or {}).clients or {}
  end
  return {}
end

local AP_PANEL_PLACEHOLDER = {
  {
    name = "CLOSET",
    msmtch = 0,
    cpu = 5,
    conn = 7,
    unkwn = 0,
    clients = "KA NGHT STND, KA PIANO, LITR, LX DRBLL, LX LVNG ROM, LX M BED, RO M BED",
  },
  {
    name = "OFFICE",
    msmtch = 0,
    cpu = 4,
    conn = 6,
    unkwn = 0,
    clients = "IPAD, KA COMP, LX CAVE, RACHIO, RO C, S24U",
  },
  {
    name = "GREAT ROOM",
    msmtch = 0,
    cpu = 7,
    conn = 15,
    unkwn = 0,
    clients = "A14, KA END T, KA FRN, LX AQR, LX CHIME, LX FRNT ENT, LX G RM, LX KTCHN, "
      .. "LX WRK RM, RO C BED, RO C WRKOUT, RO G RM, SUBZ, TAURUS, WLED AQR",
  },
}

function M.access_points_panel_data()
  local cfg = clients_cfg()
  local wrap_col = tonumber(cfg.wrap_col) or 64
  local max_lines = tonumber(cfg.lines) or 3

  local aps = {}
  for _, ap in ipairs(AP_PANEL_PLACEHOLDER) do
    aps[#aps + 1] = {
      name = ap.name,
      msmtch = ap.msmtch,
      cpu = ap.cpu,
      conn = ap.conn,
      unkwn = ap.unkwn,
      client_lines = wrap_lines(ap.clients, wrap_col, max_lines),
    }
  end
  return aps
end

return M
