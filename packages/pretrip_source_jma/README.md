# pretrip_source_jma

Japan Meteorological Agency (AMeDAS) **measured surface-visibility** source for
the [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
pre-trip "Before you drive" briefing.

`JmaVisibilityProvider` fetches the nearest fresh visibility reading (metres)
from the JMA AMeDAS open-data network and emits a source-neutral
`VisibilityObservation` — the same typed measurement the Finnish Digitraffic
source emits — which the advisor merges into the **departure hour** via
`mergeObservedVisibility`.

Pure Dart. Only `http` and `pretrip_decision_advisor` runtime dependencies.

## ⚠ SAFETY-class — honesty rules (binding)

This package feeds a driver-safety decision. The following rules are binding
and must not be relaxed by any consumer of this package:

- **visibility NEVER estimated**
- **a warning NEVER produces a number**
- **an observation valid for the departure hour only**
- **null = the driver's own judgment, never a fabricated hazard**

In code terms: a value is served only when its AMeDAS QC flag is `0` (normal);
any other flag, no station within `maxDistanceKm`, no fresh visibility in a
snapshot newer than `maxObservationAge`, or any fetch/parse failure → `null`
(or a thrown `JmaVisibilityException` on HTTP/parse failure). A measured value
is valid for the hour she is leaving in and is merged into that single
departure-hour slot only — it is never projected forward into later forecast
hours, because that would fabricate forecast visibility the publisher never
issued. The condition contract is condition-general: visibility is carried in
**metres** and forecasts are **hourly**, so it serves every weather turmoil
(fog, dust, heavy rain, whiteout snow) — not a snow-only path.

## Measurement vs. warning — pick the sibling for your need (C8)

This package is one of a sibling pair drawing on the **same upstream provider**
(気象庁 / Japan Meteorological Agency):

| Package | Emits | Shape | pub-add it when you need… |
|---------|-------|-------|---------------------------|
| **`pretrip_source_jma`** (this) | a **MEASUREMENT** | `VisibilityObservation` (a real number, metres) | a measured visibility value to merge into the departure hour |
| **`condition_aggregator_jma`** (sibling) | a **WARNING** | `Advisory` (a categorical warning event) | a JMA winter-warning event for the condition-aggregator advisory stream |

A warning never produces a number; a measurement never produces a warning. Use
the measurement source (this package) to reach the advisor's measured
whiteout/severe band; use the warning sibling for categorical advisory events.

## Sibling sources — same contract, pick by region

The `pretrip_source_*` family all feed the same
[`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
and emit the SAME typed inputs, so you can swap region without changing your UI
code:

| Region / network | `pub add` | Emits |
|---|---|---|
| Japan — JMA / AMeDAS | `pretrip_source_jma` (this package) | measured `VisibilityObservation` (metres) |
| Finland — Fintraffic Digitraffic | [`pretrip_source_digitraffic`](https://pub.dev/packages/pretrip_source_digitraffic) | measured `VisibilityObservation` (metres) |
| Global — MET Norway locationforecast | [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway) | hourly `WeatherForecast` |

## Full reference integration (Flutter)

A standalone, edge-developer-shaped Flutter app that assembles and RENDERS a
pre-trip briefing from `pretrip_decision_advisor` + `pretrip_source_jma` — no
SNGNav app widgets — lives at
[`examples/edge_dev_akita_briefing/`](https://github.com/aki1770-del/SNGNav/tree/main/examples/edge_dev_akita_briefing).

## Service trace (driver in unexpected snow; ≤4 hops)

```
JMA AMeDAS visibility sensor (e.g. 秋田/Akita station 32402)
  → JmaVisibilityProvider (this package)
  → mergeObservedVisibility into the departure-hour forecast slot
  → pretrip_decision_advisor briefing an edge developer renders so a driver in
    unexpected snow — in Japan, including her mother in Akita — can decide
    before she sets out
```

This package exists so an edge developer can build their own UI/XI that warns a
driver in unexpected snow — and her family — **before** the whiteout, including
HER mother in Akita (a heavy-snow prefecture). Package count is not the success
metric; an edge developer running and seeing a real briefing is. Of 1286 AMeDAS
stations, 151 publish a live `visibility` sensor (probed 2026-06-14), including
秋田/Akita (32402) and 17 across Tōhoku/Hokkaidō — closing the measured-visibility
gap the MET Norway base and the JMA winter-warning merge alone cannot reach.

## Usage

```dart
import 'package:pretrip_source_jma/pretrip_source_jma.dart';

Future<void> main() async {
  final provider = JmaVisibilityProvider();
  try {
    final obs = await provider.fetchNearestVisibility(
      latitude: 39.72, // 秋田 / Akita
      longitude: 140.10,
    );
    if (obs == null) {
      // No fresh QC-normal reading in range — the driver's own judgement.
      return;
    }
    print('${obs.meters} m at ${obs.stationName} '
        '(${obs.distanceKm.toStringAsFixed(1)} km away)');
  } finally {
    provider.close();
  }
}
```

### Merge into a pre-trip briefing

```dart
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_jma/pretrip_source_jma.dart';

Future<PretripBriefing> brief(
  WeatherForecast base,
  DateTime departure,
) async {
  final provider = JmaVisibilityProvider();
  try {
    final obs = await provider.fetchNearestVisibility(
      latitude: 39.72,
      longitude: 140.10,
    );
    // No observation → brief on the base forecast unchanged (nothing
    // estimated). An observation → merge into the departure hour only.
    final forecast =
        obs == null ? base : mergeObservedVisibility(base, obs, departure);
    return const SnowAwarePretripAdvisor().brief(
      forecast: forecast,
      commute: CommuteShape(
        plannedDeparture: departure,
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['akita-route'],
        flexibility: CommuteFlexibility.discretionary,
      ),
      profile: const DriverProfileSpec(
        profileTag: 'akita',
        reactionTimeSeconds: 1.5,
      ),
    );
  } finally {
    provider.close();
  }
}
```

## License + attribution (binding)

This adapter package code is licensed under [BSD 3-Clause](LICENSE).

The visibility data is **気象庁 / Japan Meteorological Agency (open data)**,
freely usable. Attribution is surfaced at the consumer-facing surface, not
optional: an integrator rendering an observation from this source MUST credit
**気象庁 / Japan Meteorological Agency** at the HMI layer where the value is
shown (per-observation detail, credits screen, about panel — any reasonable
manner). The provider consumes the JMA data unmodified; nearest-station
selection and the QC-flag-0 filter are derivations of representation, not
modifications of the underlying publisher data.

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
