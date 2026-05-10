import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

class _StaticVehicleClassProvider implements VehicleClassProvider {
  const _StaticVehicleClassProvider(this._token);
  final String? _token;
  @override
  String? get vehicleClassToken => _token;
}

void main() {
  group('VehicleClassProvider', () {
    test('contract: returning a non-null token surfaces it verbatim', () {
      const provider = _StaticVehicleClassProvider('kei-car');
      expect(provider.vehicleClassToken, 'kei-car');
    });

    test('contract: returning null is the absent-signal convention', () {
      const provider = _StaticVehicleClassProvider(null);
      expect(provider.vehicleClassToken, isNull);
    });

    test('null-token routed through DrivingContext falls back to baseline', () {
      const provider = _StaticVehicleClassProvider(null);
      final base = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: DrivingContext(vehicleClassToken: provider.vehicleClassToken),
        vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
      );
      final raw = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      // Null token => no override applied; warning thresholds match
      // the per-profile baseline.
      expect(base.warningVisibilityMeters, raw.warningVisibilityMeters);
      expect(base.warningTemperatureCelsius, raw.warningTemperatureCelsius);
    });

    test('arbitrary token values are accepted (no taxonomy enforcement)', () {
      // The package does NOT prescribe a vehicle-class taxonomy at the
      // type system level. Any string is a valid token; the registry
      // determines whether an override applies.
      const provider = _StaticVehicleClassProvider(
        'integrator-defined-token-xyz',
      );
      expect(provider.vehicleClassToken, 'integrator-defined-token-xyz');
    });
  });
}
