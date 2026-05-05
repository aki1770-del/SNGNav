# Changelog

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

