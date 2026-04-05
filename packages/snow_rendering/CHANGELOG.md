## 0.1.0

- Initial extraction from `driving_conditions` (SNGNav P1, D-SC22-2).
- `RoadSurfaceState` — six-state road surface classification with grip factors.
- `PrecipitationConfig` — particle configuration derived from weather conditions.
- `VisibilityDegradation` — opacity and blur parameters from visibility distance.
- `DrivingConditionAssessment` — combined assessment with advisory message.
- `HysteresisFilter<T>` — debounce filter for state oscillation at boundary conditions.
