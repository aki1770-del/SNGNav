# Changelog

## 0.1.1

- **Tests only — the `lib/` is byte-identical to the published 0.1.0** (verified
  by diff against the pub.dev 0.1.0 archive); this release adds regression
  coverage and changes no production behaviour. (The behaviour bullets that an
  earlier draft of this entry listed under 0.1.1 in fact shipped in 0.1.0 and are
  re-attributed there below — they were not new in 0.1.1.)
- Added regression guards on every threshold and the two safety-critical
  invariants of this D3-worst-case advisor, so a future relaxing tweak fails
  loudly: (a) exact band-boundary tests pinning each `k*` edge inclusive/exclusive
  (visibility 1000/999, 500/499, 200/199 m; freshness 300 s; suspect/degraded
  radius 150 m; stale-fix 60 s; fast-speed 13.4 m/s); (b) an **exhaustive
  non-deterrence** sweep over the full input space including `null`/NaN/±infinity/
  out-of-range values (211,200 combinations) asserting NO input ever produces an
  action beyond `considerStopping` — the package is structurally incapable of
  telling her to turn back; (c) an **exhaustive no-under-warn** sweep asserting
  every KNOWN position-concern ≥ 2 paired with a KNOWN visibility-concern ≥ 2
  reaches `considerStopping` AND sets `compounding` (the D3 stacked-danger core
  never stays calm); (d) a pin on the deliberate under-confirmation boundary
  (degraded position + UNKNOWN/STALE visibility holds at `heightenedCaution`,
  surfacing both uncertainties, never over-warning a whiteout it cannot confirm);
  (e) a speed-axis monotonicity guard; and a constants-pinned test that catches
  any relaxation of the calibration values.

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
- Every raised action carries a statable WHY: each escalated action has a
  non-empty `reasons` set. The mild single-axis bands each emit one reason —
  `reducedVisibility` (~500–1000 m, milder counterpart to `lowVisibility`) and
  `moderateAdvisory` (the moderate level, milder counterpart to `severeAdvisory`)
  — and each axis emits exactly one reason (mild XOR hard, never double-counted).
- Sight-stopping hint calibrated to the worst-credible winter surface: it assumes
  glare/black-ice grip (`kWinterDecelMps2` 1.0 m/s²) and a winter see-then-react
  time (`kReactionTimeSeconds` 2.5 s), plans to stop within HALF the visible
  distance, and is capped at a winter ceiling (`kSightHintCeilingMps`, ~48 km/h).
  It is surfaced ONLY in the low/whiteout band (`null` in the clear/reduced
  bands), so it can never emit an "all-clear-ish" figure that overstates the
  speed at which she could actually stop on ice.
- First-class unknowns: `null`/NaN/stale visibility (including a reading whose
  age is `null`), missing position, and unknown speed surface as explicit
  `Unknown` values and distinct `CautionReason`s, held at a non-zero caution
  floor and never coerced to "clear".
- `suspect` position tracks its confidence radius and fix-staleness: a suspect
  dot at neighbourhood scale, or with no trusted fix for a long blind period,
  bumps from concern 1 → 2 (matching `degraded`); a small/fresh suspect fix is
  unchanged.
- Mirror enums (`PositionTrust`, `AdvisoryLevel`) restated locally so the
  package carries zero runtime dependencies and the integrator maps across the
  `localization_fallback` / `condition_aggregator` / `pretrip_source_*` seams
  with one switch per axis.
- Pure Dart, zero runtime dependencies, no Flutter, no IO, no clock,
  32-bit-ARM friendly.
