# pretrip_source_digitraffic

One call that fetches the nearest **measured** road-visibility (metres) from
Finland's Fintraffic Digitraffic road-weather network — never estimated; `null`
when no fresh sensor is in range. Pure Dart, no Flutter.

```
dart pub add pretrip_source_digitraffic
```

(Pulls its only runtime peer, `pretrip_decision_advisor`, automatically.)

## Quick start

```dart
import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficVisibilityProvider();
  // Nearest measured road visibility to Helsinki (60.17 N, 24.93 E), now.
  final obs = await provider.fetchNearestVisibility(latitude: 60.17, longitude: 24.93);
  provider.close();

  if (obs == null) {
    // No fresh sensor in range — visibility is NEVER estimated; the call stays the driver's.
    print('No fresh measured visibility in range — not estimated.');
    return;
  }
  print('Measured ${obs.meters} m visibility at ${obs.stationName} '
      '(${obs.distanceKm.toStringAsFixed(1)} km away), at ${obs.measuredAt.toIso8601String()}.');
  print(kDigitrafficVisibilityAttributionString); // CC BY 4.0 attribution — required at your UI.
}
```

You get back a `VisibilityObservation` with `.meters`, `.stationName`,
`.distanceKm`, and `.measuredAt` — a real value measured *now* at the nearest
road-weather station — or `null` when none is fresh in range. Run it
(`dart run example/quickstart.dart`) and it prints a live reading, e.g.:

```
Measured 20000.0 m visibility at kt51_Hki_Lapinlahti (1.8 km away), at 2026-06-26T22:02:25.000.
Source: Fintraffic / digitraffic.fi, license CC 4.0 BY.
```

To put the measurement onto a forecast for a pre-trip briefing, see
[`example/main.dart`](example/main.dart) (merges it onto the departure-hour slot
with `mergeObservedVisibility`).

---

## The road, not only the sky

The same station also measures the **road surface**. One call, no extra network
cost — through 0.2.3 these sensors were parsed and discarded.

```dart
final provider = DigitrafficVisibilityProvider();
final obs = await provider.fetchNearestRoadSurface(latitude: 66.50, longitude: 25.73);
provider.close();
```

Run it (`dart run example/road_surface_quickstart.dart`). Live output,
2026-09-24:

```
Station vt4_Rovaniemi_Revontuli (#14034), 0.6 km away, measured 2026-09-24T15:13:17.000
  KELI_1: 2 = "Moist"  VSS=(no VSS equivalent — not guessed)
  KELI_2: 2 = "Moist"  VSS=(no VSS equivalent — not guessed)
  coldest surface: 7.0 °C (TIE_3)
  highest freezing point: 0.0 °C (JÄÄTYMISPISTE_1)
  fastest cooling: -0.2 °C/h (TIE_2_DERIVAATTA)
  present but NOT interpreted (no publisher code table): KELI_3, KELI_4, TIENPINNAN_TILA_1, TIENPINNAN_TILA_2, TIENPINNAN_TILA_3, TIENPINNAN_TILA_4
Source: Fintraffic / digitraffic.fi, license CC 4.0 BY.
```

### ⚠️ FINLAND ONLY — and the same call proves it

Digitraffic's road-weather network covers Finland. There is **no road-surface
source for Japan** — not from this publisher and not from any publisher this
catalog calls. The same call, measured live 2026-09-24:

| point | result |
|---|---|
| Rovaniemi, Lapland | station 0.6 km away, surface state + temperature + freezing point |
| Helsinki | station 1.8 km away — and its two channels **disagree**: `KELI_1` "Moist", `KELI_2` "Dry" |
| **Akita, Japan** | **`null` — no measured road surface. Not estimated.** |

### What it refuses to tell you

- **A channel the publisher does not define gets no meaning.** Fintraffic
  publishes a code table for `KELI_1`/`KELI_2` and an **empty** one for
  `KELI_3`, `KELI_4` and every `TIENPINNAN_TILA_n`. Those six carry live
  integers with no published meaning; borrowing `KELI_1`'s scale because the
  name matches would be an assumption, not a measurement. They are listed in
  `uninterpretedSensors` so you see that data exists which this package refused
  to read — silence is never absence.
