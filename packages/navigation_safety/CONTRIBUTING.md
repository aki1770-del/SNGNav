# Contributing a Safety Signal to navigation_safety

## What contributing means

Adding a field to `SafetyScore` that covers one uncovered threat scenario.
Each field moves one cell in the 62-scenario SNGNav coverage matrix from
`UNCOVERED` to `COVERED`.

**Time required**: ~3 hours for an experienced Dart developer.
**Prerequisites**: familiarity with `flutter_test`. No KUKSA, Valhalla, or
embedded Linux knowledge required.

## How to contribute (6 steps)

1. Choose an open scenario from the table below
2. Read `lib/src/models/safety_score.dart` (72 lines) and
   `lib/src/models/navigation_safety_config.dart`
3. Add one field to `SafetyScore` for your scenario
4. Add a corresponding threshold to `NavigationSafetyConfig`
5. Update `toAlertSeverity()` to check your new field
6. Write 3 tests (boundary / clamp / severity mapping) and open a PR with
   the scenario ID in the title: `feat(scenario): cover S-NNN [scenario name]`

Your name appears in `CHANGELOG.md` and in the SNGNav safety argument document.

## Open scenario slots (good first issues)

| ID | Scenario | Signal needed | Difficulty |
|:--:|----------|---------------|:----------:|
| S-007 | Offline tile miss on region boundary crossing | `tileMissProbability` (0.0–1.0) | easy |
| S-014 | Black ice at intersection approach | `blackIceRisk` (0.0–1.0) | easy |
| S-015 | Black ice on bridge deck | `bridgeIceRisk` (0.0–1.0) | easy |
| S-019 | Aquaplaning risk at speed | `aquaplaningRisk` (0.0–1.0) | easy |
| S-022 | Tunnel ventilation ice drip | `infrastructureRiskScore` (0.0–1.0) | easy |
| S-029 | GPS denied in urban canyon | `gpsConfidence` (0.0–1.0) | medium |
| S-031 | Black ice pre-warning from V2X | `v2xIceWarning` (0.0–1.0) | medium |
| S-035 | Slope aspect shadow (ice in shade) | `slopeAspectIceRisk` (0.0–1.0) | medium |
| S-041 | Wet-bridge microclimate | `microclimateBridgeRisk` (0.0–1.0) | medium |
| S-047 | Crosswind severity at highway speed | `crosswindRisk` (0.0–1.0) | medium |
| S-051 | Low-vision accessibility contrast | `contrastRatio` (0.0–1.0, WCAG AA = 0.21) | hard |
| S-058 | Right-to-left locale alert rendering | locale string support in `SafetyOverlay` | hard |

## SOTIF boundary reminder

**You compute the score. This package displays it.**

Pass `0.0` when uncertain — the package alerts conservatively.
Do not couple a new field to an actuator path. Display only.

## Recognition

- Your name in `CHANGELOG.md` under the version that includes your field
- Scenario ID marked `COVERED` in `sngnav_coverage.yaml`
- Named in the SNGNav Safety Argument traceability matrix (GSN)

## Questions

Open a GitHub issue or ping `@komada` in the issue thread.
