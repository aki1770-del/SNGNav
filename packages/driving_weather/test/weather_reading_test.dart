/// WeatherReading — staleness and unavailability are TYPES, not flags.
///
/// A `bool isStale` field would have been ignorable, and being ignorable is
/// exactly how the 0.4.4 silent-re-emit defect shipped. A sealed hierarchy
/// cannot be ignored: an exhaustive switch refuses a consumer who has not
/// written the stale and unavailable branches.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';

void main() {
  final observedAt = DateTime(2026, 3, 12, 6);
  final condition = WeatherCondition(
    precipType: PrecipitationType.snow,
    intensity: PrecipitationIntensity.heavy,
    temperatureCelsius: -4.0,
    visibilityMeters: 150,
    windSpeedKmh: 40,
    iceRisk: true,
    source: ObservationSource.measured,
    timestamp: observedAt,
  );

  /// Consumers are forced through this shape. There is no fourth case, and no
  /// way to fall through to a default that quietly treats stale as fresh.
  String render(WeatherReading reading) => switch (reading) {
    WeatherObserved(:final condition) => 'fresh: ${condition.hazard.name}',
    WeatherStale(:final age) => 'stale: ${age.inMinutes} min old',
    WeatherUnavailable() => 'no data',
  };

  test('an observed reading carries the condition it just fetched', () {
    final r = WeatherObserved(condition);

    expect(r.condition, condition);
    expect(render(r), 'fresh: hazardous');
  });

  test('a stale reading carries the REAL observation time, age and cause', () {
    final r = WeatherStale(
      lastKnown: condition,
      observedAt: observedAt,
      age: const Duration(minutes: 12),
      cause: Exception('connection refused'),
    );

    // The value survives — but it can no longer masquerade as fresh.
    expect(r.lastKnown, condition);
    expect(r.observedAt, observedAt);
    expect(r.age, const Duration(minutes: 12));
    expect(r.cause, isNotNull);
    expect(render(r), 'stale: 12 min old');
  });

  test(
    'an unavailable reading states that there is nothing, and since when',
    () {
      final since = DateTime(2026, 3, 12, 7);
      final r = WeatherUnavailable(since: since, cause: Exception('offline'));

      expect(r.since, since);
      expect(r.cause, isNotNull);
      expect(render(r), 'no data');
    },
  );

  test(
    'the three readings are distinct types — none can stand in for another',
    () {
      final observed = WeatherObserved(condition);
      final stale = WeatherStale(
        lastKnown: condition,
        observedAt: observedAt,
        age: Duration.zero,
      );
      final unavailable = WeatherUnavailable(since: observedAt);

      expect(observed, isA<WeatherReading>());
      expect(stale, isA<WeatherReading>());
      expect(unavailable, isA<WeatherReading>());

      expect(stale, isNot(isA<WeatherObserved>()));
      expect(unavailable, isNot(isA<WeatherObserved>()));
      expect(unavailable, isNot(isA<WeatherStale>()));
    },
  );
}
