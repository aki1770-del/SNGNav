# Build HER winter-safety briefing in 15 minutes

This is a step-by-step on-ramp for an **edge developer** who has never touched
these packages. You start from an empty `flutter create` and finish with a
working, **offline** pre-trip briefing that tells a driver in Akita whether to
wait out a whiteout — assembled from **two published packages** and **your own**
UI widget.

What you'll have at the end (rendered by the code in this tutorial — see
`test/akita_briefing_capture_test.dart`, which writes the same PNG):

```
┌────────────────────────────────────────────┐
│ Before you drive — Akita                     │
│ Planned departure 07:15 · winter morning     │
│ ┌──────────────────────────────────────────┐ │
│ │ Consider waiting about 1 h —             │ │  ← verdict, coloured by severity
│ │ conditions are hazardous now             │ │
│ └──────────────────────────────────────────┘ │
│ •  Visibility may drop to ~80 m around 07:00 │  ← plain-language hazard chips
│    — whiteout conditions.                    │
│ •  Conditions improve by about 08:15.        │
│ ──────────────────────────────────────────── │
│ Departure-hour visibility MEASURED: 80 m at  │  ← the real measured reading
│ Akita (0.4 km away)                          │
│ Data: Japan Meteorological Agency / AMeDAS.  │
└────────────────────────────────────────────┘
```

Nothing here depends on the SNGNav app. Everything runs **offline and
deterministic** — no network in the render path, no LLM, no Google Maps, no GPS.
That is the point: when all of that has gone away, this still helps her decide.

**Prerequisites:** Flutter 3.10+ (`flutter --version`). ~15 minutes.

---

## Step 1 — New app + the two packages (2 min)

```sh
flutter create akita_briefing
cd akita_briefing
flutter pub add pretrip_decision_advisor pretrip_source_jma
```

That is the *entire* dependency footprint from us — two packages, both pure
Dart + Flutter with **no native plugins** (so they build anywhere Flutter does).
`pretrip_source_jma` pulls `pretrip_decision_advisor` in automatically; you add
both explicitly so your imports read clearly.

- **`pretrip_decision_advisor`** — the contract: the advisor, the typed
  `PretripBriefing` result, and the source-neutral `VisibilityObservation` /
  `mergeObservedVisibility`.
- **`pretrip_source_jma`** — `JmaVisibilityProvider`, which turns a real Japan
  Meteorological Agency AMeDAS reading into a `VisibilityObservation`.

---

## Step 2 — The data path (5 min)

Create `lib/akita_data.dart`. **The whole of your data logic is three
published-package calls** — merge a measured visibility into the departure-hour
forecast, then brief on it. This is pure Dart (no Flutter), so it's trivially
testable:

```dart
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_jma/pretrip_source_jma.dart'
    show JmaVisibilityProvider, JmaVisibilityException;

// 秋田 / Akita — AMeDAS station 32402.
const double akitaLat = 39.72;
const double akitaLon = 140.10;

// A deterministic winter-morning forecast: temperature only, NO visibility —
// exactly the shape a compact forecast product gives, and exactly why a
// MEASURED visibility source is needed to reach the whiteout band.
WeatherForecast akitaWinterForecast() => WeatherForecast(
      issuedAt: DateTime(2026, 1, 1, 6),
      hourly: [
        for (var h = 7; h <= 11; h++)
          HourlyForecast(hour: DateTime(2026, 1, 1, h), tempCelsius: -6),
      ],
    );

CommuteShape akitaCommute() => CommuteShape(
      plannedDeparture: DateTime(2026, 1, 1, 7, 15),
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['akita-morning-errand'],
      flexibility: CommuteFlexibility.discretionary,
    );

DriverProfileSpec akitaDriver() =>
    const DriverProfileSpec(profileTag: 'akitaRural', reactionTimeSeconds: 1.5);

// The whiteout-case measured reading, shaped exactly as JmaVisibilityProvider
// emits it. (80 m is the demonstration whiteout value — see Honesty below.)
VisibilityObservation akitaWhiteoutObservation() => VisibilityObservation(
      meters: 80,
      stationId: 32402,
      stationName: 'Akita',
      measuredAt: DateTime(2026, 1, 1, 7, 10),
      distanceKm: 0.4,
    );

// ── The whole edge-developer data path: three published-package calls. ──
PretripBriefing assembleAkitaBriefing(VisibilityObservation observation) {
  final forecast = akitaWinterForecast();
  final commute = akitaCommute();

  // 1. Merge the NOW measurement into the departure-hour slot only.
  final merged =
      mergeObservedVisibility(forecast, observation, commute.plannedDeparture);

  // 2. Brief on the merged forecast.
  const advisor = SnowAwarePretripAdvisor();
  return advisor.brief(
      forecast: merged, commute: commute, profile: akitaDriver());
}
```

That's it — `assembleAkitaBriefing` returns a typed `PretripBriefing` your UI
renders. The temperature-only forecast on its own would never reach the severe
band; the **measured 80 m** is what lights the whiteout verdict.

---

## Step 3 — Your own UI (4 min)

You render the typed `PretripBriefing` **however you like** — this is *your*
UI/XI, not ours. The result exposes everything you need:

