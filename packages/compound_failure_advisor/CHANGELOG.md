# Changelog

## Unreleased

Hardening from a 6-lens adversarial review (OPS-068). Behaviour changes are all
caution-add-only / fail-toward-slower:

- **Every raised action now carries a statable WHY (honesty-contract fix).**
  Two mild single-axis degradations previously raised the action to
  `heightenedCaution` with an **empty `reasons` set** — a reduced visibility
  reading (~500–1000 m) and a `moderate` advisory each raised the action but
  contributed no reason, so an integrator was told to ease the driver's speed
  with no WHY to state (breaking the contract that `reasons` explain the caution
  with no re-derivation). Added two `CautionReason` members — `reducedVisibility`
  (the reduced band, milder counterpart to `lowVisibility`) and `moderateAdvisory`
  (the moderate level, milder counterpart to `severeAdvisory`) — emitted for those
  bands. Each axis emits exactly one reason (mild XOR hard, never double-counted).
  The invariant *"any action above `continueDriving` has a non-empty `reasons`
  set"* is now asserted in code and swept across the full input space in tests.
- **Sight-stopping hint recalibrated to the worst-credible surface.** The hint
  now assumes glare/black-ice grip (`kWinterDecelMps2` 2.0 → 1.0 m/s²) and a
  winter see-then-react time (`kReactionTimeSeconds` 1.5 → 2.5 s), plans to stop
  within HALF the visible distance, and is capped at a winter ceiling
  (`kSightHintCeilingMps`, ~48 km/h). It is now surfaced ONLY in the low/whiteout
  band (`null` in the clear/reduced bands), so it can no longer emit an
  "all-clear-ish" 90–180 km/h figure that over-stated the speed at which she
  could actually stop on ice.
- **A visibility reading with `null` age is no longer trusted as fresh.** Like a
  NaN age, an unknown-currency reading is held at the level-1 floor (not
  `continueDriving`, no grounded hint) — closing an internal-consistency gap.
- **`suspect` position now tracks its confidence radius and fix-staleness.** A
  suspect dot at neighbourhood scale, or with no trusted fix for a long blind
  period, bumps from concern 1 → 2 (matching `degraded`); a small/fresh suspect
  fix is unchanged.
- **Docs corrected.** The README advisory-seam snippet now uses an explicit
  `switch` over `AdvisorySeverity` (the previously documented `.toAdvisoryLevel()`
  helper never existed and would not compile); the surface-model and
  `continueDriving`-gate wording is corrected; and a new "Scope & known
  limitations" section documents the compounding-requires-both-known rule and
  the grip-only-via-advisory boundary.

## 0.1.0

Initial release.

- `adviseInDrive(DriveSituation) -> DriveAdvice`: one total, deterministic,
  synchronous pure function that fuses position-trust × visibility (with
  advisory severity + speed as escalators) into a single honest, immutable
  in-drive caution record.
- The load-bearing **compounding** rule: an uncertain position AND low
  visibility *together* yields the strongest caution (`considerStopping`) and
  sets `compounding == true` — worse than either alone.
- Three-rung action ladder (`continueDriving` / `heightenedCaution` /
  `considerStopping`). Structurally **no** turn-back / abort / do-not-drive
  rung — the package cannot deter a needed trip.
- First-class unknowns: `null` and stale visibility, missing position, and
  unknown speed surface as explicit `Unknown` values and distinct
  `CautionReason`s, held at a non-zero caution floor and never coerced to
  "clear".
- Optional `sightStoppingSpeedHintMps`, computed only when visibility is a
  grounded reading; `null` otherwise.
- Mirror enums (`PositionTrust`, `AdvisoryLevel`) restated locally so the
  package carries zero runtime dependencies and the integrator maps across the
  `localization_fallback` / `condition_aggregator` / `pretrip_source_*` seams
  with one switch per axis.
- Pure Dart, zero runtime dependencies, no Flutter, no IO, no clock,
  32-bit-ARM friendly.
