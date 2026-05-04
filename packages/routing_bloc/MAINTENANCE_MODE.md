# routing_bloc — Maintenance Mode

**Package**: `routing_bloc`
**Version**: 0.3.0
**Disposition**: Maintenance-mode (edge-developer-component class).
**Date**: 2026-05-06

---

## Status

This package is in **maintenance-mode**. No Q3 maturation push is
planned; no new feature additions are admissible against this
disposition. Bug-fix patches are admissible on the existing API
surface; new-API surface additions are explicitly out-of-scope.

The disposition was ratified as part of the unit's strategic
clarification that *"Routing stays with incumbents (Yahoo!カーナビ,
Google Maps)"* — i.e., end-user routing-as-product is owned by
incumbents in the unit's target market (Japanese rural / snow-road
edge developer scope). The unit's routing-class packages on pub.dev
serve **edge developers** building parallel navigation tools, not
end-driver routing-as-product directly.

`routing_bloc` is the bloc-state-machine layer that consumes
`routing_engine`; both share the same maintenance-mode disposition
(see `../routing_engine/MAINTENANCE_MODE.md`).

## What this means

### Admissible work

- **Bug fixes** on the existing 0.3.0 API surface — `RouteState`
  finite-state-machine correctness; transition correctness; idle /
  loading / active / error state semantics. PATCH version bumps are
  the path for these.
- **Documentation corrections** (README, dartdoc, CHANGELOG entries).
- **Compatibility maintenance** with newer flutter_bloc / Flutter
  SDK / Dart SDK; e.g., minor version bumps to the
  `flutter_bloc` constraint as the upstream evolves.
- **Test-class additions** that solidify existing semantics
  without expanding the API surface.
- **Security-class fixes** in transitive dependencies.

### Out-of-scope

- New states beyond the four-state model (idle / loading / active
  / error). The state machine shape is locked.
- New events that require a state-machine extension. Integrators
  wishing to add new events compose at their own boundary by
  wrapping `routing_bloc` in a parent bloc.
- New routing-engine integrations beyond the existing
  `routing_engine` dependency. The bloc speaks to the engine
  through the existing API; alternative backends are layered at
  the engine package, not the bloc.
- API-shape redesigns. The bloc shape is locked.
- New events / payloads that change `RouteState` value-object
  shape.

### Status communication

- README and pub.dev publishing metadata reflect the
  maintenance-mode disposition explicitly so edge-developer
  consumers do not assume a roadmap commitment that does not
  exist.
- No SLA escalation is offered for this package; bug reports are
  triaged at the unit's available cadence.
- This disposition does NOT indicate "abandoned" — it indicates
  "stable; durable contract; no roadmap push." The package
  remains installable from pub.dev.

## For consumers

If you are a Flutter edge developer integrating `routing_bloc`
into a navigation tool you are building:

- **Pin to 0.3.x** in your `pubspec.yaml` if you want the durable
  contract.
- **Open issues** for bugs on the existing surface; the unit
  triages at maintenance cadence.
- **Do NOT depend** on new features landing — the disposition is
  durable.
- **Compose at your boundary** by wrapping `routing_bloc` in a
  parent bloc when you need behaviors beyond idle / loading /
  active / error.
- **Migration path**: if your need outgrows the maintenance-mode
  disposition, fork the package and evolve in your own namespace;
  the unit's BSD-3-Clause license permits this freely.

## Why maintenance-mode (rationale)

The unit's strategic frame distinguishes between:

- **Customer-facing-products** (e.g., end-driver routing apps): owned
  by incumbents (Yahoo!カーナビ, Google Maps); not the unit's
  scope.
- **Edge-developer-components** (e.g., `routing_engine`,
  `routing_bloc`): packages that *help edge developers build their
  own* navigation tools. These ship as Direction B
  pub.dev packages but do not push toward end-user-product
  maturation themselves.

Routing-bloc state machines sit firmly in the
edge-developer-component bucket. Continued maturation push (Q3
escalation, new state introductions, multimodal extensions) would
(a) duplicate incumbent product investment and (b) shift the unit
away from the directions where its work materially helps the
driver in unexpected snow on a Japanese rural road — which is the
data-fusion / advisory / driver-assist component class, not
routing-state-machine.

The maintenance-mode disposition keeps `routing_bloc` **healthy**
(bug fixes, security maintenance, durable contract for
edge-developer consumers) without diluting the unit's strategic
push toward driver-assist component classes.

## Cross-references

- Sibling: `../routing_engine/MAINTENANCE_MODE.md` (parallel
  disposition for the routing engine this bloc consumes).
- Constitution + governance: package-class disposition discipline
  per the unit's per-package boundary records (see
  `SAFETY_BOUNDARY.md` siblings across other SNGNav packages
  for the shape of per-package disciplines).
- Direction B (edge-developer-component): the unit's strategic
  pub.dev push lands data-fusion / advisory / safety-core
  packages forward; routing-class packages stay in
  maintenance-mode per this disposition.

## Disposition history

- **2026-05-06**: Maintenance-mode disposition recorded at this
  file as part of the unit's per-package documentation
  discipline. Strategic-clarification anchor: routing-as-product
  owned by incumbents; routing-class packages serve edge
  developers.
