-- SitRep header status column (DOCSIS / PFSENSE) and the WAN panel's
-- CM1000 detail column (T3/DS1 SNR/DS2 SNR/US AVG power, plus the
-- conditional MTR (PI5) row appended at the end — see
-- cm1000_fields()/M.wan_panel_data()).
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
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-sitrep")
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "sitrep"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local CACHE = {
  tick = nil, lines = { "DOCSIS", "PFSENSE" },
  alert_tick = nil, alert_lines = { "NO DATA" },
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

-- Single read of modem's status.json, shared by docsis_word() (and
-- available for any other CM1000 consumer that needs Disabled/Unconfigured/
-- Stale precedence without a second jq call).
local function modem_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "modem", false)

  local profile = suite_profile("modem", "local")
  local path = string.format("%s/shared/modem/%s/status.json", CACHE_ROOT, profile)
  local row = json_row(
    path,
    '[.state, (.note // ""), (.connectivity_state.status // ""), (.connectivity_state.comment // "")] | @tsv'
  )
  local fields = split_tsv(row, 4)

  local cache_ttl_sec = toml_number(parse_simple_toml(RUNTIME_ROOT .. "/profiles/modem/" .. profile .. ".toml"), "", "cache_ttl_sec", 300)
  local mtime = file_mtime(path)
  local cache_age_sec = mtime and (os.time() - mtime) or nil

  return {
    enabled = enabled,
    state = fields[1],
    note = fields[2],
    connectivity_status = fields[3],
    connectivity_comment = fields[4],
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

-- WAN panel, CM1000 detail table: MTR (PI5) row. Reads mtr_state.json,
-- written by gtex62-core's providers/mtr/fetch_mtr.sh — the SSH trigger
-- to Pi5 that starts (never stops — Option B, no auto-kill; see
-- design/sitrep-design-notes.md § Alert banner / outage detection, "MTR
-- auto-trigger") the pre-existing, untouched mtr_overnight_log.sh once
-- the gateway-offline duration crosses the same threshold the SEVERE
-- alert uses. This reads that state file directly, per the stub's own
-- prior comment — not the gateway-offline duration (crossing the
-- threshold means the script *should* be running, not that it's
-- confirmed running; fetch_mtr.sh's own confirm/reconfirm step is what
-- makes `running` here trustworthy).
--
-- Hidden-unless-triggered: absent whenever nothing is running, not just
-- when data happens to be quiet. Disabled/SSH-Down/Stale precedence
-- (resolve_state_word(), used by pfsense_word()/docsis_word()) is
-- deliberately not surfaced here — this row is meant to stay invisible in
-- the overwhelmingly common case (mtr_overnight_log.sh not running), so a
-- routine SSH hiccup to Pi5 shouldn't turn it into a second always-on
-- status line. Appended to the CM1000 column's line list by
-- M.wan_panel_data() below, not drawn separately.
local function mtr_line()
  local profile = suite_profile("mtr", "pi5")
  local path = string.format("%s/shared/mtr/%s/mtr_state.json", CACHE_ROOT, profile)
  local row = json_row(path, '[(.running // false), (.started_at_epoch // "")] | @tsv')
  local fields = split_tsv(row, 2)
  local running, started_epoch = fields[1], fields[2]

  if running ~= "true" then return nil end

  local started = tonumber(started_epoch)
  if not started then
    return "MTR (PI5)"
  end
  local elapsed = math.max(0, os.time() - started)
  local hours = math.floor(elapsed / 3600)
  local mins = math.floor((elapsed % 3600) / 60)
  return string.format("MTR (PI5) %02d:%02d", hours, mins)
end

local function refresh()
  local tick = os.time()
  if CACHE.tick == tick then return end
  CACHE.tick = tick

  local pf_ok, pf_word = pcall(pfsense_word)
  if not pf_ok then pf_word = "NO DATA" end

  local modem_ok, modem = pcall(modem_fields)
  local docsis
  if modem_ok then
    local d_ok, d_word = pcall(docsis_word, modem)
    docsis = d_ok and d_word or "NO DATA"
  else
    docsis = "NO DATA"
  end

  CACHE.lines = {
    "DOCSIS // " .. docsis,
    "PFSENSE // " .. pf_word,
  }
end

function M.header_status_lines()
  refresh()
  return CACHE.lines
end

-- SitRep header, alert-banner column (right side): severity-sorted,
-- parent/child-grouped alert queue from gtex62-core's alert-banner
-- watcher (providers/alerts/fetch_alerts.sh -> shared/alerts/{profile}/
-- banner.json). Local-only collector, no ssh_gate (same shape as
-- vpn.lua's vpn_fields()) — gated on providers.alerts (core.toml) and
-- its own profile TTL. No profiles/alerts/{profile}.toml ships yet
-- (fetch_alerts.sh has no TTL notion of its own — "safe to re-run on any
-- cadence" per its own header comment), so cache_ttl_sec below falls
-- back to a 60s default. Note: fetch_alerts.sh also isn't wired into
-- gtex62-core-launch or any cron yet (core.toml's providers.alerts
-- comment), so banner.json only advances when something runs it
-- manually — a future-session gap, not fixed here.
--
-- banner.json's queue[] is already severity-sorted server-side (SEVERE
-- before CAUTION; top-level entries are never INFORMATIONAL — only
-- children carry that tier) and parent/child grouped by nesting
-- (children[] always present, empty array when there are none).
-- message text is pre-built server-side and displayed verbatim — never
-- reconstructed here.
local function alert_banner_cfg()
  local ok, theme = pcall(dofile, SUITE_DIR .. "/theme/theme.lua")
  if ok and type(theme) == "table" then
    return theme.alert_banner or {}
  end
  return {}
end

-- Flattens each queue entry to one display line immediately followed by
-- its children's lines, in banner.json's existing array order — no
-- re-sorting, re-grouping, or separating a parent from its children.
-- Filter deliberately avoids jq's `as $var` binding: json_row() shells
-- out through a double-quoted string (Lua's %q is Lua-string quoting,
-- not shell quoting — it does not escape `$`), so a named variable like
-- `$e` gets stripped by shell variable expansion before jq ever sees it.
-- The implicit `.` already carries the right context across both parts
-- of the comma expression, so no variable is needed.
local function alert_flat_lines(path)
  local lines = {}
  local raw = json_row(path, '.queue[]? | ([.message]), (.children[]? | [.message]) | @tsv')
  if not raw then return lines end
  for line in raw:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  return lines
end

local function alert_banner_lines()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "alerts", false)

  local profile = suite_profile("alerts", "main_router")
  local path = string.format("%s/shared/alerts/%s/banner.json", CACHE_ROOT, profile)
  local row = json_row(path, '[.state, (.note // "")] | @tsv')
  local fields = split_tsv(row, 2)
  local state, note = fields[1], fields[2]

  local cache_ttl_sec = toml_number(parse_simple_toml(RUNTIME_ROOT .. "/profiles/alerts/" .. profile .. ".toml"), "", "cache_ttl_sec", 60)
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
    -- Every other panel sits next to its own labeled box, so a bare
    -- state word ("STALE - 14M AGO") is self-evident there. This column
    -- has no title of its own (right half of the header row) — prefixed
    -- so it's self-labeled regardless of position. resolve_state_word()'s
    -- shared chain is untouched; only this call site's return is
    -- prefixed, so no other panel's wording changes. SSH DOWN never
    -- reaches here (alerts has no ssh_gate, ssh_tripped omitted above,
    -- same as vpn.lua) — DISABLED/UNCONFIGURED/STALE/NO DATA are the
    -- reachable branches, all fall through this one prefix point.
    -- Measured against the real column width (339px, header box width
    -- minus the divider+inset offset) and the real font/size this column
    -- renders at: "ALERT BANNER STALE - 14M AGO" is 302px, comfortably
    -- under, even a 4-digit-minute edge case (324px) still fits — no
    -- need for the shorter "ALERTS" fallback.
    return { "ALERT BANNER " .. word }
  end

  local all_lines = alert_flat_lines(path)
  if #all_lines == 0 then
    return { "NO ACTIVE ALERTS" }
  end
  if #all_lines <= 3 then
    return all_lines
  end

  -- More than 3 lines queued: the whole banner scrolls upward one line
  -- at a time (sitrep-design-notes.md § Alert banner / outage detection,
  -- "Scroll behavior"). window_start is a pure function of wall-clock
  -- time (no persisted animation counter — matches this codebase's
  -- existing os.time()-keyed recompute idiom, e.g. this file's own
  -- refresh(), rather than inventing frame-tick state), so it can't
  -- drift on a missed redraw and needs nothing extra preserved across
  -- reloads. Wraps circularly (marquee-style) rather than bouncing back
  -- to the top, so the window is always exactly 3 lines, never padded.
  local interval = tonumber(alert_banner_cfg().scroll_interval_sec) or 3
  if interval <= 0 then interval = 3 end
  local total = #all_lines
  local start = math.floor(os.time() / interval) % total
  local shown = {}
  for i = 0, 2 do
    shown[#shown + 1] = all_lines[((start + i) % total) + 1]
  end
  return shown
end

function M.header_alert_lines()
  local tick = os.time()
  if CACHE.alert_tick ~= tick then
    CACHE.alert_tick = tick
    local ok, lines = pcall(alert_banner_lines)
    CACHE.alert_lines = (ok and type(lines) == "table" and #lines > 0) and lines or { "NO DATA" }
  end
  return CACHE.alert_lines
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
-- fields are dropped (nil, rendered as "/" by frame.lua's fallback). The
-- router row still surfaces that word spanning the merged L01-L15 width
-- (frame.lua, same region the old single LOAD cell occupied) since it has
-- no other display location. The interface row does not: WAN/HOME/IOT/
-- GUEST/INFRA/CAM/VPN fall back to plain "/" placeholders on a collector
-- failure rather than repeating the word into one narrow ~89px cell —
-- confirmed 2026-09-07 this was landing in the WAN and VPN cells
-- (ifaces[1].tx / vpn entry.tx) and, for wider words like "STALE - NM
-- AGO", visibly overflowing into the neighboring cell with no clipping.
-- The header status column (pfsense_word() above) and the VPN box's own
-- STATUS block (vpn.lua) are each collector's one authoritative surfaced
-- location for that word; the interface table is data-only.

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

-- ncpu is polled fresh from router.json every cycle (sysctl hw.ncpu over
-- SSH, see fetch_router.sh) — not a build-time constant — so this formats
-- each L01/L05/L15 cell's suffix off the same single live-read ncpu value
-- passed in by the caller, rather than hardcoding "4C" as a literal string
-- three times.
local function format_load_cell(value, ncpu)
  value, ncpu = tonumber(value), tonumber(ncpu)
  if not value or not ncpu then return nil end
  return string.format("%.2f/%dC", value, ncpu)
end

local function hardware_model()
  local site_cfg = parse_simple_toml(RUNTIME_ROOT .. "/site.toml")
  return (site_cfg.pfsense or {}).hardware_model
end

-- PFSENSE panel, system-info row: VERSION/CPU/BIOS/L01/L05/L15 from
-- router.json (fetch_router.sh). Independent chain, gated on
-- providers.pfsense.router and router.json's own mtime — same shape as
-- pfsense_word() above but keyed to a different collector/TTL ([router]
-- section, 60s default, matching fetch_router.sh's own default).
--
-- On a non-healthy word (Disabled/Unconfigured/SSH Down/Stale/no-data),
-- load_l1/l5/l15 are all nil and load_word carries the word instead —
-- frame.lua draws that spanning the merged L01-L15 width rather than
-- squeezed into one 98px cell (some words, e.g. "STALE - 14M AGO", are
-- too wide for a single cell; the merged region is exactly the space the
-- single LOAD cell used to occupy). Same "surfaced once" convention as
-- pfsense_interfaces_fields()/vpn_interface_fields() below.
local function router_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers.pfsense", "router", false)

  local profile = suite_profile("pfsense", "main_router")
  local path = string.format("%s/shared/pfsense/%s/router.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.ssh_gate.tripped // false), (.version // ""), (.hw_model // ""), (.ncpu // 0), '
    .. '(.load.l1 // 0), (.load.l5 // 0), (.load.l15 // 0), (.bios_version // "")] | @tsv'
  )
  local fields = split_tsv(row, 10)
  local state, note, ssh_tripped = fields[1], fields[2], fields[3]
  local version, hw_model, ncpu, load_l1, load_l5, load_l15, bios_version =
    fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10]

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
    return { version = nil, cpu = nil, bios = nil, load_word = word }
  end
  return {
    version = strip_version_suffix(version),
    cpu = extract_cpu_code(hw_model),
    bios = extract_bios_ver(bios_version),
    load_l1 = format_load_cell(load_l1, ncpu),
    load_l5 = format_load_cell(load_l5, ncpu),
    load_l15 = format_load_cell(load_l15, ncpu),
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
  if not word then
    entry.rx = human_bytes(rx_bytes)
    entry.tx = human_bytes(tx_bytes)
  end
  return entry
end

function M.pfsense_panel_data()
  local router_ok, router = pcall(router_fields)
  if not router_ok then router = { load_word = "NO DATA" } end

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
    load_word = router.load_word,
    load_l1 = router.load_l1,
    load_l5 = router.load_l5,
    load_l15 = router.load_l15,
    interfaces = interfaces,
  }
end

-- WAN box, GATEWAY meter: loss%/avg-latency two-bar meter. Previously a
-- static placeholder (fetch_pfsense.sh's gateway.online was a boolean, not
-- a loss%/latency sample); now real, since fetch_pfsense.sh's live dpinger
-- read added gateway.loss_pct/latency_ms/latency_stddev_ms to status.json
-- this session. On no-data (see below), returns nil for both fields rather
-- than a numeric placeholder — frame.lua's bar-drawing renders that as an
-- explicit "XXX%"/"XXX" label with a zero-height bar, an obviously-fake
-- placeholder rather than a plausible-looking number (a static 25%/53ms
-- used to be indistinguishable from a real reading at a glance).
--
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
    return {}
  end

  return {
    loss_pct = tonumber(loss_pct),
    avg_ms = tonumber(latency_ms),
  }
end

-- WAN box, CM1000 column: T3 count / DS1 SNR / DS2 SNR / US AVG power,
-- from modem's status.json (fetch_modem.py). Independent
-- Disabled/Unconfigured/Stale chain gated on providers.modem (core.toml)
-- and modem's own profile TTL (cache_ttl_sec, 300s default) — same shape
-- as router_fields() above, but with no ssh_tripped check: modem's
-- status.json has no ssh_gate key (it's a direct HTTP scrape of the
-- CM1000 admin UI, not an SSH collector), matching
-- modem_fields()/docsis_word() above.
--
-- DS1/DS2 are downstream_ofdm_channels[0]/[1] (0-based jq index — by
-- array position, not by which channel is actually worse) — DS2's index
-- confirmed against the live cache file, where that entry's snr_db (35.8)
-- matched the previz label's "DS2 SNR 35.8DB" exactly. DS1 added
-- 2026-09-02 after a real incident showed the blind spot in only
-- surfacing [1]: during that outage, channel 193 (index 0, previously
-- not displayed) took the harder SNR hit (40.3 -> 22.3dB) while channel
-- 194 (index 1, the one shown) stayed comparatively healthy — so both
-- channels need to be visible, not just one. Same read/format/precision
-- as DS2, no new derivation logic; drawn directly above DS2 so the pair
-- reads together. US AVG power is the mean power_dbmv across
-- upstream_channels with locked == true (unlocked slots carry 0.0 and
-- must not drag the average down). T3 count is recent_t3_timeouts.
--
-- "T3 X N TOTAL", not "T3 X N (1H)" (changed 2026-09-08, see roadmap's
-- Sept 8 session log): recent_t3_timeouts is a whole collapsed row's
-- docsDevEvCounts, not "how many happened in the last hour" — the CM1000
-- collapses a repeating identical event into one row and only ever
-- updates that row's LastTime/Counts, so once the row's LastTime lands
-- inside the trailing window, its *entire* history rides along with it.
-- The old "(1H)" suffix implied a fresh-this-hour count and a user was
-- misreading a count going 90 -> 91 as "91 fresh timeouts this hour"
-- when it was really "one more on a condition recurring since early
-- that morning" — confirmed live that the CM1000's own GUI can't even
-- show the difference (it renders a collapsed row's FirstTime as "Time"
-- and never surfaces LastTime/Counts at all, so the row looked
-- frozen/quiet all day while it was actually still active). "TOTAL" is
-- the honest word for what this number actually is. The matching
-- "SINCE HH:MM" anchor (recent_t3_since, from fetch_modem.py's
-- compute_recent_t3()) lives in the Alert Banner's comcast-degraded-t3
-- child instead of here — see fetch_alerts.sh — where a single line has
-- room for both the total and the anchor together; this column only has
-- room for the total.
--
-- This is unrelated to mtr_line() above, which M.wan_panel_data() below
-- appends to this column's line list as its final entry, rather than
-- folding it in here.
local function cm1000_fields()
  local core_cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  local enabled = toml_bool(core_cfg, "providers", "modem", false)

  local profile = suite_profile("modem", "local")
  local path = string.format("%s/shared/modem/%s/status.json", CACHE_ROOT, profile)
  local row = json_row(path,
    '[.state, (.note // ""), (.recent_t3_timeouts // 0), '
    .. '(.downstream_ofdm_channels[0].snr_db // 0), (.downstream_ofdm_channels[1].snr_db // 0), '
    .. '([.upstream_channels[]? | select(.locked) | .power_dbmv] | if length > 0 then (add / length) else 0 end)'
    .. '] | @tsv'
  )
  local fields = split_tsv(row, 6)
  local state, note = fields[1], fields[2]
  local t3_count, ds1_snr, ds2_snr, us_avg = fields[3], fields[4], fields[5], fields[6]

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

  return {
    string.format("T3 X %d TOTAL", tonumber(t3_count) or 0),
    string.format("DS1 SNR %.1fDB", tonumber(ds1_snr) or 0),
    string.format("DS2 SNR %.1fDB", tonumber(ds2_snr) or 0),
    string.format("US AVG %.1fDBMV", tonumber(us_avg) or 0),
  }
end

function M.wan_panel_data()
  local cm_ok, cm1000 = pcall(cm1000_fields)
  if not cm_ok or type(cm1000) ~= "table" then
    cm1000 = { "NO DATA" }
  end

  -- MTR (PI5) row: appended last, same hidden-unless-triggered contract as
  -- mtr_line() itself — absent (nil) in the overwhelmingly common case.
  local mtr_ok, mtr = pcall(mtr_line)
  if mtr_ok and mtr then
    cm1000[#cm1000 + 1] = mtr
  end

  local gw_ok, gw = pcall(gateway_meter_fields)
  if not gw_ok or type(gw) ~= "table" then
    gw = {}
  end

  return {
    loss_pct = gw.loss_pct,
    avg_ms = gw.avg_ms,
    cm1000 = cm1000,
  }
end

return M
