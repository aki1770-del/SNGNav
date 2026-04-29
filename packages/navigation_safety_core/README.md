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

## Scope: driving automation regimes

This package is intended for **SAE J3016 Level 0 and Level 1 supportive
use** — the driver performs the dynamic driving task (DDT) at all
times; this package's surfaces (alert severity, alert-density throttle,
condition explainer, safety score, road-surface vocabulary) inform the
driver but never actuate the vehicle and never close a control loop.

**This package does not provide L2+ automation or handover-class
supervision.** Consumers operating at SAE J3016 Level 2 or above are
responsible for adding their own handover-class driver-attention
monitoring, take-over-request signalling, and minimum-risk-manoeuvre
fallback. Treating this package's advisory output as input to an
automation-handover safety contract is out of the documented scope.

**Standards-mapping summary** (full detail in
[`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md#standards-mapping-current-advisory-framing)):

- **ISO 26262**: under the current advisory-only framing, this package
  is product-quality scope, not functional-safety scope. The integrator
  performs the hazard analysis and decides the final ASIL classification
  for their integration; the package's wording discipline is consistent
  with QM at the application layer.
- **SAE J3016**: L0/L1 supportive. No L2+ claim.
- **JIS / JASO** (Japanese-domestic automotive standards): not mapped at
  this scope. Consult a qualified Japanese-domestic functional-safety
  partner before any IVI-vendor or OEM-pilot integration that targets
  the Japanese-domestic certification surface.

**When this package's alerts are appropriate**: informational +
density-throttled HMI surfaces over a base map, in a navigation app
where the driver retains full control authority and the alert is one
of several driver-supervision aids.

**When this package's alerts are insufficient**: any deployment where
alert acknowledgment is part of an automation-handover safety contract,
or where loss of an alert frame must be guaranteed-bounded by a
functional-safety case rather than by product-quality reliability.

**Equal-dignity invariant**: alert visibility, severity ordering, and
plane-allocation priority in the consuming HMI MUST be **severity-driven,
never profile-driven**. Per-profile differentiation belongs in
verbosity, locale, and density-cap surfaces (already provided by
`AlertExplainer` and `AlertDensityThrottle`); it MUST NOT enter the
visibility / preemption path. See `KNOWN_LIMITATIONS.md` for full
discussion.

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
