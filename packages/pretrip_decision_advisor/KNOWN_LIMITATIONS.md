# Known Limitations

> **Deploy-phase 0.1.0. Interface-only contract. Reference implementations expected to compose with this contract.**

## Scope

This package ships an interface and data shapes only. There is no
concrete advisor implementation included.

## Specific limitations

- **Interface-only at 0.1.0.** This package ships an interface + DTOs +
  spec; not a concrete advisor implementation. Concrete advisors
  compose this contract; this package by design does not include the
  implementation.
- **Reference implementation roadmap.** A reference advisor
  implementation (with concrete weather data source + route
  integration + driver-profile bridge) is out of scope at 0.1.0;
  expected at a future cadence.
- **API may change.** The shape of the contract, the DTOs, and the
  enums may evolve in a future minor version. Do not pin application
  logic to specific field names or enum cases without reading the
  current CHANGELOG entry.
- **No numerical thresholds.** The interface does not declare any
  delay durations, severity boundaries, or confidence widths as
  defaults. Any concrete advisor must justify its own numbers.
- **No taxonomy claims.** `CommuteFlexibility` and the road-condition
  enum are working substrate, not declared-final taxonomies.
- **No driver-profile coupling.** `DriverProfileSpec` is intentionally
  small and decoupled from any other package. A concrete advisor
  needing a richer profile model should adapt at its boundary, not
  push the dependency back into this interface.

## When this file becomes obsolete

This file becomes obsolete only when a reference advisor
implementation graduates alongside this contract — at which point the
honesty disclosures here can be re-evaluated against a concrete
shipping artifact. Until then, treat every section here as a current
binding constraint.
