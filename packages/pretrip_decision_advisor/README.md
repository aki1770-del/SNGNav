# pretrip_decision_advisor

> **EXPLORE-PHASE.** Interface-only spike. No concrete advisor is shipped.
> This package is **not published** and is not intended for production use.

## Aspiration declaration

When a phone running an SNGNav-class app needs pre-trip departure-timing
decision support, the navigation safety substrate must expose an interface
that a future advisor implementation can satisfy without coupling to weather
data integration, route data integration, or driver profile bridging in this
package.

## What this is

- A small set of Dart abstractions describing the **shape** of a pre-trip
  departure-timing advisor.
- An abstract `PretripAdvisor` class with a single `advise(...)` entry point.
- Plain data types describing the inputs (forecast, commute shape, driver
  profile spec) and the output (`PretripRecommendation`).
- A test suite that exercises the contract through a small in-test mock.

## What this is NOT

- **Not an implementation.** No concrete `PretripAdvisor` is provided.
- **Not a forecast source.** The package does not fetch, parse, or interpret
  weather data.
- **Not a routing engine.** The package does not compute routes or commute
  durations.
- **Not a driver-profile bridge.** `DriverProfileSpec` is an opaque local
  spec; richer profile models adapt to it at their own boundary.
- **Not stable.** Names and shapes may change without notice.

## Status

Explore-phase. The interface exists so callers can prototype against it and
so a future implementation has a target shape to satisfy. Do not depend on
this package from any production code path. See `KNOWN_LIMITATIONS.md`.
