# Changelog

## 0.1.0

### Safety defect in 0.0.7 and earlier — please read

**A weather-feed outage was indistinguishable from a clear sky.**

`fetchActiveAdvisoriesAtPoint` returned `List<Advisory>`. When every provider
failed, it returned an **empty list** — the exact same value it returns when the
sky is genuinely clear and no advisory is in force.

The adapter was never at fault. `condition_aggregator_jma` refuses to lie: on an
unreachable prefecture it throws *"Incomplete border read for prefectures …"*.
**The lamp was lit.** This package caught that, flattened it into a `String`,
filed it in a `providerErrors` list that **nothing anywhere ever read**, and
returned the empty list anyway. The lamp was lit and put in a drawer.

**If you called this during a JMA outage in a blizzard, your app told your driver
that no advisory was in force. It did not know that. It could not have known
that. It had not looked.**

### The fix, and why it is breaking

`List<Advisory>` **cannot express "I could not look."** So the return type is now
a sealed `AdvisoryLookup`:

* `AdvisoryLookupComplete` — every source answered. An empty list here genuinely
  means *no advisory in force*. **This is the only shape in which that sentence
  is true.**
* `AdvisoryLookupPartial` — act on what was `seen`; you may **not** conclude
  "nothing is in force", because the warning you are missing may be in the source
  that did not answer.
* `AdvisoryLookupUnavailable` — **we did not look. We know nothing.** Not clear.

A sealed class cannot be ignored: Dart's exhaustive `switch` refuses to compile a
consumer who has not written the unreachable branch. A field you *can* ignore
*will* be ignored — that is precisely how this shipped.

### Migration — it is two lines, and we owe you the map

```dart
// before
final r = await agg.fetchActiveAdvisoriesAtPoint(...);
for (final a in r.advisories) { ... }

// after — act on what was seen (a hazard seen is a hazard real, even on
// partial data), and only claim "nothing in force" when you are allowed to
final r = await agg.fetchActiveAdvisoriesAtPoint(...);
for (final a in r.seen) { ... }

if (r.canAssertNoAdvisory && r.seen.isEmpty) {
  showNoAdvisory();          // every source answered; the silence is real
} else if (r.seen.isEmpty) {
  showFeedDown(r.failures);  // we could not look — tell her that, not "clear"
}
```

`r.failures` carries a **typed** `AdvisoryUnavailableReason`, not a string, so you
can render it in the language your driver actually reads. She can act on *"the
weather service did not answer."* She cannot act on a `SocketException`.

**The asymmetry, stated once:** positive evidence fires on partial knowledge; a
negative conclusion requires whole knowledge. That is what lets a system be
honest without crying wolf.


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
