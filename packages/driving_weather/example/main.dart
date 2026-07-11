import 'dart:async';

import 'package:driving_weather/driving_weather.dart';

Future<void> main() async {
  final provider = SimulatedWeatherProvider(
    interval: const Duration(milliseconds: 200),
  );

  final subscription = provider.conditions.take(3).listen((reading) {
    // The reading is sealed: you cannot forget the stale and unavailable cases.
    switch (reading) {
      case WeatherObserved(:final condition):
        print(describe(condition));
      case WeatherStale(:final lastKnown, :final age):
        print('STALE (${age.inMinutes} min old): ${describe(lastKnown)}');
      case WeatherUnavailable(:final since):
        print('NO DATA since $since — conditions unknown');
    }
  });

  await provider.startMonitoring();
  await subscription.asFuture<void>();
  await provider.stopMonitoring();
  provider.dispose();
}

/// Renders a condition without inventing anything it does not carry.
String describe(WeatherCondition c) {
  final visibility = c.visibilityMeters == null
      ? 'visibility=unknown'
      : 'visibility=${c.visibilityMeters!.toStringAsFixed(0)}m';

  // The hazard verdict is tri-state. `unknown` is not "no hazard" — it means
  // nobody measured the road, and the driver is told exactly that.
  final hazard = switch (c.hazard) {
    SafetyVerdict.hazardous => 'HAZARDOUS',
    SafetyVerdict.notHazardous => 'no hazard',
    SafetyVerdict.unknown => 'UNKNOWN — could not assess',
  };

  return '${c.precipType?.name ?? "?"}/${c.intensity?.name ?? "?"} '
      '$visibility $hazard';
}
