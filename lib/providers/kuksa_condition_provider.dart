/// KUKSA in-vehicle condition source — the compound-failure worst-case data path.
///
/// When the network and GPS are gone, the vehicle's *own* signals are still on
/// the local KUKSA databroker bus: road-friction estimate (ESC), TCS/ABS
/// engagement, wiper / rain-sensor intensity, and ambient temperature. This
/// provider subscribes to those VSS signals over gRPC via our published
/// `kuksa_dart_sdk` client and fuses them — **deterministically and typed** —
/// into the SAME `driving_conditions` picture (`DrivingConditionAssessment`)
/// that already drives the 3D Snow Scene. No network, no GPS, no cloud weather:
/// just the bus the car already speaks.
///
/// ## Determinism
///
/// The fusion is a pure, total function of the decoded signals: there is NO
/// LLM, NO prose, NO ad-hoc heuristic. Raw VSS values are mapped to a
/// [WeatherCondition] by explicit typed rules (see
/// [vehicleSignalsToWeatherCondition]) and then handed to the EXISTING pipeline
/// — [DrivingConditionAssessment.fromCondition] (which itself calls
/// [RoadSurfaceState.fromCondition]) — rather than duplicating classification
/// logic. Surface-state flicker is debounced with the existing
/// [HysteresisFilter].
///
/// ## Honest degradation (no fabrication)
///
/// If no databroker is reachable, or the stream errors/ends mid-session, the
/// provider NEVER invents a condition. It emits a
/// [KuksaConditionUpdate.unavailable] marker (so the caller can keep its
/// last-good / offline-first default and stop claiming "live") — exactly the
/// honest-degradation contract the GPS-loss path already follows. Reads only;
/// this provider never writes to or commands the vehicle.
///
/// ## Honest bounds
///
/// A vehicle does not measure meteorological visibility. The visibility band
/// here is an **explicit typed proxy** derived from precipitation intensity
/// (wiper / rain-sensor), documented as such in [_visibilityMetersForLevel] —
/// it is a glanceable cue, not a sensor reading. Likewise wiper/rain intensity
/// cannot distinguish rain from snow; ambient temperature disambiguates
/// (≤ 0 °C → snow). Road friction and TCS/ABS engagement, by contrast, ARE
/// direct road-surface measurements and gate the ice-risk decision.
library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';

// ---------------------------------------------------------------------------
// Deterministic fusion thresholds (typed, named — no magic numbers inline).
// ---------------------------------------------------------------------------

/// Road-friction estimate (0.0–1.0) below which the surface is treated as
/// icy/snowy. Matches the threshold documented on
/// [kRoadFrictionMostProbable] in `kuksa_dart_sdk`.
const double kIcyFrictionThreshold = 0.3;

/// Ambient temperature (°C) at/below which a TCS/ABS traction-loss event is
/// attributed to ice rather than aquaplaning / hard braking.
const double kColdSlipCelsius = 2.0;

/// Ambient temperature (°C) assumed when the vehicle does not publish
/// `Vehicle.Exterior.AirTemperature`. Above freezing so a *missing* signal
/// never fabricates ice — ice is only ever asserted from a real friction /
/// traction measurement.
const double kAssumedAboveFreezingCelsius = 5.0;

// ---------------------------------------------------------------------------
// Typed snapshot of the decoded snow-safety signals.
// ---------------------------------------------------------------------------

/// An immutable, decoded snapshot of the snow-safety VSS signals.
///
/// All fields are nullable: a signal the vehicle has not (yet) published is
/// `null`, never a fabricated default.
class VehicleConditionSignals {
  const VehicleConditionSignals({
    this.roadFriction,
    this.tcsEngaged,
    this.absEngaged,
    this.wiperIntensity,
    this.rainIntensity,
    this.airTempC,
    this.speedKmh,
  });

  /// Most-probable road friction estimate (0.0–1.0) from the ESC.
  final double? roadFriction;

