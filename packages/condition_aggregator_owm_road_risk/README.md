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
  condition_aggregator: ^0.0.3
  condition_aggregator_owm_road_risk: ^0.1.0
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

- **Severity is caution-add-only.** When the publisher's `event_level`
  is at a bucket boundary, `OwmRoadRiskMapper` rounds to the lower
  (more conservative) of the two adjacent CAP buckets so the consumer
  warns earlier, not later.
- **Verbatim relay (Article 17 β).** The publisher's `event` and
  `description` strings are preserved as `Advisory.eventClass` and
  `Advisory.description`. The adapter does not transform publisher
  wording.
- **AdvisorySource for 0.1.0.** The umbrella enum
  `condition_aggregator` 0.0.3 does not yet name OpenWeatherMap as a
  dedicated source; 0.1.0 reports `AdvisorySource.other`. A forward-
  additive enum bump in `condition_aggregator` 0.0.4+ will introduce
  a dedicated value; `AdvisoryAggregator` consumers do not need to
  change.

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

## License

BSD-3-Clause. See [`LICENSE`](LICENSE).
