# condition_aggregator_owm_road_risk

[![pub package](https://img.shields.io/pub/v/condition_aggregator_owm_road_risk.svg)](https://pub.dev/packages/condition_aggregator_owm_road_risk)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

OpenWeatherMap Road Risk adapter for the
[`condition_aggregator`](https://pub.dev/packages/condition_aggregator)
interface. Maps OWM Road Risk `alerts[]` entries to source-neutral
`Advisory` typed events so an integrator consumes one shape across
publishers — JMA in Japan, NOAA NWS in the United States, OpenWeatherMap
Road Risk for the broader US / EU commercial-API surface.

## Why this package exists

A driver entering an unexpected snow or ice region in the US or EU
needs winter-hazard signal that arrives through whatever the consuming
app already has access to. OpenWeatherMap's Road Risk endpoint surfaces
road-surface temperature, black-ice probability, and national-agency
alerts along a route or at a destination point. This package consumes
that endpoint and returns Dart objects an app can compose — alongside
`condition_aggregator_jma` (Japan) and `condition_aggregator_nws`
(US public-domain feed) — through a single typed shape.

### Driver impact chain (≤4 hops)

```
OWM Road Risk (api.openweathermap.org/data/2.5/roadrisk)
  -> OwmRoadRiskProvider (this package)
    -> AdvisoryAggregator typed merge with sibling adapters
      -> driver in unexpected snow region (US / EU)
```

Four hops, with the driver as the terminal beneficiary.

## Status

**0.1.0 ships the adapter pattern.** Operators supply their own
OpenWeatherMap API key (`appid`); this package does **not** bundle one.
Tests run against `MockClient` with a golden response fixture so CI
does not burn publisher quota. Live consumer testing requires the
operator to register at openweathermap.org and pass their key at
provider construction time.

## Quick start

### a. Install + import

```yaml
dependencies:
  condition_aggregator: ^0.0.5
  condition_aggregator_owm_road_risk: ^0.1.4
```

```dart
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_owm_road_risk/condition_aggregator_owm_road_risk.dart';
```

### b. One-shot point query

```dart
final provider = OwmRoadRiskProvider.withApiKey(
  apiKey: 'your-openweathermap-api-key',
);
await provider.init();

final advisories = await provider.fetchActiveAdvisoriesAtPoint(
  latitude: 42.886,
  longitude: -78.879,
);

for (final a in advisories) {
  print('${a.severity.name}: ${a.eventClass} — ${a.description}');
}

provider.close();
```

### c. Composition through AdvisoryAggregator

```dart
final aggregator = AdvisoryAggregator(providers: [
  OwmRoadRiskProvider.withApiKey(apiKey: 'your-key'),
  // + sibling adapters: condition_aggregator_jma, condition_aggregator_nws
]);
final result = await aggregator.fetchActiveAdvisoriesAtPoint(
  latitude: 42.886,
  longitude: -78.879,
);
print('${result.advisories.length} advisories from '
      '${result.advisories.length} providers; '
      '${result.providerErrors.length} provider errors.');
```

### d. Lower-level multi-waypoint track query

```dart
final client = OwmRoadRiskClient(apiKey: 'your-key');
final alerts = await client.fetchTrack([
  OwmRoadRiskWaypoint(latitude: 42.886, longitude: -78.879, unixTime: now),
  OwmRoadRiskWaypoint(latitude: 43.000, longitude: -79.000, unixTime: now),
]);
```

## Mapping discipline

- **Severity bucket boundaries are chosen caution-add-only.**
  `OwmRoadRiskMapper.severityFromEventLevel` maps the publisher's
  monotonic `event_level` integer directly to a CAP-class
  `AdvisorySeverity` (`1 → minor`, `2 → moderate`, `3 → severe`,
  `≥4 → extreme`, `≤0 → unknown`). The bucket cut-points were picked
  conservatively so the consumer warns earlier rather than later; the
  mapping itself is a fixed lookup — there is no runtime rounding step.
- **Verbatim relay (Article 17 β).** The publisher's `event` and
  `description` strings are preserved as `Advisory.eventClass` and
  `Advisory.description`. The adapter does not transform publisher
  wording.
- **AdvisorySource.** The umbrella enum `condition_aggregator` has no
  dedicated OpenWeatherMap source value, so this adapter reports
  `AdvisorySource.other`. `AdvisoryAggregator` consumers handle it like
  any other advisory.

## When the publisher is silent

A source can be silent in ways that are not the same fact, and this adapter
keeps them apart rather than resolving them all to one convenient value. An
unmeasured field never buys a downgrade here: "we do not know" and "it is fine"
are different sentences, and only one of them is safe to tell a driver.

| the publisher… | you get |
| --- | --- |
| answered, and nothing is active at this point | an empty list, and `OwmRoadRiskRead.isComplete == true` |
| answered with a good alert, but stated no `event_level` | the alert, with `reportedEventLevel == null` and `Advisory.severity == AdvisorySeverity.unknown` — never a low severity |
| could not be reached, or answered unreadably in full | a thrown `OwmRoadRiskHttpException` / `OwmRoadRiskParseException` — never an empty list |
| answered, and part of the answer was unreadable | the readable advisories **plus** a `minor`-severity notice with `eventClass == kOwmRoadRiskIncompleteReadEventClass` |
| told us it does not cover this point or hour | **nothing — see the honest bound below** |

**Read `reportedEventLevel`, not `eventLevel`.** `eventLevel` is non-null for
source compatibility and reads `0` both when the publisher stated level `0` and
when it stated no level at all, so a threshold such as `eventLevel >= 2`
silently treats an unstated level as a mild one. `reportedEventLevel` is `null`
in that case, which is *off* the scale rather than at the benign end of it, and
the analyzer will stop the comparison instead of letting it under-warn.

**Honest bound — declared coverage gaps have no vocabulary here.** The
publisher's road-risk response has no field that says "this point or this hour
is outside my coverage". So a genuine all-clear and an uncovered slice arrive at
this adapter identically, and this package **cannot** distinguish them. The
distinction is absent at the wire, and rather than invent a signal we do not
have, we state that we do not have it. If OpenWeatherMap adds a coverage
declaration, carrying it into `Advisory` is an upstream proposal to
`condition_aggregator`, not something this adapter may decide alone.

Our honesty is also bounded at the wire in one further way: if the publisher
sends a figure that is itself wrong, this adapter relays it faithfully. We do
not claim past that.

## Standards mapping

This package is intended for **SAE J3016 Level 0 and Level 1 supportive
use** — the driver performs the dynamic driving task at all times; the
package surfaces inform the driver but never actuate the vehicle and
never close a control loop.

| Standard | Mapping |
|---|---|
| **SAE J3016** | L0 / L1 supportive. **No L2+ claim.** |
| **ISO 26262** | Product-quality scope at the package boundary, not functional-safety scope. The integrator performs the hazard analysis. |
| **JIS / JASO** | Not mapped at this scope. |

See [`SAFETY_BOUNDARY.md`](SAFETY_BOUNDARY.md) for the full safety-case
boundary disclosure.

## What this is NOT

- **Not a publisher API key bundler.** Operators supply their own
  `appid`. The OpenWeatherMap terms of service govern key usage and
  data redistribution; consult those terms before building consumer
  surfaces over this adapter.
- **Not a claim that silence is safety.** An empty result from this adapter
  means the publisher answered and reported nothing — not that the road is
  clear, and not that this point is covered. It throws rather than returning an
  empty list when it could not read the answer, but a publisher that simply does
  not cover a place will say nothing, and that is indistinguishable from an
  all-clear at this API. Do not build a "conditions normal" affirmation on an
  empty result from one adapter.
- **Not an offline-first data source.** The OpenWeatherMap Road Risk
  endpoint is a commercial, internet-only API. In a compound-failure
  scenario where internet is lost, this provider will throw
  `OwmRoadRiskHttpException`; the integrator decides the cache /
  fallback policy. `condition_aggregator_jma` and
  `condition_aggregator_nws` siblings remain available for their
  respective regions if their feeds are reachable.
- **Not a route planner.** The publisher's track request shape supports
  multi-waypoint forecasts along a planned route, but this adapter
  does not plan routes; the integrator supplies the waypoints.
- **Not an L2+ automation or handover-class supervision package.**

## Data attribution

This adapter's *code* is BSD-3-Clause (below). The road-risk and weather
**data** it relays is supplied by **OpenWeatherMap** and is © OpenWeatherMap.
OpenWeatherMap provides its automated self-service plan data under the
**Open Database License (ODbL)** (per the OpenWeatherMap pricing/licensing
pages). Consumers building surfaces over this adapter must attribute
OpenWeatherMap as the data source and comply with the ODbL and the
[OpenWeatherMap terms](https://openweathermap.org/terms) and
[pricing/license terms](https://openweathermap.org/price) for their plan. Data
license is independent of this package's source-code license.

## License

BSD-3-Clause (source code). See [`LICENSE`](LICENSE).
