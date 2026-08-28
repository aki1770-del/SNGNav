# pretrip_decision_advisor

> **0.6.1. Contract + working reference advisor + localized reason chips +
> humidity-aware black-ice (radiative frost) condition.**
>
> ⚑ **0.6.1 is a deliberate behavioural break: `brief(...)` now throws rather
> than call an unmeasured morning clear.** If you are upgrading from 0.6.0,
> read **Absence is not an all-clear** below before you upgrade — the
> migration is a typed `catch`, not a method swap.
>
> This package ships an abstract contract, its data shapes, **and** a working
> pure-Dart reference advisor (`SnowAwarePretripAdvisor`) plus a source-neutral
> measured-visibility merge. `pub add`-ing it gives you a usable advisor, not
> just types. It does not fetch weather or integrate a route engine — a
> source-specific fetcher (which owns any HTTP dependency) stays outside this
> package, so the package itself remains pure Dart with a single runtime
> dependency — `navigation_safety_calibration`, the family's dependency-free
> Magnus effective-temperature source of truth (added in 0.5.0 for the
> humidity-aware black-ice condition; depend-don't-copy) — and no FFI, so the
> offline core runs on 32-bit ARM (`armv7`) car-class hardware.
> The pure-Dart core was run-verified on genuine `armv7` (`uname armv7l`, 32-bit
> ARM Dart) producing the Akita briefing identical to the documented x86_64
> output; see the [runnability proof](https://github.com/aki1770-del/SNGNav/blob/main/examples/edge_dev_akita_briefing/_capture/armv7_runnability_proof.txt).
> (The Flutter visual render on `armv7` is gated on [flutter/flutter#188063](https://github.com/flutter/flutter/pull/188063) and is not yet proven.)

## Aspiration

The pre-trip departure-timing decision is often a larger pain point than
in-drive alerts. A driver asking "should I leave now or wait an hour?"
has to combine a forecast, a commute shape, and personal context, and the
answer changes whether the trip happens at all. Apps focused on alerts
during driving address a smaller window than apps that address departure
timing. This package defines the shape of an advisor that could help with
that question, so other packages and applications can experiment against
a common interface.

## Cohorts served

The package serves several distinct downstream cohorts:

- **Integrator developers** building parallel navigation products on top
  of common interfaces.
- **Open-source consumers** depending on shared safety-domain vocabulary.
- **Configuration consumers** inheriting predictable defaults.
- **Drivers** (indirectly, via integrator products) who benefit from the
  pre-trip decision layer addressing a prevention scenario before the
  in-drive compound-failure scenario.
- **Parallel-product builders** publishing their own concrete advisors
  against this contract without forking it.

## What is in the package

- `PretripAdvisor` — abstract advisor contract. Given a forecast, a
  commute shape, and a driver profile spec, it returns a recommendation,
  or `null` to mean "no recommendation; the driver should depart on
  their own judgment."
- `PretripRecommendation` — a suggested delay window, a confidence
  window, a recommendation strength, and a list of human-readable
  reason chips.
- `RecommendationStrength` — `advisoryWeak`, `advisoryStrong`, and
  `honestyMode`. `honestyMode` is used when the commute is required
  and the advisor explicitly defers to the driver rather than telling
  someone to risk being late for required obligations.
- `CommuteShape` and `CommuteFlexibility` — describe the planned trip,
  including whether the commute is required, discretionary, or unknown.
- `WeatherForecast`, `HourlyForecast`, and `RoadConditionEstimate` —
  the forecast inputs the advisor consumes.
- `DriverProfileSpec` — a small profile spec, decoupled from any
  specific full driver-profile package, so consumers can adopt this
  advisor without taking on a full safety-core dependency.
- `SnowAwarePretripAdvisor` — a deterministic, pure-Dart reference
  implementation of the contract. No LLM, no network, no clock: the same
  typed inputs always produce the same recommendation, so the worst-case
  path stays offline. Null forecast fields never fabricate a hazard, and it
  returns `null` when the forecast does not cover the departure window.
- `PretripBriefing`, `PretripVerdict`, and `HourHazard` — the richer typed
  verdict the reference advisor exposes via `brief(...)`, for UIs that want
  the structured result alongside the contract-shaped recommendation.
- `VisibilityObservation` and `mergeObservedVisibility` — a source-neutral
  measured-visibility observation and its departure-hour merge (a real sensor
  value overrides forecast visibility for the departure hour only, and is
  never projected into later forecast hours).
- `PretripMessages` — a hand-rolled, pure-Dart locale table for the advisor's
  reason chips. `PretripMessages.en` (default + fallback) and `PretripMessages.ja`;
  `PretripMessages.forLanguage(code)` resolves one and falls back to English
  (never throws). Measured numbers pass through every locale verbatim. Extend it
  to localize into a language this package does not yet carry.

## What is NOT in the package

- No weather data fetching (no HTTP dependency — a source-specific fetcher
  produces the typed inputs and stays outside this package).
- No route engine integration.

## Quick start

```sh
dart pub add pretrip_decision_advisor
```

## Absence is not an all-clear (behavioural break in 0.6.1)

**`brief(...)` can throw, and that is new in 0.6.1.**

Up to 0.6.0 a forecast slot carrying a temperature and nothing else — no
visibility, no road surface, no precipitation, no humidity — failed every
guarded hazard test, fell through to `clear`, and the briefing reported *no
winter hazard signals in your trip window*. That sentence was produced by the
absence of evidence rather than by evidence. It was not an edge case: a compact
global product such as [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway)
emits `visibilityMeters: null` and `estimatedRoadCondition: null` on every slot
by its own honesty rule, so a mild morning there was an all-clear across hazard
families that had never been checked.

0.6.1 gates **only the affirmative all-clear**:

- `brief(...)` throws `PretripAssessmentIncompleteException` when a forecast
  **does** cover your departure window but too little was measured to earn a
  "no winter hazard" conclusion.
- A **measured** hazard is never withheld — it still reports from partial data
  exactly as before. A temperature-only window is not automatically a throw; a
  cold-enough temperature is itself a measurement and returns a normal
  briefing.
- A window **nothing** forecast at all does not throw. It returns
  `peakHazard: HourHazard.unknown`, exactly as 0.6.0 did.

### Migrating from 0.6.0 — a typed `catch`, not a method swap

```dart
PretripBriefing briefing;
var assessmentIncomplete = false;
try {
  briefing = advisor.brief(forecast: f, commute: c, profile: p);
} on PretripAssessmentIncompleteException {
  assessmentIncomplete = true;
  // Take this package's own briefing for the state rather than composing a
  // second one that could drift from it.
  briefing = advisor.briefOrUnassessed(forecast: f, commute: c, profile: p);
}
```

That `assessmentIncomplete` flag is the point of the shape: **the throw is the
only thing on the public surface that separates the two absences.**

`briefOrUnassessed(...)` and `briefOrNull(...)` are compatibility shims for
callers that need a total function, and **neither is the migration**. Both
collapse the two absences — a window a forecast covered but did not measure,
and a window nothing forecast at all: `verdict` is `PretripVerdict.noData` and
`peakHazard` is `HourHazard.unknown` for both, `briefOrNull` is `null` for
both, and only `chips` differ.

They are fine for a caller that renders `chips`, logs, batch-scores, or treats
`peakHazard: unknown` as "do not conclude". They are **wrong for any surface
that derives a headline, banner, colour band or spoken line from `verdict`
alone** — that surface will tell the driver *there is no forecast for your
departure window* on a morning a forecast arrived, which is the same
false-sentence-from-absence this release exists to fix, moved to where it is
read first.

The per-method migration table, the two absences side by side, and a worked
opposed-pair widget test are in the CHANGELOG's **Migrating from 0.6.0**
section — [pub.dev changelog](https://pub.dev/packages/pretrip_decision_advisor/changelog).
It is deliberately not duplicated here, so the two cannot drift apart.

## End-to-end: measured source → briefing

This package is pure Dart, offline, and deterministic. A `pretrip_source_*`
provider gives you a measured `VisibilityObservation` and a `WeatherForecast`;
you merge the measurement into the **departure hour**, call `brief(...)`, and
render the typed result in your own UI. The snippet below constructs its inputs
inline so it runs with **no network** — see "Pair with a measured source" to
fetch real measurements. (This is also the package's `example/main.dart`.)

```dart
// End-to-end pre-trip briefing from this package, offline + deterministic.
//
// A pretrip_source_* provider (JMA / MET Norway / Digitraffic) gives you a
// measured VisibilityObservation and a WeatherForecast; here we construct them
// inline so the example is reproducible with no network. See those packages to
// fetch real measurements.
//
// HONESTY (binding): visibility is NEVER estimated; a warning never produces a
// number; an observation is valid for the DEPARTURE HOUR only; null = the
// driver's own judgment (a real source returns null, never a fabricated value).
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

void main() {
  // 1. A winter-morning forecast — temperature only, NO visibility (exactly the
  //    shape a compact global forecast gives; this is why a MEASURED visibility
  //    source is needed to reach the whiteout band).
  final forecast = WeatherForecast(
    issuedAt: DateTime(2026, 1, 1, 6),
    hourly: [
      for (var h = 7; h <= 11; h++)
        HourlyForecast(hour: DateTime(2026, 1, 1, h), tempCelsius: -6),
    ],
  );

  // 2. A MEASURED visibility observation, exactly as a pretrip_source_* provider
  //    emits it. 80 m is the labelled whiteout case; a real provider returns
  //    null (never a fabricated number) when no fresh reading is in range.
  final observed = VisibilityObservation(
    meters: 80,
    stationId: 32402,
    stationName: 'Akita',
    measuredAt: DateTime(2026, 1, 1, 7, 10),
    distanceKm: 0.4,
  );

  final commute = CommuteShape(
    plannedDeparture: DateTime(2026, 1, 1, 7, 15),
    plannedDuration: const Duration(minutes: 30),
    routeIdentifiers: const ['akita-morning-errand'],
    flexibility: CommuteFlexibility.discretionary,
  );

  // 3. Merge the NOW measurement into the DEPARTURE-HOUR slot only (never
  //    projected forward), then brief.
  final merged =
      mergeObservedVisibility(forecast, observed, commute.plannedDeparture);
  final briefing = const SnowAwarePretripAdvisor().brief(
    forecast: merged,
    commute: commute,
    profile: const DriverProfileSpec(
        profileTag: 'akitaRural', reactionTimeSeconds: 1.5),
  );

  // 4. Read the typed result out — this is what an edge dev renders in their UI.
  print('Verdict : ${briefing.verdict.name}');
  print('Strength: ${briefing.recommendation?.strength.name ?? "(none)"}');
  print('Delay   : ${briefing.recommendation?.suggestedDelay ?? Duration.zero}');
  print('Chips   :');
  for (final c in briefing.chips) {
    print('  - $c');
  }
  print('Measured: ${observed.meters} m at ${observed.stationName} '
      '(${observed.distanceKm.toStringAsFixed(1)} km away)');
}
```

Running it (`dart run example/main.dart`) prints the typed result an edge
developer renders — the measured 80 m lights the whiteout/severe band a
temperature-only forecast alone could never reach:

```text
Verdict : waitAdvised
Strength: advisoryStrong
Delay   : 1:00:00.000000
Chips   :
  - Visibility may drop to ~80 m around 07:00 — whiteout conditions.
  - Conditions improve by about 08:15.
Chips (ja):
  - 07:00頃、視界が約80mまで低下する可能性があります — ホワイトアウト状態です。
  - 08:15頃までに状況は改善します。
Measured: 80.0 m at Akita (0.4 km away)
```

## Pair with a measured source

This package is pure Dart and fetches nothing. Pair it with a source package
that produces the typed inputs — all emit the SAME `VisibilityObservation` /
`WeatherForecast`, so you can swap region without changing your UI code:

| Region / network | `pub add` | Emits |
|---|---|---|
| Japan — JMA / AMeDAS | [`pretrip_source_jma`](https://pub.dev/packages/pretrip_source_jma) | measured `VisibilityObservation` (metres) |
| Finland — Fintraffic Digitraffic | [`pretrip_source_digitraffic`](https://pub.dev/packages/pretrip_source_digitraffic) | measured `VisibilityObservation` (metres) |
| Global — MET Norway locationforecast | [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway) | hourly `WeatherForecast` |

## Localized reason chips

The reason chips can speak the driver's language. Pass a `PretripMessages`
table; English is the default and the fallback for any language not carried, so
existing callers are unchanged:

```dart
final advisor = SnowAwarePretripAdvisor(
  messages: PretripMessages.forLanguage(locale.languageCode), // 'ja' → Japanese
);
```

`PretripMessages.en` (default + fallback) and `PretripMessages.ja` ship today;
`forLanguage` degrades to English for any language not carried (it never
throws). Measured numbers — visibility, temperature, minutes, hours — are
identical in every locale; only the surrounding words change, so a translation
can never restate a safety value.

Need a language this package does not carry yet? `PretripMessages` is an
abstract class — extend it with your own strings (the same pattern as the
built-in `PretripMessages.ja`) and pass it as `messages:`. You must implement
every method (the analyzer enforces this — a missing override will not
compile). The deterministic hazard logic is unchanged and every measured
number is handed to your method already computed — pass it through verbatim; a
localization may reorder words but must never restate a measured safety value.

```dart
class KoPretripMessages extends PretripMessages {
  const KoPretripMessages();
  @override
  String visibilityWhiteout(int meters, String at) => '...';
  // ...implement the rest of the abstract methods...
}
// SnowAwarePretripAdvisor(messages: const KoPretripMessages())
```

## Full reference integration (Flutter)

A standalone, edge-developer-shaped Flutter app that assembles and RENDERS a
pre-trip briefing from `pretrip_decision_advisor` + `pretrip_source_jma` — no
SNGNav app widgets — lives at
[`examples/edge_dev_akita_briefing/`](https://github.com/aki1770-del/SNGNav/tree/main/examples/edge_dev_akita_briefing).

Start from its [15-minute QUICKSTART](https://github.com/aki1770-del/SNGNav/blob/main/examples/edge_dev_akita_briefing/QUICKSTART.md) (`flutter create` → offline Akita briefing). To ship that offline core onto 32-bit ARM (`armv7`) car-class hardware, see the [embedded-armv7 on-ramp](https://github.com/aki1770-del/SNGNav/blob/main/examples/edge_dev_akita_briefing/EMBEDDED_ARMV7.md) — the pure-Dart core is `armv7`-proven; the Flutter render is gated on [flutter/flutter#188063](https://github.com/flutter/flutter/pull/188063).

## Honesty

If a commute is marked `CommuteFlexibility.required`, an advisor
implementing this contract must not return a strong "wait" recommendation;
it should return either `null` or a `honestyMode` recommendation. The
advisor cannot tell a driver to risk being late for a required obligation,
because the cost of doing so is borne by the driver, not the advisor.

## Status

0.6.1. Contract + working reference advisor, localized reason chips, the
humidity-aware black-ice (radiative frost) condition bounded to the
calibration's documented envelope, and the earned-all-clear gate: an
affirmative "no winter hazard" conclusion now requires that the deciding
fields were actually measured.
Interface stability is committed at this version within the bounds described in
`KNOWN_LIMITATIONS.md`.
