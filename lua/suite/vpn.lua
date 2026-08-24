-- VPN box content: LTNCY meter + STATUS text block.
--
-- Both blocks are wired to fetch_vpn.sh's shared/vpn/{profile}/vpn.json
-- (gtex62-core/providers/vpn/fetch_vpn.sh) — a local-only collector (no
-- SSH/ssh_gate), gated on providers.vpn (core.toml) and its own profile
-- TTL (cache_ttl_sec, 10s default), same resolve_state_word()
-- Disabled/Unconfigured/Stale chain used throughout pf.lua.
--
-- LTNCY reads tunnel_latency_ms — a single ICMP echo through the tunnel
-- interface (ping -I <iface> 1.1.1.1) added to fetch_vpn.sh this session;
-- there's no pre-computed source for it (piactl has no latency/ping
-- subcommand, and PIA's own per-region LatencyTracker is internal daemon
-- RPC state, unreachable from here). Same GATEWAY-meter treatment as
-- pf.lua's gateway_meter_fields(): its own independent state-chain read,
-- falling back to LTNCY_MS_PLACEHOLDER (not a dash/word in the bar
-- itself) whenever the chain isn't clean or tunnel_latency_ms comes back
-- null — which it does both when disconnected (health=DEAD) and when the
-- ping itself fails while otherwise connected.
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "sitrep"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local LTNCY_MS_PLACEHOLDER = 25

local CACHE = {
  tick = nil,
  ltncy_ms = LTNCY_MS_PLACEHOLDER,
  status_lines = { "NO DATA" },
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
-- the copy in pf.lua — vpn.json has no ssh_gate key of its own, so
-- ssh_tripped is always passed as nil here and that branch never fires).
-- Returns a display word on any non-healthy branch, or nil when the
-- caller should fill in its own "healthy" wording.
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

-- PROTOCOL: piactl reports the long form ("wireguard", "openvpn"); the
-- previz wants a short code ("WG"). "openvpn" -> "OVPN" is PIA's other
-- supported protocol, not confirmed against live data (this box has only
-- ever been observed on WireGuard) — falls back to the raw uppercased
-- string for anything else so an unrecognized value is still visible
-- rather than swallowed.
local PROTOCOL_CODES = {
  wireguard = "WG",
  openvpn = "OVPN",
}

local function protocol_code(protocol)
  if not protocol or protocol == "" then return nil end
  return PROTOCOL_CODES[protocol:lower()] or protocol:upper()
end

-- HANDSHAKE age: latest_handshake_seconds is a raw seconds count; the
-- previz wants M:SS ("0:55").
local function format_handshake_age(seconds)
  seconds = tonumber(seconds)
  if not seconds then return nil end
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- health is HEALTHY/STALE/DEAD (docs/network-providers-roadmap.md,
-- "Health Classification": handshake age vs 60s/180s thresholds against
-- the 25s PIA keepalive) — a different signal than resolve_state_word()'s
-- own STALE (that one fires when the collector stops writing vpn.json at
-- all; this one fires when the tunnel handshake itself goes quiet even
-- though the file is fresh). HEALTHY maps to NOMINAL to match SitRep's
-- display convention (PFSENSE/DOCSIS's existing NOMINAL wording); STALE/
-- DEAD pass through as-is since they're already meaningful display words.
local function health_word(health)
  if health == "HEALTHY" then return "NOMINAL" end
  return health
end

local function vpn_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "vpn", false)

  local profile = suite_profile("vpn", "local")
  local path = string.format("%s/shared/vpn/%s/vpn.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.region // ""), '
    .. '(.protocol // ""), (.latest_handshake_seconds // -1), (.killswitch // false), '
    .. '(.health // "")] | @tsv'
  )
  local fields = split_tsv(row, 8)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]
  local region, protocol, handshake_sec, killswitch, health = fields[4], fields[5], fields[6], fields[7], fields[8]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/vpn/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "", "cache_ttl_sec", 10)
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
    return { word }
  end

  local handshake_seconds = tonumber(handshake_sec)
  if handshake_seconds and handshake_seconds < 0 then handshake_seconds = nil end

  return {
    health_word(health) or "NO DATA",
    "REGION: " .. (region ~= "" and region:upper() or "?"),
    "PROTOCOL: " .. (protocol_code(protocol) or "?"),
    "HANDSHAKE " .. (format_handshake_age(handshake_seconds) or "?"),
    "KS " .. ((killswitch == "true") and "ON" or "OFF"),
  }
end

local function refresh()
  local tick = os.time()
  if CACHE.tick == tick then return end
  CACHE.tick = tick

  local ok, lines = pcall(vpn_fields)
  CACHE.status_lines = (ok and type(lines) == "table") and lines or { "NO DATA" }
end

-- VPN box, LTNCY meter: single-value ms reading, same treatment as WAN's
-- GATEWAY meter (pf.lua's gateway_meter_fields()) — its own independent
-- json_row read against vpn.json, same resolve_state_word() chain as
-- vpn_fields() above (enabled/state/note/cache_age/cache_ttl; ssh_tripped
-- omitted since that branch never fires here either — vpn.json has no
-- ssh_gate key). Falls back to LTNCY_MS_PLACEHOLDER, matching GATEWAY's
-- own fallback-to-fixed-number convention, whenever the chain isn't clean
-- or tunnel_latency_ms comes back null (jq's `// null` renders as an
-- empty TSV field, same as GATEWAY's missing-field case) — covers both
-- disconnected (health=DEAD) and a ping failure while otherwise connected.
local function ltncy_meter_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "vpn", false)

  local profile = suite_profile("vpn", "local")
  local path = string.format("%s/shared/vpn/%s/vpn.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.tunnel_latency_ms // null)] | @tsv'
  )
  local fields = split_tsv(row, 3)
  local state, note, ltncy_ms = fields[1], fields[2], fields[3]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/vpn/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "", "cache_ttl_sec", 10)
  local mtime = file_mtime(path)
  local cache_age_sec = mtime and (os.time() - mtime) or nil

  local word = resolve_state_word({
    enabled = enabled,
    state = state,
    note = note,
    cache_age_sec = cache_age_sec,
    cache_ttl_sec = cache_ttl_sec,
  })

  if word or ltncy_ms == "" then
    return LTNCY_MS_PLACEHOLDER
  end

  return tonumber(ltncy_ms) or LTNCY_MS_PLACEHOLDER
end

function M.vpn_panel_data()
  refresh()

  local ltncy_ok, ltncy_ms = pcall(ltncy_meter_fields)
  if not ltncy_ok or type(ltncy_ms) ~= "number" then
    ltncy_ms = LTNCY_MS_PLACEHOLDER
  end

  return {
    ltncy_ms = ltncy_ms,
    status_lines = CACHE.status_lines,
  }
end

return M
