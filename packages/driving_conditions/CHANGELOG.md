# Changelog

## 0.5.0

- **New**: `FleetConfidenceProvider` abstract interface — pluggable fleet confidence for safety simulation.
- **New**: `ConstantFleetConfidenceProvider` — explicit named replacement for the `0.8` literal.
- **New**: `FleetHazardConfidenceAdapter` — derives confidence from `List<FleetReport>` using road condition safety factors (dry 1.0, wet 0.7, snowy 0.4, icy 0.1).
- `CpuSafetyScoreSimulationEngine`, `NativeSafetyScoreSimulationEngine`, and `SafetyScoreSimulator` now accept an optional `FleetConfidenceProvider`. Default behaviour is unchanged (0.8 constant).
- Native `simulation_run_batch` C function now accepts `fleet_confidence` as a parameter. Shared library rebuilt.
- Adds `fleet_hazard: ^0.3.0` as a dependency.

## 0.4.0

- **Breaking**: `SafetyScoreSimulator.simulate()` and `SafetyScoreSimulationEngine.simulate()` now return `SimulationResult` instead of `SafetyScore`.
- **New type**: `SimulationResult` — wraps the mean `SafetyScore` with statistical measures: `variance`, `incidentCount`, and (native engine only) `executionMs`.
- **Promoted**: `NativeSafetyScoreSimulationEngine` is now part of the public API. Edge developers can instantiate it directly to access native-engine execution timing.
- `CpuSafetyScoreSimulationEngine.simulate()` now computes and exposes `variance` and `incidentCount` from the Monte Carlo runs.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

