-- PI-HOLE box content: a 4-line SYSTEM status readout (ACTIVE/INACTIVE +
-- L01/L05/L15 load) beside a TOTALS label/value table (BLOCKED count + %,
-- DOMAINS, TOTAL queries).
--
-- Wired to fetch_pihole.sh's shared/pfsense/{profile}/pihole.json
-- (gtex62-core/providers/pfsense/fetch_pihole.sh) — despite the "pihole"
-- name this lives under the pfsense domain, not a separate pihole
-- profile: the script's own comment says it's "nested here to match
-- fetch_pfsense.sh's existing four-output structure" since Pi-hole runs
-- on Pi5, reached over its own SSH target/gate, not pfSense itself. So
-- this reuses suite_profile("pfsense", "main_router") — same profile pf.lua
-- reads status.json/router.json from — just a different filename; no
-- overlap with what pf.lua itself reads. Gate flag is
-- providers.pfsense.pihole in core.toml (not a top-level providers.pihole),
-- confirmed against core.toml's [providers.pfsense] section.
--
-- Independent Disabled/Unconfigured/SSH-Down/Stale precedence chain
-- (resolve_state_word(), same shape as pf.lua/vpn.lua's copies), keyed to
-- profiles/pfsense/{profile}.toml's own [pihole] section, cache_ttl_sec = 60
-- (lowered from the fetch_pihole.sh/pihole.lua built-in 300s default so the
-- whole panel — TOTALS/BLOCKED/DOMAINS/LOAD — reads fresher; falls back to
-- that 300s default only if the key is ever removed from the profile).
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "sitrep"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local CACHE = {
  tick = nil,
  system_lines = { "NO DATA" },
  totals_rows = { { label = "", value = "NO DATA" } },
}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function command_output(cmd)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

local function file_mtime(path)
  local out = command_output(string.format("stat -c %%Y %q 2>/dev/null", path))
  return tonumber(out)
end

-- Section headers may be dotted (e.g. "[providers.pfsense]") — unlike the
-- word-char-only section parser elsewhere in this codebase, this one keeps
-- "providers" and "providers.pfsense" as distinct tables rather than
-- silently flattening the dotted section into its parent.
local function parse_simple_toml(path)
  local out = {}
  local section = nil
  local s = read_file(path)
  if not s then return out end

  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local sec = line:match("^%[(.-)%]$")
      if sec then
        section = sec
        out[section] = out[section] or {}
      else
        local key, value = line:match("^([%w_%-]+)%s*=%s*(.+)$")
        if key and value then
          value = value:gsub('^"', ""):gsub('"$', "")
          if section then
            out[section][key] = value
          else
            out[key] = value
          end
        end
      end
    end
  end

  return out
end

local function toml_bool(cfg, section, key, default)
  local raw = (cfg[section] or {})[key]
  if raw == nil then return default end
  return raw == "true" or raw == true
end

local function toml_number(cfg, section, key, default)
  local raw = (cfg[section] or {})[key]
  return tonumber(raw) or default
end

local function suite_profile(domain, default)
  local cfg = parse_simple_toml(string.format("%s/suites/%s.toml", RUNTIME_ROOT, SUITE_ID))
  return ((cfg.profiles or {})[domain]) or default
end

local function json_row(path, filter)
  if not read_file(path) then return nil end
  return command_output(string.format("jq -r %q %q 2>/dev/null", filter, path))
end

local function split_tsv(row, count)
  if not row then return {} end
  local fields = {}
  local pattern = "([^\t]*)"
  local pos = 1
  for _ = 1, count do
    local _, e, field = row:find(pattern, pos)
    fields[#fields + 1] = field or ""
    pos = (e or #row) + 2
  end
  return fields
end

local function looks_unconfigured(note)
  note = (note or ""):lower()
  if note == "" then return false end
  return note:match("profile") ~= nil
    or note:match("credential") ~= nil
    or note:match("placeholder") ~= nil
    or note:match("change_me") ~= nil
    or note:match("password") ~= nil
    or note:match("ssh_target") ~= nil
    or note:match("not configured") ~= nil
end

-- Shared Disabled/Unconfigured/SSH Down/Stale precedence chain (mirrors
-- the copy in pf.lua/vpn.lua). Returns a display word on any non-healthy
-- branch, or nil when the caller should fill in its own "healthy" wording.
local function resolve_state_word(opts)
  if not opts.enabled then
    return "DISABLED"
  end
  if not opts.state then
    return "NO DATA"
  end
  if opts.state == "error" and looks_unconfigured(opts.note) then
    return "UNCONFIGURED"
  end
  if opts.ssh_tripped == "true" then
    return "SSH DOWN"
  end
  if opts.cache_age_sec and opts.cache_ttl_sec and opts.cache_age_sec > (2 * opts.cache_ttl_sec) then
    return string.format("STALE - %dM AGO", math.floor(opts.cache_age_sec / 60))
  end
  if opts.state == "error" then
    return "NO DATA"
  end
  return nil
end

-- Groups an integer count into thousands with commas (10478313 ->
-- "10,478,313"). No shared helper for this exists elsewhere in the suite —
-- PFSENSE's byte counts use human_bytes()'s K/M/G/T scaling instead, and
-- ACCESS POINTS' counts are small enough not to need grouping.
local function comma_format(n)
  n = math.floor(tonumber(n) or 0)
  local s = string.format("%d", n)
  local sign = ""
  if s:sub(1, 1) == "-" then
    sign, s = "-", s:sub(2)
  end
  local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return sign .. formatted
end

-- PI-HOLE box: SYSTEM (ACTIVE/INACTIVE + L01/L05/L15 load) and TOTALS
-- (BLOCKED count + %, DOMAINS, TOTAL) from pihole.json (fetch_pihole.sh).
-- "active" here is the instantaneous systemctl is-active read, not the
-- duration-gated PI-HOLE INACTIVE alert-banner condition (core.toml's
-- alerts.pihole_inactive_duration_sec, 600s) — that's separate, future
-- alert-banner work; this readout just reflects the current sample.
--
-- l1/l5/l15 are all already present in pihole.json's schema
-- (/proc/loadavg on Linux always returns all three windows natively —
-- confirmed against the live cache, fetch_pihole.sh unchanged) — this is
-- display-only, widening the jq filter from the old l15-only read.
-- No ncpu suffix here (unlike pf.lua's L01/L05/L15): Pi-hole's collector
-- doesn't track core count, so none is fabricated or borrowed from
-- pfSense's router.json.
local function pihole_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "pihole", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/pihole.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.active // false), '
    .. '(.load.l1 // 0), (.load.l5 // 0), (.load.l15 // 0), (.queries_blocked // 0), (.queries_total // 0), '
    .. '(.blocked_pct // 0), (.domains_blocked // 0)] | @tsv'
  )
  local fields = split_tsv(row, 11)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]
  local active, l1, l5, l15, blocked, total, blocked_pct, domains =
    fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "pihole", "cache_ttl_sec", 300)
  local mtime = file_mtime(path)
  local cache_age_sec = mtime and (os.time() - mtime) or nil

  local word = resolve_state_word({
    enabled = enabled,
    state = state,
    note = note,
    ssh_tripped = ssh_tripped,
    cache_age_sec = cache_age_sec,
    cache_ttl_sec = cache_ttl_sec,
  })

  if word then
    return {
      system_lines = { word },
      totals_rows = { { label = "", value = word } },
    }
  end

  return {
    system_lines = {
      (active == "true") and "ACTIVE" or "INACTIVE",
      string.format("L01: %.2f", tonumber(l1) or 0),
      string.format("L05: %.2f", tonumber(l5) or 0),
      string.format("L15: %.2f", tonumber(l15) or 0),
    },
    totals_rows = {
      { label = "BLOCKED:", value = comma_format(blocked) },
      { label = "",         value = string.format("%.0f%%", tonumber(blocked_pct) or 0) },
      { label = "DOMAINS:", value = comma_format(domains) },
      { label = "TOTAL:",   value = comma_format(total) },
    },
  }
end

local function refresh()
  local tick = os.time()
  if CACHE.tick == tick then return end
  CACHE.tick = tick

  local ok, data = pcall(pihole_fields)
  if ok and type(data) == "table" then
    CACHE.system_lines = data.system_lines
    CACHE.totals_rows = data.totals_rows
  else
    CACHE.system_lines = { "NO DATA" }
    CACHE.totals_rows = { { label = "", value = "NO DATA" } }
  end
end

function M.pihole_panel_data()
  refresh()
  return {
    system_lines = CACHE.system_lines,
    totals_rows = CACHE.totals_rows,
  }
end

return M
