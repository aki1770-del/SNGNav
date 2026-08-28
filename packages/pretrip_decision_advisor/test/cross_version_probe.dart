// Compiles against BOTH published 0.6.0 and 0.6.1: uses only API that exists
// in 0.6.0. Discriminates by BEHAVIOUR, not by symbol availability.
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final base = DateTime.utc(2026, 1, 15, 7, 0);
  const advisor = SnowAwarePretripAdvisor();
  const profile = DriverProfileSpec(
    profileTag: 'her',
    reactionTimeSeconds: 1.5,
  );
  final h2 = base.add(const Duration(hours: 1));

  CommuteShape commute([Duration d = const Duration(minutes: 30)]) =>
      CommuteShape(
        plannedDuration: d,
        routeIdentifiers: const ['akita'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: base,
      );

  // A refusal (of any kind) reads as "no verdict", which is the point.
  PretripVerdict? verdictOf(
    List<HourlyForecast> h, [
    Duration d = const Duration(minutes: 30),
  ]) {
    try {
      return advisor
          .brief(
            forecast: WeatherForecast(issuedAt: base, hourly: h),
            commute: commute(d),
            profile: profile,
          )
          .verdict;
    } catch (_) {
      return null;
    }
  }

  HourHazard? peakOf(
    List<HourlyForecast> h, [
    Duration d = const Duration(minutes: 30),
  ]) {
    try {
      return advisor
          .brief(
            forecast: WeatherForecast(issuedAt: base, hourly: h),
            commute: commute(d),
            profile: profile,
          )
          .peakHazard;
    } catch (_) {
      return null;
    }
  }

  HourlyForecast unmeasured(DateTime h) =>
      HourlyForecast(hour: h, tempCelsius: 5.0);
  HourlyForecast measured(DateTime h) => HourlyForecast(
    hour: h,
    tempCelsius: 5.0,
    visibilityMeters: 20000,
    precipitationMmPerHour: 0,
    humidityRH: 40,
    estimatedRoadCondition: RoadConditionEstimate.dry,
  );
  HourlyForecast whiteout(DateTime h) => HourlyForecast(
    hour: h,
    tempCelsius: -6,
    visibilityMeters: 40,
    precipitationMmPerHour: 2.0,
    humidityRH: 95,
    estimatedRoadCondition: RoadConditionEstimate.ice,
  );

  group('DEFECT PROBES — must FAIL on 0.6.0, PASS on 0.6.1', () {
    test('P1 unmeasured morning is never reported clear', () {
      expect(
        verdictOf([unmeasured(base), unmeasured(h2)]),
        isNot(PretripVerdict.clear),
      );
    });
    test('P2 NaN visibility is never reported clear', () {
      HourlyForecast s(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: 5.0,
        visibilityMeters: double.nan,
        precipitationMmPerHour: 0,
        humidityRH: 40,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );
      expect(verdictOf([s(base), s(h2)]), isNot(PretripVerdict.clear));
    });
    test('P3 Infinity visibility is never reported clear', () {
      HourlyForecast s(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: 5.0,
        visibilityMeters: double.tryParse('1e400'),
        precipitationMmPerHour: 0,
        humidityRH: 40,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      );
      expect(verdictOf([s(base), s(h2)]), isNot(PretripVerdict.clear));
    });
    test('P4 an honest "road unknown" is not treated as a dry road', () {
      HourlyForecast s(DateTime h, RoadConditionEstimate r) => HourlyForecast(
        hour: h,
        tempCelsius: 5.0,
        visibilityMeters: 20000,
        precipitationMmPerHour: 0,
        humidityRH: 40,
        estimatedRoadCondition: r,
      );
      expect(
        verdictOf([
          s(base, RoadConditionEstimate.unknown),
          s(h2, RoadConditionEstimate.unknown),
        ]),
        isNot(
          verdictOf([
            s(base, RoadConditionEstimate.dry),
            s(h2, RoadConditionEstimate.dry),
          ]),
        ),
      );
    });
    test('P5 a 3h trip with only 1h forecast is never reported clear', () {
      expect(
        verdictOf([measured(base)], const Duration(hours: 3)),
        isNot(PretripVerdict.clear),
      );
    });
    test('P6 a non-finite reading never throws an UNTYPED error', () {
      HourlyForecast s(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: double.negativeInfinity,
        visibilityMeters: double.negativeInfinity,
        precipitationMmPerHour: 1.0,
        humidityRH: 95,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      );
      try {
        advisor.brief(
          forecast: WeatherForecast(issuedAt: base, hourly: [s(base), s(h2)]),
          commute: commute(),
          profile: profile,
        );
      } on UnsupportedError catch (e) {
        fail('untyped UnsupportedError escaped: $e');
      } catch (_) {
        /* typed stop is fine */
      }
    });
  });

  group('CONTROLS — must PASS on BOTH 0.6.0 and 0.6.1', () {
    test('C1 a fully measured benign morning IS clear', () {
      expect(verdictOf([measured(base), measured(h2)]), PretripVerdict.clear);
    });
    test(
      'C2 a measured whiteout beside an unmeasured hour is still severe',
      () {
        expect(
          peakOf([whiteout(base), unmeasured(h2)], const Duration(minutes: 90)),
          HourHazard.severe,
        );
      },
    );
    test('C3 an empty forecast is unknown, never clear', () {
      expect(peakOf(const []), HourHazard.unknown);
    });
    test('C4 a measured ice road reports severe from partial data', () {
      HourlyForecast s(DateTime h) => HourlyForecast(
        hour: h,
        tempCelsius: -3,
        estimatedRoadCondition: RoadConditionEstimate.ice,
      );
      expect(peakOf([s(base), s(h2)]), HourHazard.severe);
    });
  });
}
