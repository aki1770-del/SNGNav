# Runtime looms in `navigation_safety_core`

This package ships *runtime looms* — pure-Dart classes that the consuming app
instantiates inside its own process to catch a named failure mode at the package
boundary.

**Why "loom".** The name is a nod to the self-stopping loom: a machine that halts
itself the moment a thread breaks, rather than relying on an operator to notice.
Each class here does the same job for one specific failure mode. The term is used
throughout this package's API (`src/looms.dart`, `LoomFitTelemetryRecord`), so it
is worth knowing; nothing about it is required to use the classes.

## What a runtime loom IS in this package

A runtime loom in `navigation_safety_core` is a pure-Dart class that:

1. Catches a documented failure mode at the package boundary.
2. Carries a class-level doc-comment naming the failure mode it prevents and the
   literature anchors that justify any embedded magnitudes.
3. Is advisory-only — the loom decides whether something fires *from the package
   boundary*; the consuming app owns delivery to the driver and retains full
   responsibility.
4. Does not actuate the vehicle.

## Catalog

| Loom (Dart class) | Failure mode caught |
|---|---|
| `AlertDensityThrottle` | Alert fatigue / over-warning desensitization — advisory tiers crowd out the credibility of `AlertSeverity.critical` |
| `AlertExplainer` | Condition-without-action alert — e.g. "icy road" stated with no driver action implied |

## Importing the runtime looms

The looms are exported both individually (via the package barrel
`navigation_safety_core.dart`) and as a category via `src/looms.dart`. Either of
these works:

```dart
import 'package:navigation_safety_core/navigation_safety_core.dart';
// ...AlertDensityThrottle, AlertExplainer available

import 'package:navigation_safety_core/src/looms.dart';
// ...AlertDensityThrottle, AlertExplainer available with a category-level
//    doc-comment describing the runtime-loom convention
```

The `src/looms.dart` import is explicit about the runtime-loom intent; the
package-barrel import is the standard route for everything else in
`navigation_safety_core`.

## What this catalog is NOT

- Not a runtime registry. Looms in this catalog do not auto-discover each other;
  the integrating app instantiates each one explicitly. See
  `KNOWN_LIMITATIONS.md` for the deferred-feature note.
- Not exhaustive. Future runtime-loom additions in this package will ship into
  this catalog using the same convention.
