/// The destination-AREA sibling of the non-finite crash 0.5.3 fixed on the
/// trip-window path.
///
/// `VisibilityObservation` is public, exported and unvalidated (`double meters`
/// / `double distanceKm`), and the source adapters build it from network JSON.
/// Up to 0.5.2 `summarizeAreaConditions` called `.round()` on both fields, so a
/// non-finite value threw `UnsupportedError: Infinity or NaN toInt` — an
/// UNTYPED error out of a pure, offline function, which the
/// `on PretripDataAbsentException` clause 0.5.2 asked integrators to write did
/// NOT catch.
///
/// Every test below states the crash it prevents, not merely the value it
/// expects.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 1, 15, 6);

  WeatherForecast tempOnly() => WeatherForecast(
    issuedAt: now,
    hourly: [HourlyForecast(hour: now, tempCelsius: -3)],
  );

  VisibilityObservation obs({
    required double meters,
    required double distanceKm,
  }) => VisibilityObservation(
    meters: meters,
    stationId: 1,
    stationName: '秋田',
    measuredAt: now,
    distanceKm: distanceKm,
  );

  AreaConditionRead read(VisibilityObservation o) => summarizeAreaConditions(
    forecast: tempOnly(),
    now: now,
    areaLabel: 'Akita',
    observed: o,
  );

  group('a non-finite reading does not crash the area read', () {
    // The exact values a JSON source can produce: `double.tryParse` — which is
    // `_readNum` in pretrip_source_jma — returns Infinity for the string
    // "Infinity" AND for an overflowing literal such as "1e400".
    for (final v in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('meters = $v is absent, not an UnsupportedError', () {
        // Before the guard: throws UnsupportedError, which is NOT a
        // PretripDataAbsentException, so no integrator catch clause holds it.
        final r = read(obs(meters: v, distanceKm: 4.2));

        expect(r.measuredVisibilityMeters, isNull);
        // One composite claim: the station and the distance go with it.
        expect(r.visibilityStationName, isNull);
        expect(r.visibilityDistanceKm, isNull);
      });

      test('distanceKm = $v is absent, not an UnsupportedError', () {
        final r = read(obs(meters: 80, distanceKm: v));

        // Positive evidence fires on partial knowledge: the measurement is a
        // real number and survives.
        expect(r.measuredVisibilityMeters, 80);
        expect(r.visibilityStationName, '秋田');
        // The distance is not a number, so it is not reported — and it is
        // emphatically NOT 0, which would place the station at HER position.
        expect(r.visibilityDistanceKm, isNull);
      });
    }

    test('a finite reading is unchanged — the guard costs nothing', () {
      final r = read(obs(meters: 80, distanceKm: 4.6));

      expect(r.measuredVisibilityMeters, 80);
      expect(r.visibilityStationName, '秋田');
      expect(r.visibilityDistanceKm, 5); // 4.6.round()
    });
  });

  group('the chips say so, in both languages', () {
    test('non-finite meters renders the honest "none" line', () {
      final r = read(obs(meters: double.nan, distanceKm: 4.2));

      expect(
        areaConditionChips(r, PretripMessages.en),
        contains('No measured visibility available for this area.'),
      );
      expect(
        areaConditionChips(r, PretripMessages.ja),
        contains('この地域の計測視程データはありません。'),
      );
    });

    test('a missing distance is never rendered as ~0 km away', () {
      final r = read(obs(meters: 80, distanceKm: double.infinity));

      final en = areaConditionChips(r, PretripMessages.en);
      final ja = areaConditionChips(r, PretripMessages.ja);

      // The precise fabrication this guard exists to stop.
      expect(en.any((c) => c.contains('0 km away')), isFalse);
      expect(ja.any((c) => c.contains('0km先')), isFalse);
      expect(en, contains('No measured visibility available for this area.'));
      expect(ja, contains('この地域の計測視程データはありません。'));
    });

    test(
      'a directly-constructed read with a null distance does not fabricate 0 '
      'either — the chip guard is not merely a mirror of the summarize guard',
      () {
        const r = AreaConditionRead(
          areaHazard: HourHazard.clear,
          forecastCovered: true,
          officialWarningVerbatim: null,
          warningCheckAvailable: true,
          measuredVisibilityMeters: 80,
          visibilityStationName: '秋田',
          visibilityDistanceKm: null,
          areaLabel: 'Akita',
        );

        expect(
          areaConditionChips(r, PretripMessages.en),
          contains('No measured visibility available for this area.'),
        );
      },
    );

    test('a complete reading still renders the full numeric chip', () {
      final r = read(obs(meters: 80, distanceKm: 4.6));

      expect(
        areaConditionChips(r, PretripMessages.en),
        contains('Nearest measured visibility ~80 m (秋田, ~5 km away).'),
      );
    });
  });

  group('the ladder is untouched — the guard cannot delete a hazard', () {
    test('the merged forecast still carries the raw reading to hazardOf', () {
      // -Infinity < 50 is true, so the ladder reports severe. That judgement is
      // the safety owner's, not this chip's; the guard must not suppress it.
      // (Named in the 0.5.3 CHANGELOG's honest bounds.)
      final r = read(obs(meters: double.negativeInfinity, distanceKm: 4.2));

      expect(r.areaHazard, HourHazard.severe);
      // ...while the chip declines to state a number it does not have.
      expect(r.measuredVisibilityMeters, isNull);
    });

    test('a finite whiteout reading still lights the band', () {
      final r = read(obs(meters: 80, distanceKm: 4.2));
      expect(r.areaHazard, HourHazard.severe);
    });
  });
}
