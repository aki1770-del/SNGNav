# Changelog

## Unreleased

- docs: `// oracle:placeholders` annotations on the `kalman_dr.dart` and
  `DeadReckoningProvider` snippets, naming the caller-supplied
  `LocationProvider` the examples stand in for (this package ships no concrete
  implementation — the platform locator is the integrator's).

  **Recorded because it is a version drift, not a change.** These landed in the
  tree AFTER 0.4.4 was published and without a bump, so repo-0.4.4 and
  pub.dev-0.4.4 are two different artifacts under one version — a divergence no
  version check can detect, which is why it went unseen until the 2026-07-22
  registry audit. Measured then: stripping comment lines makes the two byte-
  identical, so the divergence is doc-only and no consumer is running different
  code. Not republished as 0.4.5 on its own — a version bump that reaches every
  consumer should carry something they need. It ships with the next real change.

- Provenance correction (honesty-of-record): the 0.4.3 CHANGELOG stated "No code
  change", but 0.4.3 in fact shipped — carried in from the 2026-06-27
  finite-position safety work — four executable NaN/non-finite guards in the
  dead-reckoning + Kalman path that were not present in the published 0.4.2:
  a non-finite latitude/longitude early-return in `_onGpsPosition`
  (`dead_reckoning_provider.dart`); an `accuracy.isFinite` condition on the
  Kalman-update gate; a non-finite-determinant guard in the matrix inverse
  (`kalman_filter.dart`); and a NaN-reject floor in the accuracy→covariance
  mapping. These guards are correctness-improving — they stop a NaN/Inf GPS fix
  from corrupting the filter or teleporting the position — and are covered by
  `finiteness_guard_test.dart`. This 0.4.4 release corrects the record; it
  contains no further code change of its own (lib is identical to 0.4.3).

## 0.4.3

- Docs: correct the README test-count claim from "200+ unit tests" to the real count (77, confirmed via `dart test`). Update the README install snippet pin to `^0.4.3` to resolve the current version. No code change.

## 0.4.2

- Docs: correct the dead-reckoning description — the package does constant-velocity extrapolation from the last GPS fix, NOT device-sensor/IMU fusion. No code change.

## 0.4.1

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.0 — 2026-05-10 — Pana score recovery + dart format alignment

- Trim pubspec `description` to ≤180 characters so search-engine
  snippets surface the package's purpose cleanly.
- Apply `dart format` across `lib/` and `test/` (9 files reformatted)
  to clear pana static-analysis formatter findings.
- No SDK source changes; metadata + formatter pass only.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

