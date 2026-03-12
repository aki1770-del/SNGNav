# navigation_safety

Safety-focused navigation session state machine and always-on-top alert overlay
for driver-assisting navigation applications.

`navigation_safety` is an **ASIL-QM, advisory-only** navigation package. It
displays safety-relevant information to help the driver decide. It does **not**
control steering, braking, throttle, or any vehicle actuation path.

## Features

- `NavigationBloc` for navigation session lifecycle: idle, navigating,
  deviated, arrived.
- `SafetyOverlay` widget that stays at the top of the UI stack when alerts are
  active.
- Pure Dart `_core` exports for `SafetyScore`, `AlertSeverity`, and
  `NavigationSafetyConfig`.
- Configurable severity thresholds for score-based safety alerts.
- Reusable README/example posture for edge developers.

## Install

```yaml
dependencies:
  navigation_safety: ^0.1.1
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

## Safety Boundary

This package is **display-only**. It exists to help the driver understand road
conditions and navigation risk quickly. It must not be used to issue vehicle
control commands or to imply ADAS certification.

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM + Valhalla)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport and layer composition state machine
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine and progress UI
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with MBTiles fallback

All ten extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause — see [LICENSE](LICENSE).