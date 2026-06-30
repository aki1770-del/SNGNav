# Changelog

## 0.0.7 — 2026-06-30 — Doc honesty

- Docs: library dartdoc no longer claims `Phase: explore` /
  `publish_to: none`; corrected to reflect the published-to-pub.dev state
  (the explore-phase graduation already fired). No code change.

## 0.0.6 — 2026-06-26 — Dev-first on-ramp

- Docs: dev-first on-ramp — install + run-verified quickstart snippet now lead;
  governance prose moved to Background. README now opens with a one-sentence
  description, the `dart pub add condition_aggregator` line, and a copy-paste
  `## Quick start` snippet (self-contained, no peer deps required) demonstrating
  the real `AdvisoryAggregator` fan-out. The mission/HER-trace/composition prose
  is preserved verbatim under `## Background & provenance`.
- `example/main.dart` now demonstrates the `AdvisoryAggregator` fan-out
  (init → fetch → typed merge → per-provider error list), matching the
  quickstart snippet, instead of only constructing a single `Advisory` struct.
- No SDK source or behaviour change.

## 0.0.5

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.0.4 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.0.3 — 2026-05-06 — Source attribution + JSON serialization

Adds source-attribution serialization so the advisory carries a
verifiable trail back to its publisher (NWS / JMA / MET Norway)
across persistence and observability boundaries. The driver-facing
rationale: *"advisory carries a verifiable trail back to its
publisher, so the driver can trust the source."*

License-driven motivation: the MET Norway feed (api.met.no) is
licensed under CC BY 4.0 which *requires* attribution in any
consumer surface. The NWS feed is U.S. Federal public-domain
(attribution not required by the publisher but conventionally
credited so the driver knows the source). The JMA feed is
public-data class (credit recommended). Encoding the attribution
through the typed Advisory layer keeps integrators honest about the
license obligation rather than relying on each integrator to know
each publisher's terms.

### Added

- **`AdvisorySource.metNorway`** enum value — Norwegian
  Meteorological Institute (MET Norway) publisher attribution.
  Backstops the second deep-dive substrate publisher in the
  active engagement portfolio per the unit's substrate prep.
- **`AdvisorySourceAttribution` extension** on `AdvisorySource`
  with `attributionString` getter producing CC-BY-4.0-compliant
  credit text per source. Stable format (change requires major
  version bump).
- **`Advisory.toJson()`** returning `Map<String, dynamic>` with
  `source` (enum name), `eventClass`, enum-class fields by name,
  ISO-8601 nullable timestamps, free-form strings verbatim.
- **`Advisory.fromJson(Map<String, dynamic>)`** static factory
  reconstructing an advisory; round-trip preserves equality.
- **`AdvisoryDeserializationException`** thrown on missing /
  wrongly-typed required fields. Unknown enum names map to
  `unknown` / `other` for forward-compat (no throw).
- Exports: `AdvisorySourceAttribution`,
  `AdvisoryDeserializationException`.

### Tests

- 5 new tests covering: round-trip serialization preserves
  equality; toJson omits Dart-side nulls correctly (effective /
  expires); attribution-string format for NWS / JMA / MET
  Norway / Other; fromJson rejects missing eventClass; fromJson
  accepts unknown enum name as `unknown` / `other` (forward-compat).

### Unchanged (back-compat)

- All 0.0.2 surface unchanged. `Advisory.stalenessAt` /
  `isStaleAt` / `isHighImpact` / `isExpiredAt` semantics
  identical. The new `metNorway` enum is additive (existing
  switches without coverage on it would warn at static-analysis
  time but not runtime; integrators are encouraged to add a
  branch).
- `AdvisoryAggregator` / `AdvisoryProvider` /
  `AdvisoryAggregateResult` / `AdvisoryProviderError` /
  `AdvisoryProviderInitException` unchanged.

## 0.0.2 — 2026-05-04 — Advisory staleness model

Adds publisher-effective-time-derived freshness to the typed advisory
event, so integrators can render freshness honestly rather than
treating a last-fetched-an-hour-ago snapshot as "current."

Driver-facing rationale: *"advisory carries its own freshness; the
driver knows when the source last updated."* When a publisher (NWS /
JMA / ...) has updated an advisory and a stale snapshot is still in
flight, the integrator composes `Advisory.stalenessAt(now)` with a
per-event-class staleness budget to surface freshness honestly.

### Added

- **`Advisory.stalenessAt(DateTime now)`** returning `Duration?`:
  - `null` when the publisher did not declare an `effective`
    timestamp (unknown-freshness; semantically distinct from
    known-fresh and known-stale at this layer).
  - `Duration.zero` clamping for advisories whose `effective` is in
    the future relative to the consumer's clock — the advisory was
    published for the future and is fresh by definition; we do not
    let a clock-skew artefact present as "negative staleness."
  - Otherwise `now − effective`.
- **`Advisory.isStaleAt(DateTime now, Duration threshold)`**: true
  iff `effective` is non-null AND `stalenessAt(now) >= threshold`.
  False on unknown-freshness (publisher omitted `effective`); the
  package does not assert staleness on unknown ground.

### Tests

- 7 new tests covering: null-effective returns null staleness;
  past-effective produces correct delta; future-effective clamps to
  zero; isStaleAt false on unknown-freshness; isStaleAt true on
  delta-meets-threshold; isStaleAt false on delta-below-threshold.

### Unchanged (back-compat)

- All 0.0.1 surface unchanged. `effective` / `expires` / `isHighImpact`
  / `isExpiredAt` semantics identical.
- `AdvisoryAggregator` / `AdvisoryProvider` / `AdvisoryAggregateResult`
  / `AdvisoryProviderError` / `AdvisoryProviderInitException`
  unchanged.

## 0.0.1 — 2026-05-03

Initial publish.

- `Advisory` typed event normalized across publisher sources
  (severity / certainty / urgency / area / effective / expires).
- `AdvisorySource` enum (`nwsUnitedStates`, `jmaJapan`, `other`).
- CAP-class enums: `AdvisorySeverity`, `AdvisoryCertainty`,
  `AdvisoryUrgency`.
- `AdvisoryProvider` adapter contract with mandatory `init()` lifecycle
  and `fetchActiveAdvisoriesAtPoint(lat, lon)` method.
- `AdvisoryAggregator` multi-source fan-out primitive with
  warn-and-continue per-provider failure capture.
- `AdvisoryProviderInitException`, `AdvisoryAggregateResult`,
  `AdvisoryProviderError` supporting types.
- 11 tests covering the value-object, init lifecycle, fan-out merge,
  warn-and-continue per-provider error capture, init-failure
  propagation, init idempotency.
- BSD-3-Clause license (matches the rest of SNGNav).
- Pure Dart, no Flutter dependency.
