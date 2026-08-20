# gtex62-sitrep

`gtex62-sitrep` is a standalone Conky suite built on the shared
[`gtex62-core`](../gtex62-core/README.md) engine model, following the same
suite/engine split as [`gtex62-osa`](../gtex62-osa/README.md).

SitRep is a single-panel network-status console: pfSense/router,
pfBlockerNG, Pi-hole, VPN, cable modem, access point, and device-inventory
status in one chassis. The suite owns the visual language and panel
composition; the engine owns the runtime model, provider orchestration, and
normalized cache SitRep reads from.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Runtime Model](#runtime-model)
- [Repository Layout](#repository-layout)
- [Panel Map](#panel-map)
- [Customization](#customization)
  - [Scale](#scale)
  - [Palette](#palette)
- [Troubleshooting](#troubleshooting)
- [Relationship to gtex62-tech-hud](#relationship-to-gtex62-tech-hud)
- [License](#license)

## Purpose

SitRep began as a network-status display inside `gtex62-tech-hud`, doing its
own SSH collection, IP-to-name mapping, and draw-time joins in a single pass.
This repo is the destination for relocating that functionality onto the
engine model, as a suite in its own right rather than a panel folded into
OSA:

- `gtex62-core` owns provider orchestration, SSH collection, device
  classification, and the normalized cache — see
  [SitRep Architecture](../gtex62-core/docs/sitrep-architecture.md) for the
  "engine gathers knowledge, SitRep reports status" principle this follows.
- `gtex62-shared-assets` owns reusable fonts, wallpapers, icons, and shared
  data assets.
- `gtex62-sitrep` owns only SitRep-specific layout, drawing, suite view
  models, documentation, and Conky entrypoints.

This repository is currently a structural scaffold: theme, layout, and Conky
entrypoint files exist and load, but no panel actually displays live
pfSense/router/pfBlockerNG/Pi-hole/VPN/modem/AP/device data yet. That is
future work — see [Repository Layout](#repository-layout) and
[Panel Map](#panel-map) below for what exists today versus what's still to
come.

## Requirements

Base runtime:

- Conky with Lua + Cairo support, for example `conky-all`
- `bash`, `jq`, `curl`
- `lua` or Lua support through Conky
- `feh` if you want the launcher to apply shared wallpapers

Data sources (once wired up — see [Purpose](#purpose)):

- SSH target for pfSense-backed network data.
- Pi-hole and pfBlockerNG, if those optional packages are installed.
- VPN, cable modem, and access point credentials, per whichever of those
  device classes you actually own — each is independently enabled or
  disabled in `~/.config/gtex62-core/core.toml`.

Shared repositories expected next to this suite:

```text
~/.config/conky/
├── gtex62-core/
├── gtex62-sitrep/
└── gtex62-shared-assets/
```

## Installation

Install system packages. Debian / Ubuntu / Mint example:

```bash
sudo apt update
sudo apt install -y conky-all jq curl lua5.4 feh
```

Clone the engine, shared assets, and suite into the Conky config root:

```bash
mkdir -p ~/.config/conky
cd ~/.config/conky
git clone https://github.com/GTex62/gtex62-core.git
git clone https://github.com/GTex62/gtex62-shared-assets.git
git clone https://github.com/GTex62/gtex62-sitrep.git
```

Install fonts from shared assets, if SitRep's chosen fonts aren't already
present:

```bash
bash ~/.config/conky/gtex62-core/scripts/install-fonts.sh
```

This copies all fonts from `gtex62-shared-assets/fonts/` into
`~/.local/share/fonts/` and rebuilds the font cache.

## Quick Start

Bootstrap the runtime config:

```bash
cd ~/.config/conky/gtex62-sitrep
bash scripts/bootstrap-runtime-root.sh
```

Edit the main local config file:

```bash
$EDITOR ~/.config/gtex62-core/site.toml
```

Then launch SitRep:

```bash
bash ~/.config/conky/gtex62-sitrep/scripts/start-conky.sh
```

The launcher asks for a palette and a shared wallpaper, exports the runtime
paths, and then delegates to:

```text
~/.config/conky/gtex62-core/bin/gtex62-core-launch --suite sitrep
```

## Configuration

Most local setup belongs in one file:

```text
~/.config/gtex62-core/site.toml
```

Domain profile files exist under:

```text
~/.config/gtex62-core/profiles/
```

Provider enable/disable flags (pfSense, VPN, AP, modem, and the pfSense
sub-domains) live in:

```text
~/.config/gtex62-core/core.toml
```

Runtime suite binding lives at:

```text
~/.config/gtex62-core/suites/sitrep.toml
```

## Runtime Model

Standard engine roots:

```text
config  ~/.config/gtex62-core/
data    ~/.local/share/gtex62-core/
cache   ~/.cache/gtex62-core/
assets  ~/.config/conky/gtex62-shared-assets/
```

Environment variables SitRep's Lua reads, same convention as OSA:

- `CONKY_SUITE_DIR`
- `GTEX62_CORE_DIR`
- `GTEX62_CONFIG_DIR`
- `GTEX62_CACHE_DIR`
- `GTEX62_SHARED_ASSETS`
- `GTEX62_SUITE_ID`

See the core README and docs for provider schemas and cache contracts:

- [gtex62-core README](../gtex62-core/README.md)
- [Core Architecture](../gtex62-core/docs/architecture.md)
- [SitRep Architecture](../gtex62-core/docs/sitrep-architecture.md)

## Repository Layout

```text
gtex62-sitrep/
├── suite.toml      # suite identity, entrypoints, shared asset roots
├── README.md
├── design/         # visual references (gitignored, empty until a previz lands)
├── docs/           # SitRep-only implementation notes and references
├── lua/
│   ├── lib/        # thin local compatibility/helper layer
│   ├── suite/      # SitRep view models over engine cache
│   ├── ui/         # chassis and panel drawing
│   └── widgets/    # Conky Lua entrypoint
├── scripts/        # SitRep launch/wrapper helpers only
├── theme/          # layout, panels, and visual theme
└── widgets/        # Conky config entrypoints
```

Not present by design:

- `assets/`
- `fonts/`
- `examples/`
- `legacy/config/`

Current implementation state:

- `theme/theme.lua`, `theme/layout.lua`, `theme/panels.lua`,
  `theme/palettes.lua` — load and resolve correctly; palette selection,
  frame geometry, and FX (shadow/lights) work, but panel box geometry
  (`theme/panels.lua`'s `boxes` table) is intentionally empty.
- `lua/suite/runtime.lua` — generic theme/layout/panels loader with
  mtime-based reload, no SitRep-specific data reads yet.
- `lua/ui/frame.lua` — draws the chassis (background, panel frame, panel
  title, frame FX) with no panel content.
- `lua/widgets/sitrep_main.lua` + `widgets/sitrep-main.conky.conf` — a
  working Conky entrypoint that renders an empty titled chassis.
- `lua/lib/` — empty; nothing has needed a compatibility helper yet.

## Panel Map

`SITREP`
: The one panel this suite renders. Currently an empty titled frame — no
  pfSense/router/pfBlockerNG/Pi-hole/VPN/modem/AP/device rows exist yet. What
  it displays, and how it's subdivided internally, is future panel-design
  work; see [SitRep Architecture](../gtex62-core/docs/sitrep-architecture.md)
  for the data model it will eventually present.

## Customization

Start with these files:

- [theme/theme.lua](theme/theme.lua): colors, fonts, spacing, frame FX.
- [theme/panels.lua](theme/panels.lua): panel position and box geometry.
- [theme/layout.lua](theme/layout.lua): frame dimensions, column positions,
  and suite scale.
- [widgets/sitrep-main.conky.conf](widgets/sitrep-main.conky.conf): Conky
  window and update interval.

### Scale

The chassis — geometry, line weights, and fonts — scales from two fields in
`theme/layout.lua`:

```lua
layout.scale_mode = "manual"   -- "manual" or "auto"
layout.scale      = 1.0        -- active when scale_mode = "manual"
```

In `"manual"` mode, `layout.scale` is a fixed multiplier applied to all
drawing. In `"auto"` mode, the scale is computed from the environment
variables `CONKY_SCREEN_W` and `CONKY_SCREEN_H` against the base frame
dimensions (`900 × 1200`). Export both before launching Conky and the suite
will fit the screen proportionally.

Restart Conky after changing `scale` or `scale_mode`.

### Palette

SitRep supports a monochrome palette selector through `CONKY_SITREP_PALETTE`,
independent of OSA's `CONKY_OSA_PALETTE` — the two suites never share a
palette catalog or runtime selection, even though the catalog shapes match.
Available palettes are defined in
[theme/palettes.lua](theme/palettes.lua); the default is `phosphor`.

Data customization belongs in `~/.config/gtex62-core/site.toml` unless the
change is truly suite-specific.

## Troubleshooting

Refresh the runtime examples from core:

```bash
bash scripts/bootstrap-runtime-root.sh --force
```

Check provider outputs once the pfSense/AP providers are enabled and
populated:

```bash
find ~/.cache/gtex62-core/shared -maxdepth 3 -type f | sort
```

If the chassis renders but stays empty, that's expected at this stage — no
panel reads cache data yet. If the chassis fails to render at all, check that
`gtex62-core/lua/runtime/window.lua` is reachable from `GTEX62_CORE_DIR` and
that `theme/palettes.lua` still has a `default` entry matching an existing
palette key.

## Relationship to gtex62-tech-hud

`gtex62-tech-hud` remains untouched and keeps running its legacy SitRep via
`~/.local/bin/sitrep`. This repository is a fresh, standalone destination for
the relocated widget — no files are copied from `gtex62-tech-hud` directly;
its SitRep is read-only reference material for what the eventual panel needs
to display, not a source to port from wholesale.

Note this repo takes a different architectural path than
[gtex62-core/docs/sitrep-relocation-plan.md](../gtex62-core/docs/sitrep-relocation-plan.md)
originally sketched: that document plans SitRep as an engine-resident,
suite-independent widget under `gtex62-core/widgets/sitrep/` (command
`sitrep-e`, no `suite.toml`, works with `CONKY_SUITE_DIR` unset). This repo
instead gives SitRep its own suite identity, matching OSA's model. The data
layer this suite will consume — provider cache schemas, enable/disable
flags, staleness handling — is unaffected by that choice and is documented in
`gtex62-core/docs/`.

## License

See [LICENSE](LICENSE).
