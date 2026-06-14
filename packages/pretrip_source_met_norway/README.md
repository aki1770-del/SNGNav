# pretrip_source_met_norway

MET Norway `locationforecast/2.0/compact` hourly-forecast **source** for the
[`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
contract. Fetches the publisher's GLOBAL forecast product and maps the FULL
hourly timeseries into the contract's `WeatherForecast` — the raw
MEASUREMENT an edge developer feeds to `pretrip_decision_advisor` to build
their own pre-trip "Before you drive" surface.

Pure Dart. Only `http` and `pretrip_decision_advisor` runtime dependencies.

## Status

Phase: extract — v0.1.0. Extracted verbatim (no behaviour change) from the
SNGNav app's `MetNorwayHourlyForecastProvider`. The `locationforecast`
product is global, so this serves a Nagoya commute as well as a Tromsø one.

## Safety contract — honesty rules (BINDING, verbatim)

This is a **SAFETY-class** package: its output drives a driver's decision to
set out before bad weather. These rules are binding and are enforced in the
source, exercised by the tests, and stated here so an integrator cannot miss
them:

- **Visibility is NEVER estimated.** The compact product carries no
  visibility and no road-surface state. `visibilityMeters` and
  `estimatedRoadCondition` are mapped as `null` ALWAYS — absence of data is
  never turned into presence (or absence) of a hazard the publisher did not
  forecast. Sky-state is not surface-state; we do not estimate what the
  publisher did not forecast.
- **A warning NEVER produces a number.** This source emits a *measurement*
  (temperature, humidity, precipitation, and honest nulls), not a warning.
  It never fabricates a visibility metre value, a road-grip figure, or any
  number the publisher did not report. Turning a measurement into a warning
  is the advisor's job, downstream — never this source's.
- **An observation is valid for the departure hour only.** Each
  `HourlyForecast` describes one hour. Slices without an hourly
  (`next_1_hours`) block — the 6-hourly tail of the timeseries — are
  skipped, not interpolated; the forecast simply ends where hourly
  resolution ends and the advisor's no-data handling takes over past that
  horizon. A slice missing the required `air_temperature` is skipped, never
  guessed.
- **Null is the driver's own judgement, never a fabricated hazard.**
  `fetchForecast` returns `null` when the response carries no usable hourly
  slice, and a missing `meta.updated_at` returns `null` rather than
  inventing an issue time (the advisor's staleness chip depends on it being
  real). When you receive `null`, surface "no data" and hand the decision to
  the driver — never substitute a default hazard or a default all-clear. All
  fetch/parse failures surface as `MetNorwayForecastException` or `null`;
  nothing is fabricated.

This contract is condition-GENERAL: visibility in metres and an hourly
forecast serve every weather turmoil (fog, rain, dust, snow), not snow
alone.

## Measurement vs warning — this package and its sibling

The same MET Norway publisher feeds two packages in this family. Pick by
what your surface needs:

| You need…                                            | `pub add`                          | It emits                       |
|------------------------------------------------------|------------------------------------|--------------------------------|
| the raw hourly forecast to reason over yourself (pre-trip departure-timing) | **`pretrip_source_met_norway`** (this) | a MEASUREMENT — `WeatherForecast` (full hourly timeseries) |
| a ready-made source-neutral alert to merge with other regions' alerts       | [`condition_aggregator_met_norway`](../condition_aggregator_met_norway/) | a WARNING — `Advisory` (CAP-class event) |

Both speak the same publisher endpoint. This package maps the **full** hourly
timeseries so the advisor can search for a better departure window; the
sibling maps a slice into a single in-trip advisory.

## Service trace (driver in unexpected weather; ≤4 hops)

```
MET Norway locationforecast/2.0/compact feed
  → MetNorwayHourlyForecastProvider (this package)
  → pretrip_decision_advisor advisor (the edge developer composes)
  → integrator pre-trip surface warns the driver — and her family —
    before she sets out into the whiteout
```

This package exists so an edge developer can warn a driver before she sets
out — HER in Nagoya, HER mother in Akita (heavy-snow), a driver in Tromsø —
and her family, especially in compound-failure conditions when standard
navigation infrastructure has gone away. Package count is not the success
metric; an edge developer running it and a driver seeing the briefing is.

## Endpoint

`https://api.met.no/weatherapi/locationforecast/2.0/compact`

No authentication required. MET Norway terms require an identifying
`User-Agent` naming your application plus a contact point — pass `userAgent`
to credit yourself (an empty UA is rejected before any request is made).
Coordinates are truncated to 4 decimals before sending (publisher
cache-friendliness AND a privacy posture — the driver's sub-11 m position is
not transmitted).

## Mapping

Per hourly slice (a slice is hourly iff it carries a `next_1_hours` block):

| `HourlyForecast` field   | Source                                                    |
|--------------------------|-----------------------------------------------------------|
| `hour`                   | `timeseries[i].time` (UTC → local wall-clock)             |
| `tempCelsius`            | `instant.details.air_temperature` (slice skipped if absent) |
| `humidityRH`             | `instant.details.relative_humidity`, or null              |
| `precipitationMmPerHour` | `next_1_hours.details.precipitation_amount`, or null      |
| `visibilityMeters`       | **null ALWAYS** (not in the compact product)              |
| `estimatedRoadCondition` | **null ALWAYS** (sky-state is not surface-state)          |

`WeatherForecast.issuedAt` ← `properties.meta.updated_at`; the mapper returns
`null` when it is absent/unparseable rather than inventing an issue time.

## Usage

```dart
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_met_norway/pretrip_source_met_norway.dart';

Future<void> main() async {
  final provider = MetNorwayHourlyForecastProvider(
    userAgent: 'your_app/1.0 contact@example.com',
  );
  try {
    final forecast = await provider.fetchForecast(
      latitude: 35.1709, // Nagoya
      longitude: 136.8815,
    );
    if (forecast == null) {
      print('No usable hourly forecast — hand the decision to the driver.');
      return;
    }
    const advisor = SnowAwarePretripAdvisor();
    final briefing = advisor.brief(
      forecast: forecast,
      commute: CommuteShape(
        plannedDeparture: DateTime.now().add(const Duration(minutes: 30)),
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['morning-commute'],
        flexibility: CommuteFlexibility.discretionary,
      ),
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );
    print('Verdict: ${briefing.verdict.name}');
  } finally {
    provider.close();
  }
}
```

See [`example/main.dart`](example/main.dart) for the runnable version.

## License + attribution (binding)

This adapter package code is licensed under [BSD 3-Clause](LICENSE).

**MET Norway forecast data is licensed CC BY 4.0.** The `locationforecast`
product is published by the Norwegian Meteorological Institute (MET Norway)
under the Creative Commons Attribution 4.0 International license. Attribution
is REQUIRED at the consumer-facing surface, not optional. Surface the credit
wherever the data is shown (per-forecast detail, credits screen, about panel —
any *"reasonable manner"* satisfying CC BY 4.0 §3(a)(2)):

> Data: © MET Norway, CC BY 4.0.

The MET Norway terms additionally require the identifying `User-Agent`
described under "Endpoint". This package consumes the publisher data
unmodified; the mapping to `WeatherForecast` (selecting hourly slices,
converting UTC to local wall-clock, carrying honest nulls) is a derivation of
representation, not a modification of the underlying forecast data.

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
