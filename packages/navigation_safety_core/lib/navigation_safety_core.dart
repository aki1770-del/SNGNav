/// Pure Dart core models for navigation safety.
///
/// These types live outside `navigation_safety` so that pure-Dart
/// consumers (e.g. `driving_conditions`) can depend on the vocabulary
/// without inheriting `navigation_safety`'s Flutter + BLoC + widget
/// dependency tree.
///
/// The full `navigation_safety` package re-exports everything here
/// for back-compat, so consumers that don't care about the Pure Dart
/// boundary can keep importing
/// `package:navigation_safety/navigation_safety.dart` and still see
/// these types.
///
/// Runtime looms — `AlertDensityThrottle` and `AlertExplainer` — are
/// also surfaced as a category via `package:navigation_safety_core/
/// src/looms.dart` (added in 0.4.1). A *loom*, in this package, is a
/// single guard that catches one named failure mode.
library;

// Calibration primitives now live in the standalone
// `navigation_safety_calibration` package (the single source of truth
// for the meteorological / kinematic design-default baseline). Core
// depends on it and re-exports it here so existing consumers keep
// seeing these symbols via `package:navigation_safety_core` — the
// depend-on + re-export design the calibration package's own docs
// anticipated (0.11.0; replaces core's former internal byte-copy).
export 'package:navigation_safety_calibration/navigation_safety_calibration.dart';

export 'src/alert_density_throttle.dart';
export 'src/alert_explainer.dart';
export 'src/alert_severity.dart';
export 'src/circadian_phase.dart';
export 'src/confidence_provider.dart';
export 'src/driver_context.dart';
export 'src/driver_profile.dart';
export 'src/driver_state.dart';
export 'src/loom_fit_telemetry.dart';
export 'src/navigation_route.dart';
export 'src/navigation_safety_config.dart';
export 'src/navigation_safety_context.dart';
export 'src/road_surface_condition.dart';
export 'src/safety_scenario.dart';
export 'src/safety_score.dart';
export 'src/session_state_provider.dart';
export 'src/ux_differentiation.dart';
export 'src/vehicle_class_provider.dart';
export 'src/vehicle_threshold_overrides.dart';
