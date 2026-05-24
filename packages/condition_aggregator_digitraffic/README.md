# condition_aggregator_digitraffic

Fintraffic Digitraffic traffic-announcements adapter for the
[`condition_aggregator`](https://pub.dev/packages/condition_aggregator)
interface. Maps Finnish traffic announcements to source-neutral
`Advisory` events.

Pure Dart. Only `http` and `condition_aggregator` runtime dependencies.

## Status

Phase: explore — v0.0.2. Ships against the open Digitraffic
traffic-announcements endpoint with point-based bounding-box
filtering and integrator-overridable CAP-class heuristic mapping by
`trafficAnnouncementType`.

This is the **first** adapter under the Nordic-region adapter family;
the **second** is
[`condition_aggregator_met_norway`](../condition_aggregator_met_norway/).

## HER-trace (≤4 hops)

```
Fintraffic Digitraffic traffic-announcements feed
  → DigitrafficAdvisoryProvider (this package)
  → AdvisoryAggregator typed merge
  → integrator HMI surfaces advisory to the driver in unexpected snow
    on Finnish roads
```

Mission anchor: this package exists to help a driver on a Finnish
road in unexpected snow — and her family — especially in
compound-failure conditions when standard navigation infrastructure
has gone away. Adapter-count is not the success metric; integrator
pull + driver-relevance is.

## Source attribution

`v0.0.2` continues to use `AdvisorySource.other` as a placeholder.
The `condition_aggregator` interface does not yet carry a Finland
member; the placeholder follows the enum's own documented
"early-scaffold without locking the surface" convention. The
`AdvisorySource.fintrafficFinland` enum-extension upstream proposal
fires when a second Finnish-publisher adapter warrants the enum
surface change; until then `other` + the verbatim Fintraffic credit
line in `Advisory.description` carry the attribution load.

## Endpoint

`https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`

No authentication required (Digitraffic swagger v3 `security: []`,
verified 2026-05-24). GeoJSON FeatureCollection response; this
adapter filters features whose geometry intersects a small bounding
box around the requested point. The 2026-05-24 live response measured
~3.5 MB across 1455 active features.

## Mapping (v0.0.2)

| Advisory field    | Source                                                 |
|-------------------|--------------------------------------------------------|
| `source`          | `AdvisorySource.other` (placeholder; see above)        |
| `eventClass`      | `properties.trafficAnnouncementType` (verbatim)        |
| `severity`        | CAP-class via `capMapping` lookup (see table below)    |
| `certainty`       | CAP-class via `capMapping` lookup                      |
| `urgency`         | CAP-class via `capMapping` lookup                      |
| `areaDescription` | English announcement `location.description` + roadName |
| `effective`       | `announcements[].timeAndDuration.startTime` (ISO 8601) |
| `expires`         | `announcements[].timeAndDuration.endTime` (ISO 8601)   |
| `headline`        | English `announcements[].title` if present, else Finnish |
| `description`     | English `additionalInformation` if present, else Finnish, with verbatim Fintraffic CC-BY-4.0 credit appended |

### Default CAP-class mapping (`defaultDigitrafficCapMapping`)

Sourced from the 2026-05-24 live API genchi-genbutsu (5 distinct
`trafficAnnouncementType` values observed across 1455 active features
at 08:53 UTC):

| `trafficAnnouncementType`      | Live count | severity   | certainty | urgency     |
|--------------------------------|------------|------------|-----------|-------------|
| `accident report`              | 711        | `severe`   | `observed`| `immediate` |
| `general`                      | 442        | `minor`    | `possible`| `expected`  |
| `preliminary accident report`  | 158        | `moderate` | `likely`  | `expected`  |
| `ended`                        | 143        | `minor`    | `observed`| `past`      |
| `retracted`                    | 1          | `minor`    | `unlikely`| `past`      |
| _unobserved future class_      | -          | `minor`    | `possible`| `unknown`   |

Integrators with region-specific risk profiles (e.g., rural-Finland
where any `general` announcement may be driver-actionable in
compound-failure-snow conditions) SHOULD override per-event-class via
the `capMapping` constructor parameter. The fallback mapping for
unobserved future event-class values is conservatively
`minor` / `possible` / `unknown`; integrators MAY override it too.

## Usage

```dart
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficAdvisoryProvider();
  try {
    await provider.init();
    final advisories = await provider.fetchActiveAdvisoriesAtPoint(
      latitude: 60.17,
      longitude: 24.93,
    );
    for (final a in advisories) {
      print('${a.eventClass} (${a.severity.name}) — ${a.headline}');
    }
  } finally {
    provider.close();
  }
}
```

### Integrator-overridable CAP mapping

```dart
final ruralFinlandProvider = DigitrafficAdvisoryProvider(
  capMapping: <String, DigitrafficCapMapping>{
    // Rural-Finland integrator elevates "general" — any active
    // announcement in compound-failure-snow conditions is potentially
    // driver-actionable.
    'general': DigitrafficCapMapping(
      severity: AdvisorySeverity.moderate,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
    ),
  },
);
```

## Composition

```dart
final aggregator = AdvisoryAggregator(providers: [
  DigitrafficAdvisoryProvider(), // Finland
  MetNorwayAdvisoryProvider(userAgent: 'your_app/1.0 contact@...'),
  // ... other adapters
]);
```

## License + attribution (binding)

This adapter package code is licensed under [BSD 3-Clause](LICENSE).

**Digitraffic data is licensed CC-BY-4.0** per Fintraffic Terms of
Service (`https://www.digitraffic.fi/en/terms-of-service/`, verified
2026-05-24): *"Fintraffic's open data is licensed under the Creative
Commons 4.0 By license."* Attribution is REQUIRED at the
consumer-facing surface, not optional.

The adapter emits the Fintraffic-required attribution string in the
`Advisory.description` field of every advisory, verbatim per
Fintraffic ToS:

> Source: Fintraffic / digitraffic.fi, license CC 4.0 BY.

Integrators MUST surface that line at the HMI layer where the
advisory is rendered (per-advisory detail, credits screen, about
panel — any *"reasonable manner"* satisfying CC-BY-4.0 §3(a)(2)).
The string is also exported as the public constant
`kDigitrafficAttributionString` for direct integrator use.

### Modification disclosure (CC-BY-4.0 §3(a)(1)(b))

This adapter transforms the Digitraffic
`/v2/traffic-announcements` GeoJSON FeatureCollection into a
CAP-class `Advisory` typed event. The original Fintraffic data is
**consumed unmodified**; the bounding-box filtering and CAP-class
heuristic mapping are derivations of representation (selecting
features near a point; ranking severity per event-class), not
modifications of the underlying publisher data. Integrators
rendering the advisory should treat the verbatim attribution credit
line as accompanying both the original Fintraffic data and this
adapter's derivative representation of it.

## What v0.0.2 still defers (carry-forward to v0.0.3+)

- `AdvisorySource.fintrafficFinland` enum-extension upstream
  proposal (fires when a second Finnish-publisher adapter warrants
  the enum surface change per NDI bylaws Rule 1(c) standing-watch).
- Symbol-class refinement via
  `properties.announcements[].features[]` (granular tags like
  `wildlife`, `road works`, `weather`).
- `If-Modified-Since` cache-friendly polling.
- `package:http` `RetryClient` wrapper.
- Integrator-facing pana score baseline + publish-readiness
  summary per NDI bylaws Rule 6 (pre-`dart pub publish` substrate).

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
