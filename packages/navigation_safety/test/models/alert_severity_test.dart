/// AlertSeverity unit tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety_core.dart';

void main() {
  group('AlertSeverity', () {
    test('has exactly three values', () {
      expect(AlertSeverity.values, hasLength(3));
    });

    test('contains info warning critical', () {
      expect(
        AlertSeverity.values.map((value) => value.name),
        containsAll(['info', 'warning', 'critical']),
      );
    });
  });
}