- **A declared fault is not a surface.** Code `0` is "The sensor has a fault";
  it sets `sensorFaultDeclared` and produces no state.
- **No VSS equivalent means `null`, never `DRY`.** Five of ten Fintraffic codes
  map onto VSS `Vehicle.Exterior.RoadSurfaceCondition` (`DRY`, `WET`, `SNOW`,
  `ICE`, `SLUSH`). `Moist`, `Wet and salty`, `Frost` and `Probably moist and
  salty` do not — the publisher's own word is carried verbatim and the VSS
  field stays `null`. Override `vssMapping` at the call site if your roads say
  otherwise.
- **No averaging.** Four surface sensors at one station disagree; a mean cannot
  say one point alone is freezing. You get the **coldest** surface, the
  **highest** freezing point and the **fastest** cooling, each naming its sensor.
- **No projection.** The cooling rate is a *measured* °C/h, not a forecast. If
  you extrapolate it, that claim is yours.

Emits VSS allowed-value **strings**, so this package takes no new dependency.
For the enum, call `RoadSurfaceCondition.fromVss(value)` from
`navigation_safety_core`.

## Background & provenance

Fintraffic Digitraffic **measured road-visibility** source for the
[`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
pre-trip briefing. Fetches the nearest fresh measured visibility
(`NÄKYVYYS_M`, metres) on the Finnish road-weather network and emits a
source-neutral `VisibilityObservation` you merge onto the departure-hour slot
of a `WeatherForecast` with `mergeObservedVisibility`.

Pure Dart. Only `http` and `pretrip_decision_advisor` runtime dependencies. No
Flutter.

### ⚠️ SAFETY — honesty rules (binding, verbatim)

This is a safety-class source for a driving-decision surface. These rules are
**binding on every consumer** and are reproduced **verbatim** from the contract
this package serves. Do not relax them in your UI/XI:

- **visibility NEVER estimated**
- **a warning NEVER produces a number**
- **an observation valid for the departure hour only**
- **null = the driver's own judgment, never a fabricated hazard**

What this means concretely for this source:

- A `VisibilityObservation` is a **NOW measurement** at a real road-weather
  station up to `maxDistanceKm` from the requested point. The caller applies it
  to the **current (departure) hour only** — never projects it forward into
  later forecast hours. `mergeObservedVisibility` enforces this: it sets the
  value on the single covering departure-hour slot and leaves every later hour
  untouched.
- No station in range / no fresh visibility sensor / a stale reading / any
  fetch failure → **`null`**. Visibility is **never estimated** from sky
  symbols, precipitation, or anything else. `null` is not a hazard and not a
  zero — it hands the call back to the driver.
- This package emits a **measurement** (a number, in metres). It does **not**
  emit a warning. The "a warning NEVER produces a number" rule lives with the
  warning side (see the sibling below): a human-facing warning must not invent a
  precise figure it did not measure. Here the figure exists only because a
  sensor reported it.

### Mission

These sources feed the published `pretrip_decision_advisor` 0.2.0 so an edge
developer can build their own UI/XI that warns **HER** (Nagoya) and **HER
mother** (Akita, a heavy-snow prefecture) **before** she drives into the
whiteout. Success is an edge developer who **runs and sees** a briefing that
helped a real driver — never a package count. Adoption is `0`; that is named,
and it ranks nothing.

### Service trace (driver in unexpected snow; ≤4 hops)

```
Fintraffic Digitraffic road-weather network (real NÄKYVYYS_M sensors)
  → DigitrafficVisibilityProvider (this package)
  → mergeObservedVisibility onto the departure-hour forecast slot
    (pretrip_decision_advisor)
  → an edge developer's pre-trip briefing warns the driver before she
    leaves, in compound-failure winter conditions
```

### Sibling: measurement vs. warning (which to `pub add`)

This package has a sibling built on the **same upstream provider** (Fintraffic
Digitraffic). They emit different things — depend on the one that matches your
need (you may use both):

| Package | Emits | Type | `pub add` when you want… |
|---|---|---|---|
| **`pretrip_source_digitraffic`** (this) | a **MEASUREMENT** | `VisibilityObservation` (metres, a number measured at a station) | to put a real, measured visibility figure onto the **departure-hour** of a pre-trip forecast/briefing |
| [`condition_aggregator_digitraffic`](../condition_aggregator_digitraffic/) | a **WARNING** | `Advisory` (CAP-class severity/certainty/urgency from traffic announcements) | to surface live road **advisories/warnings** near a point through the `condition_aggregator` interface |

Rule of thumb: a **number you measured** → this package; a **human-facing
warning** → the sibling. Per the honesty rules, never let a warning invent a
number — keep the two paths distinct.

### Sibling sources — same contract, pick by region

The `pretrip_source_*` family all feed the same
[`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
and emit the SAME typed inputs, so you can swap region without changing your UI
code:

| Region / network | `pub add` | Emits |
|---|---|---|
| Japan — JMA / AMeDAS | [`pretrip_source_jma`](https://pub.dev/packages/pretrip_source_jma) | measured `VisibilityObservation` (metres) |
| Finland — Fintraffic Digitraffic | `pretrip_source_digitraffic` (this package) | measured `VisibilityObservation` (metres) |
| Global — MET Norway locationforecast | [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway) | hourly `WeatherForecast` |

### Full reference integration (Flutter)

A standalone, edge-developer-shaped Flutter app that assembles and RENDERS a
pre-trip briefing from `pretrip_decision_advisor` + `pretrip_source_jma` — no
SNGNav app widgets — lives at
[`examples/edge_dev_akita_briefing/`](https://github.com/aki1770-del/SNGNav/tree/main/examples/edge_dev_akita_briefing).

### The contract this serves condition-general

This source is **not snow-specific**. It emits visibility **in metres** for the
**departure hour** — which serves any weather turmoil that drops visibility
(fog, heavy rain, dust, smoke), not only snow. The snow framing is the driving
mission, not a regression on the contract; the data path stays general.

### Endpoint

Road-weather station network base: `https://tie.digitraffic.fi/api/weather/v1`

- `GET /stations` — GeoJSON station metadata (~20 KB gzip); the nearest
  `GATHERING` station to the requested point within `maxDistanceKm` is chosen.
- `GET /stations/{id}/data` — the `NÄKYVYYS_M` sensor (or `NÄKYVYYS_KM` × 1000),
  accepted only when `measuredTime` is within `maxObservationAge` (30 min
  default).

No authentication required. Requests carry an identifying `User-Agent`, as
Digitraffic asks integrations to identify themselves. Measured 2026-06-12: 453
of 526 stations (86%) report a live visibility sensor.

### Merge onto a forecast (departure-hour only)

```dart
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficVisibilityProvider();
  try {
    final departure = DateTime.now();
    final observation = await provider.fetchNearestVisibility(
      latitude: 60.17,
      longitude: 24.93,
      now: departure,
    );

    if (observation == null) {
      // No fresh sensor in range — nothing is estimated. The call stays
      // with the driver.
      return;
    }

    // Valid for the departure hour ONLY — mergeObservedVisibility never
    // projects it forward into later hours. (`forecast` is your own
    // WeatherForecast for the trip; see example/main.dart for a full one.)
    final merged = mergeObservedVisibility(forecast, observation, departure);
    // ... hand `merged` to pretrip_decision_advisor's brief().
  } finally {
    provider.close();
  }
}
```

See [`example/main.dart`](example/main.dart) for a complete runnable program.

### License + attribution (binding)

This package code is licensed under [BSD 3-Clause](LICENSE).

**Digitraffic data is licensed CC BY 4.0** per Fintraffic Terms of Service
(`https://www.digitraffic.fi/en/terms-of-service/`): *"Fintraffic's open data is
licensed under the Creative Commons 4.0 By license."* Attribution is **REQUIRED**
at the consumer-facing surface, not optional. Surface this line, verbatim, where
the visibility is rendered (per-reading detail, credits screen, about panel —
any *"reasonable manner"* satisfying CC BY 4.0 §3(a)(2)):

> Source: Fintraffic / digitraffic.fi, license CC 4.0 BY.

It is also exported as the constant `kDigitrafficVisibilityAttributionString`
for direct integrator use.

### License

BSD 3-Clause License. See [LICENSE](LICENSE).
