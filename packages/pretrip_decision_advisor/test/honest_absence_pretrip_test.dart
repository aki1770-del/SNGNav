// The pre-trip surface must not tell HER the morning is clear when it has no
// forecast at all.
//
// Up to 0.5.1, `brief()` returned, for a trip window with ZERO forecast
// coverage:
//
//   PretripBriefing(verdict: noData, chips: [], recommendation: null,
//                   peakHazard: HourHazard.clear)          // <-- fabrication
//
// `peakHazard` is a NON-NULLABLE public field, `HourHazard` had no `unknown`
// member, and this catalog's own example prints `briefing.peakHazard.name`
// with no verdict check (pretrip_source_met_norway/example/main.dart). So an
// integrator rendered the word "clear" for a trip nobody forecast — the same
// empty-feed -> confident-positive defect as `WeatherCondition.clear()`, in
// the package that speaks to her BEFORE she leaves.
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final base = DateTime.utc(2026, 1, 15, 7, 0);

  const profile = DriverProfileSpec(
    profileTag: 'ageingRural',
    reactionTimeSeconds: 1.5,
  );

  CommuteShape commute() => CommuteShape(
    plannedDuration: const Duration(minutes: 30),
    routeIdentifiers: const ['route-a'],
    flexibility: CommuteFlexibility.discretionary,
    plannedDeparture: base,
  );

  group('an unforecast morning is not a clear morning', () {
    test('an EMPTY forecast yields peakHazard unknown, never clear', () {
      final b = const SnowAwarePretripAdvisor().brief(
        forecast: WeatherForecast(issuedAt: base, hourly: const []),
        commute: commute(),
        profile: profile,
      );

      expect(b.verdict, PretripVerdict.noData);
      expect(b.peakHazard, isNot(HourHazard.clear));
      expect(b.peakHazard, HourHazard.unknown);
      expect(b.recommendation, isNull);
    });

    test('a forecast that MISSES the window yields unknown, never clear', () {
      // Slots exist, but for a different day entirely.
      final b = const SnowAwarePretripAdvisor().brief(
        forecast: WeatherForecast(
          issuedAt: base,
          hourly: [
            HourlyForecast(
              hour: base.add(const Duration(days: 3)),
              tempCelsius: 4.0,
              estimatedRoadCondition: RoadConditionEstimate.dry,
            ),
          ],
        ),
        commute: commute(),
        profile: profile,
      );

      expect(b.verdict, PretripVerdict.noData);
      expect(b.peakHazard, HourHazard.unknown);
    });

    test('the unknown band never renders as good news, en or ja', () {
      expect(
        PretripMessages.en.areaHazardBand(HourHazard.unknown),
        isNot(contains('no winter hazard')),
      );
      expect(
        PretripMessages.ja.areaHazardBand(HourHazard.unknown),
        isNot(contains('危険の兆候なし')),
      );
    });

    // AMENDED in 0.6.1. This test previously omitted `visibilityMeters` and
    // still asserted `clear` — i.e. it asserted the defect 0.6.1 fixes. At
    // +6 C with a dry road, fog can still take visibility under 500 m
    // (caution) or under 100 m (severe), so an absent visibility leaves the
    // ladder undecided and the all-clear unearned. A "REAL forecast" has to
    // carry the fields that decide.
    test('a REAL forecast still resolves to a real band', () {
      final b = const SnowAwarePretripAdvisor().brief(
        forecast: WeatherForecast(
          issuedAt: base,
          hourly: [
            HourlyForecast(
              hour: base,
              tempCelsius: 6.0,
              visibilityMeters: 20000,
              estimatedRoadCondition: RoadConditionEstimate.dry,
            ),
            HourlyForecast(
              hour: base.add(const Duration(hours: 1)),
              tempCelsius: 6.0,
              visibilityMeters: 20000,
              estimatedRoadCondition: RoadConditionEstimate.dry,
            ),
          ],
        ),
        commute: commute(),
        profile: profile,
      );

      expect(b.peakHazard, HourHazard.clear);
      expect(b.verdict, PretripVerdict.clear);
    });

    test('the SAME forecast minus visibility no longer earns that band', () {
      // One field removed from the test above. Nothing else differs.
      HourlyForecast at(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: 6.0,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );
      final forecast = WeatherForecast(
        issuedAt: base,
        hourly: [at(base), at(base.add(const Duration(hours: 1)))],
      );

      expect(
        () => const SnowAwarePretripAdvisor().brief(
          forecast: forecast,
          commute: commute(),
          profile: profile,
        ),
        throwsA(isA<PretripAssessmentIncompleteException>()),
      );
    });
  });

  group('an unknown station distance is not 0 km', () {
    test('a measured visibility with no station distance says so', () {
      final s = PretripMessages.en.areaMeasuredVisibility(400, 'Akita', null);

      // "~0 km away" told her the reading was taken where she is standing —
      // making the LEAST trustworthy reading look like the most trustworthy.
      expect(s, isNot(contains('0 km')));
      expect(s, contains('not known'));
    });

    test('ja: an unnamed station and unknown distance are both admitted', () {
      final s = PretripMessages.ja.areaMeasuredVisibility(400, null, null);

      expect(s, isNot(contains('0km')));
      expect(s, contains('不明'));
    });

    test('a fully-known observation is unchanged', () {
      final s = PretripMessages.en.areaMeasuredVisibility(400, 'Akita', 12);

      expect(s, contains('Akita'));
      expect(s, contains('12 km'));
    });
  });
}
