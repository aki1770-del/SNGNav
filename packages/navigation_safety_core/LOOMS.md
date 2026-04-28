# Runtime looms in `navigation_safety_core`

This package ships *runtime looms* — Pure Dart classes that the
consuming app instantiates inside its own process to catch failure
modes named by the Loom Protocol vocabulary. Each loom carries a
3-slot vision attribution in its class-level doc-comment, matching
the convention documented in the SPA AI loom-authoring guide.

The 3-slot schema is the cross-language binding between two related
projects:

- **SPA AI** ships *build-time* looms in Python — one Jidoka halt per
  loom, installed via pull request to the target repo. See
  https://github.com/aki1770-del/spa-ai/blob/main/docs/loom_authoring_guide.md
  for the canonical authoring guide.
- **`navigation_safety_core`** ships *runtime* looms in Pure Dart —
  one Jidoka halt per loom, instantiated by the consuming app inside
  its own process.

Both sets share the same Loom Protocol vocabulary. The 3-slot
attribution (`sakichi_vision_id` / `method_vision_ids` /
`stance_vision_ids`) is documentation today; future tooling may parse
it.

## What a runtime loom IS in this package

A runtime loom in `navigation_safety_core` is a Pure Dart class that:

1. Catches a documented failure mode at the package boundary.
2. Carries a class-level doc-comment naming the 3-slot vision
   attribution + the literature anchors that justify any embedded
   magnitudes.
3. Is advisory-only — the loom decides whether something fires *from
   the package boundary*; the consuming app owns delivery to the
   driver and retains full responsibility.
4. Does not actuate the vehicle.

## Cross-reference table

| Loom (Dart class) | `sakichi_vision_id` | `method_vision_ids` | `stance_vision_ids` | Failure mode caught |
|---|---|---|---|---|
| `AlertDensityThrottle` | 14 | 77, 18, 99 | 22, 100 | Alert-fatigue / over-warning desensitization (advisory tiers crowd out credibility of `AlertSeverity.critical`) |
| `AlertExplainer` | 96 | 77, 99 | 22, 96, 100 | Condition-without-action alert (e.g. "icy road" with no driver action implied) |

The vision-id key:

- **V14** — silent failure / anti-Jidoka.
- **V18** — 5-Whys terminates at mechanism, not at blame.
- **V22** — loom-serves-weaver.
- **V77** — genchi-genbutsu (grounding in actual literature / actual
  driver-guidance corpus, not in invention).
- **V96** — maintainers-as-edge-developers (the integrating app
  developer is a weaver too, served by complete package boundaries).
- **V99** — write-decision-down (the cap table or action-string table
  IS the recorded decision).
- **V100** — equal dignity for every weaver / driver class.

## Importing the runtime looms

The looms are exported both individually (via the package barrel
`navigation_safety_core.dart`) and as a category via
`src/looms.dart`. Either of these works:

```dart
import 'package:navigation_safety_core/navigation_safety_core.dart';
// ...AlertDensityThrottle, AlertExplainer available

import 'package:navigation_safety_core/src/looms.dart';
// ...AlertDensityThrottle, AlertExplainer available with category-level
//    doc-comment surfacing the runtime-loom convention
```

The `src/looms.dart` import is explicit about the runtime-loom
intent; the package-barrel import is the standard route for everything
else in `navigation_safety_core`.

## What this catalog is NOT

- Not a runtime registry. Looms in this catalog do not auto-discover
  each other; the integrating app instantiates each one explicitly.
  See `KNOWN_LIMITATIONS.md` (`looms.dart barrel + LOOMS.md (added in
  0.4.1)`) for the deferred-feature note.
- Not a cross-language verification tool. The 3-slot attribution is a
  documentation convention today; no runtime check enforces that a
  Dart loom and a Python loom with the same `loom_id` declare matching
  attribution slots. Future tooling may add this.
- Not exhaustive. Future runtime-loom additions in this package will
  ship into this catalog using the same convention.
