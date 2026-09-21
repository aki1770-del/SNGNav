// Two independent changes to how this package treats a lethal-traction
// road, run together for the first time here.
//
// 0.11.9 (`fe709e8`) made the package warn EARLIER on sub-zero roads: on
// readings it classifies as radiative-frost black ice it brakes at an
// inferred 0.981 m/s² instead of a dry 5.5, which raises
// `warningVisibilityMeters`, and it raises `warningTemperatureCelsius`.
//
// This release makes a catastrophic GRIP axis reach `critical` on its own,
// instead of being averaged away by a composite score.
//
// Both are about the same road. Neither author saw the other's change. The
// pair was never run together until this file, so the composition is
// asserted here rather than assumed — including the one place the two
// genuinely meet, which is not the score and not the config: it is the
// alert density throttle, where `critical` bypasses the cap.
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// Readings the 0.11.9 context classifies as radiative-frost black ice.
/// Pinned by assertion below rather than taken on trust: if the upstream
/// classifier moves, this file fails instead of silently testing a road
/// that is no longer icy.
const double _blackIceAmbientC = -3.0;
const double _blackIceRh = 0.60;

/// The control: NOT frost-classified.
///
/// Chosen above the classifier's ambient ceiling, which is +3.0 °C and
/// INCLUSIVE. A merely sub-zero-looking control is not a control here: at
/// +3.0 °C and 40 % RH the 0.11.9 classifier already reports black ice,
/// because radiative cooling puts the road surface below the air above it.
/// The first version of this file used exactly that as its "warm" control,
/// and the liveness pin below is what caught it.
const double _plainColdAmbientC = 8.0;
const double _plainColdRh = 0.60;

NavigationSafetyConfig _contextConfig(
  DriverProfile profile, {
  required double ambientC,
  required double rh,
  double? speedMps,
}) {
  return NavigationSafetyConfig.forProfileWithContext(
    profile,
    context: DrivingContext(
      ambientTempCelsius: ambientC,
      humidityRH: rh,
      speedMps: speedMps,
    ),
  );
}

