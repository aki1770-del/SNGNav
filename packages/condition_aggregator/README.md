# condition_aggregator

A pure-Dart primitive that fans one lat/lon query out across N weather-advisory
sources and returns a typed, normalized `Advisory` list (warn-and-continue: one
source failing never drops the others).

```
dart pub add condition_aggregator
```

## Quick start

```dart
import 'package:condition_aggregator/condition_aggregator.dart';

// A provider is any class implementing AdvisoryProvider. Real adapters
// (condition_aggregator_nws / _jma) fetch live feeds; here is a 6-line one.
class MyProvider implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;
  @override
  Future<void> init() async {}
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint(
          {required double latitude, required double longitude}) async =>
      const [
        Advisory(
            source: AdvisorySource.nwsUnitedStates,
            eventClass: 'Winter Storm Warning',
            severity: AdvisorySeverity.severe,
            certainty: AdvisoryCertainty.likely,
            urgency: AdvisoryUrgency.expected,
            areaDescription: 'Erie County, NY',
            effective: null,
            expires: null,
            headline: 'Heavy snow expected',
            description: 'Travel could be very difficult to impossible.'),
      ];
}

Future<void> main() async {
  final agg = AdvisoryAggregator(providers: [MyProvider()]);
  await agg.init(); // mandatory before fetch
  final r = await agg.fetchActiveAdvisoriesAtPoint(
      latitude: 47.9253, longitude: -97.0329);
  for (final a in r.advisories) {
    print('[${a.source.name}] ${a.severity.name}: ${a.headline}');
  }
  print('${r.advisories.length} advisory, ${r.providerErrors.length} errors');
}
```

You get back an `AdvisoryAggregateResult`: `r.advisories` is the typed,
normalized merge across every provider, and `r.providerErrors` lists which
sources failed (so a single failing feed never silently drops the rest).

## An empty list is not always an all-clear (read this)

`r.advisories.isEmpty` is **true in two very different situations**:

1. every source answered and no advisory is in force — the road really is clear;
2. every source was **down**, so nothing was read — you have no idea if it is clear.

They render as the same empty list. During a feed outage in a blizzard, reading
case 2 as case 1 tells a driver the road is clear when you never looked.

**So gate any "no advisory in force" message on `r.canAssertNoAdvisory`**, which
is `true` only when every source answered:

```dart
// oracle:placeholders r, show, showNoAdvisory, showFeedDown
for (final a in r.advisories) show(a);      // always safe: a hazard seen is real

if (r.advisories.isEmpty) {
  if (r.canAssertNoAdvisory) {
    showNoAdvisory();                        // every source answered — real all-clear
  } else {
    showFeedDown(r.providerErrors);          // we could not look — say so, not "clear"
  }
}
```

Or use `r.fold(...)`, whose three callbacks are `required` so it will not let you
forget the outage case:

```dart
// oracle:placeholders r
final banner = r.fold(
  complete: (advisories) => advisories.isEmpty ? '警報なし' : advisories.first.headline,
  partial: (seen, down) => seen.isEmpty ? '一部の気象情報を取得できません' : seen.first.headline,
  unavailable: (down) => '気象情報を取得できません',   // NOT "clear"
);
```

Each `providerErrors` entry carries a typed `reason` (`AdvisoryUnavailableReason`)
so you can tell the driver *"the weather service did not answer"* in her language
rather than showing her a `SocketException`. If you would rather fail than risk a
false all-clear, `r.requireCompleteLookup()` throws
`AdvisoryLookupIncompleteException` (with the way forward in its message).

**The asymmetry:** act on what was *seen* even on partial data; only claim
*silence* when the lookup was complete. That is honesty without crying wolf.

> **Want the compiler to enforce this?** `condition_aggregator` **0.1.0** —
> when it is available on pub.dev — changes the return type to a sealed
> `AdvisoryLookup` (`Complete` / `Partial` / `Unavailable`) — Dart's exhaustive
> `switch` then refuses to compile a caller who never handled "could not look."
> That is a breaking change; 0.0.8 is the non-breaking patch that reaches you
> first.

Running the snippet (`dart run example/quickstart.dart`) prints:

```
[nwsUnitedStates] severe: Heavy snow expected
1 advisory, 0 errors
```

## Behaviours worth knowing

- **Init is mandatory.** Calling `fetchActiveAdvisoriesAtPoint` before
  `init` throws `StateError`. Init failures (schema-version mismatch,
  required configuration missing) propagate from `init` — the
  aggregator does NOT swallow init failures, since init is the
  canonical surface for surfacing configuration drift before any
  caller depends on a broken provider.

- **Per-provider failures do not abort the fan-out.** When one provider
  raises during `fetchActiveAdvisoriesAtPoint`, its error is captured
  in `result.providerErrors`; surviving providers' advisories appear
  in `result.advisories`. The integrator surfaces staleness to the
  driver honestly (e.g. "JMA unavailable; NWS data shown").

- **`Advisory` is Equatable.** Stream de-duplication can use
  `distinct()` directly.

