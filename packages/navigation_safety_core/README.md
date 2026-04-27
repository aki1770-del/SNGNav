# navigation_safety_core

[![pub package](https://img.shields.io/pub/v/navigation_safety_core.svg)](https://pub.dev/packages/navigation_safety_core)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Pure Dart core models for driving-navigation safety.**

`SafetyScore`, `AlertSeverity`, `NavigationRoute`, `SafetyScenario`,
`NavigationSafetyConfig` — the type vocabulary that
[`navigation_safety`](https://pub.dev/packages/navigation_safety) wraps
with Flutter BLoCs and widgets.

This package exists so that **non-Flutter consumers** — CLI tools,
server-side logic, test fixtures, pure-Dart packages like
[`driving_conditions`](https://pub.dev/packages/driving_conditions) —
can depend on the safety vocabulary without inheriting Flutter +
flutter_bloc.

If you're building a Flutter app and want the BLoC layer too, depend on
`navigation_safety` instead; it re-exports everything here for
back-compatibility.

## What's in here

- **`SafetyScore`** — composite score across road-surface, visibility,
  hazard-density, and route-condition axes.
- **`AlertSeverity`** — `info` / `warning` / `critical`. Declaration
  order is load-bearing (callers compare `.index` to enforce monotonic
  alert upgrades; lower severity never replaces higher).
- **`NavigationRoute`** — typed route representation independent of
  any specific routing engine.
- **`SafetyScenario`** — enumeration of driving-condition scenarios
  (clear / wet / icy / heavy-snow / etc.) used by the score computation.
- **`NavigationSafetyConfig`** — knobs for safety-overlay behavior
  (alert thresholds, dismissibility, severity caps).

Pure Dart, no native dependencies, no Flutter.

## Install

```yaml
dependencies:
  navigation_safety_core: ^0.1.0
```

## Use

```dart
import 'package:navigation_safety_core/navigation_safety_core.dart';

void main() {
  const config = NavigationSafetyConfig();
  final scenario = SafetyScenario.heavySnow;
  final score = SafetyScore.forScenario(scenario, config: config);

  if (score.severity.index >= AlertSeverity.warning.index) {
    print('Alert: ${score.severity.name} — ${score.advisoryMessage}');
  }
}
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).
