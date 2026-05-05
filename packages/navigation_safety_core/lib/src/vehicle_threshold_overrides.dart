/// Vehicle-class threshold-override registry for caution-adding-only
/// adjustments to per-profile baseline thresholds.
///
/// `VehicleThresholdOverrides` is an integrator-supplied registry of
/// vehicle-class-token → threshold-transform-function mappings. It is
/// passed (optionally) to
/// [NavigationSafetyConfig.forProfileWithContext]. When the
/// [DrivingContext.vehicleClassToken] field matches a registered key,
/// the registered transform applies to the baseline-plus-context
/// threshold config produced by the factory's earlier stages.
///
/// **Caution-add-only invariant** (load-bearing): a registered
/// transform MUST produce a config whose `warningVisibilityMeters` is
/// `>=` the input baseline AND whose `warningTemperatureCelsius` is
/// `>=` the input baseline. (Both fields use the convention that
/// HIGHER values mean EARLIER warning — a longer visibility floor and
/// a higher temperature floor each fire the warning sooner.)
/// Registering a transform that relaxes either threshold is a
/// programmer error. The factory enforces this at runtime via a
/// debug-mode assertion in [applyOverrideForToken]; in release builds
/// the assertion is elided per Dart's `assert` semantics.
///
/// **Severity-not-profile invariant** (load-bearing): vehicle-class
/// adjustments tune TIMING (warn-earlier-floors) only. They MUST NOT
/// modify the score-floor tiers (`safeScoreFloor`, `infoScoreFloor`,
/// `warningScoreFloor`), the critical thresholds, or the
/// alerts-per-minute cap override. The runtime assertion in
/// [applyOverrideForToken] checks score-floor preservation explicitly.
///
/// **HER kei-car-at-65 cohort default**: the [withKeiCarDefault]
/// factory ships a built-in override for the `'kei-car'` token. The
/// override raises `warningVisibilityMeters` by `+50m` and
/// `warningTemperatureCelsius` by `+1°C` relative to the input
/// baseline. The deltas are **design-default hypotheses** pending
/// field-measurement validation (kei-car-specific visibility and
/// thermal-mass calibration not yet anchored in published literature
/// at the vehicle-class layer specifically; flagged in
/// `CHANGELOG.md` 0.9.0 entry).
///
/// Typical wiring:
///
/// ```dart
/// // Use the built-in kei-car default:
/// final overrides = VehicleThresholdOverrides.withKeiCarDefault();
///
/// // Or compose a custom registry. The transform receives the
/// // baseline config and returns a new config (no mutation):
/// final overrides = VehicleThresholdOverrides({
///   'commercial-light': (base) => NavigationSafetyConfig(
///         safeScoreFloor: base.safeScoreFloor,
///         infoScoreFloor: base.infoScoreFloor,
///         warningScoreFloor: base.warningScoreFloor,
///         infoTemperatureCelsius: base.infoTemperatureCelsius,
///         warningTemperatureCelsius: base.warningTemperatureCelsius,
///         criticalTemperatureCelsius: base.criticalTemperatureCelsius,
///         infoVisibilityMeters: base.infoVisibilityMeters,
///         warningVisibilityMeters: base.warningVisibilityMeters + 30,
///         criticalVisibilityMeters: base.criticalVisibilityMeters,
///         alertsPerMinuteCapOverride: base.alertsPerMinuteCapOverride,
///       ),
/// });
/// ```
library;

import 'navigation_safety_config.dart';

/// Registry of vehicle-class-token → threshold-transform-function
/// mappings consumed by
/// [NavigationSafetyConfig.forProfileWithContext]. See library
/// documentation for the caution-add-only invariant and the
/// HER kei-car-at-65 cohort default.
class VehicleThresholdOverrides {
  /// Map of vehicle-class token (e.g. `'kei-car'`) to a function that
  /// produces a caution-adding-only override of the supplied baseline
  /// config.
  ///
  /// The function receives the per-profile-baseline config (post
  /// live-context adjustment) and MUST return a config whose
  /// `warningVisibilityMeters` and `warningTemperatureCelsius` are
  /// both `>=` the baseline. Score-floor tiers and the critical
  /// thresholds MUST be preserved.
  final Map<String, NavigationSafetyConfig Function(NavigationSafetyConfig baseline)>
      overrides;

  const VehicleThresholdOverrides(this.overrides);