- **Adapter package boundary is per-publisher.** Each publisher (NWS,
  JMA, JARTIC, NEXCO, prefectural, etc.) ships its own
  `condition_aggregator_<source>` package. License, cybersecurity, and
  AAA-class safety boundary are audited per adapter package, not at
  this interface.

## Real adapters

Use a real publisher feed by depending on an adapter package instead of the
inline `MyProvider` above:

```dart
// oracle:placeholders package:condition_aggregator_nws/condition_aggregator_nws.dart, NwsAdvisoryProvider
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_nws/condition_aggregator_nws.dart';

final agg = AdvisoryAggregator(providers: <AdvisoryProvider>[
  NwsAdvisoryProvider(
    userAgent: '(myapp.example, contact@myapp.example)',
  ),
  // additional adapters added here as further sources graduate
]);
```

## Dependency posture

- Pure Dart. No Flutter dependency.
- Sole runtime dependency: `equatable` ^2.0.7.
- Dev dependencies: `test` ^1.25.0, `lints` ^5.1.1.
- Strict-cast / strict-inference / strict-raw-types analyser settings.

## License

BSD-3-Clause. See [LICENSE](LICENSE) (matches the rest of SNGNav).

---

## Background & provenance

Source-neutral interface for severity-qualified meteorological-advisory
aggregation. Defines the typed `Advisory` event, the `AdvisoryProvider`
adapter contract, and the `AdvisoryAggregator` multi-source fan-out
primitive consumed by per-source adapter packages.

**Status**: published on pub.dev (v0.0.6); early and evolving — the
`Advisory` interface may still change with a minor version bump.

Pure Dart. No Flutter dependency. Sole runtime dependency: `equatable`.

### What this package is

The interface defines:

- `Advisory` — one typed advisory event, normalized across publisher
  sources. Fields: `source`, `eventClass`, `severity`, `certainty`,
  `urgency`, `areaDescription`, `effective`, `expires`, `headline`,
  `description`. Equatable for stream de-duplication.
- `AdvisorySource` — enum naming the publisher (`nwsUnitedStates`,
  `jmaJapan`, `other`).
- `AdvisorySeverity` / `AdvisoryCertainty` / `AdvisoryUrgency` —
  CAP-class normalized scales. Non-CAP sources (e.g. JMA) map their
  native classification to these scales at adapter boundary.
- `AdvisoryProvider` — adapter contract. One method:
  `fetchActiveAdvisoriesAtPoint(lat, lon)`. Plus an `init()` lifecycle
  hook for surfacing schema-version / configuration errors before any
  caller depends on a broken provider.
- `AdvisoryAggregator` — multi-source fan-out primitive. Holds N
  providers; init's them all; queries them all; returns merged results
  plus per-provider error list (warn-and-continue, not abort).
- `AdvisoryProviderInitException` — uniform init-failure exception
  type adapters MAY throw; subtypable for adapter-specific
  discrimination.
- `AdvisoryAggregateResult` / `AdvisoryProviderError` — fan-out result
  types.

### What this package is not

- Not a publisher. The package consumes and merges; it does not generate
  advisories. Per-source adapter packages (`condition_aggregator_nws`,
  `condition_aggregator_jma`, etc.) wrap publisher feeds.
- Not a renderer. The package returns typed value objects; it does not
  paint UI. Integrators (e.g. `driving_conditions`, `driving_weather`,
  app HMI) consume `Advisory` records.
- Not a forecaster. The package never time-shifts, derives, or fuses
  publisher data into novel predictions. Severity-not-profile invariant
  applies: `Advisory.severity` reflects the publisher's authority; the
  package adds no severity assertion of its own.
- Not a control loop. The package emits no actuator signal; the driver
  always drives.

### HER-trace (≤4-hop)

```
publisher advisory feed (NWS / JMA / etc.)
  → per-source adapter (condition_aggregator_<source>)
  → AdvisoryAggregator typed merge
  → integrator HMI surfaces advisory to the driver in unexpected snow
```

4 hops. The driver in unexpected snow receives a typed `Advisory`
event with severity / certainty / urgency / area / effective / expires
normalized across whichever publisher (NWS, JMA, etc.) issued the
underlying alert.

### Driver-facing loom

When a publisher (NWS, JMA, etc.) has issued an advisory for the
driver's current point, the integrator HMI surfaces a typed `Advisory`
event with severity / certainty / urgency / area / effective / expires
normalized across sources — as the driver's decision substrate, not as
raw GeoJSON or XML feed text. The Sakichi reading: the loom is a
multi-postman who carries each publisher's letter to the driver
without rewriting it; the loom does ONE thing well — typed merge with
warn-and-continue per-provider failure handling — and does NOT add
layers the driver did not ask for and the publishers did not author.

### Composition with sibling packages

```
noaa_nws_adapter (raw NWS HTTP+GeoJSON adapter)
  → condition_aggregator_nws (maps WinterAlert → Advisory)
  → condition_aggregator (this package; AdvisoryAggregator merges)
  → driving_conditions / driving_weather integrators
  → SNGNav app HMI / driver
```
