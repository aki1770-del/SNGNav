import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

WeatherForecast _forecast(List<HourlyForecast> hourly, DateTime issuedAt) =>
    WeatherForecast(hourly: hourly, issuedAt: issuedAt);

void main() {
  final now = DateTime(2026, 1, 1, 7);

  group('summarizeAreaConditions', () {
    test('elevated band: near-freezing precip slot at now', () {
      final forecast = _forecast([
        HourlyForecast(hour: now, tempCelsius: -3, precipitationMmPerHour: 1.0),
      ], now);

      final r = summarizeAreaConditions(
        forecast: forecast,
        now: now,
        areaLabel: 'Akita',
      );

      expect(r.areaHazard, HourHazard.elevated);
      expect(r.forecastCovered, isTrue);
    });

    test('verbatim warning passes through and appears in chips (en + ja)', () {
      final forecast = _forecast([
        HourlyForecast(hour: now, tempCelsius: 1),
      ], now);

      final r = summarizeAreaConditions(
        forecast: forecast,
        now: now,
        areaLabel: 'Akita',
        warningEventVerbatim: '大雪警報',
      );

      expect(r.officialWarningVerbatim, '大雪警報');
      expect(
        areaConditionChips(
          r,
          PretripMessages.en,
        ).any((c) => c.contains('大雪警報')),
        isTrue,
      );
      expect(
        areaConditionChips(r, PretripMessages.ja),
        contains('この地域で発表中の警報・注意報: 大雪警報。'),
      );
    });

    test('measured visibility lights severe + renders station/distance', () {
      final forecast = _forecast([
        HourlyForecast(hour: now, tempCelsius: 1, visibilityMeters: 8000),
      ], now);

      final r = summarizeAreaConditions(
        forecast: forecast,
        now: now,
        areaLabel: 'Akita',
        observed: VisibilityObservation(
          meters: 80,
          stationId: 1,
          stationName: '秋田',
          measuredAt: now,
          distanceKm: 5,
        ),
      );

      expect(r.areaHazard, HourHazard.severe);
      expect(
        areaConditionChips(r, PretripMessages.en),
        contains('Nearest measured visibility ~80 m (秋田, ~5 km away).'),
      );
      expect(
        areaConditionChips(r, PretripMessages.ja),
        contains('最寄りの計測視程: 約80m(秋田、約5km先)。'),
      );
    });

    test(
      'real-sensor-or-nothing: no observation ⇒ null + no digit in chip',
      () {
        final forecast = _forecast([
          HourlyForecast(hour: now, tempCelsius: 1),
        ], now);

        final r = summarizeAreaConditions(
          forecast: forecast,
          now: now,
          areaLabel: 'Akita',
        );

        expect(r.measuredVisibilityMeters, isNull);
        expect(r.visibilityStationName, isNull);
        expect(r.visibilityDistanceKm, isNull);

        final visChip = areaConditionChips(r, PretripMessages.en).last;
        expect(visChip, PretripMessages.en.areaNoMeasuredVisibility());
        expect(
          RegExp(r'\d').hasMatch(visChip),
          isFalse,
          reason: 'no digit may appear in the no-measurement chip',
        );
      },
    );

    test(
      'window uncovered: all slots before now ⇒ not covered, no band word',
      () {
        final forecast = _forecast([
          HourlyForecast(
            hour: now.subtract(const Duration(hours: 2)),
            tempCelsius: -5,
          ),
          HourlyForecast(
            hour: now.subtract(const Duration(hours: 1)),
            tempCelsius: -5,
          ),
        ], now);

        final r = summarizeAreaConditions(
          forecast: forecast,
          now: now,
          areaLabel: 'Akita',
        );

        expect(r.forecastCovered, isFalse);
        final chips = areaConditionChips(r, PretripMessages.en);
        expect(chips, contains(PretripMessages.en.areaForecastNotCovered()));
        // The hazard chip line must be the not-covered line, not a band.
        expect(chips[1], PretripMessages.en.areaForecastNotCovered());
        for (final band in HourHazard.values) {
          expect(
            chips[1].contains(PretripMessages.en.areaHazardBand(band)),
            isFalse,
          );
        }
      },
    );

    group('hazard-band positive mapping (en + ja)', () {
      const enWords = {
        HourHazard.clear: 'no winter hazard signal',
        HourHazard.caution: 'caution',
        HourHazard.elevated: 'elevated',
        HourHazard.severe: 'severe',
      };
      const jaWords = {
        HourHazard.clear: '危険の兆候なし',
        HourHazard.caution: '注意',
        HourHazard.elevated: '警戒',
        HourHazard.severe: '重度',
      };

      test('each band maps to its correct word, bands stay distinct', () {
        for (final b in HourHazard.values) {
          // The driver-facing hazard SIGNAL itself, not just the enum.
          expect(PretripMessages.en.areaHazardBand(b), enWords[b]);
          expect(PretripMessages.ja.areaHazardBand(b), jaWords[b]);
          expect(PretripMessages.en.areaHazardChip(b), contains(enWords[b]!));
          expect(PretripMessages.ja.areaHazardChip(b), contains(jaWords[b]!));
        }
        // No two enums may collapse to one label (clear<->severe swap guard).
        expect(enWords.values.toSet().length, HourHazard.values.length);
        expect(jaWords.values.toSet().length, HourHazard.values.length);
      });
    });

    test('warning check failed: carries the "may be in effect" caveat', () {
      final forecast = _forecast([
        HourlyForecast(hour: now, tempCelsius: 1),
      ], now);

      final r = summarizeAreaConditions(
        forecast: forecast,
        now: now,
        areaLabel: 'Akita',
        warningCheckAvailable: false,
      );

      final en = areaConditionChips(r, PretripMessages.en);
      expect(en[0], PretripMessages.en.areaWarningCheckUnavailable());
      expect(en[0].contains('may be in effect'), isTrue);

      final ja = areaConditionChips(r, PretripMessages.ja);
      expect(ja[0], PretripMessages.ja.areaWarningCheckUnavailable());
      expect(ja[0].contains('可能性があります'), isTrue);
    });

    test(
      'warm benign slots never show a caution band on the mother\u2019s-area '
      'surface (radiative-frost proportionality pin)',
      () {
        // The family-thread surface consumes advisor.hazardOf; the 0.5.0
        // radiative-frost condition is envelope-bounded (ambient <= +3.0),
        // so a mild dry day must stay clear here — no cry-wolf toward the
        // person-adjacent read.
        final forecast = _forecast([
          HourlyForecast(hour: now, tempCelsius: 15.0, humidityRH: 30),
          HourlyForecast(
            hour: now.add(const Duration(hours: 1)),
            tempCelsius: 20.0,
            humidityRH: 25,
          ),
        ], now);

        final r = summarizeAreaConditions(
          forecast: forecast,
          now: now,
          areaLabel: 'Akita',
        );
        expect(r.areaHazard, HourHazard.clear);
      },
    );
  });
}
