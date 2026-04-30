# Known limitations

> **EXPLORE-PHASE.** This package ships an interface only. Do not depend
> on it from any production code path.

## Interface only

- No concrete `PretripAdvisor` is provided by this package.
- The included tests use a small in-test mock advisor that exercises the
  abstract contract; the mock is not a reference implementation and is
  not exported.

## API may change without notice

- Class names, field names, enum cases, and method signatures may change
  in any release before a 0.1.x line is published.
- DTO equality and hashing semantics may be tightened or relaxed.
- New required fields may be added to existing DTOs.

## Out of scope for this package

- Fetching, parsing, or interpreting weather data.
- Computing routes, commute durations, or arrival times.
- Bridging to richer driver-profile models. `DriverProfileSpec` is
  deliberately minimal; consumers adapt at their own boundary.
- Localization, copy, and UI surfacing of recommendations.

## Do NOT depend on this for production

- This package is `publish_to: 'none'` and is not on pub.dev.
- The interface exists to let callers prototype against a target shape
  and to give a future implementation something to satisfy. Treat it as
  a sketch.
