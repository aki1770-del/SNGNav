# Changelog

## 0.3.0 — 2026-09-24 — Read the ROAD, not only the sky

The station payload this package already fetches carries ~97 sensors. Through
0.2.3 it took `NÄKYVYYS_M` — a number about the SKY — and discarded every
sensor about the ROAD: surface temperature, surface state, freezing point,
rate of change. Those were parsed and thrown away on every call. This release
reads them, at no additional network cost.

- **New: `DigitrafficVisibilityProvider.fetchNearestRoadSurface()`** returns a
  `DigitrafficRoadSurfaceObservation` — surface state in the publisher's own
  words, coldest surface temperature, highest freezing point, fastest cooling
  rate — or `null` when nothing fresh is in range. Same endpoint, same station
  selection, same freshness gate as `fetchNearestVisibility`.
- **New: `parseDigitrafficRoadSurface()`**, a pure function over one
  `/stations/{id}/data` payload. No I/O, no clock; the freshness gate is
  injectable.

### What this release refuses to do, and why

- **A channel the publisher does not define is never given a meaning.**
  `/api/weather/v1/sensors` (read 2026-09-24) publishes a 10-entry code table
  for `KELI_1` and `KELI_2` — and an EMPTY table for `KELI_3`, `KELI_4` and all
  four `TIENPINNAN_TILA_n`, whose `description` is `null` outright. Those six
  channels carry live integers with no published meaning. Borrowing `KELI_1`'s
  scale for `KELI_3` because the name matches is an assumption, not a
  measurement. They are reported by name in `uninterpretedSensors` so a
  consumer can never mistake our silence for their absence.
- **A declared fault is not a surface class.** Code `0` reads "The sensor has a
  fault". It sets `sensorFaultDeclared` and yields no state. A source declaring
  its own blindness must not arrive as a road condition.
- **A class with no VSS equivalent stays `null`, never the benign one.** Five of
  Fintraffic's ten codes map cleanly onto the VSS
  `Vehicle.Exterior.RoadSurfaceCondition` allowed-value set (`DRY`, `WET`,
  `SNOW`, `ICE`, `SLUSH`). The other five — `Moist`, `Wet and salty`, `Frost`,
  `Probably moist and salty`, and the fault code — do not. `DRY` would be a lie
  toward benign; inventing a value would be a lie outright. The publisher's own
  word is carried verbatim and the VSS field stays `null`. The mapping is
  integrator-overridable at the call site.
- **An aggregate never averages a cold point away.** Up to four surface sensors
  sit at one station and disagree. A mean cannot say that one point alone is
  freezing. The COLDEST surface, HIGHEST freezing point and FASTEST cooling are
  reported, each naming the sensor it came from.
- **Two channels at one station may disagree, and both are carried.** Measured
  live at Helsinki `kt51_Hki_Lapinlahti` on 2026-09-24: `KELI_1` = "Moist",
  `KELI_2` = "Dry". No hazard ranking is imposed — the publisher does not
  publish one, and the numeric code order is not one (`4` "Wet and salty" is
  less hazardous than `3` "Wet").

### Scope bound — stated because it would otherwise be assumed

**This serves a Finnish rural driver. It does not serve a Japanese one.**
Digitraffic covers Finland only. For Japan there is no road-surface source at
all. Measured live on 2026-09-24, the same call: Rovaniemi returns a station
0.6 km away; **Akita returns `null`**. Nothing in this release moves Akita one
metre. Proving the pipeline where the data exists is not the same as serving
the driver it was built for, and the two must not be reported as one thing.

Emits VSS allowed-value STRINGS rather than an enum, so this package takes no
new dependency; consumers wanting the enum call
`RoadSurfaceCondition.fromVss(value)` from `navigation_safety_core`.


## 0.2.3

- Widen the `pretrip_decision_advisor` constraint to `'>=0.5.0 <0.7.0'` so this
  package resolves against `pretrip_decision_advisor` 0.6.0 (which adds
  `HourHazard.unknown` — a trip with NO forecast no longer reports its peak
  hazard as `clear`). This package's `lib/` reads neither changed symbol, so
  0.6.0 is source-compatible; for a 0.x package a caret does not admit the next
  minor, so without the widen `^0.5.0` and 0.6.0 have an EMPTY intersection.

- **Take pretrip_decision_advisor ^0.5.0.** The previous `^0.4.0` pin silently
  excluded the 0.5.x line — hosted consumers of this adapter never received
  the black-ice window and route-corridor bridge-icing pre-trip warnings
  (橋は路面より先に凍結します) shipped there. No behavior change in this
  package itself; the constraint widening is the release.


## 0.2.2 — 2026-06-29 — Docs: remove stray tool-markup lines

- Docs: remove stray tool-markup lines that rendered on the pub.dev page. No source change.

## 0.2.1 — 2026-06-26 — Docs: dev-first on-ramp

- The README now leads with what-it-is, a `dart pub add pretrip_source_digitraffic`
  line, and a run-verified `## Quick start` snippet (byte-identical to
  `example/quickstart.dart`, verified live against the Digitraffic API), followed
  by what the developer gets back. All governance / mission / HER-trace / safety
  / sibling / endpoint prose is preserved verbatim, moved below under
  `## Background & provenance`.
- The prior `## Usage` snippet (which referenced an undeclared `forecast`) is now
  the "Merge onto a forecast" example under Background with a clarifying comment;
  the runnable `example/main.dart` remains the complete merge demo.
- Docs-only change; no public API, behaviour, or dependency change.

## 0.2.0 — 2026-06-24 — Re-pin advisor to ^0.4.0 (catalog resolvability)

- Shifts the `pretrip_decision_advisor` requirement from the 0.2.x range to the
  0.4.x range; advisor 0.2.x/0.3.x are no longer supported by this version. This
  package's own public API is unchanged. Minor bump because the resolution
  requirement is consumer-affecting.
- The published `pretrip_decision_advisor` 0.4.0 is live on pub.dev; the
  original `^0.2.0` constraint was incompatible with it and blocked edge
  developers from `pub add`-ing this source together with the current advisor
  in a single project.
- The `VisibilityObservation` measurement contract this package emits is
  unchanged across advisor 0.2.0 → 0.4.0.

## 0.1.0 — 2026-06-14 — Initial extraction

- Extracted `DigitrafficVisibilityProvider` from the SNGNav app
  (`lib/providers/digitraffic_visibility.dart`) into a standalone pure-Dart
  package under the new `pretrip_source_*` namespace.
- Fetches the nearest fresh measured road-network visibility (`NÄKYVYYS_M`,
  metres; falls back to `NÄKYVYYS_KM` × 1000) from Fintraffic's open
  Digitraffic road-weather network and emits a source-neutral
  `VisibilityObservation` (owned by `pretrip_decision_advisor` ^0.2.0).
- Runtime dependencies: `http` + `pretrip_decision_advisor` only. No Flutter.
- Safety contract preserved verbatim (see README.md): visibility is never
  estimated; an observation is valid for the departure hour only; `null` is the
  driver's own judgment, never a fabricated hazard.
- Sibling package: `condition_aggregator_digitraffic` (same upstream provider,
  emits a WARNING `Advisory`; this package emits a MEASUREMENT).
