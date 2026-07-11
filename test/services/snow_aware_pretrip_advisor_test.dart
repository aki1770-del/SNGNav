import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';

void main() {
  const advisor = SnowAwarePretripAdvisor();

  final dep = DateTime(2026, 1, 1, 7, 15);
  final issued = DateTime(2026, 1, 1, 6, 0);

  HourlyForecast slot(
    int hour, {
    double temp = -2,
    double? precip,
    double? vis,
    RoadConditionEstimate? road,
  }) => HourlyForecast(
    hour: DateTime(2026, 1, 1, hour),
    tempCelsius: temp,
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
      final b = advisor.brief(
        forecast: forecast([
          slot(7, temp: 3, vis: 8000, precip: 0),
          slot(8, temp: 3, vis: 8000),
        ]),
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

    test('null fields never fabricate a hazard', () {
      final b = advisor.brief(
        forecast: forecast([
          HourlyForecast(hour: DateTime(2026, 1, 1, 7), tempCelsius: 5),
          HourlyForecast(hour: DateTime(2026, 1, 1, 8), tempCelsius: 5),
        ]),
        commute: commute(),
        profile: profile,
      );
      expect(b.verdict, PretripVerdict.clear);
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
