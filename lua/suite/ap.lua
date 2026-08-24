-- ACCESS POINTS box content: one repeating block per AP — a 5-cell
-- stat header (name + MSMTCH/CPU/CONN/UNKWN) followed by a wrapped,
-- comma-separated client list, capped at a fixed row count
-- (theme.access_points.clients.lines) regardless of how many lines
-- actually wrap, so every AP block takes the same vertical space.
--
-- Wired to fetch_ap.sh's shared/pfsense/{profile}/ap_status.json +
-- ap_clients.json (gtex62-core/providers/ap/fetch_ap.sh — despite the
-- "ap" domain name, it shares the pfsense cache namespace and profile
-- TOML, same as pihole.lua/pfblockerng.lua do). MSMTCH (mismatches[]
-- length) and UNKWN (unknown[] length) are already core-computed;
-- CPU/CONN come from ap_status.json. Client display_names are already
-- MAC-to-devices.toml resolved inside fetch_ap.sh itself — no lookup
-- needed here. Gated on providers.ap (core.toml) + the ap profile's
-- own TTL, same Disabled/Unconfigured/SSH Down/Stale precedence chain
-- as every other panel (resolve_state_word()). AP count is whatever
-- ap_status.json actually lists (currently 3: CLOSET/OFFICE/GREAT
-- ROOM, from site.toml's [ap] labels), not assumed fixed at 3.
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-sitrep")
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "sitrep"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

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
-- the copy in pf.lua/pihole.lua/pfblockerng.lua/vpn.lua). Returns a
-- display word on any non-healthy branch, or nil when the caller should
-- fill in its own "healthy" wording.
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

-- One row per AP from ap_status.json: label, online, cpu_pct (nil when
-- the AP was offline for this poll), clients (raw station count).
local function ap_status_rows(path)
  local rows = {}
  local raw = json_row(path,
    '.aps[]? | [(.label // ""), (.online // false), (.cpu_pct // ""), (.clients // 0)] | @tsv'
  )
  if not raw then return rows end
  for line in raw:gmatch("[^\r\n]+") do
    local f = split_tsv(line, 4)
    rows[#rows + 1] = {
      label = f[1] or "",
      online = f[2] == "true",
      cpu_pct = tonumber(f[3]),
      clients = tonumber(f[4]) or 0,
    }
  end
  return rows
end

-- One row per AP from ap_clients.json: label, mismatch/unknown counts
-- (already core-computed, reused directly rather than recomputed), and
-- the client display_name list joined "A, B, C" (already MAC-to-
-- devices.toml resolved by fetch_ap.sh — no lookup needed here).
local function ap_clients_rows(path)
  local rows = {}
  local raw = json_row(path,
    '.aps[]? | [(.label // ""), ((.mismatches // []) | length), ((.unknown // []) | length), '
    .. '([(.clients // [])[].name] | join(", "))] | @tsv'
  )
  if not raw then return rows end
  for line in raw:gmatch("[^\r\n]+") do
    local f = split_tsv(line, 4)
    rows[#rows + 1] = {
      label = f[1] or "",
      mismatch = tonumber(f[2]) or 0,
      unknown = tonumber(f[3]) or 0,
      names = f[4] or "",
    }
  end
  return rows
end

local function index_by_label(rows)
  local map = {}
  for _, row in ipairs(rows) do
    if row.label and row.label ~= "" then
      map[row.label] = row
    end
  end
  return map
end

-- Builds the panel's AP list. A single panel-wide word (DISABLED/
-- UNCONFIGURED/SSH DOWN/STALE/NO DATA) collapses the whole panel to one
-- synthetic block showing that word as the name, same convention as
-- pihole.lua/vpn.lua putting the word in their one status slot. Once
-- healthy, each AP block is built inside its own pcall so one AP's bad
-- row can't blank the rest — same spirit as PFSENSE's per-row
-- independence (pf.lua's router/interfaces/vpn collectors).
local function ap_entries()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "ap", false)

  local profile = suite_profile("ap", "main_router")
  local status_path = string.format("%s/shared/pfsense/%s/ap_status.json", CACHE_ROOT, profile)
  local clients_path = string.format("%s/shared/pfsense/%s/ap_clients.json", CACHE_ROOT, profile)

  local envelope = split_tsv(
    json_row(status_path, '[.state, (.note // ""), (.ssh_gate.tripped // false)] | @tsv'),
    3
  )
  local state, note, ssh_tripped = envelope[1], envelope[2], envelope[3]

  -- fetch_ap.sh reuses profiles/pfsense/{profile}.toml (its own [ap]
  -- section, currently absent — falls back to site.toml's [ap]
  -- cache_ttl_sec=120, same value as the 120 default below).
  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "ap", "cache_ttl_sec", 120)
  local mtime = file_mtime(status_path)
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
    return { { name = word, msmtch = 0, cpu = 0, conn = 0, unkwn = 0, client_lines = {} } }
  end

  local cfg = clients_cfg()
  local wrap_col = tonumber(cfg.wrap_col) or 64
  local max_lines = tonumber(cfg.lines) or 3

  local status_rows = ap_status_rows(status_path)
  local clients_by_label = index_by_label(ap_clients_rows(clients_path))

  local aps = {}
  for _, s in ipairs(status_rows) do
    local ok, entry = pcall(function()
      local c = clients_by_label[s.label] or {}
      return {
        name = s.label ~= "" and s.label or "AP",
        msmtch = c.mismatch or 0,
        cpu = s.cpu_pct or 0,
        conn = s.clients or 0,
        unkwn = c.unknown or 0,
        client_lines = wrap_lines((c.names or ""):upper(), wrap_col, max_lines),
      }
    end)
    aps[#aps + 1] = ok and entry or {
      name = s.label ~= "" and s.label or "AP",
      msmtch = 0,
      cpu = 0,
      conn = 0,
      unkwn = 0,
      client_lines = {},
    }
  end

  return aps
end

local CACHE = { tick = nil, aps = {} }

local function refresh()
  local tick = os.time()
  if CACHE.tick == tick then return end
  CACHE.tick = tick

  local ok, aps = pcall(ap_entries)
  CACHE.aps = (ok and type(aps) == "table") and aps or {}
end

function M.access_points_panel_data()
  refresh()
  return CACHE.aps
end

return M
