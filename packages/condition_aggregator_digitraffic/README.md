# condition_aggregator_digitraffic

Fintraffic Digitraffic traffic-announcements adapter for the
[`condition_aggregator`](https://pub.dev/packages/condition_aggregator)
interface. Maps Finnish traffic announcements to source-neutral
`Advisory` events.

Pure Dart. Only `http` and `condition_aggregator` runtime dependencies.

## Status

Phase: explore — v0.0.1. First slice; ships against the open
Digitraffic traffic-announcements endpoint with point-based
bounding-box filtering.

## HER-trace (≤4 hops)

```
Fintraffic Digitraffic traffic-announcements feed
  → DigitrafficAdvisoryProvider (this package)
  → AdvisoryAggregator typed merge
  → integrator HMI surfaces advisory to the driver in unexpected snow
    on Finnish roads
```

## Source attribution

`v0.0.1` uses `AdvisorySource.other` as a placeholder. The
`condition_aggregator` interface does not yet carry a Finland member;
the placeholder follows the enum's own documented "early-scaffold
without locking the surface" convention. A future interface release
adding `AdvisorySource.fintrafficFinland` is a known carry-forward;
this adapter rebases when that lands.

Digitraffic data is published openly by Fintraffic; the consumer
surface should credit the publisher.

## Endpoint

`https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`

No authentication required (Digitraffic swagger v3 `security: []`,
verified 2026-05-24). GeoJSON FeatureCollection response; this adapter
filters features whose geometry intersects a small bounding box around
the requested point.

## Mapping (v0.0.1)

| Advisory field    | Source                                                 |
|-------------------|--------------------------------------------------------|
| `source`          | `AdvisorySource.other` (placeholder; see above)        |
| `eventClass`      | `properties.trafficAnnouncementType` (verbatim)        |
| `severity`        | `unknown` (Digitraffic does not expose CAP-class)      |
| `certainty`       | `unknown` (same)                                       |
| `urgency`         | `unknown` (same)                                       |
| `areaDescription` | English announcement `location.description` + roadName |
| `effective`       | `announcements[].timeAndDuration.startTime` (ISO 8601) |
| `expires`         | `announcements[].timeAndDuration.endTime` (ISO 8601)   |
| `headline`        | English `announcements[].title` if present, else Finnish |
| `description`     | English `additionalInformation` if present, else Finnish |

Heuristic CAP-class severity mapping from `trafficAnnouncementType` is
a v0.0.2 candidate.

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
      print('${a.eventClass} — ${a.headline}');
    }
  } finally {
    provider.close();
  }
}
```

## Composition

```dart
final aggregator = AdvisoryAggregator(providers: [
  DigitrafficAdvisoryProvider(),
  // ... other adapters
]);
```

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
