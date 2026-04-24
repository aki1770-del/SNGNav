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
library;

export 'src/alert_severity.dart';
export 'src/navigation_route.dart';
export 'src/navigation_safety_config.dart';
export 'src/safety_scenario.dart';
export 'src/safety_score.dart';
