# Reading the Widget

Quick reference for interpreting the live SitRep display — what each
field means, where its number actually comes from, and whether a
given reading is normal or a real problem. Written against the source
in `lua/suite/{pf,ap,vpn,pihole,pfblockerng}.lua` and `lua/ui/frame.lua`
as of this writing; if the code changes, this doc is wrong until
updated to match.

---

## 1. State-word legend

Every panel/collector runs the same precedence chain,
`resolve_state_word()` (duplicated per-file: `pf.lua`, `ap.lua`,
`vpn.lua`, `pihole.lua`, `pfblockerng.lua`). Given a collector's
enable flag, its cache's `state`/`note` fields, an `ssh_gate.tripped`
flag (where applicable), and the cache's age vs. its TTL, it returns
one of these words, checked **in this order** — the first match wins:

| Word | Condition | Meaning |
| --- | --- | --- |
| `DISABLED` | `providers.*` flag is off in `core.toml` | Collector is turned off on purpose. Not a fault. |
| `UNCONFIGURED` | cache `state == "error"` and the `note` text looks like a setup problem (matches `profile`/`credential`/`placeholder`/`change_me`/`password`/`ssh_target`/`not configured`) | Collector ran but hit a config problem (bad profile, missing credential, etc.), not a runtime failure. |
| `SSH DOWN` | `ssh_gate.tripped == true` | The collector's SSH reachability gate has tripped — box is unreachable over SSH. Local-only collectors (VPN) never show this; their `ssh_tripped` is always nil. |
| `STALE - <N>M AGO` | cache age > 2× the provider's `cache_ttl_sec` | The cache file hasn't been refreshed recently enough to trust. `<N>` is `floor(age_seconds / 60)`. TTLs differ by provider — see table below. |
| `NO DATA` | no cache file / unparseable state, or `state == "error"` without an unconfigured-looking note | Something else went wrong reading the cache; genuinely unclassified. |
| *(falls through)* | none of the above | Caller fills in its own healthy wording — usually `NOMINAL`, or the panel's real field values. |

