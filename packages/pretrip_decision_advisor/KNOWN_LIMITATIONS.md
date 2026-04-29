# Known Limitations

> **Explore-phase. Interface only. NOT for production use. NOT published to pub.dev.**

## Scope

This package ships an interface and data shapes only. There is no
concrete advisor implementation included.

## Specific limitations

- **No implementation.** The `PretripAdvisor` contract has no concrete
  subclass in this package. A real advisor would need a weather data
  source, route data, and a driver-profile bridge, all of which are
  out of scope while the package is in explore-phase.
- **API may change.** The shape of the contract, the DTOs, and the
  enums may change without notice during explore-phase. Do not pin
  application logic to specific field names or enum cases yet.
- **No numerical thresholds.** The interface does not declare any
  delay durations, severity boundaries, or confidence widths as
  defaults. Any concrete advisor must justify its own numbers.
- **No production use.** This package is not intended for use in
  shipping applications, and is not published to pub.dev. The
  `publish_to: none` field in `pubspec.yaml` enforces this.
- **No taxonomy claims.** `CommuteFlexibility` and the road-condition
  enum are explore-phase substrate, not declared-final taxonomies.
- **No driver-profile coupling.** `DriverProfileSpec` is intentionally
  small and decoupled from any other package. A concrete advisor
  needing a richer profile model should adapt at its boundary, not
  push the dependency back into this interface.

## When this file becomes obsolete

This file becomes obsolete only after the package leaves explore-phase
through a documented graduation. Until then, treat every section here
as a current binding constraint.
