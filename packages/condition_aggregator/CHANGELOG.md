# Changelog

## 0.0.10 — A feed that stopped being written could still say "no advisory in force"

**An honesty fix at the one predicate that gates a positive all-clear — and it
is inert until an adapter feeds it. Both halves of that sentence are load-bearing.**

*This release was headlined "Safety fix" in draft. AAA's audit called that a
reach claim for a guard that cannot currently fire, and it was right: the
headline is the line that travels, and it would have travelled further than the
truth. Corrected before publish.*

`canAssertNoAdvisory` is the getter this package tells you to gate any
"nothing is in force" message on. Its own documentation says *"never tell her it
is clear."* It was defined over **reachability**:

```dart
if (providerErrors.isNotEmpty) return false;
return sourcesQueried > 0;
```

**A frozen publisher is reachable.** It serves HTTP 200, valid JSON and an empty
warning list, indefinitely. Nothing fails, so `providerErrors` stays empty, so
the predicate returned `true` — and `fold` took the `complete` branch,
`toLookup` returned `AdvisoryLookupComplete`, and `requireCompleteLookup` stayed
silent. Four honesty surfaces, one wrong answer, because they all derive from
that single predicate.

### What was measured (live, 2026-08-16)

JMA `bosai/warning/data/warning/` documents:

* Niigata `150000` — last written **2026-05-26T15:45+09:00**, **81.8 days**,
  zero warnings. Our winter instrument records two branches for that point and
  says to quote neither alone: the primary read was `heightenedCaution` — but
  **only ever about the visibility reading's age** — and the in-car-sensor
  counterfactual was `continueDriving` with no reason and no stated unknown.
  **Neither branch mentioned the feed being 81 days dead, because nothing in
  the stack could.**
* Akita `050000` — **2026-05-28T06:11+09:00**.
* Yamagata `060000` — **2026-05-28T09:48+09:00**. Not lockstep; no single
  "frozen at T" figure is right.
* Confirmed at origin via `last-modified`, so not a cache artifact, and
  nationwide rather than regional. JMA itself was **not** down — its official
  developer feed was live with 515 警報・注意報 entries the same minute.

The existing per-advisory freshness surfaces (`Advisory.effective`,
`stalenessAt`, `isStaleAt`) are correct and could not help: a frozen document
listing zero warnings produces **no `Advisory` object** to carry a timestamp, so
they are structurally unreachable in exactly the case that matters. Freshness
had to become reportable about the **source**.

### Added

- **`AdvisoryFeedStaleness`** — one source's measured report that its own
  upstream document has stopped being updated: `source`, `documentTime`, `age`,
  `detail`.
- **`AdvisoryFeedFreshnessReporting`** — an **opt-in** adapter capability,
  deliberately a *separate* interface rather than a new member on
  `AdvisoryProvider`, so that every adapter already implementing that contract
  compiles and behaves **unchanged**.
- **`AdvisoryAggregateResult.staleSources`** + **`hasStaleSource`**.
- **`AdvisoryLookupPartial.staleSources`** — so a lookup that is `Partial` with
  an *empty* `unreachable` list can still be explained to a driver.

### Changed

- **`canAssertNoAdvisory` now returns `false` when any source reported itself
  stale.** This propagates to `fold`, `toLookup` and `requireCompleteLookup`.
- `requireCompleteLookup` throws a frozen-specific message naming the document
  and its age — a message about unreachable sources would be actively
  misleading here, because nothing was unreachable.

### ⚑ Read this before upgrading — and then read the honest part

**Nothing changes for you today.** The guard fires only on a *positive,
measured* staleness report from an adapter that opted in, and **zero of the five
packages implementing `AdvisoryProvider` have opted in** as of 2026-08-16 —
`condition_aggregator_jma`, `_nws`, `_met_norway`, `_digitraffic`,
`_owm_road_risk`. Verified: all five analyze clean and their **143 existing
tests pass unchanged** against this release, as do the two downstream consumers
`driving_weather` (88) and `drive_situation_fusion` (13).

**Which means the guard is armed and unfed, and we are telling you rather than
letting the version number imply otherwise.** Until an adapter reports freshness,
a frozen feed still satisfies `canAssertNoAdvisory` through that adapter. If
feed-freshness matters to you — and on a winter-driving surface it does — see
**AoU-CA-004** in `SEOOC_ASSUMPTIONS.md` for the three things you can do now.

Once an adapter *does* opt in, a lookup that used to be `Complete` can become
`Partial`. That is the fix working, not a regression, and it is disclosed here
rather than left for you to find in production.

**We did not default unmeasured sources to "stale"** — that manufactures doubt
on a clear day, which is the same class of lie as manufacturing calm, pointed
the other way. **We did not default them to "fresh"** — that is the defect.
Neither default is honest, so there is no default.

### Also added

- `SOTIF_INSUFFICIENCIES.md` — the ISO 21448 performance-insufficiency table
  (SOTIF-CA-001 fixed here; **CA-002 coverage-gap, CA-003 never-expiring
  advisory and CA-004 completeness-lost-at-the-advisor-seam remain OPEN and are
  named, not buried**).
- `SEOOC_ASSUMPTIONS.md` — ISO 26262 Part 10 assumptions of use. Nine rows;
  **three enforced by code, six stated only**, and that ratio is written down.

### Verified by

`test/frozen_feed_test.dart` — 8 tests, GREEN, including a "no cry-wolf" group
pinning the deliberate no-op for adapters that never opted in.

