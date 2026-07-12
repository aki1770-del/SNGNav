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
/// ## Absence stops the loom (changed in 0.4.5)
///
/// An **empty** advisory feed and an **unreachable** feed are both absence of
/// data, not observations of a clear road. Neither produces a
/// [WeatherCondition] any more: the stream emits a
/// [WeatherDataUnavailableException] saying what happened, why we will not
/// guess, and how to move forward. Listen with `onError`.
///
/// Attribution: data © Fintraffic, CC BY 4.0. The
/// [DigitrafficAdvisoryProvider] already appends the Fintraffic credit line
/// to every advisory's `description`; the worst advisory's `headline` is
/// surfaced to the driver via the alert message path.
library;

import 'dart:async';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';

import 'weather_absence.dart';
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

    List<Advisory> advisories;
    try {
      advisories = await _source.fetchActiveAdvisoriesAtPoint(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (error) {
      // The feed is unreachable. We do NOT re-emit the last condition as if it
      // were current: old data with no staleness marker is indistinguishable
      // from fresh data, and a road that was clear ten minutes ago is not a
      // measurement of the road now. The stream STOPS and SAYS WHY; the
      // listener decides (and may still choose to show the last value, clearly
      // marked as old — lastObservedAt carries its age).
      if (_controller == null || _controller!.isClosed) return;
      _controller!.addError(
        WeatherDataUnavailableException(
          reason: WeatherAbsenceReason.feedUnreachable,
          latitude: latitude,
          longitude: longitude,
          lastObservedAt: _lastCondition?.timestamp,
          cause: error,
        ),
      );
      return;
    }

    if (_controller == null || _controller!.isClosed) return;

    try {
      final condition = advisoriesToCondition(
        advisories,
        latitude: latitude,
        longitude: longitude,
      );
      _lastCondition = condition;
      _controller!.add(condition);
    } on WeatherDataUnavailableException catch (absence) {
      if (_controller == null || _controller!.isClosed) return;
      _controller!.addError(absence);
    }
  }

  /// Reduces a list of [Advisory] records to a single [WeatherCondition].
  ///
  /// Visible for testing. The worst-severity advisory drives the condition;
  /// a driver needs the most severe hazard on the road ahead, not an average.
  ///
  /// **An empty list THROWS [WeatherDataUnavailableException]** — it does not
  /// return a clear condition. Digitraffic publishing no advisory means no
  /// authority announced anything at this point; it says nothing whatever about
  /// the temperature, the visibility or the ice on the road, and black ice is
  /// routine with zero advisories published. Up to and including 0.4.4 this
  /// returned `WeatherCondition.clear()` — hardcoded +5 °C, 10 km visibility,
  /// `iceRisk: false` — which was a manufactured all-clear. It now stops.
  static WeatherCondition advisoriesToCondition(
    List<Advisory> advisories, {
    double? latitude,
    double? longitude,
  }) {
    final now = DateTime.now();
    if (advisories.isEmpty) {
      throw WeatherDataUnavailableException(
        reason: WeatherAbsenceReason.noAdvisoryPublished,
        latitude: latitude,
        longitude: longitude,
      );
    }

    final worst = advisories.reduce(
      (a, b) => _severityRank(a.severity) >= _severityRank(b.severity) ? a : b,
    );

    return _severityToCondition(worst.severity, now);
  }

  /// Orders severities for the worst-advisory reduction.
  ///
  /// [AdvisorySeverity.unknown] is declared FIRST in `condition_aggregator`, so
  /// its `index` is 0 — the lowest. Comparing raw indexes therefore made an
  /// advisory whose severity the authority never stated LOSE to a `minor` one
  /// and be discarded. An unstated severity means "something was declared, and
  /// how bad it is was not said" — it is not the benign end of the scale. It
  /// ranks above `minor`/`moderate` and below the stated `severe`/`extreme`.
  static int _severityRank(AdvisorySeverity severity) {
    switch (severity) {
      case AdvisorySeverity.minor:
        return 0;
      case AdvisorySeverity.moderate:
        return 1;
      case AdvisorySeverity.unknown:
        return 2;
      case AdvisorySeverity.severe:
        return 3;
      case AdvisorySeverity.extreme:
        return 4;
    }
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
  ///
  /// **Known limitation, not fixable inside 0.4.x.** The temperature,
  /// visibility and wind numbers below are carriers for an advisory's severity
  /// — Digitraffic never published them. `WeatherCondition`'s fields are
  /// non-nullable in this line, so a hazard *declared* by an authority cannot
  /// be carried without putting *some* number in them, and dropping the
  /// condition entirely would drop the driver's alert. They err toward caution
  /// (they never manufacture an all-clear), but do not read them as
  /// measurements. The 0.5.x line carries the declaration as an assertion and
  /// leaves the unmeasured fields null.
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
      // An advisory whose severity the authority did not state is NOT the
      // benign end of the scale. Up to 0.4.4 it was mapped alongside `minor`,
      // to a light, not-hazardous condition — downgrading an unstated severity
      // to "nothing much". It now carries the same caution band as `moderate`.
      case AdvisorySeverity.unknown:
        return WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -1.0,
          visibilityMeters: 800,
          windSpeedKmh: 25,
          timestamp: now,
        );
      case AdvisorySeverity.minor:
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
