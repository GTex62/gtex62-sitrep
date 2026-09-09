# SitRep Docs

This directory holds SitRep-specific implementation notes and domain
references.

- [reading-the-widget.md](reading-the-widget.md) — the field guide for the
  live widget: the shared state-word precedence chain, what every panel's
  numbers mean and where they come from, and which fields are still known
  placeholders or only shown conditionally.

General core architecture, provider contracts, and the
pfSense/router/pfBlockerNG/Pi-hole/VPN/modem/AP/devices cache schemas SitRep
consumes all live in `../../gtex62-core/docs/`, in particular:

- [SitRep Architecture](../../gtex62-core/docs/sitrep-architecture.md) — the
  stable design reference: what SitRep is, the "engine gathers knowledge,
  SitRep reports status" principle, and the device inventory model.
- [SitRep Relocation Plan](../../gtex62-core/docs/archive/sitrep-relocation-plan.md) —
  the mechanics of moving the legacy widget out of `gtex62-tech-hud`
  (written against an earlier engine-resident-widget design; this repo takes
  the standalone-suite path instead — see this suite's own README).
- [pfSense Provider Status](../../gtex62-core/docs/pfsense-provider-status.md)
  and [AP Provider Status](../../gtex62-core/docs/ap-provider-status.md) —
  current state of the data sources SitRep will read from.
