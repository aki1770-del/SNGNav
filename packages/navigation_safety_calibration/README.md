# navigation_safety_calibration

[![pub package](https://img.shields.io/pub/v/navigation_safety_calibration.svg)](https://pub.dev/packages/navigation_safety_calibration)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Pure Dart navigation-safety calibration primitives.** Three
pure-computation helper functions extracted from
[`navigation_safety_core`](https://pub.dev/packages/navigation_safety_core)
for consumers who need the calibration math without paying for the
larger core-package surface area or its transitive dependencies.

- `computeSurfaceMoistureFraction` — exponential surface-moisture
  decay after a precipitation event ends. Default 90-minute half-life
  is conservative (biased toward "still wet"); accepts ambient
  temperature for forward-compatible API shape.
- `computeEffectiveTemperatureCelsius` — Magnus formula dew-point
  computation and an effective road-surface temperature for
  frost-risk reasoning. Constants `a = 17.625` / `b = 243.04 °C` per
  Alduchov & Eskridge (1996) modern parameterisation.
- `computeSpeedAdjustedVisibilityMeters` — speed-adjusted visibility
  floor combining reaction-time distance and braking distance over a
  per-profile baseline. Caution-add-only: the per-profile floor never
  lowers; speed only raises the warning threshold.

No Flutter dependency. No transitive dependencies (beyond `test` +
`lints` for development).

## Who is this for?

CLI tools, server-side test fixtures, and non-Flutter Dart packages
doing meteorological-class calculations want Magnus constants +
precipitation decay + speed-visibility heuristic without paying for
the full `navigation_safety_core` Flutter surface. This package
serves the **config-defaults consumers via predictable inheritance**
cohort within the SNGNav universal-edge-developer dignity model.

Typical consumers:

- Non-Flutter data-analysis pipelines computing dew-point against
  recorded ambient/humidity series.
- Server-side route-condition forecasters running pure-computation
  visibility budgets ahead of a navigation session.
- Test fixtures that need deterministic Magnus / decay / visibility
  values without booting a Flutter binding.

## Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  navigation_safety_calibration: ^0.1.0
```

Then import the barrel:

```dart
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';
```

## Example

```dart
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';

void main() {
  // Surface moisture 60 minutes after precipitation ended at 5 °C.
  final moisture = computeSurfaceMoistureFraction(
    timeSincePrecipitation: const Duration(minutes: 60),
    ambientCelsius: 5.0,
  );
  print('moisture fraction = ${moisture.toStringAsFixed(3)}');

  // Effective road-surface temperature at 4 °C, 80% RH.
  final tEffective = computeEffectiveTemperatureCelsius(
    ambientCelsius: 4.0,
    humidityRH: 0.8,
  );
  print('effective temperature ≈ ${tEffective.toStringAsFixed(2)} °C');

  // Speed-adjusted visibility floor — 100 m baseline, 25 m/s, 1.5 s RT.
  final vis = computeSpeedAdjustedVisibilityMeters(
    profileBaseMeters: 100.0,
    speedMps: 25.0,
    driverReactionTimeSeconds: 1.5,
  );
  print('required visibility ≈ ${vis.toStringAsFixed(1)} m');
}
```

## Relationship to navigation_safety_core

The three calibration source files in this package are byte-identical
to the corresponding files in `navigation_safety_core` 0.10.0 at the
time of extraction. A subsequent `navigation_safety_core` 0.11.0
release will depend-on and re-export from this package for ABI-compat,
so existing consumers of `navigation_safety_core` will not need to
change imports.

## Caveats — heuristic-class scope

The three primitives are **engineering heuristics**, not measured
ground truth. See [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) for
the explicit bounded-validity discussion (Magnus formula validity
range; decay coefficient empirical anchor; visibility heuristic
single-axis approximation; when NOT to use). The caution-add-only
invariant is preserved across all three primitives — they may make
warnings fire earlier but never later than baseline.

## License

BSD-3-Clause. See `LICENSE`.
