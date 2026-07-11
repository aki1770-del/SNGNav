import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/jma_briefing_merge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';

void main() {
  final issued = DateTime(2026, 1, 1, 6, 0);
  final windowStart = DateTime(2026, 1, 1, 7, 15);
  const windowDuration = Duration(minutes: 30);

  // A Japan-shaped forecast: temperature only, no visibility, no road state —
  // exactly what the MET Norway compact product yields for Nagoya.
  HourlyForecast jpSlot(int hour, {double temp = -2}) =>
      HourlyForecast(hour: DateTime(2026, 1, 1, hour), tempCelsius: temp);

  WeatherForecast jpForecast() => WeatherForecast(
    hourly: [jpSlot(7), jpSlot(8), jpSlot(9)],
    issuedAt: issued,
  );

  group('roadConditionForJmaSnowAdvisory', () {
    test('大雪警報 → packedSnow', () {
      expect(
        roadConditionForJmaSnowAdvisory('大雪警報'),
        RoadConditionEstimate.packedSnow,
      );
    });
    test('暴風雪警報 → packedSnow', () {
      expect(
        roadConditionForJmaSnowAdvisory('暴風雪警報'),
        RoadConditionEstimate.packedSnow,
      );
    });
    test('着雪注意報 → ice', () {
      expect(
        roadConditionForJmaSnowAdvisory('着雪注意報'),
        RoadConditionEstimate.ice,
      );
    });
    test('non-snow advisory → null', () {
      expect(roadConditionForJmaSnowAdvisory('強風注意報'), isNull);
      expect(roadConditionForJmaSnowAdvisory(''), isNull);
    });
  });

  group('mergeJmaWinterAdvisory', () {
    test('heavy-snow warning applies packedSnow to the window slot', () {
      final merged = mergeJmaWinterAdvisory(
        jpForecast(),
        jmaEventName: '大雪警報',
        windowStart: windowStart,
        windowDuration: windowDuration,
      );
      // The 07:00 slot covers [07:00, 08:00) which overlaps the 07:15 window.
      final s7 = merged.hourly.firstWhere((s) => s.hour.hour == 7);
      expect(s7.estimatedRoadCondition, RoadConditionEstimate.packedSnow);
    });

    test('a snow warning never fabricates a visibility number', () {
      final merged = mergeJmaWinterAdvisory(
        jpForecast(),
        jmaEventName: '大雪警報',
        windowStart: windowStart,
        windowDuration: windowDuration,
      );
      for (final s in merged.hourly) {
        expect(s.visibilityMeters, isNull);
      }
    });

    test('out-of-window slots are untouched', () {
      final merged = mergeJmaWinterAdvisory(
        jpForecast(),
        jmaEventName: '大雪警報',
        windowStart: windowStart,
        windowDuration: windowDuration,
      );
      final s9 = merged.hourly.firstWhere((s) => s.hour.hour == 9);
      expect(s9.estimatedRoadCondition, isNull);
    });

    test('an existing road condition is never overridden', () {
      final forecast = WeatherForecast(
        hourly: [
          HourlyForecast(
            hour: DateTime(2026, 1, 1, 7),
            tempCelsius: -2,
            estimatedRoadCondition: RoadConditionEstimate.wet,
          ),
        ],
        issuedAt: issued,
      );
      final merged = mergeJmaWinterAdvisory(
        forecast,
        jmaEventName: '大雪警報',
        windowStart: windowStart,
        windowDuration: windowDuration,
      );
      expect(
        merged.hourly.single.estimatedRoadCondition,
        RoadConditionEstimate.wet,
      );
    });

    test('a non-snow advisory is a no-op', () {
      final original = jpForecast();
      final merged = mergeJmaWinterAdvisory(
        original,
        jmaEventName: '強風注意報',
        windowStart: windowStart,
        windowDuration: windowDuration,
      );
      expect(merged, original);
    });

    test('the merged forecast lifts the advisor out of "no hazard"', () {
      const advisor = SnowAwarePretripAdvisor();
      final commute = CommuteShape(
        plannedDeparture: windowStart,
        plannedDuration: windowDuration,
        routeIdentifiers: const ['jp'],
        flexibility: CommuteFlexibility.discretionary,
      );
      const profile = DriverProfileSpec(
        profileTag: 'jp',
        reactionTimeSeconds: 1.5,
      );

      // Before: temperature-only JP forecast — the advisor sees no snow/ice.
      final before = advisor.brief(
        forecast: jpForecast(),
        commute: commute,
        profile: profile,
      );
      // After: the official JMA heavy-snow warning is merged in.
      final after = advisor.brief(
        forecast: mergeJmaWinterAdvisory(
          jpForecast(),
          jmaEventName: '大雪警報',
          windowStart: windowStart,
          windowDuration: windowDuration,
        ),
        commute: commute,
        profile: profile,
      );

      expect(before.peakHazard, HourHazard.caution); // subzero frost only
      expect(after.peakHazard, HourHazard.elevated); // packed snow now seen
    });
  });
}
