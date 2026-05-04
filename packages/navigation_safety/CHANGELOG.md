# Changelog

## 0.8.0 — 2026-05-04 — wire AlertDensityThrottle + AlertExplainer at alert-firing seam

Wires the `navigation_safety_core` 0.8.0 driver-facing looms
(`AlertDensityThrottle` + `AlertExplainer` + `LoomFitTelemetry`) at
the `_onSafetyAlert` integration seam in `NavigationBloc`. The
integration is opt-in: an integrator that supplies no driver
profile sees no behaviour change from 0.7.x.

### Added

- **`NavigationBloc({DriverProfile? profile, AlertDensityThrottle?
  throttle, LoomFitTelemetry? telemetry})`** — three optional
  constructor parameters. When `profile` is supplied, the bloc
  lazy-constructs a per-profile `AlertDensityThrottle` (or uses one
  passed in) on first `_onSafetyAlert` call and gates non-critical
  alerts against the per-profile alerts/min cap; critical alerts
  always fire regardless of cap by documented invariant. When
  `telemetry` is supplied, every `shouldFire` decision emits one
  record (`fired` / `droppedByThrottle` / `criticalBypass` /
  `coldStart`) onto the broadcast stream so the consuming-app
  analytics layer can ask *did the loom fit each driver-class?*
- **`SafetyAlertReceived.condition`** — optional
  `RoadSurfaceCondition` field. When supplied alongside a bloc
  profile, the bloc resolves
  `AlertExplainer.forConditionAndProfile(condition, profile)` and
  uses the explainer's action string as the rendered alert message,
  overriding the free-form `message` field for that emit. The
  free-form `message` remains the fallback when condition is null
  OR the bloc has no driver profile configured (back-compat).
- **`SafetyAlertReceived.ambientThreshold`** — optional
  caller-supplied identifier of the active threshold context
  (e.g. `"icy_road_30km"`). Surfaced into telemetry records.
- **`NavigationState.alertCondition`** — optional
  `RoadSurfaceCondition` field carrying the condition into
  downstream consumers (e.g. `voice_guidance` for action-coupled
  hazard rendering).

### Why this exists

The 0.7.x line shipped all per-profile primitives at the core
package boundary (`navigation_safety_core` 0.7.x:
`AlertDensityThrottle`, `AlertExplainer`, `RoadSurfaceConditionGlossary`)
but no integrator wired them at the alert-firing seam, so the
literature-anchored caps + action-coupled vocabulary stayed
substrate-only. The 0.8.0 wiring brings those primitives to the
state-machine boundary integrators consume, gated on opt-in
profile + condition supply so existing call sites are unaffected.

Anchors (inherited from `navigation_safety_core` 0.4.0 / 0.4.1
runtime-loom rationales):
- [PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/)
  alarm-fatigue scoping review.