  /// Construct a registry pre-loaded with the HER kei-car-at-65
  /// cohort default override. The default keys on the `'kei-car'`
  /// token and applies caution-adding-only deltas:
  ///
  /// - `warningVisibilityMeters` += 50m (kei-car windscreen +
  ///   headlight cluster smaller than compact-sedan baseline; warn
  ///   earlier on visibility loss to preserve reaction-margin)
  /// - `warningTemperatureCelsius` += 1°C (kei-car cabin lower
  ///   thermal mass + faster glass condensation in winter; warn
  ///   earlier on cold-temperature transitions)
  ///
  /// Both deltas are **design-default hypotheses** pending
  /// field-measurement validation; see `CHANGELOG.md` 0.9.0 entry
  /// for the UNVERIFIED-magnitude flag and the
  /// kei-car-class-calibration-validation follow-up note.
  ///
  /// To compose with additional integrator-defined overrides, build
  /// the registry directly via the default constructor and merge.
  factory VehicleThresholdOverrides.withKeiCarDefault() {
    return VehicleThresholdOverrides({
      'kei-car': _keiCarOverride,
    });
  }

  /// Apply the override registered for [token] to [baseline], or
  /// return [baseline] unchanged if [token] is `null` or unregistered.
  ///
  /// Enforces the caution-add-only invariant in debug builds via
  /// [assert]; the assertion is elided in release builds per Dart's
  /// `assert` semantics, but a relaxing override remains a programmer
  /// error and is detectable via [vehicle_threshold_overrides_test.dart].
  NavigationSafetyConfig applyOverrideForToken(
    String? token,
    NavigationSafetyConfig baseline,
  ) {
    if (token == null) return baseline;
    final transform = overrides[token];
    if (transform == null) return baseline;
    final adjusted = transform(baseline);

    // Caution-add-only invariant: warning thresholds may only move
    // toward earlier-warn (higher visibility floor, higher
    // temperature floor). Lower values mean later-warn = relaxing.
    assert(
      adjusted.warningVisibilityMeters >= baseline.warningVisibilityMeters,
      'VehicleThresholdOverrides for token "$token" relaxed '
      'warningVisibilityMeters '
      '(${baseline.warningVisibilityMeters} -> '
      '${adjusted.warningVisibilityMeters}); caution-add-only '
      'invariant violated.',
    );
    assert(
      adjusted.warningTemperatureCelsius >= baseline.warningTemperatureCelsius,
      'VehicleThresholdOverrides for token "$token" relaxed '
      'warningTemperatureCelsius '
      '(${baseline.warningTemperatureCelsius} -> '
      '${adjusted.warningTemperatureCelsius}); caution-add-only '
      'invariant violated.',
    );

    // Severity-not-profile invariant: vehicle-class adjusts TIMING,
    // never SEVERITY tiers. Score floors MUST be preserved.
    assert(
      adjusted.safeScoreFloor == baseline.safeScoreFloor,
      'VehicleThresholdOverrides for token "$token" modified '
      'safeScoreFloor; severity-not-profile invariant violated.',
    );
    assert(
      adjusted.infoScoreFloor == baseline.infoScoreFloor,
      'VehicleThresholdOverrides for token "$token" modified '
      'infoScoreFloor; severity-not-profile invariant violated.',
    );
    assert(
      adjusted.warningScoreFloor == baseline.warningScoreFloor,
      'VehicleThresholdOverrides for token "$token" modified '
      'warningScoreFloor; severity-not-profile invariant violated.',
    );

    return adjusted;
  }

  /// Built-in HER kei-car-at-65 default override. See
  /// [VehicleThresholdOverrides.withKeiCarDefault] for delta semantics
  /// and the design-default-hypothesis flag.
  static NavigationSafetyConfig _keiCarOverride(
    NavigationSafetyConfig baseline,
  ) {
    return NavigationSafetyConfig(
      safeScoreFloor: baseline.safeScoreFloor,
      infoScoreFloor: baseline.infoScoreFloor,
      warningScoreFloor: baseline.warningScoreFloor,
      infoTemperatureCelsius: baseline.infoTemperatureCelsius,
      warningTemperatureCelsius: baseline.warningTemperatureCelsius + 1,
      criticalTemperatureCelsius: baseline.criticalTemperatureCelsius,
      infoVisibilityMeters: baseline.infoVisibilityMeters,
      warningVisibilityMeters: baseline.warningVisibilityMeters + 50,
      criticalVisibilityMeters: baseline.criticalVisibilityMeters,
      alertsPerMinuteCapOverride: baseline.alertsPerMinuteCapOverride,
    );
  }
}
