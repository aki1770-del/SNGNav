/// GUARD — `HourHazard.clear` is a POSITIVE claim and must be earned.
///
/// `HourHazard.unknown` exists in this package precisely because
/// `peakHazard: HourHazard.clear` on a `noData` briefing once printed "clear"
/// for a trip with zero forecast data (see its doc comment). That fix covered
/// the case where NO SLOT COVERED THE WINDOW.
///
/// It did not cover the case where a slot exists and carries almost nothing.
/// `hazardOf` reads five inputs; four of them (`visibilityMeters`,
/// `precipitationMmPerHour`, `estimatedRoadCondition`, `humidityRH`) are
/// nullable, and its own doc says "Null fields contribute nothing". A slot
/// whose only measured field is the temperature therefore falls through every
/// rung and returns `HourHazard.clear` — "No winter hazard signals in your
/// trip window." — which is a negative claim about a road nobody looked at.
///
/// This is reachable from a source shipping in this very catalog:
/// `pretrip_source_met_norway` sets `visibilityMeters: null` and
/// `estimatedRoadCondition: null` on EVERY slot ("compact product carries
/// neither"), and takes humidity and precipitation from `_readNum`, which
/// returns null whenever the key is absent or non-numeric.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  const advisor = SnowAwarePretripAdvisor();
  final hour = DateTime.utc(2026, 1, 15, 6);

  group('an unmeasured hour is never a clear hour', () {
    test('a slot carrying ONLY a temperature is not classified clear', () {
      final offenders = <double>[];
      for (final t in <double>[0.5, 1.0, 2.0, 3.0, 5.0, 12.0]) {
        final bare = HourlyForecast(hour: hour, tempCelsius: t);
        if (advisor.hazardOf(bare) == HourHazard.clear) offenders.add(t);
      }
      expect(offenders, isEmpty,
          reason: 'visibility, precipitation, road state and humidity were all '
              'absent. `clear` means "No winter hazard signal in this slot" — '
              'a negative claim requiring complete knowledge. Claimed at these '
              'temperatures (°C) on one measured field: $offenders');
    });

    test('the humidity reading alone must not decide clear-vs-caution', () {
      // Same hour, same temperature. One has a hygrometer, one does not.
      final withRh = HourlyForecast(hour: hour, tempCelsius: 1.0, humidityRH: 30);
      final withoutRh = HourlyForecast(hour: hour, tempCelsius: 1.0);

      expect(advisor.hazardOf(withRh), HourHazard.caution,
          reason: 'sanity: with humidity measured this IS the frost window');
      expect(advisor.hazardOf(withoutRh), isNot(HourHazard.clear),
          reason: 'the frost check ABSTAINED (humidity null). An abstention '
              'reported as "clear" is the fabricated-clear defect class');
    });

    test('the driver is never told "no winter hazard" from one field', () {
      final briefing = advisor.brief(
        forecast: WeatherForecast(
          hourly: [
            HourlyForecast(hour: hour, tempCelsius: 1.0),
            HourlyForecast(
                hour: hour.add(const Duration(hours: 1)), tempCelsius: 1.0),
          ],
          issuedAt: hour.subtract(const Duration(hours: 1)),
        ),
        commute: CommuteShape(
          plannedDeparture: hour,
          plannedDuration: const Duration(minutes: 40),
          routeIdentifiers: const ['akita-r13'],
          flexibility: CommuteFlexibility.discretionary,
        ),
        profile: const DriverProfileSpec(
          profileTag: 'ageingRural',
          reactionTimeSeconds: 1.0,
        ),
      );

      expect(briefing.verdict, isNot(PretripVerdict.clear),
          reason: 'a window of slots carrying only temperatures produced an '
              'affirmative clear verdict');
      expect(briefing.chips, isNot(contains(PretripMessages.en.noWinterHazard())),
          reason: 'she reads "${PretripMessages.en.noWinterHazard()}" for a '
              'trip window in which visibility, precipitation, road state and '
              'humidity were never measured');
    });

    test('a fully measured benign hour STAYS clear (must NOT regress)', () {
      // Guarding absence must not make every good morning read "unknown" —
      // that is the cry-wolf inverse and would be its own defect.
      final measured = HourlyForecast(
        hour: hour,
        tempCelsius: 8.0,
        humidityRH: 55,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 20000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );
      expect(advisor.hazardOf(measured), HourHazard.clear,
          reason: 'every input was measured and none fired');
    });
  });
}
