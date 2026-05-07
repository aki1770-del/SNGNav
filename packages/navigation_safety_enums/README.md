# navigation_safety_enums

[![pub package](https://img.shields.io/pub/v/navigation_safety_enums.svg)](https://pub.dev/packages/navigation_safety_enums)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Pure Dart navigation-safety domain enums.** Four stable enum
types extracted from
[`navigation_safety_core`](https://pub.dev/packages/navigation_safety_core)
for consumers who need the safety vocabulary without paying for the
larger core-package surface area or its transitive dependencies.

- `AlertSeverity` — info / warning / critical, with declaration-
  order-load-bearing severity comparison via `.index`.
- `CircadianPhase` — 24-hour partition for circadian-aware
  threshold tuning, with a caution-add-only multiplier extension
  and a `circadianPhaseFromHour(int)` helper.
- `DriverState` — live driver-state axis (alert / fatigued /
  distracted / impairedVisibility), orthogonal to driver-trait.
- `DriverProfile` — driver-class trait axis (`ageingRural` /
  `snowZoneExperienced` / `noviceUrban` / `professional` /
  `agriculturalForestry` / `foreignTouristSnowZone`).

No Flutter dependency. No transitive dependencies (beyond
`test` + `lints` for development). Safe to consume from CLI tools,
server-side logic, test fixtures, and any other pure-Dart package
that needs the safety vocabulary.

## Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  navigation_safety_enums: ^0.1.0
```

Then import the barrel:

```dart
import 'package:navigation_safety_enums/navigation_safety_enums.dart';
```

## Example

```dart
import 'package:navigation_safety_enums/navigation_safety_enums.dart';

void main() {
  // Severity ordering is declaration-order-load-bearing.
  assert(AlertSeverity.critical.index > AlertSeverity.warning.index);
  assert(AlertSeverity.warning.index > AlertSeverity.info.index);

  // Map a 24-hour clock hour to a circadian phase.
  final phase = circadianPhaseFromHour(DateTime.now().hour);
  print('phase=${phase.name} multiplier=${phase.multiplier}');

  // Driver state and driver profile are orthogonal axes.
  const profile = DriverProfile.foreignTouristSnowZone;
  const state = DriverState.fatigued;
  print('profile=${profile.name} state=${state.name}');
}
```

## Relationship to navigation_safety_core

The four enum source files in this package are byte-identical to the
corresponding files in `navigation_safety_core` 0.10.0 at the time
of extraction. A subsequent `navigation_safety_core` 0.11.0 release
will depend-on and re-export from this package for ABI-compat, so
existing consumers of `navigation_safety_core` will not need to
change imports.

This package is intended for two cohorts who consume the enum
vocabulary directly:

- **open-source-consumers** — pure-Dart packages and CLI tools that
  need the vocabulary without the larger core-package surface area.
- **parallel-product-builders** — integrators building independent
  navigation or driver-assist products who want a stable shared
  vocabulary without coupling their dependency tree to the full
  `navigation_safety_core` evolution.

## Caveats — UNVERIFIED magnitudes

The numeric multiplier values on `CircadianPhase` are
**design-default hypotheses** pending field-measurement validation.
See the in-source documentation and `navigation_safety_core`'s
`KNOWN_LIMITATIONS.md` for the UNVERIFIED-magnitude flag.

The state-axis adjustment magnitudes documented on `DriverState`
values are similarly UNVERIFIED at this spike. Both axes carry the
caution-add-only invariant — values may make thresholds warn
earlier than baseline but never later.

## License

BSD-3-Clause. See `LICENSE`.
