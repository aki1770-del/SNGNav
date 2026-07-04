/// Humidity-aware black-ice (radiative frost) — the no-precipitation killer.
///
/// Every numeric pin below is PROBE-MEASURED against the calibration package
/// (Magnus, a=17.625 b=243.04), not assumed:
///   95% RH @ 0.5 °C → effective −0.21 → frost fires
///   95% RH @ 1.0 °C → effective +0.29 → no fire
///   95% RH @ 2.0 °C → effective +1.28 → no fire
///   60% RH @ 1.0 °C → effective −5.90 → frost fires
///   40% RH @ 5.0 °C → effective −7.50 → frost fires (deliberately
///     conservative: dry air has a deep dew-point depression, so the
///     surface estimate dives — the calibration's documented early-warning
///     stance; this test records that behavior OPENLY rather than hiding it)
///   99% RH @ 0.2 °C → effective +0.06 → no fire (near-saturated air keeps
///     the surface estimate at ambient, which is above zero)
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  const advisor = SnowAwarePretripAdvisor();
  final at = DateTime(2026, 1, 15, 6); // an Akita winter pre-dawn hour

  HourlyForecast slot({required double temp, double? rh}) => HourlyForecast(
        hour: at,
        tempCelsius: temp,
        humidityRH: rh,
      );

  group('radiativeFrostRisk — probe-measured Magnus pins', () {
    test('fires in the above-zero-ambient black-ice window', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 95)), isTrue);
      expect(advisor.radiativeFrostRisk(slot(temp: 1.0, rh: 60)), isTrue);
    });

    test('does not fire when the surface estimate stays above freezing', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 1.0, rh: 95)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 2.0, rh: 95)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 0.2, rh: 99)), isFalse);
    });

    test('dry air fires early — the documented conservative stance', () {
      // 40% RH @ 5.0 °C → dew-point depression ≈ 12.5 → effective −7.50.
      // The calibration is deliberately early-warning (UNVERIFIED surface
      // magnitude, conservative direction); recorded openly, not hidden.
      expect(advisor.radiativeFrostRisk(slot(temp: 5.0, rh: 40)), isTrue);
    });

    test('absence or dirty data is never presence of hazard', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5)), isFalse,
          reason: 'null humidity adds nothing');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 0.0)), isFalse,
          reason: '0.0 is the missing-data sentinel');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: -5.0)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 120.0)), isFalse,
          reason: 'implausible reading adds nothing (feed bug, not hazard)');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: double.nan)),
          isFalse);
    });

    test('supersaturation reads as saturated air (percent-door semantics)', () {
      // 100 < RH <= 105 → fraction 1.0 → depression 0 → effective == ambient.
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 101.0)), isFalse,
          reason: 'saturated air at +0.5 ambient: surface estimate +0.5 > 0');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.0, rh: 101.0)), isTrue,
          reason: 'saturated air at 0.0 ambient: surface estimate 0.0 <= 0');
    });
  });

  group('hazardOf — the caution band gains the black-ice window', () {
    test('STRICT: above-zero ambient + humidity crossing → caution '
        '(deleting the radiative-frost condition fails this test)', () {
      // Ambient 0.5 > frost threshold 0.0, no precip, no visibility issue —
      // every pre-existing condition is silent; only the new check fires.
      expect(advisor.hazardOf(slot(temp: 0.5, rh: 95)), HourHazard.caution);
    });

    test('caution-add-only: without humidity the same slot stays clear', () {
      expect(advisor.hazardOf(slot(temp: 0.5)), HourHazard.clear);
    });

    test('never lowers an existing band', () {
      // Ambient at/below frost already cautions; humidity must not change it.
      expect(advisor.hazardOf(slot(temp: -1.0, rh: 95)), HourHazard.caution);
      expect(advisor.hazardOf(slot(temp: -1.0)), HourHazard.caution);
      // A severe condition stays severe.
      final severe = HourlyForecast(
        hour: at,
        tempCelsius: 0.5,
        humidityRH: 95,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      );
      expect(advisor.hazardOf(severe), HourHazard.severe);
    });
  });

  group('the chip describes the window honestly (JA + EN)', () {
    test('JA: 放射冷却/ブラックアイス chip for the above-zero window', () {
      final text = PretripMessages.ja.blackIceRadiativeRisk('06:00');
      expect(text, contains('路面凍結'));
      expect(text, contains('放射冷却'));
      expect(text, contains('ブラックアイス'));
    });

    test('EN: surface-can-freeze-above-zero chip', () {
      final text = PretripMessages.en.blackIceRadiativeRisk('06:00');
      expect(text.toLowerCase(), contains('black ice'));
      expect(text, contains('above 0'));
    });
  });
}
