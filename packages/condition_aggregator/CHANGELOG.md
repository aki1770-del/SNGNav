# Changelog

## 0.0.1 — 2026-05-03

Initial publish.

- `Advisory` typed event normalized across publisher sources
  (severity / certainty / urgency / area / effective / expires).
- `AdvisorySource` enum (`nwsUnitedStates`, `jmaJapan`, `other`).
- CAP-class enums: `AdvisorySeverity`, `AdvisoryCertainty`,
  `AdvisoryUrgency`.
- `AdvisoryProvider` adapter contract with mandatory `init()` lifecycle
  and `fetchActiveAdvisoriesAtPoint(lat, lon)` method.
- `AdvisoryAggregator` multi-source fan-out primitive with
  warn-and-continue per-provider failure capture.
- `AdvisoryProviderInitException`, `AdvisoryAggregateResult`,
  `AdvisoryProviderError` supporting types.
- 11 tests covering the value-object, init lifecycle, fan-out merge,
  warn-and-continue per-provider error capture, init-failure
  propagation, init idempotency.
- BSD-3-Clause license (matches the rest of SNGNav).
- Pure Dart, no Flutter dependency.
