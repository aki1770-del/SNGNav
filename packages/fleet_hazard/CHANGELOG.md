# Changelog

## 0.5.1

### The aggregator could not tell "no data" from "the road is clear"

Up to and including 0.5.0, `HazardAggregator.aggregate()` returned **the same
empty list for three different roads**:

* nobody had reported it — *no vehicle has been down this road*;
* the fleet had reported it and found it fine — *the road is clear*;
* every vehicle that drove it returned `RoadCondition.unknown` — *the road was
  driven and could not be read*.

A caller receiving `[]` had no way to tell which. If your surface rendered an
empty result as a clear road, it has been showing drivers a clear road for
stretches where **nothing was known at all** — including roads no vehicle had
touched. Absence rendered as calm is the failure that matters here: the driver
is told the road is fine precisely where we have nothing to say about it.

`RoadCondition.unknown` was part of this: the hazard filter keeps only `snowy`
and `icy`, so a report saying *"I drove it and my sensor could not tell"* was
dropped without leaving any trace in the result.

**Recency was documented but never enforced.** `FleetReport.isRecent` existed and
was never called by anything in this package. The safety boundary document
described surfacing counts like *"N vehicles reported in the last 30 min"*, but
no code applied any age limit — every report counted, however old. That window
was a promise the API could not keep.

### Fixed, without breaking you

Nothing existing changed. `aggregate()` keeps its exact signature, return type
and clustering behavior; there is a regression test pinning that. This release
only **adds**:

* **`HazardAggregator.aggregateWithProvenance()`** — returns the new
  **`FleetAggregate`** instead of a bare list, carrying `zones`, `reportCount`,
  `unknownCount`, `staleCount` and `freshestReportAt`, plus the accessors that
  separate the three worlds: `isSilent` (nobody reported), `isMeasuredClear`
  (reported, readable, and clear) and `isAllUnknown` (reported, and unreadable).
  `freshestReportAt` is `null` when there is nothing to report — `null` means NOT
  KNOWN and must not be coalesced into a time.
* **A `maxAge` argument on that method** that actually consults
  `FleetReport.isRecent`. Reports older than `maxAge` are excluded from
  clustering and counted in `staleCount`. If you tell a driver "in the last 30
  minutes", pass `maxAge: const Duration(minutes: 30)` and the window is now
  genuinely enforced. When `maxAge` is omitted, no age filter is applied — and
  that is stated rather than implied.
* Documentation on `aggregate()` stating plainly that it cannot distinguish
  absence from an all-clear, and applies no recency filter.

If you render fleet data to a driver, moving to `aggregateWithProvenance()` is
the point of this release. `aggregate()` continues to work and is not
deprecated, but it cannot tell you whether the empty list it just handed you
means the road is safe or means nobody has looked.

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