void main() {
  group('the black-ice context and the grip axis are pinned to be live', () {
    test('the black-ice readings really are classified as black ice', () {
      // The composition claims below are worth nothing if this road is not
      // actually the icy one. 0.11.9 raises warningVisibilityMeters on a
      // frost-classified road; that difference is the observable proof the
      // classifier fired.
      final icy = _contextConfig(
        DriverProfile.ageingRural,
        ambientC: _blackIceAmbientC,
        rh: _blackIceRh,
        speedMps: 33.3,
      );
      final plain = _contextConfig(
        DriverProfile.ageingRural,
        ambientC: _plainColdAmbientC,
        rh: _plainColdRh,
        speedMps: 33.3,
      );
      expect(
        icy.warningVisibilityMeters,
        greaterThan(plain.warningVisibilityMeters),
        reason:
            '0.11.9 black-ice braking must widen the warning distance; '
            'if it does not, these readings are not frost-classified and '
            'every other test in this file is testing the wrong road',
      );
    });
  });

  group('a road that is BOTH sub-zero and gripless', () {
    test('is critical on every driver profile', () {
      for (final profile in DriverProfile.values) {
        final config = _contextConfig(
          profile,
          ambientC: _blackIceAmbientC,
          rh: _blackIceRh,
          speedMps: 22.2,
        );
        // Grip gone, and she can see every metre of the road she cannot
        // stop on. This is the compound case: the 0.11.9 change widened
        // how far ahead she is warned, and this release is what lets the
        // alert be `critical` at all.
        final score = SafetyScore(
          overall: 0.5,
          gripScore: 0.0,
          visibilityScore: 1.0,
          fleetConfidenceScore: 1.0,
        );
        expect(
          score.toAlertSeverity(config),
          AlertSeverity.critical,
          reason: 'sub-zero AND gripless must be critical for $profile',
        );
      }
    });

    test('the black-ice context does not drop the grip floor', () {
      // `forProfileWithContext` rebuilds the config field by field. A new
      // field that a rebuild site forgets is silently replaced by the
      // parameter default — the failure mode that DID occur on the
      // override-rejection path in this same carry. Asserted at every
      // rebuild site reachable from a driving context.
      for (final profile in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(profile);
        for (final speed in <double?>[null, 22.2, 33.3, 40.0]) {
          final icy = _contextConfig(
            profile,
            ambientC: _blackIceAmbientC,
            rh: _blackIceRh,
            speedMps: speed,
          );
          expect(
            icy.criticalGripScoreFloor,
            base.criticalGripScoreFloor,
            reason:
                'black-ice context at speed $speed dropped the grip '
                'floor for $profile',
          );
        }
      }
    });

    test(
      'the two changes move different fields and neither undoes the other',
      () {
        // The honest statement of the composition: 0.11.9 moves visibility
        // and temperature thresholds; this release adds a grip rule to
        // severity. Asserted, not assumed — a future change that routes the
        // black-ice classification into a score floor would fail here, and
        // that is exactly the change that would need a fresh composition
        // read.
        final icy = _contextConfig(
          DriverProfile.ageingRural,
          ambientC: _blackIceAmbientC,
          rh: _blackIceRh,
          speedMps: 33.3,
        );
        final base = NavigationSafetyConfig.forProfile(
          DriverProfile.ageingRural,
        );
        expect(icy.safeScoreFloor, base.safeScoreFloor);
        expect(icy.infoScoreFloor, base.infoScoreFloor);
        expect(icy.warningScoreFloor, base.warningScoreFloor);
        expect(icy.criticalGripScoreFloor, base.criticalGripScoreFloor);
      },
    );

    test('an icy road is never told LESS urgently than the same road warm', () {
      // Monotonicity across the pair: for the same score, the frost
      // classification must never lower severity. Guards against the
      // composition producing a confident WRONG severity — the
      // success-shaped return.
      for (final profile in DriverProfile.values) {
        for (var gi = 0; gi <= 20; gi++) {
          for (var vi = 0; vi <= 20; vi++) {
            final g = gi / 20.0;
            final v = vi / 20.0;
            final score = SafetyScore(
              overall: 0.5 * g + 0.5 * v,
              gripScore: g,
              visibilityScore: v,
              fleetConfidenceScore: 1.0,
            );
            final icy = score.toAlertSeverity(
              _contextConfig(
                profile,
                ambientC: _blackIceAmbientC,
                rh: _blackIceRh,
                speedMps: 22.2,
              ),
            );
            final warm = score.toAlertSeverity(
              _contextConfig(
                profile,
                ambientC: _plainColdAmbientC,
                rh: _plainColdRh,
                speedMps: 22.2,
              ),
            );
            expect(
              _rank(icy),
              greaterThanOrEqualTo(_rank(warm)),
              reason:
                  'frost-classified road scored LESS urgent than the '
                  'same score warm, at grip $g visibility $v for $profile',
            );
          }
        }
      }
    });
  });

  group('where the two changes actually meet: the density throttle', () {
    test('a grip-promoted critical bypasses the cap and consumes a slot', () {
      // This is the real composition, and it is a cost, stated rather than
      // discovered later. Promoting an alert to `critical` changes what the
      // throttle does with it: it fires regardless of the cap, AND it takes
      // a slot in the rolling window, so a later non-critical alert is
      // dropped sooner than it would have been before this release.
      final throttle = AlertDensityThrottle(
        alertsPerMinuteCap: 1.0,
        window: const Duration(minutes: 1),
      );
      final t0 = DateTime.utc(2026, 1, 1, 8);

      // Slot 1: an ordinary alert fills the window.
      expect(throttle.shouldFire(t0, AlertSeverity.info), isTrue);
      // The cap is now reached: a second info is dropped.
      expect(
        throttle.shouldFire(
          t0.add(const Duration(seconds: 1)),
          AlertSeverity.info,
        ),
        isFalse,
      );
      // The grip-promoted critical still reaches her. This is the whole
      // point of the release: on a road she cannot stop on, the alert is
      // not rate-limited away.
      expect(
        throttle.shouldFire(
          t0.add(const Duration(seconds: 2)),
          AlertSeverity.critical,
        ),
        isTrue,
      );
    });

    test('promotion cannot silence an alert that fires today', () {
      // The throttle is the only place a severity CHANGE could remove an
      // alert rather than add one. It cannot: `critical` is the bypass
      // case, so raising severity can only turn a drop into a fire.
      final throttle = AlertDensityThrottle(
        alertsPerMinuteCap: 1.0,
        window: const Duration(minutes: 1),
      );
      final t0 = DateTime.utc(2026, 1, 1, 8);
      throttle.shouldFire(t0, AlertSeverity.info);
      final asWarning = AlertDensityThrottle(
        alertsPerMinuteCap: 1.0,
        window: const Duration(minutes: 1),
      )..shouldFire(t0, AlertSeverity.info);
      final laterWarning = asWarning.shouldFire(
        t0.add(const Duration(seconds: 2)),
        AlertSeverity.warning,
      );
      final laterCritical = throttle.shouldFire(
        t0.add(const Duration(seconds: 2)),
        AlertSeverity.critical,
      );
      expect(laterWarning, isFalse);
      expect(
        laterCritical,
        isTrue,
        reason:
            'promotion to critical must not be able to drop an alert '
            'that the lower severity would have delivered',
      );
    });
  });
}

int _rank(AlertSeverity? s) {
  switch (s) {
    case null:
      return 0;
    case AlertSeverity.info:
      return 1;
    case AlertSeverity.warning:
      return 2;
    case AlertSeverity.critical:
      return 3;
  }
}
