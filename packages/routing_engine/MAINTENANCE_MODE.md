# routing_engine — Maintenance Mode

**Package**: `routing_engine`
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

This is the same edge-developer-component class disposition
referenced for the routing-bloc sibling package (see
`../routing_bloc/MAINTENANCE_MODE.md`).

## What this means

### Admissible work

- **Bug fixes** on the existing 0.3.0 API surface (correctness fixes;
  no behavioral re-shaping). PATCH version bumps (0.3.0 → 0.3.1 → ...)
  are the path for these.
- **Documentation corrections** (README, dartdoc, CHANGELOG entries).
- **Compatibility maintenance** with newer Dart SDK / pub.dev
  metadata (e.g., topic / category fixes, license-file refresh).
- **Security-class fixes** in transitive dependencies — admitted as
  bug-fix-class.

### Out-of-scope

- New backends beyond OSRM and Valhalla (e.g., GraphHopper,
  Mapbox Directions, Apple MapKit). Integrators wishing to add a
  new backend should fork or compose at their own boundary.
- New routing concepts (e.g., elevation-aware routing, transit
  modes, multimodal). The 0.3.0 surface is the durable contract.
- API-shape redesigns. The package shape is locked.
- New profile / vehicle-class additions beyond the existing 0.3.0
  surface.
- Performance optimization beyond what existing tests already
  demand. Performance-class new requirements are out-of-scope.

### Status communication

- README and pub.dev publishing metadata reflect the
  maintenance-mode disposition explicitly so edge-developer
  consumers do not assume a roadmap commitment that does not
  exist.
- No SLA escalation is offered for this package; bug reports are
  triaged at the unit's available cadence and may take weeks to
  reach a fix.
- This disposition does NOT indicate "abandoned" — it indicates
  "stable; durable contract; no roadmap push." The package
  remains installable from pub.dev and the unit replies to
  issues at maintenance cadence.

## For consumers

If you are an edge developer integrating `routing_engine` into a
navigation tool you are building:

- **Pin to 0.3.x** in your `pubspec.yaml` if you want the
  durable contract.
- **Open issues** for bugs on the existing surface; the unit
  triages at maintenance cadence.
- **Do NOT depend** on new features landing — the disposition is
  durable.
- **Compose at your boundary** if you need new routing backends
  or routing concepts beyond the 0.3.0 surface — wrap
  `routing_engine` and add your extensions in your own package.
- **Migration path**: if your need outgrows the maintenance-mode
  disposition, the recommended path is to fork the package and
  evolve in your own namespace; the unit's BSD-3-Clause license
  permits this freely.

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

Routing-class packages sit firmly in the edge-developer-component
bucket. Continued maturation push (Q3 escalation, new-feature
admittance) would (a) duplicate incumbent product investment and
(b) shift the unit away from the directions where its work
materially helps the driver in unexpected snow on a Japanese
rural road — which is the data-fusion / advisory / driver-assist
component class, not routing-as-product.

The maintenance-mode disposition keeps `routing_engine`
**healthy** (bug fixes, security maintenance, durable contract for
edge-developer consumers) without diluting the unit's strategic
push toward driver-assist component classes (data-fusion,
advisory, severity-aware UX, voice guidance, navigation safety
core).

## Cross-references

- Sibling: `../routing_bloc/MAINTENANCE_MODE.md` (parallel
  disposition for the bloc-state-machine that consumes this
  engine).
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
