/// Safety-focused navigation session and overlay package.
///
/// Re-exports the pure-Dart core (`navigation_safety_core`) for
/// back-compat — consumers that only need the model vocabulary
/// (severity, score, route, scenario, config) should depend on
/// `navigation_safety_core` directly to avoid the Flutter + BLoC +
/// widget dependency tree.
library;

// Pure-Dart core types (moved to navigation_safety_core in 0.6.0).
export 'package:navigation_safety_core/navigation_safety_core.dart';

// Flutter-dependent surface — BLoC + widgets.
export 'src/bloc/navigation_bloc.dart';
export 'src/bloc/navigation_event.dart';
export 'src/bloc/navigation_state.dart';
export 'src/widgets/safety_overlay.dart';
export 'src/widgets/alert_explainer_expandable_sheet.dart';

// Pure-Dart per-profile primitives (advisory; no actuator).
export 'src/modal_alert_duration.dart';
export 'src/glance_budget_tracker.dart';
