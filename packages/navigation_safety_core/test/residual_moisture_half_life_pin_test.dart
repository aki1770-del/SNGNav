// The 90-minute residual-moisture half-life is a recorded decision; no
// source gives it. This test pins what the factory returns, so any change
// to that number is a visible, reviewed change and not a silent one.
//
// snowZoneExperienced baseline 200 m; margin = round(200 * 2^(-t/90)).
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  const cases = <int, int>{0: 400, 90: 300, 180: 250, 360: 213, 720: 201};
  cases.forEach((minutes, expected) {
    test('$minutes min after precipitation at 5 C: $expected m', () {
      final c = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: DrivingContext(
          timeSincePrecipitation: Duration(minutes: minutes),
          ambientTempCelsius: 5.0,
        ),
      );
      expect(c.warningVisibilityMeters, expected);
    });
  });
}
