# routing_bloc — Maintenance Mode

**Package**: `routing_bloc`
**Status**: maintenance mode
**Since**: 2026-05-06 (recorded at version 0.3.0)

---

## Status

This package is in **maintenance mode**. No new features are planned, and none
will be added. Bug fixes to the existing API are in scope; additions to the API
are not.

Routing for drivers is already served by established products (for example
Yahoo!カーナビ and Google Maps). This project's routing packages are not meant to
compete with them. They exist for developers who build their own navigation
tools, and the project's own effort goes into road-condition, advisory and
driver-assistance components for drivers on rural and snow-covered roads in
Japan.

`routing_bloc` is the bloc state-machine layer on top of `routing_engine`; both
are in maintenance mode (see `../routing_engine/MAINTENANCE_MODE.md`).

## What this means

### In scope

- **Bug fixes** on the existing API — `RouteState` state-machine correctness;
  transition correctness; idle / loading / active / error semantics. These ship
  as PATCH releases.
- **Documentation corrections** (README, dartdoc, CHANGELOG entries).
- **Compatibility maintenance** with newer flutter_bloc / Flutter SDK / Dart
  SDK; e.g., minor version bumps to the `flutter_bloc` constraint as the
  upstream evolves.
- **Tests** that pin down existing behaviour without expanding the API.
- **Security fixes** in transitive dependencies.

### Out of scope

- New states beyond the four-state model (idle / loading / active / error). The
  state machine's shape is fixed.
- New events that would need the state machine extended. To add your own
  events, wrap `routing_bloc` in a parent bloc at your own boundary.
- New routing-engine integrations beyond the existing `routing_engine`
  dependency. The bloc talks to the engine through its existing API;
  alternative backends belong in the engine package, not the bloc.
- API redesigns. The bloc's shape is fixed.
- New events or payloads that change the shape of the `RouteState` value
  object.

### Where the status is stated

- This file is where the status is recorded. The README and the pub.dev
  listing do not mention it yet, so a developer who reads only those will not
  see it.
- No support-level commitment is offered for this package; bug reports are
  triaged as maintainer time allows.
- Maintenance mode does NOT mean "abandoned". It means "stable; the contract
  holds; no new features." The package remains installable from pub.dev.

## For developers using this package

If you are integrating `routing_bloc` into a navigation tool you are building:

- **Pin to one minor line** in your `pubspec.yaml` (currently 0.4.x) if you
  want a fixed contract.
- **Open issues** for bugs on the existing API; they are triaged at
  maintenance pace.
- **Do NOT depend** on new features landing — maintenance mode is durable.
- **Compose at your boundary** by wrapping `routing_bloc` in a parent bloc
  when you need behaviours beyond idle / loading / active / error.
- **If your needs outgrow maintenance mode**, fork the package and evolve it
  under your own name; its BSD-3-Clause license permits this freely.

## Why maintenance mode

Two kinds of software are kept apart here:

- **Products for drivers** (e.g., routing apps for end users): served by
  established products (Yahoo!カーナビ, Google Maps); not this project's
  scope.
- **Components for developers** (e.g., `routing_engine`, `routing_bloc`):
  packages that *help developers build their own* navigation tools. These ship
  on pub.dev, but they are not pushed toward becoming a finished product
  themselves.

A routing bloc state machine is a component for developers. Pushing it further
(new states, multimodal extensions) would (a) duplicate what established
products already do and (b) pull effort away from where the project's work
helps a driver in unexpected snow on a rural road in Japan the most: data
fusion, advisories and driver-assistance components, not a routing state
machine.

Maintenance mode keeps `routing_bloc` **healthy** (bug fixes, security
maintenance, a durable contract for the developers who depend on it) without
diverting that effort.

## Cross-references

- Sibling: `../routing_engine/MAINTENANCE_MODE.md` (the same status for the
  routing engine this bloc uses).
- Packages in this repository record their scope in per-package documents
  (see the `SAFETY_BOUNDARY.md` files in the other packages); this file does
  the same for this package's maintenance status.
- The project's active development goes into data-fusion, advisory and
  safety-core packages; the routing packages stay in maintenance mode.

## History

- **2026-05-06**: Maintenance mode recorded in this file, at version 0.3.0.
  Reason: routing for drivers is served by established products; the routing
  packages here serve developers.
- **2026-09-20**: Reworded in plain language. The pinning example now names the
  current minor line (0.4.x) instead of 0.3.x, the line current when the file
  was written. An earlier sentence said the README and pub.dev listing state
  this status; they do not, and the section above now says so.
