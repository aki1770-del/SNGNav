# navigation_safety

[![pub package](https://img.shields.io/pub/v/navigation_safety.svg)](https://pub.dev/packages/navigation_safety)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Show drivers what matters before it's too late.** Safety alerts that stay on
top of your navigation UI — always visible, never controlling.

Use `navigation_safety` when you need a navigation session state machine with a
safety overlay that renders alerts (ice, low visibility, GPS loss) without
blocking the driver's view or controlling the vehicle.

## Features

- `NavigationBloc` for navigation session lifecycle: idle, navigating,
  deviated, arrived.
- `SafetyOverlay` widget that stays at the top of the UI stack when alerts are
  active.
- Pure Dart `_core` exports for `SafetyScore`, `AlertSeverity`, and
  `NavigationSafetyConfig`.
- Configurable severity thresholds for score-based safety alerts.
- Composable with `routing_bloc` and `voice_guidance` without coupling to either.

## Install

```yaml
dependencies:
  navigation_safety: ^0.3.0
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';

class MyNavScreen extends StatelessWidget {
  const MyNavScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NavigationBloc(),
      child: Scaffold(
        body: Stack(
          children: const [
            Placeholder(),
            SafetyOverlay(),
          ],
        ),
      ),
    );
  }
}
```

## API Overview

| API | Purpose |
|-----|---------|
| `NavigationBloc` | Navigation session lifecycle and alert state |
| `NavigationState` | Session state, maneuver progress, active alert |
| `NavigationEvent` | Navigation start/stop, maneuver advance, alert input |
| `SafetyOverlay` | Safety alert presentation layer |
| `SafetyScore` | Pure Dart score model for grip, visibility, fleet confidence |
| `NavigationSafetyConfig` | Pure Dart threshold configuration |
| `AlertSeverity` | `info`, `warning`, `critical` |

## OODA Latency Budget

| Phase | Budget | Owner |
|:-----:|:------:|:-----:|
| Observe | < 200 ms | Sensor streams |
| Orient | < 500 ms | `NavigationBloc` |
| Display | < 300 ms | `SafetyOverlay` |
| Total to display | < 1 second | SNGNav domain |

## SafetyOverlay Rules

| Rule | Requirement |
|:----:|-------------|
| 1 | Always rendered - never removed from the widget tree |
| 2 | Always on top - Z=5 (topmost) |
| 3 | Passthrough when inactive - no input blocking |
| 4 | Modal when active - blocks interaction until acknowledged |
| 5 | Independent state - not reset by unrelated navigation transitions |

## Threshold Configuration

```dart
import 'package:navigation_safety/navigation_safety_core.dart';

final config = NavigationSafetyConfig(
  safeScoreFloor: 0.80,
  infoScoreFloor: 0.50,
  warningScoreFloor: 0.30,
  criticalTemperatureCelsius: -5,
  warningVisibilityMeters: 200,
);

final score = SafetyScore(
  overall: 0.42,
  gripScore: 0.35,
  visibilityScore: 0.40,
  fleetConfidenceScore: 0.75,
);

final severity = score.toAlertSeverity(config);
```

## Safety Boundary (SOTIF scope)

**This package is responsible for display. You are responsible for score computation.**

If your score is uncertain, pass `0.0` — the package will alert conservatively.
This package must not be used to issue vehicle control commands or to imply ADAS
certification. Classification: ASIL-QM (display-only). No actuator path.

## SafetyScore Computation

`SafetyScore.overall` is compared against thresholds in `NavigationSafetyConfig`:

```
overall < warningScoreFloor  → AlertSeverity.critical
overall < infoScoreFloor     → AlertSeverity.warning
overall < safeScoreFloor     → AlertSeverity.info
otherwise                    → no alert
```

The component scores (`gripScore`, `visibilityScore`, `fleetConfidenceScore`) are
inputs you compute from your sensor data. The package does not read sensors — it
displays what you give it. Each component is clamped to `[0.0, 1.0]`.

## Contributing a Signal

You can extend this package to cover a new threat scenario in about 3 hours:

1. Read `lib/src/models/safety_score.dart` (72 lines) and `lib/src/models/navigation_safety_config.dart`
2. Add one field to `SafetyScore` for your scenario (e.g., `infrastructureRiskScore`)
3. Add a corresponding threshold to `NavigationSafetyConfig`
4. Update `toAlertSeverity()` to check your new field
5. Write 3 tests: boundary value, clamp behaviour, severity mapping
6. Open a PR referencing the scenario ID from [CONTRIBUTING.md](CONTRIBUTING.md)

No KUKSA, Valhalla, or embedded Linux knowledge required. The SOTIF boundary
above is what protects you — you only need to compute a float and pass it in.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the list of open scenario slots.

## Works With

| Package | How |
|---------|-----|
| [driving_weather](https://pub.dev/packages/driving_weather) | Weather conditions feed into safety score computation |
| [driving_conditions](https://pub.dev/packages/driving_conditions) | Road surface and grip data drive alert severity |
| [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) | Safety overlay sits at Z5 in the viewport layer stack |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Route lifecycle state machine
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).