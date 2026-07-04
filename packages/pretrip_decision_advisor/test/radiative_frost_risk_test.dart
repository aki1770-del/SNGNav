/// Humidity-aware black-ice (radiative frost) — the no-precipitation killer,
/// BOUNDED to the calibration's documented envelope (ambient a few degrees
/// above 0 °C; ceiling +3.0 °C).
///
/// Every numeric pin below is PROBE-MEASURED against the calibration package
/// (Magnus, a=17.625 b=243.04), not assumed:
///   95% RH @ 0.5 °C → effective −0.21 → fires
///   60% RH @ 1.0 °C → effective −5.90 → fires
///   80% RH @ 3.0 °C → effective −0.11 → fires (ceiling boundary, inclusive)
///   95% RH @ 1.0 °C → effective +0.29 → no fire
///  100% RH @ 3.0 °C → effective +3.00 → no fire (saturated air ≈ ambient)
///   99% RH @ 0.2 °C → effective +0.06 → no fire
///   40% RH @ 5.0 °C → dew point −7.50 BUT ambient above the ceiling → no
///     fire. The unbounded dew-point test fired here — and at 20 °C/25% RH —
///     which is cry-wolf on benign dry days; the adversarial panel caught it,
///     and the ceiling is the fix. This test pins the ceiling.
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

  group('radiativeFrostRisk — probe-measured pins inside the envelope', () {
    test('fires in the above-zero-ambient black-ice window', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 95)), isTrue);
      expect(advisor.radiativeFrostRisk(slot(temp: 1.0, rh: 60)), isTrue);
      expect(advisor.radiativeFrostRisk(slot(temp: 3.0, rh: 80)), isTrue,
          reason: 'the ceiling is inclusive: 3.0 °C is inside the envelope');
    });

    test('does not fire when the surface estimate stays above freezing', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 1.0, rh: 95)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 0.2, rh: 99)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 3.0, rh: 100)), isFalse,
          reason: 'saturated air: surface estimate == ambient == +3.0');
    });

    test('CEILING: warm ambient never fires, whatever the dew point '
        '(the cry-wolf class the adversarial panel caught)', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 5.0, rh: 40)), isFalse,
          reason: 'dew point −7.5 but ambient 5.0 > ceiling 3.0');
      expect(advisor.radiativeFrostRisk(slot(temp: 10.0, rh: 45)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 15.0, rh: 30)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 20.0, rh: 25)), isFalse,
          reason: 'the benign dry afternoon must NEVER chip black ice');
      expect(advisor.radiativeFrostRisk(slot(temp: 3.1, rh: 40)), isFalse,
          reason: 'just above the ceiling');
    });

    test('absence or dirty data is never presence of hazard — and never '
        'an exception (adapted-from-core semantics: ignore, don\'t throw)',
        () {
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5)), isFalse,
          reason: 'null humidity adds nothing');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 0.0)), isFalse,
          reason: '0.0 is the missing-data sentinel');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: -5.0)), isFalse);
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 120.0)), isFalse,
          reason: 'implausible reading adds nothing (feed bug, not hazard)');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: double.nan)),
          isFalse);
      // A mis-wired FRACTION in the percent field (0.95 == 0.95% RH) would
      // fabricate a deep depression — ignored, like core's percent door
      // rejects it (core throws; a briefing must not).
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 0.95)), isFalse,
          reason: 'sub-1%% is almost certainly a mis-wired fraction');
    });

    test('SUBNORMAL humidity must not crash the briefing '
        '(execution-proven crash before the guard: rh/100 underflows to 0.0, '
        'outside the calibration domain)', () {
      final subnormal = slot(temp: 0.5, rh: 5e-324);
      expect(() => advisor.radiativeFrostRisk(subnormal), returnsNormally);
      expect(advisor.radiativeFrostRisk(subnormal), isFalse);
      expect(() => advisor.hazardOf(subnormal), returnsNormally,
          reason: 'ONE corrupt slot must never take down the whole briefing');
    });

    test('supersaturation reads as saturated air', () {
      expect(advisor.radiativeFrostRisk(slot(temp: 0.5, rh: 101.0)), isFalse,
          reason: 'saturated air at +0.5 ambient: surface estimate +0.5 > 0');
      expect(advisor.radiativeFrostRisk(slot(temp: 0.0, rh: 101.0)), isTrue,
          reason: 'saturated air at 0.0 ambient: surface estimate 0.0 <= 0');
    });
  });

  group('hazardOf — the caution band gains the bounded black-ice window', () {
    test('STRICT: above-zero ambient + humidity crossing → caution '
        '(deleting the radiative-frost condition fails this test)', () {
      expect(advisor.hazardOf(slot(temp: 0.5, rh: 95)), HourHazard.caution);
    });

    test('caution-add-only: without humidity the same slot stays clear', () {
      expect(advisor.hazardOf(slot(temp: 0.5)), HourHazard.clear);
    });

    test('warm benign slots stay clear (proportionality — no cry-wolf)', () {
      expect(advisor.hazardOf(slot(temp: 15.0, rh: 30)), HourHazard.clear);
      expect(advisor.hazardOf(slot(temp: 20.0, rh: 25)), HourHazard.clear);
    });

    test('never lowers an existing band', () {
      expect(advisor.hazardOf(slot(temp: -1.0, rh: 95)), HourHazard.caution);
      expect(advisor.hazardOf(slot(temp: -1.0)), HourHazard.caution);
      final severe = HourlyForecast(
        hour: at,
        tempCelsius: 0.5,
        humidityRH: 95,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      );
      expect(advisor.hazardOf(severe), HourHazard.severe);
    });
  });

  group('brief() — the chip actually reaches the briefing '
      '(mutation guard for the _describe emission half)', () {
    PretripBriefing briefFor(List<HourlyForecast> hours) {
      final dep = at.add(const Duration(minutes: 30));
      return advisor.brief(
        forecast: WeatherForecast(
          hourly: hours,
          issuedAt: at.subtract(const Duration(hours: 1)),
        ),
        commute: CommuteShape(
          plannedDeparture: dep,
          plannedDuration: const Duration(minutes: 30),
          routeIdentifiers: const ['akita-commute'],
          flexibility: CommuteFlexibility.discretionary,
        ),
        profile: const DriverProfileSpec(
            profileTag: 'akita', reactionTimeSeconds: 1.5),
      );
    }

    test('a radiative-frost-only window carries the blackIce chip — never '
        'the generic fallback (deleting the _describe branch fails this)',
        () {
      final briefing = briefFor([
        slot(temp: 0.5, rh: 95),
        HourlyForecast(
            hour: at.add(const Duration(hours: 1)),
            tempCelsius: 0.5,
            humidityRH: 95),
      ]);
      final chips = briefing.recommendation!.rationale.join(' | ');
      expect(chips, contains('Black ice possible'),
          reason: 'the radiative-frost chip must describe the slot');
      expect(chips, isNot(contains('Winter conditions possible')),
          reason: 'the specific chip must not fall through to the generic');
    });

    test('at/below-zero ambient keeps freezingAir precedence '
        '(no double-description of the same slot)', () {
      final briefing = briefFor([
        slot(temp: -1.0, rh: 95),
        HourlyForecast(
            hour: at.add(const Duration(hours: 1)),
            tempCelsius: -1.0,
            humidityRH: 95),
      ]);
      final chips = briefing.recommendation!.rationale.join(' | ');
      expect(chips, contains('Freezing air'));
      expect(chips, isNot(contains('Black ice possible')));
    });
  });

  group('the chip describes the window honestly (JA + EN)', () {
    test('JA: 放射冷却/ブラックアイス chip for the above-zero window', () {
      final text = PretripMessages.ja.blackIceRadiativeRisk('06:00');
      expect(text, contains('路面凍結'));
      expect(text, contains('放射冷却'));
      expect(text, contains('ブラックアイス'));
    });

    test('EN chip states the mechanism without claiming a time of day', () {
      final text = PretripMessages.en.blackIceRadiativeRisk('06:00');
      expect(text.toLowerCase(), contains('black ice'));
      expect(text, contains('above 0'));
      expect(text.toLowerCase(), isNot(contains('overnight')),
          reason: 'the chip is emitted per-slot; it must not claim a time '
              'of day the slot may contradict');
    });
  });
}
