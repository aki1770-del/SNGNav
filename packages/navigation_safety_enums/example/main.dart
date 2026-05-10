// Minimal example for navigation_safety_enums.
//
// Demonstrates the four domain-vocabulary enums the package re-exports:
// AlertSeverity / CircadianPhase / DriverState / DriverProfile.

import 'package:navigation_safety_enums/navigation_safety_enums.dart';

void main() {
  print(
    'AlertSeverity values: ${AlertSeverity.values.map((v) => v.name).toList()}',
  );
  print(
    'CircadianPhase values: ${CircadianPhase.values.map((v) => v.name).toList()}',
  );
  print(
    'DriverState values: ${DriverState.values.map((v) => v.name).toList()}',
  );
  print(
    'DriverProfile values: ${DriverProfile.values.map((v) => v.name).toList()}',
  );

  // Severity ordering is load-bearing — declaration order is monotonic.
  assert(AlertSeverity.info.index < AlertSeverity.warning.index);
  assert(AlertSeverity.warning.index < AlertSeverity.critical.index);
  print('AlertSeverity declaration-order monotonicity: OK');
}
