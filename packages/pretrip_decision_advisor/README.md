# pretrip_decision_advisor

> **0.2.0. Contract + working reference advisor.**
>
> This package ships an abstract contract, its data shapes, **and** a working
> pure-Dart reference advisor (`SnowAwarePretripAdvisor`) plus a source-neutral
> measured-visibility merge. `pub add`-ing it gives you a usable advisor, not
> just types. It does not fetch weather or integrate a route engine — a
> source-specific fetcher (which owns any HTTP dependency) stays outside this
> package, so the package itself remains pure Dart.

## Aspiration

The pre-trip departure-timing decision is often a larger pain point than
in-drive alerts. A driver asking "should I leave now or wait an hour?"
has to combine a forecast, a commute shape, and personal context, and the
answer changes whether the trip happens at all. Apps focused on alerts
during driving address a smaller window than apps that address departure
timing. This package defines the shape of an advisor that could help with
that question, so other packages and applications can experiment against
a common interface.

## Cohorts served

The package serves several distinct downstream cohorts:

- **Integrator developers** building parallel navigation products on top
  of common interfaces.
- **Open-source consumers** depending on shared safety-domain vocabulary.
- **Configuration consumers** inheriting predictable defaults.
- **Drivers** (indirectly, via integrator products) who benefit from the
  pre-trip decision layer addressing a prevention scenario before the
  in-drive compound-failure scenario.
- **Parallel-product builders** publishing their own concrete advisors
  against this contract without forking it.

## What is in the package

- `PretripAdvisor` — abstract advisor contract. Given a forecast, a
  commute shape, and a driver profile spec, it returns a recommendation,
  or `null` to mean "no recommendation; the driver should depart on
  their own judgment."
- `PretripRecommendation` — a suggested delay window, a confidence
  window, a recommendation strength, and a list of human-readable
  reason chips.
- `RecommendationStrength` — `advisoryWeak`, `advisoryStrong`, and
  `honestyMode`. `honestyMode` is used when the commute is required
  and the advisor explicitly defers to the driver rather than telling
  someone to risk being late for required obligations.
- `CommuteShape` and `CommuteFlexibility` — describe the planned trip,
  including whether the commute is required, discretionary, or unknown.
- `WeatherForecast`, `HourlyForecast`, and `RoadConditionEstimate` —
  the forecast inputs the advisor consumes.
- `DriverProfileSpec` — a small profile spec, decoupled from any
  specific full driver-profile package, so consumers can adopt this
  advisor without taking on a full safety-core dependency.
- `SnowAwarePretripAdvisor` — a deterministic, pure-Dart reference
  implementation of the contract. No LLM, no network, no clock: the same
  typed inputs always produce the same recommendation, so the worst-case
  path stays offline. Null forecast fields never fabricate a hazard, and it
  returns `null` when the forecast does not cover the departure window.
- `PretripBriefing`, `PretripVerdict`, and `HourHazard` — the richer typed
  verdict the reference advisor exposes via `brief(...)`, for UIs that want
  the structured result alongside the contract-shaped recommendation.
- `VisibilityObservation` and `mergeObservedVisibility` — a source-neutral
  measured-visibility observation and its departure-hour merge (a real sensor
  value overrides forecast visibility for the departure hour only, and is
  never projected into later forecast hours).

## What is NOT in the package

- No weather data fetching (no HTTP dependency — a source-specific fetcher
  produces the typed inputs and stays outside this package).
- No route engine integration.

## Quick start

```sh
dart pub add pretrip_decision_advisor
```

```dart
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

String describeStrength(RecommendationStrength s) => switch (s) {
      RecommendationStrength.advisoryWeak => 'advisory (weak)',
      RecommendationStrength.advisoryStrong => 'advisory (strong)',
      RecommendationStrength.honestyMode => 'honesty (driver decides)',
    };

String describeFlexibility(CommuteFlexibility f) => switch (f) {
      CommuteFlexibility.required => 'required commute',
      CommuteFlexibility.discretionary => 'discretionary commute',
      CommuteFlexibility.unknown => 'unknown flexibility',
    };
```

## Honesty

If a commute is marked `CommuteFlexibility.required`, an advisor
implementing this contract must not return a strong "wait" recommendation;
it should return either `null` or a `honestyMode` recommendation. The
advisor cannot tell a driver to risk being late for a required obligation,
because the cost of doing so is borne by the driver, not the advisor.

## Status

0.2.0. Contract + working reference advisor. Interface stability is committed
at this version within the bounds described in `KNOWN_LIMITATIONS.md`.
