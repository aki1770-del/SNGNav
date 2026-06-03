# Changelog

## 0.4.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.2 — 2026-05-10 — Pana score recovery (Theme α P4)

- Trim pubspec `description` to within the pana 60–180 character target.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.4.1

- **Renamed** the `AlertSeverity` enum (introduced in 0.4.0) to
  `AlertSeverityClass`. The 0.4.0 name collided with `AlertSeverity` in
  `navigation_safety_core` and `noaa_nws_adapter`, breaking compilation
  for any consumer importing both packages. The renamed name is
  consistent with the other instrumentation enums (`...Class` /
  `...State` / `...Reason`).
- Consumers that pulled 0.4.0 in the brief window before 0.4.1 should
  update `AlertSeverity` references on `AlertFired.severity` to
  `AlertSeverityClass`. The values (`info`, `warning`, `critical`,
  `unknown`) are unchanged.
- No other API changes.

## 0.4.0

- Added: 4 new `ConsentPurpose` enum values for instrumentation-class
  consent — `alertExperienceInstrumentation`, `voiceExperienceInstrumentation`,
  `cohortCalibrationInstrumentation`, `tripContextInstrumentation`.
- Added: `InstrumentationService` abstract interface with `recordEvent`,
  `readEvents`, `getRetention`, `setRetention`, `deleteAllEvents`,
  `pruneExpired`, and a stable per-install `driverPseudonym`.
- Added: `InstrumentationEvent` sealed class with 4 subtypes —
  `AlertFired`, `VoicePaceAdjusted`, `CohortMultiplierObserved`,
  `TripContextCaptured`. Zero GPS, zero destination, zero PII.
- Added: `InMemoryInstrumentationService` test-class implementation
  carrying an explicit *not for production* comment at the file top;
  pseudonym derived from `dart:math` `Random.secure()` plus
  `DateTime.microsecondsSinceEpoch`. No new package dependencies.
- Jidoka extended to instrumentation: `recordEvent` throws `StateError`
  unless the corresponding consent status is explicitly `granted`.
  UNKNOWN equals DENIED at this gate too.
- Reserved: data-flow scopes beyond on-device (integrator-aggregated /
  maintainer-class aggregation) for v0.5+ separate substrate-class
  decisions. v0.4.0 keeps instrumentation events on-device by default.
- No breaking changes; the v0.3.0 API is preserved verbatim.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

