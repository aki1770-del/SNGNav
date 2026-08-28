import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';

void main() {
  const advisor = SnowAwarePretripAdvisor();

  final dep = DateTime(2026, 1, 1, 7, 15);
  final issued = DateTime(2026, 1, 1, 6, 0);

  /// A FULLY MEASURED slot: every field the hazard ladder reads carries a
  /// value, so a `clear` verdict built from it is EARNED rather than
  /// fallen-through.
  ///
  /// ⚑ The defaults were `null` until 2026-08-28, and `null` is exactly the
  /// shape published 0.6.0 read as benign: every test in `hazardOf` is guarded
  /// `field != null && ...`, so a slot carrying a temperature and nothing else
  /// failed every test, fell through all of them and scored `clear` having
  /// decided nothing. Fixtures built from those defaults could therefore reach
  /// an all-clear the ladder never earned — the defect `pretrip_decision_advisor`
  /// 0.6.1 closes, sitting inside the tests that were supposed to catch it.
  ///
  /// Absence is now written out longhand at the call site (a direct
  /// `HourlyForecast(...)`), so a test that MEANS "unmeasured" says so instead
  /// of getting it by default.
  HourlyForecast slot(
    int hour, {
    double temp = -2,
    double precip = 0,
    double vis = 8000,
    double humidity = 60,
    RoadConditionEstimate road = RoadConditionEstimate.dry,
  }) => HourlyForecast(
    hour: DateTime(2026, 1, 1, hour),
    tempCelsius: temp,
    humidityRH: humidity,
    precipitationMmPerHour: precip,
    visibilityMeters: vis,
    estimatedRoadCondition: road,
  );

  CommuteShape commute({
    CommuteFlexibility flexibility = CommuteFlexibility.discretionary,
    Duration duration = const Duration(minutes: 30),
    DateTime? departure,
  }) => CommuteShape(
    plannedDeparture: departure ?? dep,
    plannedDuration: duration,
    routeIdentifiers: const ['r1'],
    flexibility: flexibility,
  );

  const profile = DriverProfileSpec(
    profileTag: 'test',
    reactionTimeSeconds: 1.5,
  );

  WeatherForecast forecast(List<HourlyForecast> hourly) =>
      WeatherForecast(hourly: hourly, issuedAt: issued);

  group('coverage', () {
    test('returns null recommendation when forecast misses the window', () {
      final b = advisor.brief(
        forecast: forecast([slot(12), slot(13)]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.noData);
      expect(b.recommendation, isNull);
    });
  });

  group('clear and caution', () {
    test('clear window recommends departing now', () {
      // 4 C, not 3. The fixture's intent — a temperature ABOVE the frost band
      // — was written 2026-06-12 (1f452c0) when `frostTempCelsius = 0.0` was
      // the only band. The radiative-frost band arrived 2026-07-05 (3cd2ce9)
      // with `radiativeFrostAmbientCeilingCelsius = 3.0`, and 3 C stopped
      // being above it — it sits exactly ON the ceiling. The fixture kept
      // reading `clear` for 23 days only because its humidity was ABSENT, and
      // absent humidity made the frost check return false. Measured
      // 2026-08-28: at 3 C this slot is `caution` for every humidity from 5%
      // to 80%. 4 C is above the ceiling, so the ladder decides it outright.
      final b = advisor.brief(
        forecast: forecast([slot(7, temp: 4), slot(8, temp: 4)]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.clear);
      expect(b.recommendation!.suggestedDelay, Duration.zero);
      expect(b.recommendation!.strength, RecommendationStrength.advisoryWeak);
    });

    test('slush is caution, not delay', () {
      final b = advisor.brief(
        forecast: forecast([
          slot(7, road: RoadConditionEstimate.slush, vis: 3000),
          slot(8, vis: 3000),
        ]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.caution);
      expect(b.recommendation!.suggestedDelay, Duration.zero);
    });

    // ⚑ THE ASSERTION HERE WAS THE DEFECT, WRITTEN DOWN AS A SPECIFICATION.
    //
    // It built a slot carrying a temperature and NOTHING else and asserted
    // `verdict == clear`. Published 0.6.0 satisfied it, and told a driver in
    // Akita 「出発時間帯に冬季の危険を示す兆候はありません」 on a morning where
    // visibility, road surface, precipitation and humidity had never been
    // measured. A test cannot catch a defect it asserts.
    //
    // The INTENT survives and is asserted below, unweakened: absence must not
    // fabricate a hazard EITHER. A gap never raises the band and never lowers
    // it — at the adverse end it would invent danger, at the benign end it
    // would invent safety. What changes is only the third outcome the old
    // assertion had no word for: the advisor may decline to conclude.
    test('null fields never fabricate a hazard — nor an all-clear', () {
      final f = forecast([
        HourlyForecast(hour: DateTime(2026, 1, 1, 7), tempCelsius: 5),
        HourlyForecast(hour: DateTime(2026, 1, 1, 8), tempCelsius: 5),
      ]);

      // THE ORIGINAL INTENT, UNCHANGED: absence invents no hazard. The
      // ladder still scores these slots `clear`; nothing was promoted to a
      // warning because a field happened to be missing.
      expect(advisor.hazardOf(f.hourly.first), HourHazard.clear);
      expect(advisor.hazardOf(f.hourly.last), HourHazard.clear);

      // AND absence invents no all-clear. `clear` on the ladder means
      // "nothing fired", which is not "nothing is there".
      expect(
        () => advisor.brief(forecast: f, commute: commute(), profile: profile),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );

      // It names WHAT it could not decide, so a caller can go and measure it
      // rather than only learn that something was missing. At 5 C neither
      // precipitation nor humidity could have changed this slot's verdict,
      // so neither is reported — the gate is exactly as tight as the ladder.
      expect(advisor.evidenceGaps(f.hourly.first), {
        HazardEvidenceGap.visibility,
        HazardEvidenceGap.roadSurface,
      });

      // The caller who would rather branch than catch is not handed a
      // fabricated band either — the honest middle value.
      final b = advisor.briefOrUnassessed(
        forecast: f,
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.noData);
      expect(b.peakHazard, HourHazard.unknown);
    });

    test('subzero dry air is caution, never clear — frost/black-ice risk, '
        'consistent with the in-trip Subzero advisory class', () {
      // Temperature is REAL data (the one required field), not a null field:
      // a −10 °C forecast reading "no winter hazard signals" was the
      // measured failure (70/620 real winter slots, 2026-06-12 quant run).
      final b = advisor.brief(
        forecast: forecast([
          HourlyForecast(hour: DateTime(2026, 1, 1, 7), tempCelsius: -10),
          HourlyForecast(hour: DateTime(2026, 1, 1, 8), tempCelsius: -10),
        ]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.caution);
      // Caution never urges a delay — prepare-and-go, not wait.
      expect(b.recommendation!.suggestedDelay, Duration.zero);
      expect(
        b.chips.any((c) => c.contains('frost or black ice')),
        isTrue,
        reason: 'the chip must name the frost risk: ${b.chips}',
      );
    });
  });

  group('hazard scoring', () {
    test('whiteout-class visibility (<100 m) is severe', () {
      expect(advisor.hazardOf(slot(7, vis: 80)), HourHazard.severe);
    });

    test('near-whiteout band (100-200 m) is elevated', () {
      expect(advisor.hazardOf(slot(7, vis: 150)), HourHazard.elevated);
    });

    test('precipitation at near-freezing is elevated (icing)', () {
      expect(
        advisor.hazardOf(slot(7, temp: 0.0, precip: 1.0, vis: 4000)),
        HourHazard.elevated,
      );
    });

    test('cold rain above icing band is caution', () {
      expect(
        advisor.hazardOf(slot(7, temp: 1.5, precip: 1.0, vis: 4000)),
        HourHazard.caution,
      );
    });
  });

  group('wait advice (discretionary)', () {
    final whiteoutThenClear = [
      slot(7, vis: 80, precip: 3, road: RoadConditionEstimate.packedSnow),
      slot(8, vis: 250, precip: 1),
      slot(9, vis: 3000, precip: 0, road: RoadConditionEstimate.dry),
      slot(10, vis: 5000, precip: 0, road: RoadConditionEstimate.dry),
      slot(11, vis: 8000, precip: 0, road: RoadConditionEstimate.dry),
    ];

    test('whiteout now + clear later → strong wait with delay', () {
      final b = advisor.brief(
        forecast: forecast(whiteoutThenClear),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.waitAdvised);
      expect(b.recommendation!.strength, RecommendationStrength.advisoryStrong);
      // 07:15 + 2h → 09:15 window sits in the clear 09:00/10:00 slots.
      expect(b.recommendation!.suggestedDelay, const Duration(hours: 2));
      expect(
        b.chips.any((c) => c.contains('whiteout')),
        isTrue,
        reason: 'chips should name the hazard plainly: ${b.chips}',
      );
    });

    test('slow reaction-time profile adds margin, not strength', () {
      final b = advisor.brief(
        forecast: forecast(whiteoutThenClear),
        commute: commute(),
        profile: const DriverProfileSpec(
          profileTag: 'ageingRural',
          reactionTimeSeconds: 3.0,
        ),
      );
      expect(
        b.recommendation!.suggestedDelay,
        const Duration(hours: 2, minutes: 30),
      );
      expect(b.recommendation!.strength, RecommendationStrength.advisoryStrong);
    });

    test('elevated hazard with better window is a weak wait', () {
      final b = advisor.brief(
        forecast: forecast([
          slot(7, vis: 150, precip: 1),
          slot(8, vis: 3000, precip: 0),
          slot(9, vis: 5000, precip: 0),
        ]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.waitAdvised);
      expect(b.recommendation!.strength, RecommendationStrength.advisoryWeak);
      expect(b.recommendation!.suggestedDelay, const Duration(hours: 1));
    });

    test('hazard through the whole horizon → honest no-delay message', () {
      final b = advisor.brief(
        forecast: forecast([
          for (var h = 7; h <= 14; h++) slot(h, vis: 90, precip: 3),
        ]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.hazardPersists);
      expect(b.recommendation!.suggestedDelay, Duration.zero);
      expect(b.chips.any((c) => c.contains('needed today')), isTrue);
    });
  });

  group('honesty rule', () {
    final whiteoutNow = [
      slot(7, vis: 80, precip: 3),
      slot(8, vis: 250),
      slot(9, vis: 3000, road: RoadConditionEstimate.dry),
      slot(10, vis: 5000, road: RoadConditionEstimate.dry),
    ];

    test('required commute never gets a strong wait', () {
      final b = advisor.brief(
        forecast: forecast(whiteoutNow),
        commute: commute(flexibility: CommuteFlexibility.required),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.requiredTripHazard);
      expect(b.recommendation!.strength, RecommendationStrength.honestyMode);
      expect(b.recommendation!.suggestedDelay, Duration.zero);
      expect(b.chips.any((c) => c.contains('required')), isTrue);
    });

    test('unknown flexibility is treated like required (no urged delay)', () {
      final b = advisor.brief(
        forecast: forecast(whiteoutNow),
        commute: commute(flexibility: CommuteFlexibility.unknown),
        profile: profile,
      );
      expect(b.recommendation!.strength, RecommendationStrength.honestyMode);
    });

    test('required commute still hears about a better window', () {
      final b = advisor.brief(
        forecast: forecast(whiteoutNow),
        commute: commute(flexibility: CommuteFlexibility.required),
        profile: profile,
      );
      expect(
        b.chips.any((c) => c.contains('if your schedule allows')),
        isTrue,
        reason: 'better-window info is offered, never urged: ${b.chips}',
      );
    });
  });

  group('staleness', () {
    test('old forecast at departure gets a staleness chip', () {
      final b = advisor.brief(
        forecast: WeatherForecast(
          hourly: [slot(7, vis: 8000), slot(8, vis: 8000)],
          issuedAt: DateTime(2025, 12, 31, 22, 0), // >6 h before departure
        ),
        commute: commute(),
        profile: profile,
      );
      expect(b.chips.any((c) => c.contains('check conditions again')), isTrue);
    });
  });

  group('contract conformance', () {
    test('advise() returns the same recommendation brief() carries', () {
      final f = forecast([
        slot(7, vis: 80),
        slot(8, vis: 3000),
        slot(9, vis: 5000),
      ]);
      final c = commute();
      final rec = advisor.advise(forecast: f, commute: c, profile: profile);
      final b = advisor.brief(forecast: f, commute: c, profile: profile);
      expect(rec, b.recommendation);
    });
  });
}
