# driving_conditions

Pure Dart computation models for weather-driven driving safety assessment.

This package converts a `WeatherCondition` into structured driving guidance:

- Road surface classification (`dry`, `wet`, `slush`, `compactedSnow`, `blackIce`, `standingWater`)
- Grip factor estimation
- Visibility degradation parameters for UI overlays
- Precipitation particle parameters for renderers
- Monte Carlo safety score simulation

## Scope

`driving_conditions` does not render UI and does not depend on Flutter. It provides computation outputs that app and package layers can consume.

## Core Models

### RoadSurfaceState

Decision tree from weather conditions:

- `iceRisk` => `blackIce`
- no precipitation and temperature `<= -3°C` => `blackIce`
- rain and heavy intensity with temperature `> 3°C` => `standingWater`
- rain and temperature `<= 0°C` => `blackIce`
- snow and temperature `> 2°C` => `slush`
- snow and temperature `< -2°C` with moderate or heavy intensity => `compactedSnow`
- sleet => `slush`

Grip factors:

| State | Grip |
| --- | ---: |
| dry | 1.0 |
| wet | 0.7 |
| slush | 0.5 |
| compactedSnow | 0.3 |
| blackIce | 0.15 |
| standingWater | 0.6 |

### PrecipitationConfig

Particle count formula:

```text
particleCount = round(intensityFactor * 500)
```

Intensity factors:

| Intensity | Factor | Particles |
| --- | ---: | ---: |
| none | 0.0 | 0 |
| light | 0.3 | 150 |
| moderate | 0.6 | 300 |
| heavy | 1.0 | 500 |

Velocity ranges:

| Type | Min m/s | Max m/s |
| --- | ---: | ---: |
| snow | 2.0 | 4.0 |
| rain | 7.0 | 12.0 |
| sleet | 4.0 | 8.0 |
| hail | 8.0 | 15.0 |

### VisibilityDegradation

Formulas:

```text
opacity = 1.0 - clamp(visibilityMeters / 1000.0, 0.1, 1.0)
blurSigma = max(0.0, (500.0 - visibilityMeters) / 50.0)
```

Examples:

- `0m` => opacity `0.9`, blur `10.0`
- `100m` => opacity `0.9`, blur `8.0`
- `500m` => opacity `0.5`, blur `0.0`
- `1000m+` => clear

### DrivingConditionAssessment

Bridge model combining:

- `RoadSurfaceState`
- `gripFactor`
- `VisibilityDegradation`
- `PrecipitationConfig`
- advisory message

### SafetyScoreSimulator

Monte Carlo scoring model:

```text
gripScore = gripFactor * (1 - gripJitter) * (1 - speedFactor * 0.3)
visibilityScore = clamp(visibilityMeters / 1000.0, 0, 1) * (1 - visJitter)
fleetConfidenceScore = 0.8
overall = gripScore * 0.4 + visibilityScore * 0.4 + fleetConfidenceScore * 0.2
```

Jitter is random `0.0..0.1` per run. Use `seed` for deterministic tests.

## Usage

```dart
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';

final condition = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -4,
  visibilityMeters: 180,
  windSpeedKmh: 25,
  iceRisk: false,
  timestamp: DateTime.now(),
);

final assessment = DrivingConditionAssessment.fromCondition(condition);

final simulator = SafetyScoreSimulator();
final score = simulator.simulate(
  speed: 50,
  gripFactor: assessment.gripFactor,
  surface: assessment.surfaceState,
  visibilityMeters: condition.visibilityMeters,
  seed: 42,
);
```

## Validation

Current package status:

- Pure Dart
- 53 passing tests (including boundary regression tests from in-flight review)
- Path-dependent monorepo package

## See Also

- [driving_weather](https://pub.dev/packages/driving_weather) — Weather conditions model (upstream dependency providing `WeatherCondition`)
- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM + Valhalla)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine with pure Dart `_core` models (provides `SafetyScore`)
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport state machine with pure Dart `_core` models
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine with pure Dart `_core` models
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with pure Dart `_core` models

All ten extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.
