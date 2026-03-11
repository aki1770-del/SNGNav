import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';

void main() {
  testWidgets('Snow Scene package resolves correctly',
      (WidgetTester tester) async {
    // Verify the package is importable and models work.
    // Full widget tests come in Day 5+ when UI widgets are built.
    final pos = GeoPosition(
      latitude: 35.1709,
      longitude: 136.8815,
      accuracy: 5.0,
      timestamp: DateTime(2026, 2, 27),
    );
    expect(pos.isNavigationGrade, isTrue);
  });
}
