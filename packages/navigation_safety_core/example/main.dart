// Example: navigation_safety_core
//
// A runnable, Pure-Dart walkthrough of the public API surface:
//
//   1. NavigationSafetyConfig.forProfile         — driver-class baseline
//   2. NavigationSafetyConfig.forProfileWithContext
//                                                — adds live driving conditions
//   3. NavigationSafetyConfig.forDriverContext   — adds live driver state
//   4. AlertDensityThrottle                      — per-profile alerts/min cap
//   5. AlertExplainer                            — per-(condition, profile) text
//
// No Flutter dependency. Run with: `dart run example/main.dart`.

import 'package:navigation_safety_core/navigation_safety_core.dart';

void main() {
  print('--- navigation_safety_core: example/main.dart ---\n');

  _showProfileBaseline();
  _showProfileWithContext();
  _showProfileWithDriverState();
  _showAlertDensityThrottle();
  _showAlertExplainer();
  _showSeverityIsLoadBearing();
}

/// 1. Driver-class baseline: pick a profile, get tuned thresholds.
void _showProfileBaseline() {
  print('[1] forProfile — driver-class baseline');

  final novice = NavigationSafetyConfig.forProfile(DriverProfile.noviceUrban);
  final tourist = NavigationSafetyConfig.forProfile(
    DriverProfile.foreignTouristSnowZone,
  );

  print(
    '  noviceUrban warning visibility:           '
    '${novice.warningVisibilityMeters} m',
  );
  print(
    '  foreignTouristSnowZone warning visibility: '
    '${tourist.warningVisibilityMeters} m   '
    '(more conservative)',
  );
  print(
    '  noviceUrban warning temperature:           '
    '${novice.warningTemperatureCelsius} C',
  );
  print('');
}

/// 2. Profile + live driving context: speed, humidity, time-since-rain.
///
/// Each context input can only make thresholds more conservative
/// (warn earlier, never later) than the per-profile baseline.
void _showProfileWithContext() {
  print('[2] forProfileWithContext — adds live conditions');

  // 80 km/h ≈ 22.2 m/s; 92% RH; ambient 1°C; rain ended 30 min ago.
  const conditions = DrivingContext(
    speedMps: 22.2,
    humidityRH: 0.92,
    ambientTempCelsius: 1.0,
    timeSincePrecipitation: Duration(minutes: 30),
  );

  final base = NavigationSafetyConfig.forProfile(
    DriverProfile.snowZoneExperienced,
  );
  final tuned = NavigationSafetyConfig.forProfileWithContext(
    DriverProfile.snowZoneExperienced,
    context: conditions,
  );

  print(
    '  baseline warning visibility:    '
    '${base.warningVisibilityMeters} m',
  );
  print(
    '  context-tuned warning visibility: '
    '${tuned.warningVisibilityMeters} m   '
    '(speed + recent-rain margin)',
  );
  print(
    '  baseline warning temperature:     '
    '${base.warningTemperatureCelsius} C',
  );
  print(
    '  context-tuned warning temperature: '
    '${tuned.warningTemperatureCelsius} C   '
    '(humidity-aware black-ice margin)',
  );
  print('');
}

/// 3. Profile + live driver state (fatigued / distracted / impaired vision).
///
/// State is opt-in via DriverContext. Pass profile-only to the older
/// factories and behaviour is unchanged.
void _showProfileWithDriverState() {
  print('[3] forDriverContext — adds live driver state');

  final alert = NavigationSafetyConfig.forDriverContext(
    const DriverContext(
      profile: DriverProfile.snowZoneExperienced,
      state: DriverState.alert,
    ),
  );
  final fatigued = NavigationSafetyConfig.forDriverContext(
    const DriverContext(
      profile: DriverProfile.snowZoneExperienced,
      state: DriverState.fatigued,
    ),
    environmentalContext: const DrivingContext(speedMps: 22.2),
  );

  print(
    '  alert state warning visibility:    '
    '${alert.warningVisibilityMeters} m',
  );
  print(
    '  fatigued state warning visibility: '
    '${fatigued.warningVisibilityMeters} m   '
    '(reaction-time penalty applied)',
  );
  print(
    '  alert state warning temperature:    '
    '${alert.warningTemperatureCelsius} C',
  );
  print(
    '  fatigued state warning temperature: '
    '${fatigued.warningTemperatureCelsius} C   '
    '(small additive lift)',
  );
  print('');
}

/// 4. Alert-density throttle: cap advisory alerts/min per profile.
///
/// Critical alerts always fire (safety invariant). Info and warning
/// alerts are gated by the profile's alerts/min cap so the driver
/// is not desensitised by over-warning.
void _showAlertDensityThrottle() {
  print('[4] AlertDensityThrottle — per-profile alerts/min cap');

  final throttle = AlertDensityThrottle.forProfile(DriverProfile.noviceUrban);
  print('  noviceUrban cap:   ${throttle.alertsPerMinuteCap} / min');

  final base = DateTime(2026, 1, 1, 8, 0, 0);
  final fire1 = throttle.shouldFire(base, AlertSeverity.info);
  final fire2 = throttle.shouldFire(
    base.add(const Duration(seconds: 10)),
    AlertSeverity.warning,
  );
  final fire3 = throttle.shouldFire(
    base.add(const Duration(seconds: 20)),
    AlertSeverity.warning,
  );
  final fire4 = throttle.shouldFire(
    base.add(const Duration(seconds: 25)),
    AlertSeverity.critical,
  );

  print('  alert 1 (info)     -> fire? $fire1   (cold-start always fires)');
  print('  alert 2 (warning)  -> fire? $fire2');
  print('  alert 3 (warning)  -> fire? $fire3   (cap reached -> dropped)');
  print('  alert 4 (critical) -> fire? $fire4   (criticals bypass cap)');
  print('');
}

/// 5. Alert explainer: pre-localised (condition, action) tuple per profile.
///
/// The factory picks verbosity (terse / brief / standard / full) and
/// locale (ja / en) for the active profile.
void _showAlertExplainer() {
  print('[5] AlertExplainer — action-coupled per-(condition, profile)');

  for (final profile in [
    DriverProfile.professional,
    DriverProfile.snowZoneExperienced,
    DriverProfile.noviceUrban,
    DriverProfile.foreignTouristSnowZone,
  ]) {
    final explainer = AlertExplainer.forConditionAndProfile(
      RoadSurfaceCondition.ice,
      profile,
    );
    print(
      '  ${profile.name.padRight(24)} '
      '(${explainer.localeTag} / ${explainer.verbosity.name})',
    );
    print('    -> ${explainer.action}');
  }
  print('');
}

/// 6. Severity ordering is load-bearing — declaration order matters.
///
/// Callers can compare `.index` to enforce monotonic upgrades: a
/// lower-severity alert must never replace a higher one already
/// shown to the driver.
void _showSeverityIsLoadBearing() {
  print('[6] AlertSeverity — declaration order is load-bearing');

  print('  info.index     = ${AlertSeverity.info.index}');
  print('  warning.index  = ${AlertSeverity.warning.index}');
  print('  critical.index = ${AlertSeverity.critical.index}');
  print(
    '  monotonic upgrade rule: '
    'never replace higher with lower (compare .index).',
  );
  print('');
}
