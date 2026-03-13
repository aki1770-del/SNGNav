# Changelog

## 0.2.0

- Added comprehensive dartdoc coverage for native simulation APIs and model quality fields.
- Fixed `dart doc` warnings so documentation builds cleanly.
- Added edge-case coverage for road-surface thresholds, hysteresis behavior, and visibility degradation.

## 0.1.1

- Add explicit Install section and API Overview table to README.
- Refresh README validation and license metadata for republish.

## 0.1.0

- Initial release.
- `RoadSurfaceState` — 6 road surface classifications with decision tree and hysteresis filter.
- `PrecipitationConfig` — particle visual parameters derived from weather conditions.
- `VisibilityDegradation` — opacity and blur sigma from visibility distance.
- `DrivingConditionAssessment` — composite assessment from weather conditions.
- `SafetyScoreSimulator` — Monte Carlo safety score simulation scaffold.
