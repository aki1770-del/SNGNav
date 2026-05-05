/// Optional vehicle-class signal source for context-aware threshold tuning.
///
/// `VehicleClassProvider` is the integrator-supplied interface that
/// surfaces a stable vehicle-class token (e.g. `'kei-car'`,
/// `'compact-sedan'`, `'4wd'`, `'commercial-light'`) to the
/// `NavigationSafetyConfig.forProfileWithContext` factory. The token
/// is consumed via [DrivingContext.vehicleClassToken] and matched
/// against an optional [VehicleThresholdOverrides] registry; when a
/// match exists, the factory applies the registered caution-adding
/// override AFTER the per-profile baseline AND AFTER the live-context
/// adjustment.
///
/// This package does NOT prescribe a vehicle-class taxonomy at the
/// type system level. The integrator picks the tokens that best
/// describe the vehicle population they serve. Tokens are advisory
/// strings, NOT control inputs: returning `'kei-car'` does not change
/// vehicle behaviour, it only sharpens the threshold-tuning floor for
/// a known under-served cohort (e.g. HER kei-car-at-65 default).
///
/// **Driver-always-drives invariant** (load-bearing): the provider
/// returns advisory tokens consumed for threshold tuning. It does NOT
/// actuate the vehicle, NOT close a control loop, and NOT modulate
/// alert SEVERITY (severity remains coupled to road-condition class
/// per the existing severity-not-profile invariant).
///
/// **Caution-add-only invariant** (load-bearing): when a token is
/// matched against a [VehicleThresholdOverrides] registry, the
/// override may make thresholds warn EARLIER than the per-profile
/// baseline, NEVER later. The factory enforces this at runtime via a
/// debug-mode assertion.
///
/// **Null-as-absent convention**: returning `null` means the
/// integrator does not have a vehicle-class signal in this trip /
/// session. The factory falls back to the per-profile baseline for
/// the threshold-tuning floor (no override applied).
///
/// Typical wiring:
///
/// ```dart
/// class MyVehicleClassProvider implements VehicleClassProvider {
///   @override
///   String? get vehicleClassToken => myFleetVehicleClass; // e.g. 'kei-car'
/// }
///
/// final ctx = DrivingContext(
///   speedMps: 18.0,
///   vehicleClassToken: provider.vehicleClassToken,
/// );
/// final config = NavigationSafetyConfig.forProfileWithContext(
///   DriverProfile.ageingRural,
///   context: ctx,
///   vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
/// );
/// ```
library;

/// Integrator-supplied source of a stable vehicle-class token.
///
/// Implement this interface in the consuming app to surface the
/// vehicle-class signal (when known) to the threshold-config factory.
/// Return `null` when the integrator does not have a vehicle-class
/// signal; the factory falls back to the per-profile baseline.
///
/// Tokens are advisory strings, NOT control inputs. See class-level
/// documentation for the caution-add-only + severity-not-profile +
/// driver-always-drives invariants.
abstract class VehicleClassProvider {
  /// Returns a stable string token identifying the integrator's
  /// vehicle-class semantic (e.g. `'kei-car'`, `'compact-sedan'`,
  /// `'4wd'`, `'commercial-light'`). Return `null` when the
  /// integrator has no vehicle-class signal; thresholds fall back to
  /// the per-profile baseline.
  String? get vehicleClassToken;
}
