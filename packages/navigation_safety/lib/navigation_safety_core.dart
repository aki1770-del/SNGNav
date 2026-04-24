/// Pure Dart core exports — transitional compat shim.
///
/// As of navigation_safety 0.6.0 the pure-Dart models live in the
/// separate `navigation_safety_core` package (D-SC22-4 Pure Dart
/// boundary). Existing consumers of
/// `package:navigation_safety/navigation_safety_core.dart` keep
/// working via this re-export, but new code should import
/// `package:navigation_safety_core/navigation_safety_core.dart`
/// directly to avoid pulling in the Flutter + BLoC dependency tree.
library;

export 'package:navigation_safety_core/navigation_safety_core.dart';
