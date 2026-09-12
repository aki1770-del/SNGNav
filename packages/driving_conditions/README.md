# driving_conditions

[![pub package](https://img.shields.io/pub/v/driving_conditions.svg)](https://pub.dev/packages/driving_conditions)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Turn weather data into actionable driving safety guidance.** Pure Dart models
that convert a weather condition into road surface classification, grip
estimation, visibility degradation, and Monte Carlo safety scores.

> **0.7.0 REMOVES the fleet term from the safety score, and is breaking.**
> `overall` is now `0.5 * grip + 0.5 * visibility` — two terms, weights stated,
> never re-normalised. The fleet term never carried a real reading, and four
> consecutive attempts to make its absence honest each failed one layer up; the
> full chain is in `SimulatedSafetyScore`'s own documentation. The
> `provider:` parameters and `SimulatedSafetyScore.fleetConfidenceScore` /
> `hasFleetData` are gone. **`FleetConfidenceProvider`,
> `ConstantFleetConfidenceProvider` and `FleetHazardConfidenceAdapter` are
> KEPT** — reading fleet telemetry is legitimate; folding it into a safety
> score with no source was not.
>
> 0.7.0 also rejects non-finite inputs instead of scoring them. On 0.6.0,
> `gripFactor: double.nan` produced `gripScore == 1.0` (`num.clamp` maps `NaN`
> to the top of the range) and a run with both sensors unreadable scored
> `overall 0.9373`, band `none` — **an all-clear rated higher than a genuinely
> perfect dry road** (0.9178). Those now throw `ArgumentError`.
>
> Read the [CHANGELOG](CHANGELOG.md) before upgrading — the compile errors are
> the fix. This is a `0.7.0` and not a `0.6.1` deliberately: `^0.6.0` means
> `>=0.6.0 <0.7.0`, so a change that moves a safety score must not arrive on a
> `pub upgrade` nobody asked for.

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
  driving_conditions: ^0.7.1
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

// Two terms. The weights are CONSTANTS that sum to 1.0, and they are never
// re-normalised — re-normalising over "the terms that are present" is
// arithmetically identical to imputing the absent one as the mean of the
// present ones, which is how absence came to RAISE the score in 0.6.0:
overall = gripScore * 0.5 + visibilityScore * 0.5
```

Jitter is random `0.0..0.1` per run. Use `seed` for deterministic tests.

`speed`, `gripFactor` and `visibilityMeters` must be finite. A non-finite value
throws `ArgumentError` rather than being clamped into a perfect reading — see
the 0.7.0 note at the top.

**There is no fleet parameter.** Read fleet telemetry directly if you have it:

```dart
final fleet = FleetHazardConfidenceAdapter(reports).confidence; // double?, null = silence
```

`null` means the fleet said nothing — not 0.8, and not 0.0.

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

// `surfaceState`, `gripFactor` and `visibilityMeters` are all NULLABLE now:
// a road that could not be classified has no surface and no grip coefficient,
// and a feed that reported no visibility did not report 10 km of clear air.
// Decide what to do when you do not know — the compiler will make you.
final surface = assessment.surfaceState;
final grip = assessment.gripFactor;
final vis = condition.visibilityMeters;
if (surface == null || grip == null || vis == null) {
  print(assessment.advisoryMessage); // "…not measured — drive to what you can see"
  return;
}

final simulator = SafetyScoreSimulator();
final result = simulator.simulate(
  speed: 50,
  gripFactor: grip,
  surface: surface,
  visibilityMeters: vis,
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
              '${assessment.surfaceState?.name ?? 'not measured'} '
              'grip=${assessment.gripFactor?.toStringAsFixed(2) ?? '—'}',
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
| `FleetConfidenceProvider` | Interface for fleet-derived safety confidence. `confidence` is `double?`; `null` means the fleet said NOTHING. **Not consumed by the safety score from 0.7.0** — it is yours to read. |
| `ConstantFleetConfidenceProvider` | Returns a fixed confidence value you ASSERT. `value` is REQUIRED from 0.7.0 (it used to default to `0.8`). `.unavailable()` is the no-fleet-data form (`confidence == null`). |
| `FleetHazardConfidenceAdapter` | Derives confidence from `List<FleetReport>` — dry 1.0, wet 0.7, snowy 0.4, icy 0.1. `unknown`, non-finite and negative self-confidences carry no weight. |
| `CpuSafetyScoreSimulationEngine` | **Default** pure-Dart Monte Carlo engine. Always available regardless of platform; no build step required. |
| `NativeSafetyScoreSimulationEngine` | **Optional** C FFI engine for higher throughput. **Not the default and not usable out of the box** — see the note below. |
| `SimulationBackend` / `SimulationOptions` | Extension points for native or alternative simulation engines. |

### Native (C FFI) engine — optional, requires a build step

The pure-Dart `CpuSafetyScoreSimulationEngine` is the default and the only path
you need for normal use. `NativeSafetyScoreSimulationEngine` is an **opt-in**
performance spike that is **not usable without first compiling the C library**.
Constructing it (or letting it load its bindings) will **throw** unless a
compiled `libsimulation_engine` (`.so` / `.dylib` / `.dll`) exists under
`native/build/` for your platform; unsupported platforms throw
`UnsupportedError`. Do not select the native path expecting a silent fallback —
there is none. Stick with the CPU engine unless you have explicitly built and
shipped the native library yourself.

**Build it:**

```bash
(cd native && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build)
```

#### `NativeSimulationAbiMismatch` — the library must declare its ABI

The Dart binding and the C library share an ABI contract. The C side exports
`simulation_abi_version()`; `NativeSimulationBindings` reads it **at
construction** and throws **`NativeSimulationAbiMismatch`** — exported from this
package, so you can catch it by type — if the value is absent or not the one
this release requires.

**Why this refuses instead of degrading.** A mismatched library does **not**
crash and does **not** fail to load. Measured on a library 166 days older than
its source: the call crossed a changed signature and returned `overall = 1.0`
exactly — the top of the scale — where the pure-Dart engine returned `0.578`.
A saturated *"safe"* reading on a safety score, with no exception and no log
line. **Refusing to run beats returning a number we cannot vouch for.**

⚑ **CORRECTION, measured on aarch64 2026-09-12 — "it saturates so you would notice" is FALSE on HER
architecture.** The `1.0` above is one **x86-64** manifestation, not the defect's signature. Called
through the mismatched ABI on aarch64 with the 4th FP argument register (`s3`) preset, `overall_mean`
comes back **unclamped and inheriting whatever is in that register**: `0.112216` · `0.312216` ·
`1.712216` · `200000.015625`, against a correct control of `0.212216`. **The dangerous cases are the
PLAUSIBLE ones** — `0.312216` on a 0–1 safety scale is indistinguishable from a real reading, and no
range check, saturation heuristic or "looks wrong" instinct catches it. The same call on x86-64
reproduced as `-nan`. **Any reasoning of the form "we would notice because it saturates" does not
hold on the architecture HER vehicle runs.** Separately, and stated the right way round after an
independent re-measure caught it backwards: **0.7.0's struct SHRANK** — 0.6.0 carries seven
fields (28 bytes, including `fleet_mean`), 0.7.0 carries six (24 bytes). So it is the
**stale ≤0.6.0 library** that writes 28 bytes into the 24-byte buffer the 0.7.x Dart side
expects. A hardened C caller aborts; Dart FFI has no canary. (A first draft of this
paragraph said 0.7.0 "grew a field" — the consequence was right and the cause was
backwards, which would send a reader hunting the wrong thing in their own diff.)

⚑ **AND 0.7.0 IS THE TRAP — the hazard is any `.so` built from ≤0.6.0.** Measured across
published archives: `0.5.5`, `0.5.6`, `0.5.7` **and** `0.6.0` all ship the identical 7-arg
signature and 28-byte struct, each self-consistent with its own Dart side. **The single ABI
break in this package's history is at 0.7.0.**
`0.7.1` is guarded. **`0.7.0` has the 6-arg C and NO version symbol — the defect is reachable there
with nothing to catch it**, and it is published and live. A consumer who upgrades 0.6.0 → 0.7.0 and
reuses a previously built `.so` hits the founding defect unguarded. Both versions ship the C source.


The thrown error carries the library path and the remedy. **If you vendored this
package, take `native_simulation.c` and `CMakeLists.txt` from the upgraded
package before rebuilding** — rebuilding your existing copy recompiles the old C
and is refused again, indefinitely.

## Validation

Current package status:

- Pure Dart — no Flutter dependency
- Published on pub.dev — **depend on the published version**, not on a path or a copy

> ### ⚑ Do not vendor this package by path or by copying it
>
> An earlier version of this section said *"use via path dependency or copy into your
> project."* **That advice is withdrawn, and it was wrong on a safety package.**
>
> A path or copied consumer cannot be reached by **any** version we publish — not a patch,
> not a major, not a retraction. If a defect is found in code you copied, **the fix cannot
> arrive and we will never know you have it.** This package computes a safety score a driver
> acts on, and it carries a **native C library you build yourself**, which is exactly the
> part that can go stale silently (see *Native engine* below).
>
> Depend on the published version so a fix has a route to you.

## Works With

| Package | How |
|---------|-----|
| [driving_weather](https://pub.dev/packages/driving_weather) | Upstream — provides `WeatherCondition` input |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Downstream — safety scores drive alert severity |
| [fleet_hazard](https://pub.dev/packages/fleet_hazard) | Direct dependency — `FleetHazardConfidenceAdapter` reads fleet reports (it no longer feeds the score; see 0.7.0) |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
