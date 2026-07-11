# snow_rendering

[![pub package](https://img.shields.io/pub/v/snow_rendering.svg)](https://pub.dev/packages/snow_rendering)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Turn weather data into driving safety guidance.** snow_rendering classifies
road surface conditions, computes grip factors, and derives visibility and
precipitation parameters from real weather observations.

Pure Dart — no Flutter dependency. Safe to use from any Dart environment.

> **0.3.0 fixes a safety defect present through 0.2.7.** A road whose conditions
> could not be classified fell through to `RoadSurfaceState.dry`, `gripFactor:
> 1.0`, `RecommendedResponse.proceed` and the advisory **"Conditions normal"** —
> a confident green light over a road nobody had measured. `surfaceState` and
> `gripFactor` are now nullable and a `conditionsUnknown` response tier exists.
> Read the [CHANGELOG](CHANGELOG.md) before upgrading — the compile errors are
> the fix.

## Features

- `RoadSurfaceState` — six-state classification (dry, wet, slush, compactedSnow, blackIce, standingWater) with grip factors, including the humidity-gated radiative-frost black-ice window (clear sky, ambient a few degrees above 0 °C, road surface frozen)
- `RoadSurfaceState.announcement` — driver-facing spoken lines (JA + EN) leading with the precise JP-domestic surface term (ブラックアイスバーン / 圧雪 / シャーベット), possibility-graded; plus `invisibleBlackIceAnnouncement` carrying the "looks merely wet" fact and the verbatim JAF advisory for invisible-ice paths
- `DrivingConditionAssessment` — combined assessment with advisory message from a single `WeatherCondition`
- `PrecipitationConfig` — particle count, velocity, size, and lifetime parameters by type and intensity
- `VisibilityDegradation` — opacity and blur sigma from visibility distance in metres
- `HysteresisFilter<T>` — debounce filter preventing rapid oscillation at boundary conditions

## Install

```yaml
dependencies:
  snow_rendering: ^0.3.0
```

## Quick Start

```dart
import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';

final condition = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -5,
  visibilityMeters: 400,
  windSpeedKmh: 30,
  iceRisk: false,
  timestamp: DateTime.now(),
);

final assessment = DrivingConditionAssessment.fromCondition(condition);

// NULLABLE (0.3.0): a road the classifier could not assess has NO surface and
// NO grip coefficient. `null` does not mean `dry`, and it does not mean 1.0 —
// inventing either is the defect this release removes.
print(assessment.surfaceState);    // RoadSurfaceState.compactedSnow (or null)
print(assessment.gripFactor);      // 0.3 (or null — surface not classified)
print(assessment.advisoryMessage); // Compacted snow — use winter tyres, reduce speed
print(assessment.visibility?.blurSigma);        // 2.0 (or null — not measured)
print(assessment.precipitation?.particleCount); // 500 (or null — not measured)

// The tier tells you which case you are in — exhaustively.
switch (assessment.recommendedResponse) {
  case RecommendedResponse.proceed:            // assessed, and benign
  case RecommendedResponse.reduceSpeed:        // hazard
  case RecommendedResponse.considerTurningBack:// whiteout class
  case RecommendedResponse.conditionsUnknown:  // NOT assessed — say so
    print(RecommendedResponse.conditionsUnknown.announcement!.jaSpokenText);
    // 路面状況を取得できていません。見える範囲で運転してください。
}
```

## Debounced Classification

Wrap in `HysteresisFilter` to prevent flickering at boundary conditions:

```dart
// NOTE the nullable type argument: `fromCondition` returns `RoadSurfaceState?`
// in 0.3.0 — a road it cannot classify has no surface, and must not be
// debounced into `dry`.
final filter = HysteresisFilter<RoadSurfaceState?>();
// Requires the same state in 2 of last 3 readings before transitioning.
final stable = filter.update(RoadSurfaceState.fromCondition(condition));
```

## Road Surface States

| State | Grip Factor | When |
|-------|:-----------:|------|
| dry | 1.0 | No precipitation, temp > -3°C, AND not the radiative-frost window below |
| wet | 0.7 | Rain above freezing |
| standingWater | 0.6 | Heavy rain, temp > 3°C |
| slush | 0.5 | Melting snow or sleet |
| compactedSnow | 0.3 | Cold heavy snow (temp < -2°C) |
| blackIce | 0.15 | Ice risk flag, freezing rain, temp ≤ -3°C, **or radiative frost** — no precipitation with measured humidity putting the dew point at/below 0 °C while ambient is ≤ +3 °C (the clear-morning "looks dry but frozen" case; abstains when the feed supplies no humidity — see `KNOWN_LIMITATIONS.md`) |
