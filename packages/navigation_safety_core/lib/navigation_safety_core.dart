/// Pure Dart core models for navigation safety.
///
/// These types live outside `navigation_safety` so that pure-Dart
/// consumers (e.g. `driving_conditions`) can depend on the vocabulary
/// without inheriting `navigation_safety`'s Flutter + BLoC + widget
/// dependency tree (D-SC22-4 boundary).
///
/// The full `navigation_safety` package re-exports everything here
/// for back-compat, so consumers that don't care about the Pure Dart
/// boundary can keep importing
/// `package:navigation_safety/navigation_safety.dart` and still see
/// these types.
///
/// Runtime looms — `AlertDensityThrottle` and `AlertExplainer` — are
/// also surfaced as a category via `package:navigation_safety_core/
/// src/looms.dart` (added in 0.4.1). See `LOOMS.md` at the package
/// root for the runtime-loom catalog and 3-slot vision-attribution
/// cross-reference.
library;

export 'src/alert_density_throttle.dart';
export 'src/alert_explainer.dart';
export 'src/alert_severity.dart';
export 'src/driver_context.dart';
export 'src/driver_profile.dart';
export 'src/driver_state.dart';
export 'src/navigation_route.dart';
export 'src/navigation_safety_config.dart';
export 'src/navigation_safety_context.dart';
export 'src/road_surface_condition.dart';
export 'src/safety_scenario.dart';
export 'src/safety_score.dart';
export 'src/ux_differentiation.dart';