  /// Traction Control System currently engaged (active traction loss).
  final bool? tcsEngaged;

  /// Anti-lock Braking System currently engaged (braking on low friction).
  final bool? absEngaged;

  /// Front wiper intensity level (0–5) — precipitation proxy.
  final int? wiperIntensity;

  /// Rain-detection sensor intensity (0–100%).
  final int? rainIntensity;

  /// Ambient outside air temperature (°C).
  final double? airTempC;

  /// Vehicle speed (km/h) — carried for context; not used in classification.
  final double? speedKmh;

  /// Whether at least one classification-relevant signal has a real value.
  bool get hasAnySignal =>
      roadFriction != null ||
      tcsEngaged != null ||
      absEngaged != null ||
      wiperIntensity != null ||
      rainIntensity != null ||
      airTempC != null;

  /// Decode a KUKSA subscribe/getValues snapshot (path → [Datapoint]) into a
  /// typed snapshot. Signals that are absent, value-less, or carry an
  /// unexpected wire type decode to `null` (never guessed).
  factory VehicleConditionSignals.fromDatapoints(
    Map<String, Datapoint> datapoints,
  ) {
    double? readDouble(String path) {
      final dp = datapoints[path];
      if (dp == null || !dp.hasValue) return null;
      return dp.floatValue ?? dp.doubleValue ?? dp.int32Value?.toDouble();
    }

    bool? readBool(String path) {
      final dp = datapoints[path];
      if (dp == null || !dp.hasValue) return null;
      return dp.boolValue;
    }

    int? readInt(String path) {
      final dp = datapoints[path];
      if (dp == null || !dp.hasValue) return null;
      return dp.int32Value ?? dp.uint32Value ?? dp.int64Value;
    }

    return VehicleConditionSignals(
      roadFriction: readDouble(kRoadFrictionMostProbable),
      tcsEngaged: readBool(kTcsIsEngaged),
      absEngaged: readBool(kAbsIsEngaged),
      wiperIntensity: readInt(kWiperFrontIntensity),
      rainIntensity: readInt(kRaindetectionIntensity),
      airTempC: readDouble(kAirTemperature),
      speedKmh: readDouble(kVehicleSpeed),
    );
  }
}

// ---------------------------------------------------------------------------
// Deterministic VSS → existing-pipeline mapping.
// ---------------------------------------------------------------------------

/// Precipitation severity bucket 0 (none) … 3 (heavy), derived as the more
/// severe of the wiper-level and rain-sensor readings.
int _precipitationLevel(VehicleConditionSignals s) {
  int wiperLevel = 0;
  final wi = s.wiperIntensity;
  if (wi != null) {
    if (wi <= 0) {
      wiperLevel = 0;
    } else if (wi <= 2) {
      wiperLevel = 1;
    } else if (wi <= 4) {
      wiperLevel = 2;
    } else {
      wiperLevel = 3;
    }
  }

  int rainLevel = 0;
  final ri = s.rainIntensity;
  if (ri != null) {
    if (ri <= 0) {
      rainLevel = 0;
    } else if (ri <= 33) {
      rainLevel = 1;
    } else if (ri <= 66) {
      rainLevel = 2;
    } else {
      rainLevel = 3;
    }
  }

  return wiperLevel > rainLevel ? wiperLevel : rainLevel;
}

PrecipitationIntensity _intensityForLevel(int level) => switch (level) {
      0 => PrecipitationIntensity.none,
      1 => PrecipitationIntensity.light,
      2 => PrecipitationIntensity.moderate,
      _ => PrecipitationIntensity.heavy,
    };

