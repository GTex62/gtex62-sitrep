-- SitRep header status column (DOCSIS / PFSENSE) and the WAN panel's
-- conditional CM1000 detail rows (Boot State / MTR).
--
-- Reads already-written core provider output only (shared/pfsense/*,
-- shared/modem/*, core.toml) — no new fetching or computation of network
-- state happens here. Display-state precedence (Disabled > Unconfigured >
-- SSH Down > Stale > healthy) follows the "Display States" table in
-- gtex62-core/docs/sitrep-relocation-plan.md § Provider Enable/Disable.
--
-- DOCSIS (this header line was NETWORK until it was repurposed): answers
-- "is the modem actually connected/registered to Comcast" via the CM1000's
-- own DOCSIS "Connectivity State" (shared/modem/*/status.json), not WAN
-- ping reachability. The 8.8.8.8/1.1.1.1 gateway-reachability check in
-- fetch_pfsense.sh is a separate, still-valid signal (feeds the alert
-- watcher) — unrelated to this line now.
local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "sitrep"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local CACHE = { tick = nil, lines = { "DOCSIS", "PFSENSE" }, boot_state_line = nil, mtr_line = nil }

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

-- Shared Disabled/Unconfigured/SSH Down/Stale precedence chain. Returns a
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

local function pfsense_word()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "status", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/status.json", CACHE_ROOT, profile)
  local row = json_row(path, '[.state, (.note // ""), (.ssh_gate.tripped // false)] | @tsv')
  local fields = split_tsv(row, 3)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]

  local cache_ttl_sec = toml_number(parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml"), "", "cache_ttl_sec", 30)
  local mtime = file_mtime(path)
  local cache_age_sec = mtime and (os.time() - mtime) or nil

  return resolve_state_word({
    enabled = enabled,
    state = state,
    note = note,
    ssh_tripped = ssh_tripped,
    cache_age_sec = cache_age_sec,
    cache_ttl_sec = cache_ttl_sec,
  }) or "NOMINAL"
end

-- Single read of modem's status.json shared by docsis_word() and the WAN
-- panel's boot-state row — one jq call instead of two.
local function modem_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "modem", false)

  local profile = suite_profile("modem", "local")
  local path = string.format("%s/shared/modem/%s/status.json", CACHE_ROOT, profile)
  local row = json_row(
    path,
    '[.state, (.note // ""), (.connectivity_state.status // ""), (.connectivity_state.comment // ""), (.boot_state.status // ""), (.boot_state.comment // "")] | @tsv'
  )
  local fields = split_tsv(row, 6)

  local cache_ttl_sec = toml_number(parse_simple_toml(RUNTIME_ROOT .. "/profiles/modem/" .. profile .. ".toml"), "", "cache_ttl_sec", 300)
  local mtime = file_mtime(path)
  local cache_age_sec = mtime and (os.time() - mtime) or nil

  return {
    enabled = enabled,
    state = fields[1],
    note = fields[2],
    connectivity_status = fields[3],
    connectivity_comment = fields[4],
    boot_status = fields[5],
    boot_comment = fields[6],
    cache_age_sec = cache_age_sec,
    cache_ttl_sec = cache_ttl_sec,
  }
end

local function docsis_word(modem)
  local shared = resolve_state_word(modem)
  if shared then return shared end

  -- Healthy modem collector: NOMINAL, matching the standing header
  -- convention (PFSENSE // NOMINAL, and the four-state model in
  -- sitrep-design-notes.md) — not the modem's own raw Comment text.
  if modem.connectivity_status == "" then
    return "NO DATA"
  end
  if modem.connectivity_status:upper() == "OK" then
    return "NOMINAL"
  end
  return modem.connectivity_status:upper()
end

-- WAN panel, CM1000 detail table: Boot State row. Hidden in the common
-- (healthy) case — only shown when it's actually reporting a problem, so it
-- doesn't compete for attention with Connectivity State on every screen.
local function boot_state_line(modem)
  if modem.boot_status == "" or modem.boot_status:upper() == "OK" then
    return nil
  end
  local word = modem.boot_status:upper()
  if modem.boot_comment ~= "" then
    word = word .. " - " .. modem.boot_comment:upper()
  end
  return "BOOT STATE // " .. word
