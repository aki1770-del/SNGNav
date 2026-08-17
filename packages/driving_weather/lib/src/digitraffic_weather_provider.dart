/// Digitraffic weather provider — live Finnish road-hazard advisories as a
/// [WeatherProvider].
///
/// Adapts the Fintraffic Digitraffic traffic-announcements feed (via the
/// `condition_aggregator_digitraffic` package) onto the app's stream-based
/// [WeatherProvider] contract, so the existing weather → safety-overlay
/// bridge fires on real Finnish advisories without any app-core change.
///
/// **Network-dependent.** This provider polls `tie.digitraffic.fi`. It is
/// the ONLINE counterpart to [SimulatedWeatherProvider] — never select it on
/// a fully-offline path. The offline GPS-loss → dead-reckoning → MBTiles
/// scenario continues to use [SimulatedWeatherProvider] and never constructs
/// this class.
///
/// ## Why an adapter is needed (the gap)
///
/// The source emits a *pull*, *point-scoped* `List<Advisory>` carrying
/// CAP-class `severity` (minor/moderate/severe/extreme). The app consumes a
/// *push* `Stream<WeatherCondition>` whose `isHazardous` keys off
/// `iceRisk` / `intensity == heavy` / `visibilityMeters < 200`. This adapter:
///   1. polls `fetchActiveAdvisoriesAtPoint` on an interval,
///   2. reduces the list to its worst-severity advisory,
///   3. maps that severity onto a [WeatherCondition] whose `isHazardous`
///      reflects the advisory severity, so the unchanged
///      `WeatherStatusBar` bridge raises a `SafetyAlertReceived`.
///
/// Offline fallback mirrors [OpenMeteoWeatherProvider]: on fetch failure the
/// last known condition is re-emitted rather than letting the stream go
/// silent.
///
/// Attribution: data © Fintraffic, CC BY 4.0. The
/// [DigitrafficAdvisoryProvider] already appends the Fintraffic credit line
/// to every advisory's `description`; the worst advisory's `headline` is
/// surfaced to the driver via the alert message path.
library;

import 'dart:async';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';

import 'weather_condition.dart';
import 'weather_provider.dart';

/// Default query point — Oulu, northern Finland: a winter-driving region on
/// the Digitraffic network. Overridable at construction time.
const double _kDefaultLatitude = 65.0124;
const double _kDefaultLongitude = 25.4682;

class DigitrafficWeatherProvider implements WeatherProvider {
  /// Latitude of the point advisories are fetched around.
  final double latitude;

  /// Longitude of the point advisories are fetched around.
  final double longitude;

  /// How often to poll the Digitraffic feed. Default 5 minutes — the feed is
  /// a national announcement set, not a sub-minute sensor.
  final Duration pollInterval;

  /// The underlying source adapter. Injectable for testing via
  /// [DigitrafficAdvisoryProvider.withClient].
  final DigitrafficAdvisoryProvider _source;

  StreamController<WeatherCondition>? _controller;
  Timer? _timer;
  WeatherCondition? _lastCondition;

  /// Constructs a provider that owns a live [DigitrafficAdvisoryProvider]
  /// (which owns its own [http.Client]).
  DigitrafficWeatherProvider({
    this.latitude = _kDefaultLatitude,
    this.longitude = _kDefaultLongitude,
    this.pollInterval = const Duration(minutes: 5),
  }) : _source = DigitrafficAdvisoryProvider();

  /// Constructs a provider against a caller-supplied source adapter (test
  /// injection — pass a [DigitrafficAdvisoryProvider.withClient] backed by a
  /// `MockClient`).
  DigitrafficWeatherProvider.withSource(
    DigitrafficAdvisoryProvider source, {
    this.latitude = _kDefaultLatitude,
    this.longitude = _kDefaultLongitude,
    this.pollInterval = const Duration(minutes: 5),
  }) : _source = source;

  @override
  Stream<WeatherCondition> get conditions {
    _controller ??= StreamController<WeatherCondition>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> startMonitoring() async {
    if (_controller == null) return; // disposed

    _timer?.cancel();
    _timer = null;

    await _source.init();

    // Fetch immediately on start.
    await _fetchAndEmit();

    if (_controller == null || _controller!.isClosed) return;

    _timer = Timer.periodic(pollInterval, (_) => _fetchAndEmit());
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
    _source.close();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _fetchAndEmit() async {
    if (_controller == null || _controller!.isClosed) return;
    try {
      final advisories = await _source.fetchActiveAdvisoriesAtPoint(
        latitude: latitude,
        longitude: longitude,
      );
      if (_controller == null || _controller!.isClosed) return;
      final condition = advisoriesToCondition(advisories);
      _lastCondition = condition;
      _controller!.add(condition);
    } catch (_) {
      // Offline fallback: re-emit last known condition if available, mirroring
      // OpenMeteoWeatherProvider. If none, stay silent — application keeps its
      // current state rather than flashing a spurious clear.
      if (_controller == null || _controller!.isClosed) return;
      if (_lastCondition != null) {
        _controller!.add(_lastCondition!);
      }
    }
  }

  /// Reduces a list of [Advisory] records to a single [WeatherCondition].
  ///
  /// Visible for testing. The worst-severity advisory drives the condition;
  /// a driver needs the most severe hazard on the road ahead, not an average.
  /// Empty list → clear.
  static WeatherCondition advisoriesToCondition(List<Advisory> advisories) {
    final now = DateTime.now();
    if (advisories.isEmpty) {
      return WeatherCondition.clear(timestamp: now);
    }

    final worst = advisories.reduce(
      (a, b) => a.severity.index >= b.severity.index ? a : b,
    );

    return _severityToCondition(worst.severity, now);
  }

  /// Maps a CAP-class [AdvisorySeverity] onto a [WeatherCondition] whose
  /// `isHazardous` getter reflects the advisory severity, so the unchanged
  /// app bridge (`isHazardous` → `SafetyAlertReceived`) fires correctly.
  ///
  /// `WeatherCondition.isHazardous == iceRisk || intensity == heavy ||
  /// visibility < 200`. We therefore drive `intensity`/`visibility` from
  /// severity:
  /// - extreme/severe → heavy snow + sub-200 m visibility → hazardous
  /// - moderate       → moderate snow + reduced (800 m) visibility → caution,
  ///   not hazardous (matches the simulated provider's "moderate" phase)
  /// - minor/unknown  → light snow, good visibility → not hazardous
  ///
  /// These are advisory-driven presentation values, not measured meteorology;
  /// Digitraffic announces road *situations*, not sensor weather. The snow
  /// precip-type is used because this provider serves the winter-road mission
  /// and the existing HMI renders snow tinting on hazard.
  static WeatherCondition _severityToCondition(
    AdvisorySeverity severity,
    DateTime now,
  ) {
    switch (severity) {
      case AdvisorySeverity.extreme:
      case AdvisorySeverity.severe:
        return WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -4.0,
          visibilityMeters: 150,
          windSpeedKmh: 40,
          iceRisk: true,
          timestamp: now,
        );
      case AdvisorySeverity.moderate:
        return WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -1.0,
          visibilityMeters: 800,
          windSpeedKmh: 25,
          timestamp: now,
        );
      case AdvisorySeverity.minor:
      case AdvisorySeverity.unknown:
        return WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 1.0,
          visibilityMeters: 3000,
          windSpeedKmh: 12,
          timestamp: now,
        );
    }
  }
}
