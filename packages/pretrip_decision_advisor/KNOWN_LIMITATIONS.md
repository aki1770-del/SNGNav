# Known Limitations

> **0.2.0. Contract + working reference advisor (`SnowAwarePretripAdvisor`). Pure Dart — no weather fetching, no route engine.**

## Scope

This package ships the abstract contract, its data shapes, and a working
pure-Dart reference advisor plus a source-neutral visibility merge. It does
**not** fetch weather data or integrate a route engine; a source-specific
fetcher (which owns any HTTP dependency) produces the typed inputs and stays
outside this package, so the package itself stays pure Dart.

## Specific limitations

- **No data acquisition.** The package ships the advisor logic and its typed
  inputs, not a weather data source or route integration. A consumer (or a
  separate fetcher package) supplies the `WeatherForecast` and `CommuteShape`.
  This keeps the package pure Dart with no `http`/Flutter dependency.
- **API may change.** The shape of the contract, the DTOs, and the
  enums may evolve in a future minor version. Do not pin application
  logic to specific field names or enum cases without reading the
  current CHANGELOG entry.
- **Reference thresholds are the reference advisor's, not the contract's.**
  The abstract contract declares no numerical defaults. `SnowAwarePretripAdvisor`
  declares its own delay durations, visibility/temperature bands, and
  confidence widths; each is documented at its declaration site, and any
  alternative `PretripAdvisor` implementation must justify its own numbers.
- **No taxonomy claims.** `CommuteFlexibility` and the road-condition
  enum are working substrate, not declared-final taxonomies.
- **No driver-profile coupling.** `DriverProfileSpec` is intentionally
  small and decoupled from any other package. A concrete advisor
  needing a richer profile model should adapt at its boundary, not
  push the dependency back into this interface.

## When this file changes

These constraints are current at 0.2.0. Re-evaluate them against the shipped
artifact whenever the contract surface or the reference advisor's behaviour
changes; until then, treat every section here as a binding constraint.
