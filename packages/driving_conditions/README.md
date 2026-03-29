# driving_conditions

[![pub package](https://img.shields.io/pub/v/driving_conditions.svg)](https://pub.dev/packages/driving_conditions)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Turn weather data into actionable driving safety guidance.** Pure Dart models
that convert a weather condition into road surface classification, grip
estimation, visibility degradation, and Monte Carlo safety scores.

This package converts a `WeatherCondition` into structured driving guidance:

- Road surface classification (`dry`, `wet`, `slush`, `compactedSnow`, `blackIce`, `standingWater`)
- Grip factor estimation
- Visibility degradation parameters for UI overlays
- Precipitation particle parameters for renderers
- Monte Carlo safety score simulation

## When to use this package

Use `driving_conditions` when you already have weather input and need
deterministic road-surface, grip, visibility, or safety-score outputs without
pulling in Flutter UI code.

## Scope

`driving_conditions` does not render UI and does not depend on Flutter. It provides computation outputs that app and package layers can consume.

## Install

```yaml
dependencies:
  driving_conditions: ^0.3.0
```

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
fleetConfidenceScore = FleetConfidenceProvider.confidence  // injectable; default 0.8
overall = gripScore * 0.4 + visibilityScore * 0.4 + fleetConfidenceScore * 0.2
```

Jitter is random `0.0..0.1` per run. Use `seed` for deterministic tests.

Inject a `FleetHazardConfidenceAdapter` to replace the 0.8 baseline with real fleet data.

## Quick Start

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
final result = simulator.simulate(
  speed: 50,
  gripFactor: assessment.gripFactor,
  surface: assessment.surfaceState,
  visibilityMeters: condition.visibilityMeters,
  seed: 42,
);
// result.score     — mean SafetyScore across all Monte Carlo runs
// result.variance  — score variance (high = mixed conditions)
// result.incidentCount — runs where overall score fell below 0.4
```

## Integration Pattern

`driving_conditions` normally sits between a weather feed and a UI layer that
needs an honest safety summary. A common wiring pattern is: subscribe to a
weather provider, derive a `DrivingConditionAssessment`, then compute a safety
score for the current vehicle speed before rendering the result.

```dart
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';

class ConditionsSummaryCard extends StatelessWidget {
  const ConditionsSummaryCard({
    super.key,
    required this.conditions,
    required this.vehicleSpeedKmh,
  });

  final Stream<WeatherCondition> conditions;
  final double vehicleSpeedKmh;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WeatherCondition>(
      stream: conditions,
      builder: (context, snapshot) {
        final condition = snapshot.data;
        if (condition == null) {
          return const Text('Waiting for weather...');
        }

        final assessment =
            DrivingConditionAssessment.fromCondition(condition);
        final result = const SafetyScoreSimulator().simulate(
          speed: vehicleSpeedKmh,
          gripFactor: assessment.gripFactor,
          surface: assessment.surfaceState,
          visibilityMeters: condition.visibilityMeters,
          seed: 42,
        );

        return Card(
          child: ListTile(
            title: Text(
              '${assessment.surfaceState.name} '
              'grip=${assessment.gripFactor.toStringAsFixed(2)}',
            ),
            subtitle: Text(
              '${assessment.advisoryMessage}\n'
              'Safety score: ${result.score.overall.toStringAsFixed(2)}',
            ),
          ),
        );
      },
    );
  }
}
```

This keeps the package in its intended role: pure computation in the middle of
the stack, no UI dependency, but a direct path to a driver-facing advisory.

## API Overview

| Type | Purpose |
|------|---------|
| `DrivingConditionAssessment` | Converts a weather condition into surface, grip, visibility, particles, and advisory output. |
| `RoadSurfaceState` | Canonical road-surface classification for dry, wet, slush, snow, ice, and standing water. |
| `PrecipitationConfig` | Particle-system parameters derived from precipitation type and intensity. |
| `VisibilityDegradation` | UI-facing opacity and blur values derived from visibility distance. |
| `SafetyScoreSimulator` | Monte Carlo simulator for advisory safety scoring under uncertain conditions. |
| `SimulationResult` | Full output of a simulation run: mean `SafetyScore`, variance, incident count, and (native engine) execution time. |
| `FleetConfidenceProvider` | Interface for fleet-derived safety confidence. Inject to replace the 0.8 baseline. |
| `ConstantFleetConfidenceProvider` | Returns a fixed confidence value. Default (0.8) preserves pre-Sprint-91 behaviour. |
| `FleetHazardConfidenceAdapter` | Derives confidence from `List<FleetReport>` — dry 1.0, wet 0.7, snowy 0.4, icy 0.1. |
| `CpuSafetyScoreSimulationEngine` | Pure-Dart Monte Carlo engine. Always available regardless of platform. |
| `NativeSafetyScoreSimulationEngine` | C FFI engine for higher throughput. Exposes `executionMs` in `SimulationResult`. |
| `SimulationBackend` / `SimulationOptions` | Extension points for native or alternative simulation engines. |

## Validation

Current package status:

- Pure Dart — no Flutter dependency
- 105 passing tests
- Distributed as a monorepo path package within [SNGNav](https://github.com/aki1770-del/SNGNav) — use via path dependency or copy into your project

## Works With

| Package | How |
|---------|-----|
| [driving_weather](https://pub.dev/packages/driving_weather) | Upstream — provides `WeatherCondition` input |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Downstream — safety scores drive alert severity |
| [fleet_hazard](https://pub.dev/packages/fleet_hazard) | Direct dependency — `FleetHazardConfidenceAdapter` bridges fleet reports into simulation |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
