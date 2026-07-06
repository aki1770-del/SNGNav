# drive_situation_fusion

The seam that supplies [`compound_failure_advisor`][cfa] from the signals the
SNGNav catalog already produces.

`compound_failure_advisor` is deliberately **zero-dependency** — it mirrors the
enum shapes it needs so it never inherits a runtime dependency tree and stays
32-bit-ARM friendly. The price of that decoupling is a seam: someone has to map
[`localization_fallback`][lf]'s `LocalizationMode` onto the advisor's
`PositionTrust`, and [`condition_aggregator`][ca]'s `AdvisorySeverity` onto
`AdvisoryLevel`. **This package is that seam** — done once, correctly, and
tested — so no integrator re-derives it, and no integrator can get the one
safety-critical case wrong.

## The safety-critical case

`LocalizationMode.deadReckoning` — GPS is gone and the dot is being carried by
dead reckoning with a growing confidence radius — maps to
**`PositionTrust.degraded`**, *not* `trusted`. A hand-mapping that treats "still
emitting a position" as trusted would silently suppress the compound caution at
the exact moment she has lost GPS in snow — the compound-failure scenario the
advisor exists for. This package makes that mapping canonical.

## Use

```dart
import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:drive_situation_fusion/drive_situation_fusion.dart';

// `estimate` from localization_fallback; `advisory` the single most-severe
// in-area advisory you already selected from condition_aggregator; visibility
// from your live weather source (you own the clock, so you pass the age).
final situation = fuseDriveSituation(
  estimate: estimate,
  advisory: advisory,               // or null — "no advisory in force"
  visibilityMeters: observation.meters,
  visibilityAgeSeconds:
      now.difference(observation.measuredAt).inSeconds.toDouble(),
  speedMetersPerSecond: speed,
);

final advice = adviseInDrive(situation); // advisory-only; she drives it.
```

## Contract

Pure Dart. **Total and deterministic** — like the advisor it feeds, it never
throws, owns no clock, and does no IO. It maps values across the advisor's
zero-dependency seam and nothing more: it does not fetch, estimate, classify, or
aggregate. Degenerate inputs (`NaN` radius, infinite time, all-`null`
optionals) pass straight through to the advisor, which is itself total and
degrades conservatively.

Advisory-only. This package labels the moment; **she drives it.** It never says
"safe" and never tells her to turn back — that is the advisor's contract, and
this seam does not widen it.

[cfa]: https://pub.dev/packages/compound_failure_advisor
[lf]: https://pub.dev/packages/localization_fallback
[ca]: https://pub.dev/packages/condition_aggregator
