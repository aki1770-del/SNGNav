# Changelog

## 0.5.0

**Breaking — anonymization fix (dignity-class).** A retained `HazardZone` no
longer carries a re-identifiable per-vehicle trail. Previously a zone retained
the full `List<FleetReport>`, including each report's `vehicleId` — so the
"anonymized, aggregated" claim in the safety boundary was false: a zone held a
`vehicleId` mapped to its sequence of `position` + `timestamp`, which is a
per-vehicle trail. This release protects the fleet-contributor drivers: their
participation no longer leaves a reconstructable trail in the aggregate.

- **New `ZoneObservation`** — the anonymized atom a zone retains: `position`,
  `condition`, `timestamp`, `confidence`, and **no `vehicleId`**.
- **`HazardZone.reports` is now `List<ZoneObservation>`** (was
  `List<FleetReport>`). `zone.reports[i].vehicleId` no longer exists — by
  design. `FleetReport` (with `vehicleId`) remains the **input atom** to
  aggregation.
- **`HazardZone.vehicleCount` is now a stored `final int`**, computed at
  aggregation time from the input reports' unique `vehicleId`s *before* the key
  is stripped. It can no longer be derived from `reports`. The honest
  "N vehicles reported" count is preserved without retaining the re-id key.
- `averageConfidence` is unchanged (still derived; `confidence` is retained on
  each `ZoneObservation`).
- `HazardAggregator.aggregate(List<FleetReport>)` is unchanged in signature and
  clustering behavior; it now drops `vehicleId` when constructing each zone.

Migration: construct `HazardZone` with `reports: <ZoneObservation>[...]` and a
`vehicleCount:`; build observations with `ZoneObservation.fromReport(report)`.

## 0.4.1

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.0 — 2026-05-10 — Pana score recovery + dart format alignment

- Trim pubspec `description` to ≤180 characters so search-engine
  snippets surface the package's purpose cleanly.
- Apply `dart format` across `lib/` and `test/` (9 files reformatted)
  to clear pana static-analysis formatter findings.
- No SDK source changes; metadata + formatter pass only.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

