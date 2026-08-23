# Changelog

## 0.5.2

### ⚠️ Behaviour change in a patch release — please read this one

**What changed for you:** when the routing server returns a route but omits its
distance or duration, `calculateRoute` now **throws `RoutingException`**. Up to
and including 0.5.1 it returned a route with those fields set to `0`.

**Do you need to do anything?** Only if you call `calculateRoute` without a
`catch`. One command tells you:

```sh
grep -rn -A6 'calculateRoute' lib/
```

If every call site sits inside a `try { … } catch` — a bare `catch (e)` is
enough; `RoutingException` is a plain exception and is exported from
`package:routing_engine/routing_engine.dart` if you prefer to name it —
**this release asks nothing of you.** If any call site is not, that site can now
throw where 0.5.1 returned a route reading `0.0 km / 0 min`.

**Why we changed it.** Both engines could hand you a route summary that was never
in the routing response. When the server omitted the distance or duration we
substituted `0` and reported `"0.0 km, 0 min"` — a figure the server never sent,
on a road the driver is still on. A zero leaves the result non-null, so an error
path never runs and the fabricated figure reaches the screen as if it were a
measurement. An absent measurement is not a measurement of zero.

* `OsrmRoutingEngine`: an absent `routes[0].distance` or `.duration`.
* `ValhallaRoutingEngine`: an absent `summary.length` / `summary.time`, or an
  absent `summary` object entirely.

Both now throw `RoutingException`, exactly as an absent `routes` / `trip` /
`legs` already did in the same functions.

**Why this is a patch number.** It is a behaviour change and a patch release
conventionally promises none — we know. `0.6.x` carries a compile-breaking
nullable-position change, so it cannot reach anyone pinned `^0.5.x`, and a
`0.5.2` is the only version that can. Leaving you on a release that reports
numbers the server never sent, while we take the corrected code for ourselves,
is not a fix — it is a fix for us. **No signature, type, dependency or SDK
constraint changed in this release. The throw above is the only difference.**

**Note on 0.5.1’s provenance.** 0.5.1 was published without a corresponding
commit in our repository. This 0.5.2 was reconstructed from the published 0.5.1
archive on pub.dev, and its source is committed.

## 0.5.1

Unlocatable maneuvers are skipped — never placed at Null Island.

**Defect fixed:** 0.5.0 (and every earlier release) substituted
`LatLng(0, 0)` — Null Island, a real coordinate in the Gulf of Guinea — for
any maneuver whose location the routing engine did not supply. On the OSRM
path this fired when a step's `maneuver.location` was missing or malformed;
on the Valhalla path when `begin_shape_index` pointed past the decoded
polyline, and a *missing* `begin_shape_index` silently anchored the maneuver
at the route start. Two tests in the published suite asserted this
substitution as correct behavior; they certified the defect rather than
catching it.

**Fix:** a maneuver that cannot be located is now skipped — it does not
appear in `RouteResult.maneuvers` at all, and no substitute coordinate is
ever emitted. Route geometry, total distance, and total duration are
unchanged. Consumers segmenting or plotting by maneuver position will no
longer receive a fabricated (0, 0) point; consumers counting maneuvers may
see fewer entries only in responses where the engine omitted a location.

- OSRM: a step whose `maneuver.location` is missing, shorter than
  `[lon, lat]`, or non-numeric is skipped (previously the non-numeric case
  could also throw mid-parse).
- Valhalla: a maneuver whose `begin_shape_index` is missing, negative, or
  beyond the decoded polyline is skipped.
- The two tests that asserted the `(0, 0)` substitution now assert the skip,
  and regression tests cover the mixed case: one located plus one unlocated
  maneuver yields exactly the located one, with no maneuver at (0, 0).

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

