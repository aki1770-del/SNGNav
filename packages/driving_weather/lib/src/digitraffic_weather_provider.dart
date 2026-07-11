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
/// ## An assertion is not a measurement (Measured-or-Absent, O4)
///
/// Digitraffic publishes road SITUATIONS declared by an authority, with a
/// CAP-class `severity` (minor/moderate/severe/extreme). **It measures no
/// temperature, no visibility and no wind.**
///
/// Up to and including 0.4.4 this adapter laundered that declaration into
/// invented sensor readings — a severe advisory became `-4.0 °C`, `150 m`
/// visibility and `40 km/h` wind, none of which Digitraffic said. Worse, an
/// EMPTY advisory list (meaning only "no advisory was published") became a
/// fabricated clear condition at `+5.0 °C` with `iceRisk: false`.
///
/// It no longer does either. The declaration is carried as a
/// [HazardAssertion]; every field Digitraffic does not measure stays `null`.
/// The driver still gets the alert — [WeatherCondition.hazard] fires
/// [SafetyVerdict.hazardous] on a severe or extreme assertion even when every
/// measured field is absent — but nothing is invented to carry it.
///
/// An empty advisory list maps to [WeatherCondition.unknown]. "No advisory was
/// published" is not "the road is clear and +5 °C".
///
/// ## Offline behaviour
///
/// On fetch failure this provider emits [WeatherStale] (carrying the real age
/// of the last observation and the cause) or, with no prior observation,
/// [WeatherUnavailable]. It never re-emits an old condition wearing a fresh
/// face.
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
import 'weather_reading.dart';

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

  StreamController<WeatherReading>? _controller;
  Timer? _timer;

  /// The last condition actually observed, and when it was actually observed.
  /// Both are null until the first successful fetch.
  WeatherCondition? _lastCondition;
  DateTime? _lastObservedAt;

  /// When the provider first found itself without data. Cleared on success.
  DateTime? _unavailableSince;

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
  Stream<WeatherReading> get conditions {
    _controller ??= StreamController<WeatherReading>.broadcast();
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
      _lastObservedAt = condition.timestamp;
      _unavailableSince = null;
      _controller!.add(WeatherObserved(condition));
    } catch (error) {
      // The fetch failed. Say so — never re-emit an old condition as though it
      // were fresh, and never substitute a synthetic clear value.
      if (_controller == null || _controller!.isClosed) return;
      final now = DateTime.now();
      final last = _lastCondition;
      final observedAt = _lastObservedAt;
      if (last != null && observedAt != null) {
        _controller!.add(
          WeatherStale(
            lastKnown: last,
            observedAt: observedAt,
            age: now.difference(observedAt),
            cause: error,
          ),
        );
      } else {
        _unavailableSince ??= now;
        _controller!.add(
          WeatherUnavailable(since: _unavailableSince!, cause: error),
        );
      }
    }
  }

  /// Reduces a list of [Advisory] records to a single [WeatherCondition].
  ///
  /// Visible for testing. The worst-severity advisory drives the condition;
  /// a driver needs the most severe hazard on the road ahead, not an average.
  ///
  /// **Empty list → [WeatherCondition.unknown], NOT a clear condition.** An
  /// empty advisory feed means "no advisory was published". It does not mean
  /// the road is clear, and it certainly does not mean +5 °C with no ice.
  /// Nothing was measured, so nothing is claimed.
  static WeatherCondition advisoriesToCondition(List<Advisory> advisories) {
    final now = DateTime.now();
    if (advisories.isEmpty) {
      return WeatherCondition.unknown(timestamp: now);
    }

    final worst = advisories.reduce(
      (a, b) => _severityRank(a.severity) >= _severityRank(b.severity) ? a : b,
    );

    return _severityToCondition(worst.severity, now);
  }

  /// Orders CAP severities for the worst-advisory reduce.
  ///
  /// NOT `AdvisorySeverity.index`. In `condition_aggregator`,
  /// `AdvisorySeverity.unknown` is declared FIRST and therefore has index 0 —
  /// the LOWEST — so a raw index comparison silently discards an advisory whose
  /// severity the authority never stated in favour of a `minor` one. That is an
  /// unstated severity sorted onto the benign end of the scale: exactly the
  /// defect `_mapSeverity` refuses one method below.
  ///
  /// An unstated severity ranks ABOVE minor and moderate — something was
  /// declared and we do not know how bad it is — and below severe/extreme,
  /// which are stated and worse.
  static int _severityRank(AdvisorySeverity severity) {
    switch (severity) {
      case AdvisorySeverity.extreme:
        return 5;
      case AdvisorySeverity.severe:
        return 4;
      case AdvisorySeverity.unknown:
        return 3;
      case AdvisorySeverity.moderate:
        return 2;
      case AdvisorySeverity.minor:
        return 1;
    }
  }

  /// Maps a CAP-class [AdvisorySeverity] onto a [WeatherCondition] carrying a
  /// [HazardAssertion] — and NOTHING else.
  ///
  /// Digitraffic announces road *situations*, not sensor weather. It supplies
  /// no temperature, no visibility, no wind and no precipitation type, so every
  /// one of those fields is left `null` here. Inventing them (as versions up to
  /// 0.4.4 did) turned an authority's declaration into a fake measurement.
  ///
  /// The safety signal survives intact: [WeatherCondition.hazard] returns
  /// [SafetyVerdict.hazardous] for a severe or extreme assertion regardless of
  /// which measured fields are absent. Minor and moderate assertions yield
  /// [SafetyVerdict.unknown] — the authority has said something, but nobody
  /// measured the road, so this is explicitly not a clear-road verdict.
  static WeatherCondition _severityToCondition(
    AdvisorySeverity severity,
    DateTime now,
  ) {
    return WeatherCondition.unknown(
      timestamp: now,
      hazardAssertion: _mapSeverity(severity),
    );
  }

  /// CAP severity → [HazardAssertion]. A pure relabelling; no data is added.
  static HazardAssertion _mapSeverity(AdvisorySeverity severity) {
    switch (severity) {
      case AdvisorySeverity.extreme:
        return HazardAssertion.extreme;
      case AdvisorySeverity.severe:
        return HazardAssertion.severe;
      case AdvisorySeverity.moderate:
        return HazardAssertion.moderate;
      case AdvisorySeverity.minor:
        return HazardAssertion.minor;
      case AdvisorySeverity.unknown:
        // An advisory exists but the feed did not state its severity. It is
        // NOT minor — downgrading an unstated severity to the benign end of
        // the scale is the defect this whole contract exists to remove.
        return HazardAssertion.unknown;
    }
  }
}
