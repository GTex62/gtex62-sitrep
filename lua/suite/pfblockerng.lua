-- PFBLOCKERNG box content: two side-by-side label/value tables, IP
-- BLOCK and DNSBL.
--
-- Wired to fetch_pfblockerng.sh's shared/pfsense/{profile}/pfblockerng.json
-- (gtex62-core/providers/pfsense/fetch_pfblockerng.sh) — despite the name
-- this lives under the pfsense domain, same as pihole.json, not a separate
-- pfblockerng profile. Same profile resolution as pihole.lua/pf.lua
-- (suite_profile("pfsense", "main_router")). Gate flag is
-- providers.pfsense.pfblockerng in core.toml (confirmed alongside .pihole
-- in the same [providers.pfsense] section).
--
-- IP BLOCK only gets one real row: the bare pfb_ip_total count, no inline
-- label (the "IP BLOCK" column header already identifies it, and it's
-- the column's only row, so a repeated "IP:" label would be redundant).
-- The collector has no IP-list hit-rate field (pfb_ip_total is a raw
-- pfctl packet count with no matching percentage), so the previz's IP
-- BLOCK "HITS:" row has no real counterpart there — that HITS label and
-- value moved to DNSBL instead, where pfb_dnsbl_pct is real
-- (pfb_dnsbl_total / resolver_total, pre-rounded to 2dp server-side).
-- DNSBL therefore carries all three of its previz values (count, HITS
-- pct, QUERIES) while IP BLOCK carries one; draw_kv_table lays out
-- whatever rows it's handed, so this uneven 1-row vs 3-row split renders
-- fine.
--
-- Independent Disabled/Unconfigured/SSH-Down/Stale precedence chain
-- (resolve_state_word(), same shape as pihole.lua/pf.lua/vpn.lua's
-- copies), keyed to profiles/pfsense/{profile}.toml's own [pfblockerng]
-- section (currently absent there -> falls back to fetch_pfblockerng.sh's
-- own 300s default, same pattern pihole_fields() hits).
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "sitrep"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local CACHE = {
  tick = nil,
  ip_block_rows = { { label = "", value = "NO DATA" } },
  dnsbl_rows = { { label = "", value = "NO DATA" } },
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
-- the copy in pihole.lua/pf.lua/vpn.lua). Returns a display word on any
-- non-healthy branch, or nil when the caller should fill in its own
-- "healthy" wording.
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
-- "10,478,313"). Duplicated from pihole.lua rather than shared — no
-- common util module exists in this suite yet (pihole.lua/vpn.lua/pf.lua
-- each already carry their own full copies of resolve_state_word() etc.),
-- so this follows the same per-file convention rather than introducing
-- a new shared location on its own.
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

-- PFBLOCKERNG box: IP BLOCK (IP total only — no hit-rate field in the
-- source data) and DNSBL (count, pct, resolver query total) from
-- pfblockerng.json (fetch_pfblockerng.sh).
local function pfblockerng_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "pfblockerng", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/pfblockerng.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.pfb_ip_total // 0), '
    .. '(.pfb_dnsbl_total // 0), (.pfb_dnsbl_pct // 0), (.resolver_total // 0)] | @tsv'
  )
  local fields = split_tsv(row, 7)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]
  local ip_total, dnsbl_total, dnsbl_pct, resolver_total = fields[4], fields[5], fields[6], fields[7]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "pfblockerng", "cache_ttl_sec", 300)
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
      ip_block_rows = { { label = "", value = word } },
      dnsbl_rows = { { label = "", value = word } },
    }
  end

  return {
    -- Blank label: the "IP BLOCK" column header already identifies this
    -- value and it's the column's only row, so a repeated "IP:" label
    -- would be redundant — same bare-value treatment as the collapsed
    -- single-line fallback rows elsewhere (cm1000_fields()/vpn_fields()),
    -- just shaped as a kv_table row since this column renders via
    -- draw_kv_table rather than a line list.
    ip_block_rows = {
      { label = "", value = comma_format(ip_total) },
    },
    dnsbl_rows = {
      { label = "DNSBL:",   value = comma_format(dnsbl_total) },
      { label = "HITS:",    value = string.format("%.2f%%", tonumber(dnsbl_pct) or 0) },
      { label = "QUERIES:", value = comma_format(resolver_total) },
    },
  }
end

local function refresh()
  local tick = os.time()
  if CACHE.tick == tick then return end
  CACHE.tick = tick

  local ok, data = pcall(pfblockerng_fields)
  if ok and type(data) == "table" then
    CACHE.ip_block_rows = data.ip_block_rows
    CACHE.dnsbl_rows = data.dnsbl_rows
  else
    CACHE.ip_block_rows = { { label = "", value = "NO DATA" } }
    CACHE.dnsbl_rows = { { label = "", value = "NO DATA" } }
  end
end

function M.pfblockerng_panel_data()
  refresh()
  return {
    ip_block_rows = CACHE.ip_block_rows,
    dnsbl_rows = CACHE.dnsbl_rows,
  }
end

return M