**STALE thresholds (2× each provider's `cache_ttl_sec`)**, read from
`profiles/<domain>/<profile>.toml` (falling back to the default shown
if that section/key is absent):

| Source file | TTL default | STALE fires above |
| --- | --- | --- |
| `pfsense/<profile>/status.json` (pfSense status, interfaces, gateway meter) | 30s | 60s |
| `pfsense/<profile>/router.json` (VERSION/CPU/BIOS/LOAD) | 60s | 120s |
| `pfsense/<profile>/pihole.json` | 60s | 120s (2 min) |
| `pfsense/<profile>/pfblockerng.json` | 300s | 600s (10 min) |
| `pfsense/<profile>/ap_status.json` / `ap_clients.json` | 120s | 240s (4 min) |
| `modem/<profile>/status.json` (DOCSIS, CM1000 detail) | 300s | 600s (10 min) |
| `vpn/<profile>/vpn.json` | 10s | 20s |

A `STALE` word replaces that collector's numeric fields with the word
itself (see per-panel notes below for exactly which cell it lands in)
— it isn't drawn alongside stale numbers.

---

## 2. Per-panel field guide

### Header — DOCSIS / PFSENSE

Two lines, `lua/suite/pf.lua`'s `M.header_status_lines()`.

- **DOCSIS** — the CM1000 modem's own reported DOCSIS *Connectivity
  State* (`modem/<profile>/status.json`, `connectivity_state.status`),
  **not** WAN ping reachability. `OK` displays as `NOMINAL`; any other
  raw value displays uppercased as-is. This answers "is the modem
  actually registered with Comcast", separate from whether the
  gateway is pingable.
- **PFSENSE** — `pfsense_word()`, from `pfsense/<profile>/status.json`.
  `NOMINAL` when the state chain resolves clean.

### Header — alert banner

Right side of the header box, `lua/suite/pf.lua`'s `M.header_alert_lines()`
(drawn by `lua/ui/frame.lua`'s `draw_header_alert_banner`). Reads
`alerts/<profile>/banner.json` (`gtex62-core/providers/alerts/fetch_alerts.sh`
— see [SitRep Architecture § Alert Banner
Watcher](../../gtex62-core/docs/sitrep-architecture.md#alert-banner-watcher)
for the full schema), gated on `providers.alerts` + its own profile TTL, same
`resolve_state_word()` chain as every other panel — a stale/disabled
**collector** is a state word, distinct from "no alerts currently active."

- **Healthy, no conditions active**: single line, `NO ACTIVE ALERTS`.
- **Healthy, conditions active**: `banner.json`'s `queue[]` is already
  severity-sorted server-side (SEVERE before CAUTION; top-level entries are
  never `INFORMATIONAL` — only `children[]` carry that tier). Each queue
  entry is flattened to one line immediately followed by its children's
  lines, preserving array order — a parent is never separated from its
  children, even across the severity sort. Message text is pre-built
  server-side (e.g. `COMCAST OUTAGE DETECTED`, `KS BLOCKING TRAFFIC`,
  `AP OFFLINE: <label>`, `MAC/IP MISMATCH (<N>)`) and displayed
  verbatim. `COMCAST DEGRADED`'s `comcast-degraded-t3` child reads
  `T3: <n> TOTAL SINCE <HH:MM>` (changed 2026-09-08, was `T3: <n> IN
  <window>M`) — the `SINCE` anchor is the WAN panel's `T3 X N TOTAL`
  line's missing timestamp; it lives here instead because this line has
  room for both the total and the anchor together, the WAN panel's
  CM1000 column doesn't (see § WAN panel above). `KS BLOCKING TRAFFIC` is a deliberately distinct SEVERE
  condition from `COMCAST OUTAGE DETECTED` — same "nothing works"
  symptom, but PIA's Advanced Kill Switch blocking traffic while
  disconnected, not a WAN outage (message shortened from the original
  "ADVANCED KILL SWITCH BLOCKING ALL TRAFFIC" — measured too wide for
  the alert-banner column's 339px width via real `text_extents` against
  the "GTex62 OSA" render font); see
  [gtex62-sitrep/design/sitrep-design-notes.md § Alert banner / outage
  detection](../design/sitrep-design-notes.md) for the full condition
  table.
- Up to 3 flattened lines are shown at once. More than 3: the whole banner
  scrolls upward one line at a time, wrapping circularly (marquee-style),
  at `theme.alert_banner.scroll_interval_sec` (default 3s) — a pure
  function of wall-clock time (`os.time()`), not a persisted animation
  counter, so it can't drift on a missed redraw.
- No profile TTL file ships yet for the `alerts` domain, so staleness falls
  back to a 60s default (STALE fires above 120s). Also worth knowing:
  `fetch_alerts.sh` isn't wired into `gtex62-core-launch` or any cron as of
  this writing — `banner.json` only advances when something runs it
  manually, so this column going `STALE` a couple minutes after the last
  manual run is expected, not a bug.

### WAN panel

`wan_panel_data()` in `pf.lua`. Two content blocks: the GATEWAY meter
and the CM1000 detail column.

- **GATEWAY meter (LOSS / AVG bars)** — real data, from
  `status.json`'s `gateway.loss_pct` / `gateway.latency_ms`, which
  `fetch_pfsense.sh` reads live off pfSense's **dpinger** socket
  (dpinger's own rolling 60-second average — same signal pfSense's own
  gateway-quality graph uses). **Normal**: `LOSS 000%`, `AVG` in the
  low single-digit ms range on a healthy local gateway hop. Both bars
  share one 0–100 scale (`theme.wan.gateway_meter.bar_max`), so the
  AVG bar is scaled 0–100ms, not auto-ranged — a bar that looks
  "full" for AVG means ≥100ms to the gateway, not a maxed-out
  percentage.
  No-data case (state chain unclean, or an old cache written before
  `loss_pct`/`latency_ms` existed in `status.json`): `LOSS XXX%` /
  `AVG XXX` with both bars at zero height — an obviously-fake
  placeholder rather than a plausible-looking number.
- **CM1000 column** — from `modem/<profile>/status.json`:
  - `T3 X N TOTAL` (changed 2026-09-08, was `T3 X N (HH)`) —
    `recent_t3_timeouts`. **Normal**: 0. **Read this as a lifetime
    count of a currently-active condition, not "N timeouts in the last
    hour":** the CM1000 collapses a repeating identical T3 event into
    one log row and only updates that row's `LastTime`/repeat counter,
    so `N` is that row's *entire* history, riding along whenever its
    `LastTime` lands inside the collector's trailing window
    (`event_log_window_minutes`) — a count going 90 -> 91 means one
    fresh occurrence on an old condition, not 91 new ones. Confirmed
    live 2026-09-08 that the CM1000's own admin GUI can't even show
    this distinction (see
    [Network Providers Roadmap's Sept 8
    session log](../../gtex62-core/docs/network-providers-roadmap.md)) —
    this field is the more trustworthy read. No timestamp is shown in
    this column (no room for it); the matching `SINCE HH:MM` anchor is
    in the header alert banner's `comcast-degraded-t3` child instead,
    when that alert is active — see below.
  - `DS1 SNR xx.xDB` / `DS2 SNR xx.xDB` — signal-to-noise ratio of
    the *first* and *second* downstream OFDM channels
    (`downstream_ofdm_channels[0]` / `[1]`, 0-based index — by array
    position, not by which channel happens to be worse). Added
    2026-09-02: a real incident showed only displaying `[1]` was a
    blind spot — channel 193 (index 0) took the harder SNR hit while
    channel 194 (index 1) stayed comparatively healthy, so both are
    now shown as a pair. No modem-health thresholds are implemented
    yet (see § 3) — read these as trend lines, not pass/fail numbers.
  - `US AVG xx.xDBMV` — mean upstream power across only the *locked*
    upstream channels (unlocked slots report 0.0 and are excluded so
    they don't drag the average down).
  - On a non-healthy state, this whole column collapses to a single
    state word instead of four lines.

### PFSENSE panel (system-info + interface table)

`pfsense_panel_data()` in `pf.lua`, three **independent** collectors —
it's expected and normal for one row (or even one interface column) to
show real data while another shows `STALE`, since each has its own
cache file and TTL.

- **HARDWARE** — not collected by any provider; a static value read
  from `site.toml`'s `[pfsense].hardware_model`. Never shows a state
  word or goes stale.
- **VERSION / CPU / BIOS / LOAD** — from `router.json`
  (`fetch_router.sh`). VERSION strips the `-RELEASE` suffix; CPU
  extracts the chip code (e.g. `N5105`) out of the full `hw_model`
  string; BIOS extracts just the version number out of the full
  Dasharo/coreboot string; LOAD is `L5 <5-min-load> / <ncpu>C`. On a
  bad state, VERSION/CPU/BIOS go blank (`/`) and the word appears in
  the LOAD cell instead.
- **WAN / HOME / IOT / GUEST / INFRA / CAM** — from `status.json`
  (`fetch_pfsense.sh`), one column per interface. rx/tx are
  `ibytes`/`obytes` **humanized directly** — cumulative byte counters
  since last reboot/reset, not an instantaneous throughput rate. A
  large `T`-scale number is expected on a long-uptime router; it is
  not a live speed. On a bad state, the word appears in the WAN
  column's tx cell.
- **VPN** — from `vpn.json` (`fetch_vpn.sh`'s `transfer.rx_bytes` /
  `tx_bytes`), same cumulative-byte-counter caveat as above. A third,
  fully independent collector (local-only, no SSH gate, its own
  `providers.vpn` flag and 10s-default TTL). On a bad state, the word
  appears in this column's tx cell.

### VPN panel

`vpn_panel_data()` in `vpn.lua`.

- **LTNCY meter** — real data, from `vpn.json`'s `tunnel_latency_ms`,
  which `fetch_vpn.sh` samples live with a single ICMP echo sent
  through the tunnel interface itself (`ping -I <iface> -c1 -W1
  1.1.1.1`, not the VPN endpoint IP — PIA excludes the endpoint's own
  IP from the tunnel's routes, so pinging it wouldn't actually test
  the tunnel). Same 0–100 scale as the WAN GATEWAY meter's AVG bar
  (`theme.vpn.ltncy_meter.bar_max`), not auto-ranged. `tunnel_latency_ms`
  is `null` both when disconnected (`health` = `DEAD`) and when the
  ping itself fails while otherwise connected — either way, renders
  `XXX` at zero-height bar rather than a state word or a
  plausible-looking number, same convention as the GATEWAY meter's
  own no-data case.
- **STATUS block**, from `vpn/<profile>/vpn.json`:
  - Line 1 — tunnel health: `health` field from `fetch_vpn.sh`
    (`HEALTHY`/`STALE`/`DEAD`, displayed as `NOMINAL`/`STALE`/`DEAD`).
    This is a **different** signal from the collector-level STALE in
    § 1 — it fires off the WireGuard handshake age even when
    `vpn.json` itself is being written on schedule. Thresholds are
    sized off WireGuard's own **REKEY-AFTER-TIME**, not PIA's
    keepalive: a session renegotiates a fresh handshake once it's
    120s old, on its own schedule, **independent of**
    `PersistentKeepalive` (25s, confirmed live) — keepalive sends
    just hold the NAT mapping open and don't trigger a handshake
    renewal themselves. Live capture confirmed this directly: the
    handshake timestamp advanced only every ~120s regardless of
    keepalive traffic, which is why the thresholds are 120s-shaped,
    not 25s-shaped. `HEALTHY` = connected and handshake < 130s (full
    normal rekey cycle plus margin), `STALE` = connected and
    handshake 130–180s (past normal rekey, not yet
    REJECT-AFTER-TIME), `DEAD` = not connected, or handshake > 180s
    (REJECT-AFTER-TIME) or absent. See
    [gtex62-core/docs/network-providers-roadmap.md § Health
    Classification (VPN)](../../gtex62-core/docs/network-providers-roadmap.md)
    for the full derivation.
  - `REGION:` — `region`, uppercased, from piactl.
  - `PROTOCOL:` — `WG` for WireGuard, `OVPN` for OpenVPN (unverified —
    this deployment has only ever been observed on WireGuard), raw
    uppercased value for anything else.
  - `HANDSHAKE` — `latest_handshake_seconds` formatted `M:SS`.
    **Normal**: cycles up to ~2:00 (REKEY-AFTER-TIME), not the 25s
    keepalive interval — the keepalive keeps the tunnel's NAT mapping
    alive but doesn't reset this timer.
  - `KS` — killswitch, `ON`/`OFF`/`ON (ADV)`. The `(ADV)` suffix means
    PIA's "Advanced Kill Switch" is the configured mode rather than the
    regular "VPN Kill Switch" — a distinction `killswitch` alone can't
    carry, since both modes route identically (`dev <iface>` +
    `blackhole` in `piavpnFwdrt`) while connected; it comes from a
    second, independent field (`killswitch_mode`, read from PIA's own
    `settings.json`). See [gtex62-core/docs/network-providers-roadmap.md
    § Killswitch Mode Detection — Advanced vs. Regular](../../gtex62-core/docs/network-providers-roadmap.md)
    for the full investigation.
  - On a bad collector state, all five lines collapse to the single
    state word.

### PI-HOLE panel

`pihole_panel_data()` in `pihole.lua`, reading
`pfsense/<profile>/pihole.json` (`fetch_pihole.sh` — lives under the
pfSense cache namespace/profile because Pi-hole runs on Pi5, reached
over its own SSH target, not on pfSense itself; gate flag is
`providers.pfsense.pihole`).

- **SYSTEM** — `ACTIVE`/`INACTIVE` (instantaneous `systemctl is-active`
  read — **not** the same thing as the duration-gated PI-HOLE INACTIVE
  alert-banner condition, which requires staying down past
  `core.toml`'s `alerts.pihole_inactive_duration_sec`), plus `L15:`
  15-minute load average.
- **TOTALS** — `BLOCKED:` count and blocked-percentage, `DOMAINS:`
  (domains on the blocklist), `TOTAL:` (queries seen). All
  comma-grouped. No inherent "normal" range — these are cumulative
  counters that only grow (until Pi-hole's own stats reset/rotation).
- On a bad state, both blocks collapse to the single state word.

### PFBLOCKERNG panel

`pfblockerng_panel_data()` in `pfblockerng.lua`, reading
`pfsense/<profile>/pfblockerng.json` (gate flag
`providers.pfsense.pfblockerng`).

- **IP BLOCK** — one bare number, `pfb_ip_total` (a raw pfctl packet
  count). No hit-rate/percentage field exists in the source data, so
  unlike DNSBL there's no `HITS:` row here — that's a genuine data-
  shape asymmetry, not a missing label.
- **DNSBL** — `DNSBL:` count (`pfb_dnsbl_total`), `HITS:` percentage
  (`pfb_dnsbl_pct` = `pfb_dnsbl_total / resolver_total`, pre-rounded
  server-side), `QUERIES:` (`resolver_total`).
- On a bad state, both columns collapse to the single state word.

### ACCESS POINTS panel

`access_points_panel_data()` in `ap.lua`, reading
`pfsense/<profile>/ap_status.json` + `ap_clients.json` (gate flag
`providers.ap`). One repeating block per AP (currently 3: CLOSET,
OFFICE, GREAT ROOM, from `site.toml`'s `[ap]` labels — not hardcoded
to 3, whatever the cache lists is what's drawn).

- **MSMTCH** — count of currently-connected clients whose MAC *is*
  known (in `devices.toml`) but whose current IP doesn't match the
  documented one. Usually a stale/incorrect `devices.toml` entry;
  occasionally worth a second look (spoofing, a device that changed
  IP without the file being updated). **Normal**: 0.
- **CPU** — the AP's own reported CPU percentage.
- **CONN** — raw connected-station count for that AP.
- **UNKWN** — count of connected clients whose MAC isn't in
  `devices.toml` at all (distinct from MSMTCH above). **Normal**: 0
  on a fully-inventoried network.
- **Client list** — comma-separated display names below the stat
  header, already MAC→name resolved by `fetch_ap.sh`; word-wrapped
  and capped at a fixed line count (`theme.access_points.clients`) so
  every AP block takes equal vertical space regardless of client
  count — a trailing `...` means the real list is longer than what's
  shown, not truncated data loss.
- A bad panel-wide state collapses the entire panel to one synthetic
  block whose name **is** the state word (no per-AP breakdown in that
  case). Once healthy, each AP block is built independently — one
  AP's bad row can't blank the others.

---

## 3. Known placeholder / deferred fields

Things on screen right now that are **not** wired to a real signal —
this is deliberate, not an oversight, but the number/behavior isn't
meaningful yet.

- **CM1000/WAN `DEGRADED` status word** — per
  [sitrep-design-notes.md § SitRep — CM1000 / WAN panel](../design/sitrep-design-notes.md),
  a derived state was planned (loss/duration threshold on the gateway
  loss data) but no such classification exists anywhere in the code —
  the GATEWAY meter only ever shows raw LOSS/AVG numbers, never a
  status word of its own. Would need threshold/duration logic added
  to `pf.lua` (or upstream in `fetch_pfsense.sh`) plus a place in the
  WAN panel to show it.
- **Modem SNR/power health thresholds** — DS1/DS2 SNR and US AVG power
  are displayed as raw readings with no pass/fail classification;
  deliberately deferred per the design notes (not enough baseline
  history yet to trust specific thresholds).

## 4. Conditional / hidden-unless-triggered fields

This WAN-panel row is **absent by design** in the normal, healthy
case — a blank space where it'd be is expected, not a sign anything
failed to load.

- **MTR (PI5) row** (`pf.lua`'s `mtr_line()`) — a real, live-sourced
  row (implemented Aug 24, 2026): reads
  `mtr/<profile>/mtr_state.json`, written by `gtex62-core`'s
  `providers/mtr/fetch_mtr.sh` — the SSH trigger to Pi5 that starts
  (never stops — see
  [sitrep-design-notes.md § SitRep — Alert banner / outage
  detection](../design/sitrep-design-notes.md)) the pre-existing,
  untouched `mtr_overnight_log.sh` once the gateway-offline duration
  crosses the same threshold the SEVERE alert uses. Absent whenever
  `running` in that file is `false`; when `true`, reads
  `MTR (PI5) HH:MM` (reformatted Aug 31, 2026, from the original
  `MTR (PI5) // RUNNING - <N>H <NN>M`) from `started_at_epoch` vs. the
  current time. `running` reflects `fetch_mtr.sh`'s own
  confirm/reconfirm belief, not a live per-poll `pgrep` — so a very
  recent start can briefly show as absent until the next poll confirms
  it. Unlike every other row in this document, this one deliberately
  does **not** run through `resolve_state_word()` — a
  permanently-tripped SSH gate to Pi5 shouldn't turn a hidden-by-design
  row into a second always-on status line — so it never appears in the
  STALE-thresholds table above, and it has no `SSH DOWN`/`STALE`
  wording of its own; check `mtr_state.json`'s own `ssh_gate`/`state`
  fields directly if Pi5 connectivity itself is in question.

Appended as the CM1000 column's own final line by `pf.lua`'s
`M.wan_panel_data()`, drawn through `draw_wan_content()`'s normal
CM1000 column loop (`lua/ui/frame.lua`) rather than a separate draw
pass — as of Aug 31, 2026 (see § "Boot State row — removed" below),
there's no other conditional-row mechanism left in the WAN panel.

**Boot State row — removed (Aug 31, 2026).** A prior version of this
doc described a second conditional row, `wan_boot_state_line()`,
surfacing the modem's `boot_state.status` when non-`"OK"`. It was
deleted along with `draw_wan_conditional_rows()` in `frame.lua` after a
real incident (2026-08-31 Comcast outage) showed both rows were being
drawn at the WAN box's own left edge (`wan.x`) instead of the CM1000
column's x-range — a separate, redundant draw pass overlaying the
GATEWAY meter rather than sitting under CM1000. Boot State specifically
was dropped rather than repositioned: judged redundant with the DOCSIS
header line. Only MTR (PI5), above, remains as a conditional CM1000
row; it no longer has a second conditional row to share a drawing
contract with.