/// Explicit typed *proxy* for visibility (metres) from precipitation level.
/// A vehicle has no meteorological visibility sensor — this is a documented
/// cue, not a measurement. Only moderate+ precipitation reduces visibility
/// enough to raise the Snow Scene's fog wall.
double _visibilityMetersForLevel(int level) => switch (level) {
      0 => 10000.0, // clear
      1 => 5000.0, // light — still clear of the fog threshold
      2 => 800.0, // moderate — fog wall begins
      _ => 300.0, // heavy — short draw distance
    };

/// Pure, total, deterministic mapping: decoded vehicle signals → the existing
/// [WeatherCondition] the `driving_conditions` pipeline already consumes.
///
/// The rules:
///  * **temperature** = ambient air temp, or [kAssumedAboveFreezingCelsius]
///    when absent (a missing temp never fabricates ice).
///  * **precipitation** present iff wiper/rain-sensor say so; type is `snow`
///    when temperature ≤ 0 °C else `rain` (temperature disambiguates what the
///    wiper cannot); intensity from [_intensityForLevel].
///  * **ice risk** iff a *direct* road measurement says so — friction below
///    [kIcyFrictionThreshold], OR TCS/ABS engaged at/below [kColdSlipCelsius].
///  * **visibility** = the documented [_visibilityMetersForLevel] proxy.
///
/// The result is handed to [DrivingConditionAssessment.fromCondition] — the
/// existing classifier — so road-surface classification logic is reused, not
/// duplicated.
WeatherCondition vehicleSignalsToWeatherCondition(
  VehicleConditionSignals s, {
  DateTime? timestamp,
}) {
  final temp = s.airTempC ?? kAssumedAboveFreezingCelsius;
  final level = _precipitationLevel(s);

  final precipType = level == 0
      ? PrecipitationType.none
      : (temp <= 0 ? PrecipitationType.snow : PrecipitationType.rain);

  final iceRisk = (s.roadFriction != null &&
          s.roadFriction! < kIcyFrictionThreshold) ||
      ((s.tcsEngaged == true || s.absEngaged == true) &&
          temp <= kColdSlipCelsius);

  return WeatherCondition(
    precipType: precipType,
    intensity: _intensityForLevel(level),
    temperatureCelsius: temp,
    visibilityMeters: _visibilityMetersForLevel(level),
    windSpeedKmh: 0.0, // not in the snow-safety signal set
    iceRisk: iceRisk,
    timestamp: timestamp ?? DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// Provider output.
// ---------------------------------------------------------------------------

/// One emission from [KuksaConditionProvider].
///
/// Either a live condition ([isAvailable] == true, [assessment] non-null), or
/// an honest unavailability marker ([KuksaConditionUpdate.unavailable]) telling
/// the caller there are no live vehicle signals — never a fabricated scene.
class KuksaConditionUpdate {
  const KuksaConditionUpdate({
    required this.assessment,
    required this.signals,
    required this.live,
    this.unavailableReason,
  });

  /// An honest "no live vehicle signals" marker — carries no assessment.
  const KuksaConditionUpdate.unavailable({String? reason})
      : assessment = null,
        signals = null,
        live = false,
        unavailableReason = reason ?? 'no live vehicle signals';

  /// The fused driving-condition picture, or `null` when unavailable.
  final DrivingConditionAssessment? assessment;

  /// The decoded vehicle signals behind [assessment], or `null` when
  /// unavailable.
  final VehicleConditionSignals? signals;

  /// True when this update reflects real, live vehicle signals.
  final bool live;

  /// Why no live signals are available, when [isAvailable] is false.
  final String? unavailableReason;

  /// Whether this update carries a usable assessment.
  bool get isAvailable => assessment != null;
}

// ---------------------------------------------------------------------------
// The provider.
// ---------------------------------------------------------------------------

/// Subscribes to KUKSA snow-safety VSS signals and emits a deterministically
/// fused [KuksaConditionUpdate] stream for the Snow Scene.
///
/// Construct directly from any `Stream<Map<String, Datapoint>>` — including a
/// test stream of mock [Datapoint]s — for full testability without a running
/// databroker; or use [KuksaConditionProvider.connect] to wire a real
/// [KuksaClient].
class KuksaConditionProvider {
  /// Primary, injectable constructor. [updates] is the raw subscribe shape
  /// (`path → Datapoint`, partial after the first emission).
  KuksaConditionProvider({
    required Stream<Map<String, Datapoint>> updates,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
    DateTime Function()? clock,
  })  : _surfaceFilter =
            surfaceFilter ?? HysteresisFilter<RoadSurfaceState>(),
        _clock = clock ?? DateTime.now {
    _sub = updates.listen(
      _onUpdate,
      onError: _onSourceError,
      onDone: _onSourceDone,
      cancelOnError: false,
    );
  }

  final HysteresisFilter<RoadSurfaceState> _surfaceFilter;
  final DateTime Function() _clock;
  final StreamController<KuksaConditionUpdate> _controller =
      StreamController<KuksaConditionUpdate>.broadcast();

  /// Running snapshot of the latest value seen per path — KUKSA `subscribe`
  /// emits only the signals that changed after the first cycle, so updates are
  /// merged here into a complete picture.
  final Map<String, Datapoint> _latest = {};

  StreamSubscription<Map<String, Datapoint>>? _sub;
  DrivingConditionAssessment? _lastAssessment;
  bool _available = true;

  /// The fused condition stream driving the Snow Scene.
  Stream<KuksaConditionUpdate> get conditions => _controller.stream;

  /// Whether the most recent activity indicates live signals are flowing.
  bool get available => _available;

  void _onUpdate(Map<String, Datapoint> update) {
    update.forEach((path, dp) {
      if (dp.hasValue) _latest[path] = dp;
    });

    final signals = VehicleConditionSignals.fromDatapoints(_latest);
    // Nothing decodable yet — do NOT fabricate a condition.
    if (!signals.hasAnySignal) return;

    _available = true;
    final weather =
        vehicleSignalsToWeatherCondition(signals, timestamp: _clock());
    final candidate = DrivingConditionAssessment.fromCondition(weather);

    // Debounce the road-surface picture with the existing HysteresisFilter:
    // hold the last-good assessment until a new surface state persists
    // (threshold readings), so the scene does not flicker at boundaries.
    final stable = _surfaceFilter.add(candidate.surfaceState);
    if (_lastAssessment == null || stable == candidate.surfaceState) {
      _lastAssessment = candidate;
    }

    if (!_controller.isClosed) {
      _controller.add(KuksaConditionUpdate(
        assessment: _lastAssessment,
        signals: signals,
        live: true,
      ));
    }
  }

  void _onSourceError(Object error, StackTrace stackTrace) {
    // Honest degradation: a broker drop / stream error NEVER fabricates a
    // condition — surface unavailability so the caller keeps its offline
    // default.
    _available = false;
    if (!_controller.isClosed) {
      _controller
          .add(KuksaConditionUpdate.unavailable(reason: error.toString()));
    }
  }

  void _onSourceDone() {
    _available = false;
    if (!_controller.isClosed) {
      _controller.add(const KuksaConditionUpdate.unavailable(
        reason: 'vehicle signal stream ended',
      ));
    }
  }

  /// Releases the source subscription and closes the output stream.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) await _controller.close();
  }

  /// Connects [client] and subscribes to [paths] (default
  /// [kSnowSafetySignals]), returning a wired provider.
  ///
  /// Connection failure rethrows — the caller owns the honest no-broker
  /// fallback (keep the offline default; never wire a fabricated source),
  /// matching the app's existing live-source opt-in pattern.
  static Future<KuksaConditionProvider> connect(
    KuksaClient client, {
    List<String> paths = kSnowSafetySignals,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
  }) async {
    await client.connect();
    return KuksaConditionProvider(
      updates: client.subscribe(paths),
      surfaceFilter: surfaceFilter,
    );
  }
}
