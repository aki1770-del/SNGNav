# condition_aggregator_met_norway

MET Norway (Meteorologisk institutt) locationforecast adapter for the
[`condition_aggregator`](https://pub.dev/packages/condition_aggregator)
interface. Maps Norwegian and Nordic-region next-hour weather
forecasts to source-neutral `Advisory` events at the adapter boundary.

Pure Dart. Only `http` and `condition_aggregator` runtime dependencies.

## Status

Phase: explore — v0.0.1. First slice; ships against the public MET
Norway `locationforecast/2.0/compact` endpoint with a heuristic
mapping from the next-hour forecast slice to a driver-actionable
`Advisory` typed event.

This is the **second** adapter under the Nordic-region adapter family
(first is
[`condition_aggregator_digitraffic`](../condition_aggregator_digitraffic/)
v0.0.1).

### What v0.0.1 covers

- Public `locationforecast/2.0/compact` endpoint, GeoJSON Point
  response.
- Next-hour slice (`timeseries[0].data.next_1_hours`) mapped to one
  `Advisory` when the slice matches a driver-actionable condition
  (freezing temperature, heavy precipitation, or subzero forecast).
- `AdvisorySource.metNorway` (the parent interface enum already
  carries the Norway member — no placeholder).
- Verbatim CC-BY-4.0 attribution string emitted in the
  `Advisory.description` field.
- Mandatory User-Agent header per MET Norway terms; coordinates
  truncated to 4 decimals per MET Norway terms.
- Heuristic CAP severity / certainty / urgency mapping; thresholds
  integrator-overridable.

### What v0.0.1 defers

- `roadforecast/2.0` direct road-surface mapping. The product
  documented at
  `https://api.met.no/weatherapi/roadforecast/2.0/documentation`
  returns HTTP 404 at curl on 2026-05-24 — the product is not publicly
  reachable. Queued for v0.0.2+ if a public road-product endpoint
  becomes available.
- `nowcast/2.0` two-hour radar overlay (Norway / Sweden / Finland /
  Denmark coverage).
- Multi-hour-horizon advisories (`next_6_hours`, `next_12_hours`).
- Symbol_code semantic mapping (full table of MET Norway symbol_code
  → CAP-class refinement; v0.0.1 uses temperature + precipitation
  thresholds + symbol_code only as a certainty signal).
- If-Modified-Since cache-friendly polling.
- `package:http` `RetryClient` wrapper.

## Endpoint

`https://api.met.no/weatherapi/locationforecast/2.0/compact`

Public endpoint; no authentication. **User-Agent is mandatory** —
MET Norway terms require an identifying User-Agent string naming the
application/domain plus a contact email or website link. Non-compliance
risks throttling or a permanent ban. Coordinates truncated to 4
decimals before request per MET Norway terms.

## Mapping (v0.0.1)

| Advisory field    | Source                                                |
|-------------------|-------------------------------------------------------|
| `source`          | `AdvisorySource.metNorway`                            |
| `eventClass`      | Derived: `Freezing precipitation` / `Heavy precipitation` / `Subzero forecast` (else: no advisory) |
| `severity`        | Heuristic by combined temperature + precipitation     |
| `certainty`       | `likely` if publisher `symbol_code` present, else `possible` |
| `urgency`         | `expected` (next-1-hour horizon)                      |
| `areaDescription` | `Lat <lat>, Lon <lon>` from GeoJSON Point             |
| `effective`       | `timeseries[0].time` (UTC)                            |
| `expires`         | `effective + 1 hour` (next-1-hour horizon)            |
| `headline`        | `<eventClass> — <symbol_code>` when symbol present    |
| `description`     | air_temperature + precipitation + symbol + CC-BY-4.0 attribution string |

### Heuristic severity at v0.0.1

| Condition                                                              | Severity   |
|------------------------------------------------------------------------|------------|
| air_temperature ≤ 0 °C AND precipitation ≥ 4 mm/h                      | `extreme`  |
| air_temperature ≤ 0 °C AND precipitation > 0                           | `severe`   |
| precipitation ≥ 4 mm/h (above freezing)                                | `severe`   |
| air_temperature ≤ 0 °C AND precipitation == 0                          | `moderate` |
| else                                                                   | (no advisory; returns `null` / empty list) |

Thresholds (4 mm/h heavy floor; 0 °C freezing floor) are
integrator-overridable at construction time.

## License + attribution (binding)

This package code is licensed under [BSD 3-Clause](LICENSE).

**MET Norway data is licensed CC-BY-4.0.** Attribution is REQUIRED by
the license at the consumer-facing surface, not optional. The adapter
emits the parent interface's verbatim attribution string in the
`Advisory.description` field:

> Source: Norwegian Meteorological Institute (Meteorologisk institutt
> / MET Norway). CC BY 4.0 — api.met.no.

Integrators MUST surface that line at the HMI layer where the
advisory is rendered. See
`AdvisorySource.metNorway.attributionString` in the parent
`condition_aggregator` interface for the canonical credit line.

## Usage

```dart
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';

Future<void> main() async {
  final provider = MetNorwayAdvisoryProvider(
    // Integrators publishing under their own identity SHOULD override:
    userAgent: 'your_app/1.0 your-contact@example.com',
  );
  try {
    await provider.init();
    final advisories = await provider.fetchActiveAdvisoriesAtPoint(
      latitude: 59.91,
      longitude: 10.75,
    );
    for (final a in advisories) {
      print('${a.eventClass} (${a.severity.name}) — ${a.headline}');
    }
  } finally {
    provider.close();
  }
}
```

## Composition

```dart
final aggregator = AdvisoryAggregator(providers: [
  DigitrafficAdvisoryProvider(), // Finland
  MetNorwayAdvisoryProvider(userAgent: 'your_app/1.0 contact@...'),
  // ... other adapters
]);
```

## HER-trace (≤4 hops)

```
MET Norway locationforecast feed
  → MetNorwayAdvisoryProvider (this package)
  → AdvisoryAggregator typed merge
  → integrator HMI surfaces advisory to the driver in unexpected
    snow on Norwegian / Nordic-region roads
```

Mission anchor: this package exists to help a driver on a Norwegian
or Nordic-region road in unexpected snow — and her family —
especially in compound-failure conditions when standard navigation
infrastructure has gone away. Adapter-count is not the success
metric; integrator pull + driver-relevance is.

## Carry-forward (post v0.0.1)

See [CHANGELOG.md](CHANGELOG.md) "Open questions surfaced" section
for the strategic-sequencing + ecosystem-engagement + family-coherence
questions opened by shipping the second Nordic adapter at the same
first-slice maturity as the first.

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
