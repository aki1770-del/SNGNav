# Changelog

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