The **RED proof is `tool/red_proof/`**, and it is separate on purpose: the guard
test references symbols this release introduced, so against 0.0.9 it does not
fail — it fails to *load*. `tool/red_proof/run_red_proof.sh` rebuilds pristine
0.0.9 **from the pub-cache tarball** and asserts the reproduction FAILS there.
Verified 2026-08-16: **4/4 red** across `canAssertNoAdvisory`, `fold`,
`requireCompleteLookup` and `toLookup`. Run it yourself; it exits 0 only if the
defect reproduces, and exits 2 rather than claiming anything if it cannot
reconstruct 0.0.9.

## 0.0.9

**The compiler-enforced version of the 0.0.8 honesty fix — shipped as a patch,
because a patch is the only thing that reaches you.**

`0.0.8` gave you `canAssertNoAdvisory`, `fold` and `requireCompleteLookup` so a
feed outage would stop rendering as a clear sky. They work. They also have to be
**remembered**, and a surface you can forget is one you will forget — that is
exactly how the original defect shipped.

This release adds the version the compiler checks.

- **NEW `AdvisoryLookup`** — a `sealed` result with `AdvisoryLookupComplete` /
  `AdvisoryLookupPartial` / `AdvisoryLookupUnavailable`. A `switch` over it is
  exhaustive, so omitting the "we could not look" branch is a **compile error**,
  not a silent all-clear.
- **NEW `AdvisoryAggregator.lookupAtPoint()`** returns it. Prefer it in new code.
- **NEW `AdvisoryAggregateResult.toLookup()`** converts an existing result, so
  you can adopt this without changing your call site.
- **NEW `AdvisorySourceFailure`** — the typed per-source failure it carries.

**Nothing was changed or removed.** `fetchActiveAdvisoriesAtPoint` still returns
`AdvisoryAggregateResult`; every 0.0.8 member is present and behaves identically.
**Verified rather than asserted:** the published `condition_aggregator_jma 0.3.1`
— which pins `^0.0.5` — was resolved against this version and analysed clean,
0 issues.

**Why a patch and not 0.1.0.** Measured with `pub_semver`, not by eye: every
consumer of this package pins a range whose upper bound is `<0.1.0` — the five
adapters and `driving_weather` at `^0.0.5`, `drive_situation_fusion` at `^0.0.7`,
and the integrator app at `>=0.0.3 <0.1.0`. **`0.1.0` reaches 0 of those 8.
`0.0.9` reaches 8 of 8.** Shipping this as a major bump would have delivered the
safety substance to nobody who already depends on us.

**Forward compatible on purpose.** These names and shapes are identical to the
ones in the unpublished `0.1.0`, where `fetchActiveAdvisoriesAtPoint` returns
`AdvisoryLookup` directly. Code written against `lookupAtPoint` compiles there
unchanged.

**What this does NOT do.** `AdvisoryUnavailableReason` is untouched at its five
members. `0.1.0` grows it to seven, which is breaking for an exhaustive `switch`
and therefore cannot ride a patch. If you switch exhaustively on it, that change
is still ahead of you.

## 0.0.8

### Safety defect in 0.0.7 and earlier — please read

**A weather-feed outage looked exactly like a clear sky.**

`fetchActiveAdvisoriesAtPoint` returns an `AdvisoryAggregateResult`. When every
advisory source failed, `result.advisories` was an **empty list** — the same
value it holds when the sky is genuinely clear and no advisory is in force.

The truth was available: the failures were recorded in `result.providerErrors`.
But nothing obliged you to read that list, and a field you *can* ignore *will*
be ignored. **If you rendered `result.advisories.isEmpty` as "no advisory in
force" — the obvious reading — then during a feed outage in a blizzard your app
told your driver the road was clear. It had not looked.**

### The fix in 0.0.8 — non-breaking, nothing you have changes meaning

No type or signature changed, so your code still compiles and behaves as
before. What is **added** is the question you can no longer skip cheaply:

* `result.canAssertNoAdvisory` — `true` **only** when every source answered.
  **An empty `advisories` list means "no advisory in force" only when this is
  `true`.** Otherwise the emptiness means "we could not look."
* `result.fold(complete:, partial:, unavailable:)` — handles all three cases;
  the callbacks are `required`, so it will not let you forget the outage case.
* `result.requireCompleteLookup()` — an opt-in loud stop that throws
  `AdvisoryLookupIncompleteException` (with the way forward in its message)
  rather than let you report an all-clear you did not earn.
* Each `providerErrors` entry now carries a typed `reason`
  (`AdvisoryUnavailableReason`) alongside its string `message`, so you can tell
  the driver *"the weather service did not answer"* in her language instead of
  showing her a `SocketException`.

### Two-line migration

```dart
final r = await agg.fetchActiveAdvisoriesAtPoint(latitude: …, longitude: …);
for (final a in r.advisories) show(a);            // unchanged — always safe

// add this before you ever say "clear":
if (r.advisories.isEmpty && !r.canAssertNoAdvisory) showFeedDown(r.providerErrors);
```

### The version where the compiler enforces it

0.0.8 puts the question in your hands. **0.1.0** changes the return type to a
sealed `AdvisoryLookup` (`Complete` / `Partial` / `Unavailable`) so Dart's
exhaustive `switch` *refuses to compile* a caller who never handled "could not
look." That is a breaking change and a deliberate one — move to it when it is
available on pub.dev and you can take the break. 0.0.8 is the patch that
reaches you without breaking your build first.

**The asymmetry, stated once:** a hazard *seen* is a hazard *real*, even on
partial data — act on `advisories` always. But "nothing is in force" is a claim
about completeness, and you may only make it when the lookup was complete. That
is what lets a system be honest without crying wolf.

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
