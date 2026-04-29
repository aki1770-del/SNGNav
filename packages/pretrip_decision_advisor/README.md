# pretrip_decision_advisor

> **Explore-phase. Interface only. NOT for production use. NOT published to pub.dev.**
>
> This package ships an abstract contract and data shapes only. There is no
> concrete advisor implementation in this package, and the API may change
> without notice while the package remains in explore-phase.

## Aspiration

The pre-trip departure-timing decision is often a larger pain point than
in-drive alerts. A driver asking "should I leave now or wait an hour?"
has to combine a forecast, a commute shape, and personal context, and the
answer changes whether the trip happens at all. This package defines the
shape of an advisor that could help with that question, so other packages
and applications can experiment against a common interface before any
concrete advisor is built.

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

## What is NOT in the package

- No concrete advisor implementation.
- No weather data fetching.
- No route engine integration.
- No published artifact on pub.dev.

## Honesty

If a commute is marked `CommuteFlexibility.required`, an advisor
implementing this contract must not return a strong "wait" recommendation;
it should return either `null` or a `honestyMode` recommendation. The
advisor cannot tell a driver to risk being late for a required obligation,
because the cost of doing so is borne by the driver, not the advisor.

## Status

Explore-phase. Interface stability is not yet promised. See
`KNOWN_LIMITATIONS.md` for the full list of explore-phase caveats.