- `briefing.verdict` — a `PretripVerdict` enum (`clear` / `caution` /
  `waitAdvised` / `hazardPersists` / `requiredTripHazard` / `noData`).
- `briefing.recommendation?.strength` and `.suggestedDelay` — how strong, how long.
- `briefing.chips` — a `List<String>` of plain-language hazard lines.

A minimal widget — the three things that matter, simply:

```dart
import 'package:flutter/material.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

class AkitaBriefingView extends StatelessWidget {
  const AkitaBriefingView({super.key, required this.briefing, required this.observation});
  final PretripBriefing briefing;
  final VisibilityObservation observation;

  @override
  Widget build(BuildContext context) {
    final rec = briefing.recommendation;
    final hazardous = briefing.verdict == PretripVerdict.waitAdvised ||
        briefing.verdict == PretripVerdict.hazardPersists;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Verdict headline, coloured by severity.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: hazardous ? const Color(0xFFFFE0D6) : const Color(0xFFE3F2E6),
              child: Text(
                hazardous
                    ? 'Consider waiting about ${rec?.suggestedDelay.inMinutes ?? 0} min'
                        ' — conditions are hazardous now'
                    : 'Conditions look clear for your trip window',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            // 2. Plain-language hazard chips.
            for (final chip in briefing.chips) Text('•  $chip'),
            const Divider(),
            // 3. The departure-hour MEASURED-visibility line — never estimated.
            Text('Departure-hour visibility MEASURED: '
                '${observation.meters.round()} m at ${observation.stationName} '
                '(${observation.distanceKm.toStringAsFixed(1)} km away)'),
            const Text('Data: Japan Meteorological Agency / AMeDAS (open data).'),
          ],
        ),
      ),
    );
  }
}
```

> Want the full severity-coloured version (every `PretripVerdict` mapped to a
> colour + headline, plus the honesty banner)? Copy `lib/akita_briefing_view.dart`
> from this example — it's a complete, drop-in `StatelessWidget`.

---

## Step 4 — Wire it up and run (2 min)

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'akita_briefing_view.dart';
import 'akita_data.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final observation = akitaWhiteoutObservation();
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Akita pre-trip briefing')),
        body: SingleChildScrollView(
          child: AkitaBriefingView(
            briefing: assembleAkitaBriefing(observation),
            observation: observation,
          ),
        ),
      ),
    );
  }
}
```

```sh
flutter run
```

You now see HER briefing — the screenshot at the top of this file. **You built a
working offline winter-safety briefing in about ten minutes**, and every safety
decision came from the published advisor, not from code you had to get right.

---

## Step 5 — Go live (1 min)

To brief on a **real** AMeDAS reading instead of the demonstration value, call
the provider. It returns `null` when no fresh in-range reading exists — the
honest "driver's own judgment" outcome, **never a fabricated number**:

```dart
Future<VisibilityObservation?> fetchLiveAkitaVisibility() async {
  final provider = JmaVisibilityProvider();
  try {
    return await provider.fetchNearestVisibility(
        latitude: akitaLat, longitude: akitaLon);
  } on JmaVisibilityException {
    return null; // honest degradation — return the decision to the driver
  } finally {
    provider.close();
  }
}
```

Then `final live = await fetchLiveAkitaVisibility(); if (live != null) rebrief(live);`
— see `lib/main.dart` for the full "Try live JMA" button wiring.

---

## Step 6 — Other regions (1 min)

The source is the only region-specific part. Swap the package; the contract and
your widget are unchanged — every source emits the same `VisibilityObservation`
(or feeds the same `WeatherForecast`) against the same advisor:

| Region | Package | What it provides |
|---|---|---|
| Japan | [`pretrip_source_jma`](https://pub.dev/packages/pretrip_source_jma) | JMA / AMeDAS measured visibility |
| Finland | [`pretrip_source_digitraffic`](https://pub.dev/packages/pretrip_source_digitraffic) | Fintraffic Digitraffic measured visibility |
| Global | [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway) | MET Norway hourly forecast |

---

## The four honesty rules (binding — they are why this is safe to ship)

These are enforced by the packages, not by your code. Keep them and you cannot
mislead a driver:

1. **Visibility is never estimated** — a source maps absent data to `null`, never to a value.
2. **A warning never produces a number** — measurement and warning live on separate packages.
3. **An observation is valid for the departure hour only** — `mergeObservedVisibility` sets the covering slot and never projects forward.
4. **`null` = the driver's own judgment**, never a fabricated hazard — and we never fabricate an "all clear".

The `80 m` here is a labelled **demonstration** whiteout value (live Akita
visibility in June reads clear). It shows the path that lights the severe band
when the sensor really does read low — which, for HER mother in Akita, it will.

---

## Where to go next

- The full worked app (live button, severity colours, capture test): the rest of
  this `examples/edge_dev_akita_briefing/` directory — see `README.md`.
- The contract + reference advisor: [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor).
- More of the offline winter-safety family on pub.dev: `navigation_safety_core`,
  `voice_guidance` (incl. haptic cues for deaf/hard-of-hearing drivers),
  `condition_aggregator_*` (live road-condition adapters).