end

-- WAN panel, CM1000 detail table: MTR (PI5) row. The SSH trigger that
-- actually starts mtr_overnight_log.sh on Pi5 is deliberately unbuilt (see
-- design/sitrep-design-notes.md § Alert banner / outage detection,
-- "Still open for a future build session") — this stub always reports "not
-- running" until a real signal exists. Once the trigger is built, this
-- should read whatever state file it writes rather than the gateway-offline
-- duration directly (crossing the threshold means the script *should*
-- start, not that it's confirmed running).
local function mtr_line()
  local mtr_running = false
  if not mtr_running then return nil end
  return "MTR (PI5) // RUNNING"
end

local function refresh()
  local tick = os.time()
  if CACHE.tick == tick then return end
  CACHE.tick = tick

  local pf_ok, pf_word = pcall(pfsense_word)
  if not pf_ok then pf_word = "NO DATA" end

  local modem_ok, modem = pcall(modem_fields)
  local docsis, boot, mtr
  if modem_ok then
    local d_ok, d_word = pcall(docsis_word, modem)
    docsis = d_ok and d_word or "NO DATA"
    local b_ok, b_line = pcall(boot_state_line, modem)
    boot = b_ok and b_line or nil
  else
    docsis = "NO DATA"
    boot = nil
  end
  local mtr_ok, mtr_result = pcall(mtr_line)
  mtr = mtr_ok and mtr_result or nil

  CACHE.lines = {
    "DOCSIS // " .. docsis,
    "PFSENSE // " .. pf_word,
  }
  CACHE.boot_state_line = boot
  CACHE.mtr_line = mtr
end

function M.header_status_lines()
  refresh()
  return CACHE.lines
end

-- Placeholder only — static text, no banner.json reading, no alert logic.
-- Occupies the header's alert-banner column (right side) with its real
-- final shape (up to 3 scrolling lines, per sitrep-design-notes.md's
-- scroll-behavior spec) so the header box's height gets measured against
-- actual final content now, not today's incomplete 2-line status column
-- alone. Replace with real banner.json-driven content in the alert banner
-- build session — this function should not survive that pass.
function M.header_alert_lines()
  return { "ALERT LINE 1", "ALERT LINE 2", "MTR SCRIPT ON PI5 BEGAN 1929UTC" }
end

-- Returns nil (row absent) or the ready-to-draw line text (row visible).
function M.wan_boot_state_line()
  refresh()
  return CACHE.boot_state_line
end

-- Returns nil (row absent) or the ready-to-draw line text (row visible).
function M.wan_mtr_line()
  refresh()
  return CACHE.mtr_line
end

-- PFSENSE box content: system-info row (HARDWARE/VERSION/CPU/BIOS/LOAD)
-- over an interface-throughput row (WAN/HOME/IOT/GUEST/INFRA/CAM/VPN).
-- Three independent collectors feed this one box, each with its own
-- Disabled/Unconfigured/SSH Down/Stale precedence chain (same
-- resolve_state_word() used by pfsense_word()/docsis_word() above) — it's
-- expected for one row, or even one interface column, to show real data
-- while another shows STALE:
--   - router.json  (fetch_router.sh)  -> VERSION/CPU/BIOS/LOAD
--   - status.json   (fetch_pfsense.sh) -> WAN/HOME/IOT/GUEST/INFRA/CAM
--   - vpn.json       (fetch_vpn.sh)     -> VPN
-- HARDWARE (the physical appliance model, e.g. "V1211") isn't collected by
-- any provider — fetch_router.sh's hw_model is the CPU string, already
-- used for CPU below — so it's read as a static site.toml config value
-- ([pfsense].hardware_model) with no STALE chain of its own.
--
-- When a collector's chain resolves to a non-healthy word, its numeric
-- fields are dropped (nil, rendered as "/" by frame.lua's fallback) and
-- the word is surfaced once: in the LOAD cell for the router row, in the
-- first interface column's tx cell for a multi-column collector (WAN for
-- pfsense's 6, the VPN column itself for vpn.json) — matching the
-- one-word-per-line economy the header status column already uses,
-- rather than repeating the same word across every cell.

local IFACE_KEYS = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }

-- ibytes/obytes (and vpn.json's transfer.*_bytes) are cumulative byte
-- counters; the previz's rx/tx values (e.g. "5.97T") are these counters
-- humanized directly, not a diffed instantaneous rate — confirmed against
-- live status.json (WAN ibytes ~2.7TiB after ~68 days uptime matches the
-- previz's T-scale).
local function human_bytes(bytes)
  bytes = tonumber(bytes) or 0
  local units = { "", "K", "M", "G", "T", "P" }
  local i = 1
  while bytes >= 1024 and units[i + 1] do
    bytes = bytes / 1024
    i = i + 1
  end
  return string.format("%.2f%s", bytes, units[i])
end

-- hw_model is a full CPU description ("Intel(R) Celeron(R) N5105 @
-- 2.00GHz"); the panel's CPU column wants just the chip code ("N5105").
local function extract_cpu_code(hw_model)
  if not hw_model or hw_model == "" then return nil end
  return hw_model:match("(%u%d%d%d%d?)") or hw_model
end

-- bios_version is "3mdeb Dasharo (coreboot+UEFI) v0.9.3 (09/06/2024)";
-- the panel's BIOS column wants just the version number ("0.9.3").
local function extract_bios_ver(bios_version)
  if not bios_version or bios_version == "" then return nil end
  return bios_version:match("v([%d%.]+)") or bios_version
end

-- version is "2.8.1-RELEASE"; the panel's VERSION column drops the
-- "-RELEASE" suffix.
local function strip_version_suffix(version)
  if not version or version == "" then return nil end
  return version:match("^([%d%.]+)") or version
end

local function format_load(l5, ncpu)
  l5, ncpu = tonumber(l5), tonumber(ncpu)
  if not l5 or not ncpu then return nil end
  return string.format("L5 %.2f / %dC", l5, ncpu)
end

local function hardware_model()
  local site_cfg = parse_simple_toml(RUNTIME_ROOT .. "/site.toml")
  return (site_cfg.pfsense or {}).hardware_model
end

-- PFSENSE panel, system-info row: VERSION/CPU/BIOS/LOAD from router.json
-- (fetch_router.sh). Independent chain, gated on providers.pfsense.router
-- and router.json's own mtime — same shape as pfsense_word() above but
-- keyed to a different collector/TTL ([router] section, 60s default,
-- matching fetch_router.sh's own default).
local function router_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "router", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/router.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.version // ""), (.hw_model // ""), (.ncpu // 0), (.load.l5 // 0), (.bios_version // "")] | @tsv'
  )
  local fields = split_tsv(row, 8)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]
  local version, hw_model, ncpu, load_l5, bios_version = fields[4], fields[5], fields[6], fields[7], fields[8]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "router", "cache_ttl_sec", 60)
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
    return { version = nil, cpu = nil, bios = nil, load = word }
  end
  return {
    version = strip_version_suffix(version),
    cpu = extract_cpu_code(hw_model),
    bios = extract_bios_ver(bios_version),
    load = format_load(load_l5, ncpu),
  }
end

-- PFSENSE panel, interface row (WAN/HOME/IOT/GUEST/INFRA/CAM) from
-- status.json (fetch_pfsense.sh) — same collector/TTL pfsense_word()
-- already reads (providers.pfsense.status, profile-root cache_ttl_sec,
-- 30s default).
local function pfsense_interfaces_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "status", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/status.json", CACHE_ROOT, profile)

  local filter_parts = { '.state', '(.note // "")', '(.ssh_gate.tripped // false)' }
  for _, key in ipairs(IFACE_KEYS) do
    filter_parts[#filter_parts + 1] = string.format('(.interfaces.%s.ibytes // 0)', key)
    filter_parts[#filter_parts + 1] = string.format('(.interfaces.%s.obytes // 0)', key)
  end
  local row = json_row(path, "[" .. table.concat(filter_parts, ", ") .. "] | @tsv")
  local fields = split_tsv(row, #filter_parts)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "", "cache_ttl_sec", 30)
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

  local ifaces = {}
  for i, key in ipairs(IFACE_KEYS) do
    local idx = 3 + (i - 1) * 2
    local entry = { label = key }
    if not word then
      entry.rx = human_bytes(fields[idx + 1])
      entry.tx = human_bytes(fields[idx + 2])
    end
    ifaces[#ifaces + 1] = entry
  end
  if word then
    ifaces[1].tx = word
  end
  return ifaces
end

-- PFSENSE panel, VPN interface column from vpn.json (fetch_vpn.sh) — a
-- third, fully independent collector (local-only, no SSH/ssh_gate, own
-- providers.vpn enable flag and own profile TTL, 10s default).
local function vpn_interface_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "vpn", false)

  local profile = suite_profile("vpn", "local")
  local path = string.format("%s/shared/vpn/%s/vpn.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.transfer.rx_bytes // 0), (.transfer.tx_bytes // 0)] | @tsv'
  )
  local fields = split_tsv(row, 5)
  local state, note, ssh_tripped, rx_bytes, tx_bytes = fields[1], fields[2], fields[3], fields[4], fields[5]

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

  local entry = { label = "VPN" }
  if word then
    entry.tx = word
  else
    entry.rx = human_bytes(rx_bytes)
    entry.tx = human_bytes(tx_bytes)
  end
  return entry
end

function M.pfsense_panel_data()
  local router_ok, router = pcall(router_fields)
  if not router_ok then router = { load = "NO DATA" } end

  local pf_ifaces_ok, pf_ifaces = pcall(pfsense_interfaces_fields)
  if not pf_ifaces_ok then pf_ifaces = {} end

  local vpn_ok, vpn_iface = pcall(vpn_interface_fields)
  if not vpn_ok then vpn_iface = { label = "VPN", tx = "NO DATA" } end

  local interfaces = {}
  for _, iface in ipairs(pf_ifaces) do
    interfaces[#interfaces + 1] = iface
  end
  interfaces[#interfaces + 1] = vpn_iface

  return {
    hardware = hardware_model(),
    version = router.version,
    cpu = router.cpu,
    bios = router.bios,
    load = router.load,
    interfaces = interfaces,
  }
end

-- WAN box, GATEWAY meter: loss%/avg-latency two-bar meter. Previously a
-- static placeholder (fetch_pfsense.sh's gateway.online was a boolean, not
-- a loss%/latency sample); now real, since fetch_pfsense.sh's live dpinger
-- read added gateway.loss_pct/latency_ms/latency_stddev_ms to status.json
-- this session. Kept as the graceful-fallback shape below for a cache
-- written before that change (gateway.online present, loss_pct/latency_ms
-- not yet) and for the non-healthy resolve_state_word() branches.
local GATEWAY_METER_PLACEHOLDER = {
  loss_pct = 25,
  avg_ms = 53,
}

-- gateway.loss_pct/latency_ms live in the exact status.json file (and
-- profile-root cache_ttl_sec TTL) pfsense_word()/pfsense_interfaces_fields()
-- above already read — no independent STALE gating, same
-- resolve_state_word() chain. gateway.latency_stddev_ms is also written
-- there but has no bar slot in this two-bar meter (frame.lua draws exactly
-- LOSS/AVG) — not read here.
local function gateway_meter_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "status", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/status.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.gateway.loss_pct // null), (.gateway.latency_ms // null)] | @tsv'
  )
  local fields = split_tsv(row, 5)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]
  local loss_pct, latency_ms = fields[4], fields[5]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/pfsense/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "", "cache_ttl_sec", 30)
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

  -- word set: Disabled/Unconfigured/SSH Down/Stale/no-data — fall back.
  -- word nil but loss_pct/latency_ms empty: a cache written before this
  -- session's fetch_pfsense.sh change (gateway.online present, the two new
  -- keys not). Same graceful fallback either way, rather than drawing a
  -- meter off missing data.
  if word or loss_pct == "" or latency_ms == "" then
    return { loss_pct = GATEWAY_METER_PLACEHOLDER.loss_pct, avg_ms = GATEWAY_METER_PLACEHOLDER.avg_ms }
  end

  return {
    loss_pct = tonumber(loss_pct) or GATEWAY_METER_PLACEHOLDER.loss_pct,
    avg_ms = tonumber(latency_ms) or GATEWAY_METER_PLACEHOLDER.avg_ms,
  }
end

-- WAN box, CM1000 column: T3 count / DS2 SNR / US AVG power, from modem's
-- status.json (fetch_modem.py). Independent Disabled/Unconfigured/Stale
-- chain gated on providers.modem (core.toml) and modem's own profile TTL
-- (cache_ttl_sec, 300s default) — same shape as router_fields() above,
-- but with no ssh_tripped check: modem's status.json has no ssh_gate key
-- (it's a direct HTTP scrape of the CM1000 admin UI, not an SSH
-- collector), matching modem_fields()/docsis_word() above.
--
-- DS2 is downstream_ofdm_channels[1] (0-based jq index = 2nd entry, not
-- the 1st) — confirmed against the live cache file, where that entry's
-- snr_db (35.8) matches the previz label's "DS2 SNR 35.8DB" exactly. US
-- AVG power is the mean power_dbmv across upstream_channels with
-- locked == true (unlocked slots carry 0.0 and must not drag the average
-- down). T3 count is recent_t3_timeouts, with its window
-- (event_log_window_minutes) rendered as whole hours to match the
-- previz's "(1H)" suffix.
--
-- This is unrelated to wan_boot_state_line()/wan_mtr_line() above, which
-- stay their own conditional rows, drawn separately by
-- draw_wan_conditional_rows() in frame.lua.
local function cm1000_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "modem", false)

  local profile = suite_profile("modem", "local")
  local path = string.format("%s/shared/modem/%s/status.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.recent_t3_timeouts // 0), (.event_log_window_minutes // 60), '
    .. '(.downstream_ofdm_channels[1].snr_db // 0), '
    .. '([.upstream_channels[]? | select(.locked) | .power_dbmv] | if length > 0 then (add / length) else 0 end)'
    .. '] | @tsv'
  )
  local fields = split_tsv(row, 6)
  local state, note = fields[1], fields[2]
  local t3_count, window_min, ds2_snr, us_avg = fields[3], fields[4], fields[5], fields[6]

  local profile_toml = parse_simple_toml(RUNTIME_ROOT .. "/profiles/modem/" .. profile .. ".toml")
  local cache_ttl_sec = toml_number(profile_toml, "", "cache_ttl_sec", 300)
  local mtime = file_mtime(path)
  local cache_age_sec = mtime and (os.time() - mtime) or nil

  local word = resolve_state_word({
    enabled = enabled,
    state = state,
    note = note,
    cache_age_sec = cache_age_sec,
    cache_ttl_sec = cache_ttl_sec,
  })

  if word then
    return { word }
  end

  local hours = math.max(1, math.floor(((tonumber(window_min) or 60) / 60) + 0.5))
  return {
    string.format("T3 X %d (%dH)", tonumber(t3_count) or 0, hours),
    string.format("DS2 SNR %.1fDB", tonumber(ds2_snr) or 0),
    string.format("US AVG %.1fDBMV", tonumber(us_avg) or 0),
  }
end

function M.wan_panel_data()
  local cm_ok, cm1000 = pcall(cm1000_fields)
  if not cm_ok or type(cm1000) ~= "table" then
    cm1000 = { "NO DATA" }
  end

  local gw_ok, gw = pcall(gateway_meter_fields)
  if not gw_ok or type(gw) ~= "table" then
    gw = { loss_pct = GATEWAY_METER_PLACEHOLDER.loss_pct, avg_ms = GATEWAY_METER_PLACEHOLDER.avg_ms }
  end

  return {
    loss_pct = gw.loss_pct,
    avg_ms = gw.avg_ms,
    cm1000 = cm1000,
  }
end

return M