- [arxiv 2410.06388](https://arxiv.org/html/2410.06388) silent
  over-warning failure framing.
- [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)
  hazard-perception RT differentials.
- AAA-FTS ADAS-exposure / driver-workload report.

### Tests

- 5 new tests in `test/bloc/navigation_bloc_test.dart` covering:
  emits state when throttle returns true (under cap); drops alert
  + emits telemetry when throttle returns false; critical bypass
  fires regardless of throttle in-window count; condition + profile
  → explainer text used as alert message; no profile →
  message-as-fallback (back-compat).
- `test/bloc/navigation_event_test.dart` updated for expanded
  `SafetyAlertReceived.props` length.

### Discipline

- **Severity-not-profile invariant preserved.** The throttle
  modulates per-profile alerts/min cap; severity-class gating
  remains upstream at `_canUpdateSeverity`. Critical alerts always
  fire.
- **Driver-always-drives invariant preserved.** `AlertExplainer`
  action verbs are advisory mood; speed numbers are published
  reference points, not system-enforced limits.
- **PHIL-001 boundary preserved.** `LoomFitTelemetry` integration
  is emit-only; the bloc does not classify "fit" vs "misfit".
  Integrators that do not subscribe pay zero data-flow cost.
- **Back-compat.** All 0.7.x / 0.6.x / 0.5.x callers see no
  behaviour change. The constructor parameters default to null;
  the event field defaults to null. New SAFETY_BOUNDARY.md authored
  for the package.

### Unchanged (back-compat)

- `NavigationBloc()` zero-arg construction works; emits the same
  states in response to the same events as 0.7.0 when no profile
  / throttle / telemetry is supplied.
- `SafetyAlertReceived(message:, severity:)` two-arg construction
  works; `condition` and `ambientThreshold` default to null.
- `NavigationState.alertCondition` defaults to null.

## 0.7.0 — 2026-05-05 — per-profile modal-alert duration primitive

Adds a pure-Dart per-profile modal-alert duration primitive
(`modalAlertDurationFor(profile)`) so consuming apps can dwell the
modal alert long enough for each driver-class to read it without
rushing. Closes the third axis of the per-profile rendering trio:
**alert-magnitude × duration × pace** is one product per Bian et al
(PubMed 38669900).

### Added

- **`modalAlertDurationFor(DriverProfile)`** in
  `lib/src/modal_alert_duration.dart` — returns a `Duration` the
  integrator passes to whatever auto-dismiss timer the integrator
  owns. Six profile multipliers on top of `kModalAlertDurationBase`
  (5 seconds engine-base):
  - `snowZoneExperienced` × 1.0 (5.0 s)
  - `professional`        × 1.0 (5.0 s)
  - `agriculturalForestry`× 1.2 (6.0 s)
  - `noviceUrban`         × 1.3 (6.5 s)
  - `ageingRural`         × 1.5 (7.5 s)
  - `foreignTouristSnowZone` × 1.5 (7.5 s)
- **`kModalAlertDurationBase`** — engine-base 5-second anchor.
- **`kModalAlertDurationMultiplierByProfile`** — published multiplier
  table with profile-specific design rules in dartdoc.

### Substrate anchor

- 100-insights #56 (per-profile modal-alert dwell-time substrate).
- Bian et al PubMed 38669900 (alert-magnitude × duration as one
  product; format-mismatch erases earlier-alert benefit).
- Conservative-only direction: all multipliers ≥ 1.0; no profile
  receives a SHORTER duration than engine-base.

### Discipline

- **Advisory not control.** The primitive returns a `Duration`; the
  package mounts no auto-dismiss timer itself. Integrator owns the
  timer surface. AAA Article 17 (β) ASIL-QM advisory class.
- **Severity-not-profile invariant preserved.** The function consumes
  only `DriverProfile`, not `AlertSeverity`. Severity decides
  whether/what; profile only decides how long the display dwells.
- **PHIL-001 boundary preserved.** No driver-data harvested; the
  primitive is pure-function on enum input.

### Tests

- 9 new tests in `test/modal_alert_duration_test.dart` covering the
  six per-profile mappings, multiplier-conservative-only invariant,
  every-profile-has-entry coverage, linear-scaling sanity, and the
  severity-not-profile single-arg API lock.

### Unchanged (back-compat)

- All 0.6.0 / 0.5.0 / 0.4.x surface unchanged. Existing call-sites
  see no behavior change. The new primitive is additive only.

## 0.5.0

### Breaking changes
- `NavigationStarted.route` is now `NavigationRoute` (was `RouteResult` from `routing_engine`)
- `RerouteCompleted.newRoute` is now `NavigationRoute` (was `RouteResult`)
- `NavigationState.route` is now `NavigationRoute?` (was `RouteResult?`)
- `NavigationState.currentManeuver` now returns `NavigationManeuver?` (was `RouteManeuver?`)
- `NavigationState.nextManeuver` now returns `NavigationManeuver?` (was `RouteManeuver?`)
- `routing_engine` is no longer a dependency of `navigation_safety`

### Added
- `NavigationRoute` — navigation layer route model (shape, maneuvers, totalDistanceKm, totalTimeSeconds, summary, eta)
- `NavigationManeuver` — navigation layer maneuver model (index, instruction, type, lengthKm, timeSeconds, position)

### Migration
Use `RouteResult.toNavigationRoute()` extension (in the main app's adapter) to convert at the boundary.

## 0.4.0

**BREAKING**: `NavigationSafetyConfig()` constructor is no longer `const`. Any `const NavigationSafetyConfig(...)` call site must remove the `const` keyword.

### Safety remediations (R4 review, April 2026)

- **G-01 (P0)**: `NavigationSafetyConfig` now throws `RangeError`/`ArgumentError` in all modes (including release) for out-of-range or inverted thresholds. Previously used `assert()` which is silently ignored in release builds.
- **G-02 (P0)**: `_canUpdateSeverity()` rewritten with explicit `const` priority map (`info:0, warning:1, critical:2`). No longer uses `AlertSeverity.index` — immune to enum reordering.
- **G-03 (P0)**: `RerouteCompleted` now passes `clearAlert: true`. Route-specific alerts no longer persist after the driver reroutes.
- **G-04 (P0)**: `SafetyOverlay` wraps non-dismissible alerts in `PopScope(canPop: false)`. Android back button and iOS swipe cannot bypass a critical non-dismissible alert.
- **G-05 (P1)**: Added `SafetyNavigationScaffold` — a convenience wrapper that places `SafetyOverlay` as the topmost `Stack` child, enforcing Z-order by construction rather than consumer contract.
- **G-06 (P1)**: `NavigationSafetyConfig` extends `Equatable`. Identical configs compare equal; eliminates unnecessary BLoC rebuilds on config change detection.
- **G-07 (P1)**: Debug-mode OODA latency logging — `_onSafetyAlert` records `Stopwatch` and prints a warning to console if BLoC processing exceeds 500 ms. No-op in release builds.
- **G-09 (P1)**: 27 new unit/bloc tests added (57 → 84 total). Covers: `AlertSeverity` ordinal invariants, `NavigationSafetyConfig` boundary validation, `SafetyScore` boundary (0.0 → critical, 1.0 → no alert), reroute alert clearing, non-dismissible alert persistence across navigation stop.

### Known deferred items (planned v0.5.0)

- **G-07**: OODA latency runtime enforcement (benchmark tests, hard limit) — deferred.
- **G-08**: `routing_engine` types (`RouteResult`, `RouteManeuver`) appear in `NavigationState`/`NavigationEvent` public API (D-SC22-4 known violation). Full fix (wrapper types) deferred to v0.5.0 pre-P2. Consumers must add `routing_engine` to their pubspec.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

