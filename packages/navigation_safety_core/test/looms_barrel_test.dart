/// Asserts the `lib/src/looms.dart` runtime-loom barrel re-exports
/// the expected runtime-loom symbols. This is a documentation-class
/// guard: if a future contributor renames a runtime loom or moves it
/// out of the barrel without updating `LOOMS.md`, this test fails
/// before the package publishes.
library;

import 'package:navigation_safety_core/src/looms.dart' as looms;
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('looms.dart barrel', () {
    test('re-exports AlertDensityThrottle', () {
      // Construct via the barrel-qualified name to verify the symbol
      // is actually re-exported and constructible through this path.
      final throttle = looms.AlertDensityThrottle.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      expect(throttle.alertsPerMinuteCap, 3.0);
      expect(throttle.bypassForCritical, isTrue);
    });

    test('re-exports AlertExplainer', () {
      final explainer = looms.AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.snowZoneExperienced,
      );
      expect(explainer.condition, RoadSurfaceCondition.ice);
      expect(explainer.localeTag, 'ja');
      expect(explainer.verbosity, looms.VerbosityLevel.brief);
    });

    test('barrel-qualified symbols are identical to package-barrel ones', () {
      // Same throttle constructed two ways must agree on cap.
      final viaBarrel = looms.AlertDensityThrottle.forProfile(
        DriverProfile.ageingRural,
      );
      final viaPackage = AlertDensityThrottle.forProfile(
        DriverProfile.ageingRural,
      );
      expect(viaBarrel.alertsPerMinuteCap, viaPackage.alertsPerMinuteCap);
    });
  });
}
