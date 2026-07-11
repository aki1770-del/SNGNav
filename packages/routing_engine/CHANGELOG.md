# Changelog

## 0.6.0

### Safety defect in 0.5.0 and earlier — please read

Up to and including 0.5.0, **both engines could hand you a maneuver position
that was never in the routing response**: they silently substituted
`const LatLng(0, 0)` — "Null Island", a real coordinate in the Gulf of Guinea —
whenever they could not resolve the real one.

* `OsrmRoutingEngine`: whenever a step's `maneuver.location` was missing or
  shorter than two elements.
* `ValhallaRoutingEngine`: whenever `begin_shape_index` fell outside the
  decoded polyline. (A *missing* `begin_shape_index` was also defaulted to
  index `0`, silently claiming the maneuver happens at the route's start.)

Nothing marked these as fabricated. `RouteManeuver.position` was a
non-nullable `LatLng`, so a consumer could not tell a parsed coordinate from a
manufactured one — and a maneuver "at 0,0" narrated or plotted for a driver in
Akita is a wrong place presented with full confidence. If you narrated,
mapped, or measured distance-to-next-maneuver from `position`, assume any
`LatLng(0, 0)` you have seen from this package was a parse failure, not a
location.

pub.dev versions are immutable: we cannot withdraw the affected releases.
This note is the recall.

### Breaking: an unknown position is now `null`, and will not compile away quietly

* `RouteManeuver.position` is now `LatLng?`. **`null` means the position is
  UNKNOWN** — never the origin, never `LatLng(0, 0)`.
* Added `RouteManeuver.hasPosition` (`position != null`).
* Both engines return `null` instead of `LatLng(0, 0)` for the cases above.
  Valhalla additionally treats a missing or negative `begin_shape_index` as
  unknown rather than as index `0`, and OSRM treats a non-numeric `location`
  as unknown rather than throwing.
* `RouteManeuver.toString()` says `position unknown` when it is absent.

Every site that reads `maneuver.position` as a `LatLng` now fails to compile.
**That compile error is the fix, not a side-effect of it** — it lands on the
exact line where an unparseable coordinate used to become a confident one.

Migration:

| 0.5.0 | 0.6.0 |
| --- | --- |
| `narrate(m.position)` | `if (m.hasPosition) narrate(m.position!)` — otherwise announce the turn *without* a place; do not invent one |
| `markers.add(m.position)` | skip the marker when `m.position == null`; the maneuver keeps its instruction, distance and time |
| `distanceTo(m.position)` | no position means no distance — show the instruction, not a number derived from `(0, 0)` |
| `if (m.position == const LatLng(0, 0))` (defect workaround) | delete it; use `!m.hasPosition` |

A maneuver with no position is still a valid maneuver: `instruction`,
`lengthKm` and `timeSeconds` remain true and usable. One unparseable
coordinate does not invalidate a route — the loom refuses the false thread,
not the whole cloth.

### Tests

Two tests in 0.5.0 *certified* this defect by name — `missing maneuver
location defaults to (0, 0)` and `begin_shape_index beyond decoded points
defaults to (0, 0)`. Both are inverted, and the absent-position cases (missing,
short, non-numeric, out-of-range, negative) are now covered explicitly,
alongside tests that a well-formed response still yields a real position.

## 0.5.0

Turn-by-turn narration honors the requested language — Japanese by default.

**Behavior change (the reason for the minor bump):** the OSRM engine now
honors `RouteRequest.language` (which has always defaulted `'ja-JP'`).
Previously it emitted hardcoded English regardless of the request. With a
default request, instructions are now Japanese; consumers that relied on
English with default requests should pass `language: 'en'` explicitly.

- Japanese car-navigation register (internal `ManeuverLocalizer`; NOT public
  API): 左折/右折, sharp turns as 鋭角に左折/右折 (preserves the tighten-up
  cue — deliberately not 大きく, which reads as a wide/gentle arc), merge 合流,
  ramps 分岐, roundabouts ロータリー. Unknown locale/type degrades to the
  engine's own English — never a wrong instruction.
- Roundabout instructions carry the exit ordinal when OSRM supplies
  `maneuver.exit` (「ロータリーに入り2番目の出口で…進む」).
- Maneuver-type mapping fixes (visible in the emitted `RouteManeuver.type`):
  a ramp whose side OSRM did not state maps to side-less `'ramp'` (previously
  fabricated `ramp_left`); an empty type+modifier maps to `'proceed'`
  (previously fabricated `'straight'`); `'exit roundabout'`/`'exit rotary'`
  map to `'roundabout_exit'` (previously fell through unmapped).
- OSRM and Valhalla responses are decoded as UTF-8 from bytes explicitly —
  instruction text and street names no longer mojibake behind servers/proxies
  that omit or mis-declare the content type. (With a proper
  `application/json` content type, `package:http` ≥1.x already defaulted to
  UTF-8; this closes the missing/mis-declared-type case.)

reach-disposition(jitreq-drunkenv2): restraint, verified 2026-07-04 — the one
known external adopter (pin `^0.3.0`) uses the VALHALLA engine path, which is
byte-unchanged since 0.3.0 apart from formatting; every 0.5.0 change is
OSRM-narration-side and does not reach their code path; repo dormant since
2026-04-20. A 0.3.x backport would carry nothing they use. Tripwire: if the
repo wakes (any push/issue) or their usage grows to the OSRM path, the serve
fires (pin-lift offer or a 0.3.x backport, as fits).

## 0.4.2
- docs: correct stale README install pin to current version (no API change).

## 0.4.1

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.0 — 2026-05-10 — dart format alignment

- Apply `dart format` across `lib/`, `test/`, and `tool/` (10 files
  reformatted) to clear pana static-analysis formatter findings.
- pubspec `description` already within ≤180-character target; no trim
  needed.
- No SDK source changes; formatter pass only.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

