/// Threshold configuration for score and environmental safety posture.
library;

import 'package:equatable/equatable.dart';

import 'driver_profile.dart';

class NavigationSafetyConfig extends Equatable {
  final double safeScoreFloor;
  final double infoScoreFloor;
  final double warningScoreFloor;

  final int infoTemperatureCelsius;
  final int warningTemperatureCelsius;
  final int criticalTemperatureCelsius;

  final int infoVisibilityMeters;
  final int warningVisibilityMeters;
  final int criticalVisibilityMeters;

  /// Build a config with thresholds tuned to a [DriverProfile].
  ///
  /// See `driver_profile.dart` for profile semantics. Use this factory
  /// when the consuming app knows the driver-class; falls back to
  /// [DriverProfile.snowZoneExperienced] (the historical defaults) for
  /// any profile whose tuning isn't more conservative or more permissive.
  ///
  /// Returns the same shape as the default constructor — callers can
  /// further override any threshold via `copyWith`-style construction
  /// once they have a profile-derived baseline.
  factory NavigationSafetyConfig.forProfile(DriverProfile profile) {
    switch (profile) {
      case DriverProfile.ageingRural:
        // More conservative: warn earlier on weather + visibility;
        // require higher score for "safe". 70+ drivers have slower
        // reaction time + may be EV-novice; the loom shifts caution.
        return NavigationSafetyConfig(
          safeScoreFloor: 0.85,
          infoScoreFloor: 0.55,
          warningScoreFloor: 0.35,
          infoTemperatureCelsius: 5,
          warningTemperatureCelsius: 1,
          criticalTemperatureCelsius: -3,
          infoVisibilityMeters: 1500,
          warningVisibilityMeters: 300,
          criticalVisibilityMeters: 80,
        );
      case DriverProfile.snowZoneExperienced:
        // Standard defaults. The loom trusts the experienced
        // snow-zone driver's interpretation of standard warnings.
        return NavigationSafetyConfig();
      case DriverProfile.noviceUrban:
        // Warn earlier on visibility (low low-visibility experience),
        // higher safe-score floor. Threshold-only shift; explainer
        // surfaces live in the consuming Flutter UX layer.
        return NavigationSafetyConfig(
          safeScoreFloor: 0.85,
          infoScoreFloor: 0.55,
          warningScoreFloor: 0.32,
          infoTemperatureCelsius: 4,
          warningTemperatureCelsius: 0,
          criticalTemperatureCelsius: -5,
          infoVisibilityMeters: 1500,
          warningVisibilityMeters: 250,
          criticalVisibilityMeters: 60,
        );
      case DriverProfile.professional:
        // Trained drivers — thresholds near standard; minimum-distraction
        // optimization happens in the Flutter UX layer (voice
        // brevity, modal-alert duration), not in the core thresholds.
        return NavigationSafetyConfig();
      case DriverProfile.agriculturalForestry:
        // Off-road semantics belong to a future revision (don't alert
        // "off route" on forest tracks). Today: same threshold defaults
        // as snowZoneExperienced; the off-route semantic extension is
        // a downstream package's job.
        return NavigationSafetyConfig();
    }
  }

  NavigationSafetyConfig({
    this.safeScoreFloor = 0.80,
    this.infoScoreFloor = 0.50,
    this.warningScoreFloor = 0.30,
    this.infoTemperatureCelsius = 3,
    this.warningTemperatureCelsius = 0,
    this.criticalTemperatureCelsius = -5,
    this.infoVisibilityMeters = 1000,
    this.warningVisibilityMeters = 200,
    this.criticalVisibilityMeters = 50,
  }) {
    if (safeScoreFloor < 0 || safeScoreFloor > 1) {
      throw RangeError.range(safeScoreFloor, 0, 1, 'safeScoreFloor');
    }
    if (infoScoreFloor < 0 || infoScoreFloor > 1) {
      throw RangeError.range(infoScoreFloor, 0, 1, 'infoScoreFloor');
    }
    if (warningScoreFloor < 0 || warningScoreFloor > 1) {
      throw RangeError.range(warningScoreFloor, 0, 1, 'warningScoreFloor');
    }
    if (safeScoreFloor < infoScoreFloor) {
      throw ArgumentError(
        'safeScoreFloor ($safeScoreFloor) must be >= infoScoreFloor ($infoScoreFloor)',
      );
    }
    if (infoScoreFloor < warningScoreFloor) {
      throw ArgumentError(
        'infoScoreFloor ($infoScoreFloor) must be >= warningScoreFloor ($warningScoreFloor)',
      );
    }
  }

  @override
  List<Object?> get props => [
        safeScoreFloor,
        infoScoreFloor,
        warningScoreFloor,
        infoTemperatureCelsius,
        warningTemperatureCelsius,
        criticalTemperatureCelsius,
        infoVisibilityMeters,
        warningVisibilityMeters,
        criticalVisibilityMeters,
      ];
}
