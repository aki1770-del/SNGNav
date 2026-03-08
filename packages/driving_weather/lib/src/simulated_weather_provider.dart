/// Simulated weather provider — generates realistic mountain pass
/// conditions for demo and testing purposes.
///
/// Emits a repeating sequence: clear → light snow → heavy snow → ice risk
/// → clearing. No network, no external dependency.
///
/// For real weather, use [OpenMeteoWeatherProvider].
library;

import 'dart:async';

import 'weather_condition.dart';
import 'weather_provider.dart';

class SimulatedWeatherProvider implements WeatherProvider {
  final Duration interval;

  StreamController<WeatherCondition>? _controller;
  Timer? _timer;
  int _step = 0;

  /// Creates a simulated weather provider.
  ///
  /// [interval] controls how frequently conditions change. Default is 5
  /// seconds for demo pacing; tests can set a shorter interval.
  SimulatedWeatherProvider({
    this.interval = const Duration(seconds: 5),
  });

  @override
  Stream<WeatherCondition> get conditions {
    _controller ??= StreamController<WeatherCondition>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> startMonitoring() async {
    _controller ??= StreamController<WeatherCondition>.broadcast();
    _step = 0;

    // Emit initial condition immediately.
    _emit();

    _timer = Timer.periodic(interval, (_) {
      _step = (_step + 1) % _scenario.length;
      _emit();
    });
  }

  @override
  Future<void> stopMonitoring() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller?.close();
    _controller = null;
  }

  void _emit() {
    if (_controller == null || _controller!.isClosed) return;
    final template = _scenario[_step];
    _controller!.add(template(DateTime.now()));
  }

  /// Mountain pass winter scenario — 6 phases.
  ///
  /// Simulates a drive from a city (clear) up a mountain road where
  /// snow intensifies, then clears on descent.
  static final List<WeatherCondition Function(DateTime)> _scenario = [
    // Phase 0: Clear — city departure.
    (ts) => WeatherCondition.clear(timestamp: ts),

    // Phase 1: Light snow begins — entering mountain area.
    (ts) => WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 1.0,
          visibilityMeters: 3000,
          windSpeedKmh: 15,
          timestamp: ts,
        ),

    // Phase 2: Moderate snow — mountain pass approach.
    (ts) => WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -1.0,
          visibilityMeters: 800,
          windSpeedKmh: 30,
          timestamp: ts,
        ),

    // Phase 3: Heavy snow — pass summit. Hazardous.
    (ts) => WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -4.0,
          visibilityMeters: 150,
          windSpeedKmh: 45,
          timestamp: ts,
        ),

    // Phase 4: Ice risk — descending pass. Temperature drop + wet road.
    (ts) => WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -3.0,
          visibilityMeters: 500,
          windSpeedKmh: 20,
          iceRisk: true,
          timestamp: ts,
        ),

    // Phase 5: Clearing — descending to valley.
    (ts) => WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 0.0,
          visibilityMeters: 2000,
          windSpeedKmh: 10,
          timestamp: ts,
        ),
  ];
}
