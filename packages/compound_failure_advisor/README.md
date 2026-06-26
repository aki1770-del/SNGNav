# compound_failure_advisor

**Pure Dart, zero-dependency, in-drive caution advisor for snow-zone navigation.**
It fuses *position-trust × what-she-can-see* into **one honest, advisory-only
caution label** for the moment when navigation infrastructure is failing while
the driver is already moving — Google Maps gone, GPS gone, low visibility on a
rural snow road. It is the in-drive counterpart to
[`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor):
that one answers *"should I leave?"* (and may say *wait*); this one answers the
strictly different in-drive question *"how should I hold the wheel right now?"* —
and its ceiling is a gentle, reversible **consider stopping**, never *turn back*.

The one thing it does that no single-signal package does: it makes the
**compounding** case explicit. An uncertain position *and* low visibility *at the
same time* is far worse than either alone — that non-linearity is the whole
reason this package exists.

```sh
dart pub add compound_failure_advisor
```

## Quickstart

A degrading drive: a trusted fix in clear weather, then a dead-reckoning fix
(the dot is now a ~220 m circle) **and** a 120 m whiteout at once. Run-verified
output below.

```dart
import 'package:compound_failure_advisor/compound_failure_advisor.dart';

void main() {
  for (final s in [
    DriveSituation( // trusted + clear
      positionTrust: PositionTrust.trusted, confidenceRadiusMeters: 12,
      secondsSinceTrustedFix: 0, hasPosition: true,
      visibilityMeters: 1500, visibilityAgeSeconds: 20,
      advisorySeverity: null, speedMetersPerSecond: 14),
    DriveSituation( // uncertain position + low visibility, together
      positionTrust: PositionTrust.degraded, confidenceRadiusMeters: 220,
      secondsSinceTrustedFix: 75, hasPosition: true,
      visibilityMeters: 120, visibilityAgeSeconds: 30,
      advisorySeverity: AdvisoryLevel.severe, speedMetersPerSecond: 14),
  ]) {
    final a = adviseInDrive(s);
    print('${a.action.name} | compounding=${a.compounding} '
        '| reasons=${a.reasons.map((r) => r.name).toList()}');
  }
}
```

Prints:

```
continueDriving | compounding=false | reasons=[]
considerStopping | compounding=true | reasons=[positionUncertain, lowVisibility, severeAdvisory, highSpeedInDegradedConditions]
```

The surface renders the words (English by default, Japanese or any other
language for the driver) from `a.action`, `a.reasons`, and `a.unknowns` — this
package never hard-codes a tone or a language.

## What it consumes (seam-injected, by value)

You assemble one `DriveSituation` from bands the catalog already publishes —
this package **mirrors** their enums as its own tiny enums so you map 1:1 with
one switch per axis. It never fetches, estimates, classifies, routes, renders,
localizes, persists, logs, or touches the clock.

| Axis | From | Field |
| --- | --- | --- |
| position trust | `localization_fallback` `LocalizationEstimate.mode` | `positionTrust` (+ radius, age, hasPosition) |
| visibility | `pretrip_source_*` `VisibilityObservation.meters` | `visibilityMeters` (+ age) — `null` = no reading |
| area advisory | the single most-severe `condition_aggregator` advisory you selected | `advisorySeverity` — `null` = none |
| her motion | your speed source | `speedMetersPerSecond` — `null` = unknown |

```dart
final advice = adviseInDrive(DriveSituation(
  positionTrust: switch (estimate.mode) {
    LocalizationMode.gpsTrusted    => PositionTrust.trusted,
    LocalizationMode.gpsSuspect    => PositionTrust.suspect,
    LocalizationMode.deadReckoning => PositionTrust.degraded,
    LocalizationMode.lost          => PositionTrust.lost,
  },
  confidenceRadiusMeters: estimate.confidenceRadiusMeters,
  secondsSinceTrustedFix: estimate.secondsSinceTrustedFix,
  hasPosition: estimate.hasPosition,
  visibilityMeters: obs?.meters,                       // null when no reading
  visibilityAgeSeconds:
      obs == null ? null : now.difference(obs.measuredAt).inSeconds.toDouble(),
  // Explicit switch — exactly like the position axis above. condition_aggregator's
  // AdvisorySeverity has FIVE members (incl. `unknown`); AdvisoryLevel has FOUR.
  // Collapse BOTH `unknown` and none to `null` ("no advisory in force"); a 5th
  // upstream member would be a compile error here, never a silent mis-map.
  advisorySeverity: switch (mostSevere?.severity) {
    null || AdvisorySeverity.unknown => null,
    AdvisorySeverity.minor    => AdvisoryLevel.minor,
    AdvisorySeverity.moderate => AdvisoryLevel.moderate,
    AdvisorySeverity.severe   => AdvisoryLevel.severe,
    AdvisorySeverity.extreme  => AdvisoryLevel.extreme,
  },
  speedMetersPerSecond: speed,                         // null when unknown
));
```

Why mirrored enums and plain values instead of catalog imports?
`localization_fallback`, `condition_aggregator`, and `pretrip_source_*` are
independent publish lineages; a hard dependency would couple their version
cadence to this advisory and break the zero-dep / 32-bit-ARM contract. One
explicit switch per axis is cheap, explicit, and independently testable.

## The action model — three rungs, a strict ladder

| Action | Meaning |
| --- | --- |
| `continueDriving` | The **absence** of a raised concern given what is KNOWN — **not** an assertion of safety. |
| `heightenedCaution` | One or more conditions degraded: ease speed, leave room, watch for the next safe option. |
| `considerStopping` | The ceiling: *if you can do so safely*, a safe place to pause is an option whenever you want one. |

Reached chiefly by the **compounding** case (uncertain position AND low
visibility together) or a single axis at its worst (lost position / whiteout /
extreme advisory).

### Why caution rose — `CautionReason`

Every action above `continueDriving` carries **at least one** `CautionReason`
(enforced in code + tested), so the integrator can state the WHY in the driver's
own terms with no re-derivation. The visibility and advisory axes each emit
exactly one reason — the *milder* member in the lower band, the *harder* member
in the upper band — never both:

| Reason | Fires when |
| --- | --- |
| `positionUncertain` | position is suspect / degraded / lost / no dot |
| `reducedVisibility` | a known reading is in the **reduced** band (~500–1000 m) |
| `lowVisibility` | a known reading is in the **low / whiteout** band (< ~500 m) |
| `unknownVisibility` | no visibility reading in hand |
| `staleVisibility` | a reading exists but is too old (or unknown age) to trust |
| `moderateAdvisory` | a **moderate** area advisory is in force |
| `severeAdvisory` | a **severe or extreme** area advisory is in force |
| `highSpeedInDegradedConditions` | covering uncertain ground fast while the core is already degraded |

## Honesty + non-deterrence bounds (binding, enforced by the types and tested)

- **Never claims false confidence.** No `safe` / `allClear` / `ok` value exists
  anywhere in the API — never falsely reassure. (Provided the upstream estimate
  honours its grows-only-while-untrusted contract, the advisory can only become
  *more* cautious while degraded; this package consumes the radius by value and
  does not itself enforce that monotonicity.)
- **Never tells her she is safe.** `continueDriving` requires trusted position
  AND known-adequate visibility AND no advisory above `minor`; it is the
  *absence* of a flag. It senses no grip and holds no live model of the road
  surface, other vehicles, or her car — its only surface assumption is the
  single disclosed worst-ice figure below, used solely for the optional hint.
- **Unknown is first-class, never coerced.** A `null` or stale visibility
  reading — and a reading whose age is `null` (unknown currency) — surfaces as
  `visibilityKnown == false` + a distinct reason + an `Unknown`, held at a
  non-zero caution floor, never treated as "clear" nor over-warned as a
  whiteout. `sightStoppingSpeedHintMps` is `null` whenever visibility is unknown
  *or adequate*: we never plot a number we cannot ground.
- **The sight-stopping hint is fail-toward-slower.** When it appears (only in
  the low/whiteout band), it assumes worst-credible glare-ice grip (~1.0 m/s²,
  not packed snow), plans to stop within HALF of what she can see, and is capped
  at a winter ceiling (~48 km/h). It is a speed to *ease toward*, never a
  permission to go that fast; on the worst surface this package targets it must
  not over-state where she could stop.
- **`compounding` is named and exposed**, so you can tell the driver that *two*
  uncertainties are stacking — honesty about *why* caution rose.
- **Never deters her from a needed trip (structural).** There is **no**
  `turnBack` / `abort` / `doNotDrive` rung — it is absent from the enum, so the
  package is incapable of telling her to abandon the drive to her family. The
  worst case demotes the **map** ("trust your own eyes until things clear"), not
  the **journey**. On a rural snow road, stopping can itself be the dangerous
  option; only the driver, present at the scene, can judge. **Advisory-only is
  the whole identity: it labels the moment; she drives it.**

## Scope & known limitations (read these before you trust an output)

- **`compounding` means BOTH axes are KNOWN-bad.** It is `true` only when
  position concern ≥ 2 AND visibility is a *known* low/whiteout reading — i.e.
  the escalation is *because* two measured dangers stack. A suspect/degraded
  position together with an **unknown or stale** visibility reading does NOT set
  `compounding` (we will not assert a visibility we cannot confirm), so the
  headline "Maps fail, GPS fails, and the sensor that says how bad it is has
  *also* dropped out" can land at `heightenedCaution`, not the ceiling. Both
  uncertainties still surface as separate reasons/unknowns; read those, not just
  the `compounding` flag. (A *suspect* position with a known whiteout reaches the
  ceiling via the visibility axis, but `compounding` stays `false` — that is the
  flag's exact meaning, not a miss.)
- **It senses no road grip.** A fully snow-packed or black-ice road in clear air
  with a trusted fix returns `continueDriving` — the controlling Akita hazard
  (grip) is invisible to both primary axes and reaches the model ONLY if you feed
  a `severe`/`extreme` area advisory. `continueDriving` is "no *measured*
  concern", never "the road is safe". Where you have a winter surface advisory,
  pass it.

## Non-functional contract

Pure Dart · zero runtime dependencies · no Flutter · no IO · no globals · no
clock · 32-bit-ARM friendly. One **total, deterministic, synchronous** pure
function: same input → same output; defined for every enum, for `null`,
`double.infinity`, and `NaN` — clamped, never thrown. The surface is small
enough that the test suite exhausts every position × visibility × advisory ×
speed combination and certifies the honesty invariants by construction.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
