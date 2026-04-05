# snow_rendering

[![pub package](https://img.shields.io/pub/v/snow_rendering.svg)](https://pub.dev/packages/snow_rendering)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Turn weather data into driving safety guidance.** snow_rendering classifies
road surface conditions, computes grip factors, and derives visibility and
precipitation parameters from real weather observations.

Pure Dart — no Flutter dependency. Safe to use from any Dart environment.

## Features

- `RoadSurfaceState` — six-state classification (dry, wet, slush, compactedSnow, blackIce, standingWater) with grip factors
- `DrivingConditionAssessment` — combined assessment with advisory message from a single `WeatherCondition`
- `PrecipitationConfig` — particle count, velocity, size, and lifetime parameters by type and intensity
- `VisibilityDegradation` — opacity and blur sigma from visibility distance in metres
- `HysteresisFilter<T>` — debounce filter preventing rapid oscillation at boundary conditions

## Install

```yaml
dependencies:
  snow_rendering: ^0.1.0
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
print(assessment.surfaceState);    // RoadSurfaceState.compactedSnow
print(assessment.gripFactor);      // 0.3
print(assessment.advisoryMessage); // Compacted snow — use winter tyres, reduce speed
print(assessment.visibility.blurSigma); // 2.0 (mild blur at 400m)
print(assessment.precipitation.particleCount); // 500 (heavy snow)
```

## Debounced Classification

Wrap in `HysteresisFilter` to prevent flickering at boundary conditions:

```dart
final filter = HysteresisFilter<RoadSurfaceState>();
// Requires the same state in 2 of last 3 readings before transitioning.
final stable = filter.update(RoadSurfaceState.fromCondition(condition));
```

## Road Surface States

| State | Grip Factor | When |
|-------|:-----------:|------|
| dry | 1.0 | No precipitation, temp > -3°C |
| wet | 0.7 | Rain above freezing |
| standingWater | 0.6 | Heavy rain, temp > 3°C |
| slush | 0.5 | Melting snow or sleet |
| compactedSnow | 0.3 | Cold heavy snow (temp < -2°C) |
| blackIce | 0.15 | Ice risk flag, freezing rain, or temp ≤ -3°C |
