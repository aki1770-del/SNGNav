# Changelog

## 0.1.0

### Breaking: the compiler now asks the question 0.0.8 put in your hands

`AdvisoryAggregator.fetchActiveAdvisoriesAtPoint` now returns a sealed
`AdvisoryLookup` instead of `AdvisoryAggregateResult`.

**Why.** Through 0.0.7, a total feed outage and a clear sky both reached you as
the same empty advisory list — the failures sat in a `providerErrors` field
nothing obliged you to read (the full story is in the 0.0.8 entry below). 0.0.8
added the un-skippable question without breaking the return type:
`canAssertNoAdvisory`, `fold`, `requireCompleteLookup`. But a question you must
remember to ask can still go unasked. A sealed class cannot be ignored: Dart's
exhaustive `switch` refuses to compile a consumer who has not written the
"could not look" branches.

* `AdvisoryLookupComplete` — every source answered. An empty list here genuinely
  means *no advisory in force*. **This is the only shape in which that sentence
  is true.**
* `AdvisoryLookupPartial` — act on what was `seen`; you may **not** conclude
  "nothing is in force", because the warning you are missing may be in the
  source that did not answer.
* `AdvisoryLookupUnavailable` — **we did not look. We know nothing.** Not clear.
  Also returned when the aggregator holds zero providers: a lookup that
  consulted nothing cannot claim completeness (0.0.8's published rule — *"zero
  sources asked is not an all-clear either"* — kept).

### Migrating from 0.0.8 (the version on pub.dev)

Everything 0.0.8 shipped survives, and almost all of it keeps its name. The
renames below are the ones 0.0.8 itself introduced *"so the migration is a
rename you can make today"*:

| 0.0.8 (`AdvisoryAggregateResult`) | 0.1.0 (`AdvisoryLookup`) |
|---|---|
| `r.advisories` | `r.seen` (same list; `seen` already existed on 0.0.8) |
| `r.providerErrors` | `r.unreachable` (or `r.failures`) — entries are now typed `AdvisorySourceFailure` (`source` / `reason` / `cause`; the string `message` is gone — read `cause`) |
| `r.canAssertNoAdvisory` | unchanged |
| `r.isUnavailable` | unchanged |
| `r.fold(complete:, partial:, unavailable:)` | unchanged shape; the failure lists are `List<AdvisorySourceFailure>` |
| `r.requireCompleteLookup()` | unchanged — still throws `AdvisoryLookupIncompleteException`, whose `unreachable` still carries `AdvisoryProviderError` values (message + typed reason + cause), so existing `catch` blocks keep working |

The carried getters are the compiler-UN-enforced migration path: `r.seen`
answers an empty list on `AdvisoryLookupUnavailable` — the founding silence
shape — without making you say anything. Only an exhaustive `switch` or `fold`
over the sealed type is compiler-enforced. So on the getter path, gate any
all-clear on `r.canAssertNoAdvisory`: coming from **0.0.8** that means keeping
the gate you already have; coming from **0.0.7 or earlier** there is no gate
to keep — `canAssertNoAdvisory` first shipped in 0.0.8 — so **add** it before
you ever render "no advisory in force".

Also in this release:

* `AdvisoryUnavailableReason` gains two values: `refused` (auth / rate limit /
  bad request) and `incompleteAreaCoverage` (the source answered for part of
  the area — a warning may exist in the part we could not read). **Breaking for
  exhaustive `switch`es** over the enum: add the two branches. The union with
  0.0.8 is name-level only: both values are inserted mid-enum, so the `.index`
  of `unparseable` / `notInitialised` / `unclassified` shifts — do not persist
  or compare this enum by `.index`.
* `AdvisoryAggregateResult` and `AdvisoryProviderError` are retained with their
  full 0.0.8 surface (getters, `fold`, `requireCompleteLookup`) for hand-built
  results — test fakes and fixtures written against 0.0.8 keep compiling. The
  aggregator itself no longer returns them.
* Failure classification is typed-first (a `TimeoutException` is `timedOut`
  because of its type, not its spelling), with message-text heuristics as the
  fallback for untyped throws. A bare `StateError` stays `unclassified` — we do
  not guess `notInitialised` from it; only `AdvisoryProviderInitException`
  earns that reason.

Migrating from **0.0.7 or earlier**? Read the 0.0.8 entry below first — it
names the defect and the asymmetry. 0.1.0 changes who asks the question
(you → the compiler) **on the exhaustive `switch` / `fold` path**: there the
compiler refuses to compile a caller who never handled "could not look". On
the getter path the question stays yours to ask — and a 0.0.7 codebase has
never asked it, because `canAssertNoAdvisory` did not exist before 0.0.8 — so
add the gate, per the note under the migration table above.

**The asymmetry, stated once:** a hazard *seen* is a hazard *real*, even on
partial data — act on `seen` always. But "nothing is in force" is a claim about
completeness, and you may only make it when the lookup was complete. That is
what lets a system be honest without crying wolf.

### Who receives this release

reach-disposition(sngnav-app): **not migrating to 0.1.0 in this release — and
not left behind by it either.** The app pins `condition_aggregator:
'>=0.0.3 <0.1.0'` (measured 2026-07-31 at `aki1770-del/sngnav-app` HEAD); that
range's own upper bound excludes 0.1.0, so what it can receive is what **0.0.8**
put in its hands — and on 2026-07-31 it took it. Commit `5afc1b5` gates every
positive all-clear on `AdvisoryAggregateResult.canAssertNoAdvisory` and adds a
fourth *advisory-lookup-incomplete* branch, so an outage can no longer render as
a clear sky; commit `b664557` welds the completeness state to the advisory level
at the only accessor that yields it, so no caller can obtain the level while
skipping the question. Both are on `origin/main`, against a resolved
condition_aggregator **0.0.8**, inside the unchanged pin — no pin lift, no
republish. The **substance** of the 0.0.7 safety defect fix therefore reaches
this consumer in range, today.

What it does **not** receive is 0.1.0's sealed `AdvisoryLookup`. On the 0.0.8
getter path the gate is correct but *voluntary*: it holds because a human wrote
it and tests guard it, not because the compiler refuses the alternative. Earning
the compile-time guarantee is a **later, deliberate migration** — lift the pin to
`^0.1.0` and write the exhaustive `switch` branches — named here rather than
deferred in silence. Until it lands, this consumer's all-clear rests on a gate
that could be deleted without a build error, which is precisely the asymmetry
0.1.0 exists to end.

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
