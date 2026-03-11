import 'dart:async';

import 'package:driving_weather/driving_weather.dart';

Future<void> main() async {
  final provider = SimulatedWeatherProvider(
    interval: const Duration(milliseconds: 200),
  );

  final subscription = provider.conditions.take(3).listen((condition) {
    print('${condition.precipType.name}/${condition.intensity.name} '
        'visibility=${condition.visibilityMeters.toStringAsFixed(0)}m '
        'hazardous=${condition.isHazardous}');
  });

  await provider.startMonitoring();
  await subscription.asFuture<void>();
  await provider.stopMonitoring();
  provider.dispose();
}