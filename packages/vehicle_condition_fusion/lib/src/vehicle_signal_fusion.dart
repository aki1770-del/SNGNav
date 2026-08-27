import 'package:driving_weather/driving_weather.dart';

import 'vehicle_condition_signals.dart';

// ---------------------------------------------------------------------------
// Deterministic fusion thresholds (typed, named — no magic numbers inline).
// ---------------------------------------------------------------------------

/// Road-friction estimate below which the surface is treated as icy/snowy.
///
/// ⚠️ THIS THRESHOLD IS IN THE NORMALIZED 0.0–1.0 SCALE of
/// [VehicleConditionSignals.roadFriction] — **not** in the unit the vehicle
/// bus carries. `Vehicle.ADAS.ESC.RoadFriction.MostProbable` is declared by
/// VSS v6.0 (`spec/ADAS/ADAS.vspec`) as `unit: percent, min: 0, max: 100`,
/// where 0 = no friction and 100 = maximum friction. An ESC on black ice
/// reports about **18**, not 0.18. [VehicleConditionSignals.fromVss] performs
/// the ÷100 conversion and the clamp; anything that decodes the wire value by
/// hand must do the same or this threshold silently never fires.
///
/// The authority is the VSS specification, not this package and not the SDK
/// README: `kuksa_dart_sdk` 0.2.3 documented the range as 0.0–1.0, which is
/// how the app came to compare `18.0 < 0.3`, conclude the road was not icy,
/// and leave the one limb that fires BEFORE a slip permanently dead.
/// Corrected in the SDK from 0.2.4 onward.
const double kIcyFrictionThreshold = 0.3;

/// Ambient temperature (°C) at/below which a TCS/ABS traction-loss event is
/// attributed to ice rather than aquaplaning / hard braking.
const double kColdSlipCelsius = 2.0;

// NOTE: `kAssumedAboveFreezingCelsius` (5.0 °C) was REMOVED in 0.5.0.
//
// It was the constant that made a vehicle with no air-temperature signal read as
// ABOVE FREEZING. Its docstring said the assumption was safe because "a missing
// signal never fabricates ice" — which is true, and beside the point: a missing
// signal was instead fabricating the *absence* of ice. An Akita vehicle whose
// temperature sensor was silent reported +5.0 °C, and the downstream classifier
// dutifully returned a dry road with full grip.
//
// This is the same defect as `WeatherCondition.clear()` (driving_weather 0.4.4),
// sitting in the OFFLINE path — the exact path a driver is on when the network
// feed is gone. See CHANGELOG 0.5.0.

// ---------------------------------------------------------------------------
// Deterministic vehicle-signal → existing-pipeline mapping.
// ---------------------------------------------------------------------------

/// Precipitation severity bucket 0 (none) … 3 (heavy), derived as the more
/// severe of the wiper-level and rain-sensor readings — or `null` when the
/// vehicle published NEITHER signal.
///
/// `null` is not level 0. Up to 0.4.0 a vehicle that reported no wiper state and
/// no rain sensor fell through to level 0, i.e. "no precipitation" — a positive
/// claim about weather nobody had observed.
int? _precipitationLevel(VehicleConditionSignals s) {
  final wi = s.wiperIntensity;
  final ri = s.rainIntensity;

  // Neither signal present → we were told nothing about precipitation.
  if (wi == null && ri == null) return null;

  int wiperLevel = 0;
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
/// cue, not a measurement, which is why the resulting condition is tagged
/// [ObservationSource.derived]. Only moderate+ precipitation reduces visibility
/// enough to raise the Snow Scene's fog wall.
double _visibilityMetersForLevel(int level) => switch (level) {
      0 => 10000.0, // clear
      1 => 5000.0, // light — still clear of the fog threshold
      2 => 800.0, // moderate — fog wall begins
      _ => 300.0, // heavy — short draw distance
    };

/// Tri-state ice determination from the vehicle's own signals.
///
/// * `true`  — POSITIVE evidence: a direct friction measurement below
///   [kIcyFrictionThreshold], or a traction-loss event (TCS/ABS/ESC) at/below
///   [kColdSlipCelsius].
/// * `false` — we actually MEASURED the road friction and it was fine.
/// * `null`  — no friction measurement at all. We do not know.
///
/// The asymmetry is the point. Up to 0.4.0 this was a bare `bool`, so a vehicle
/// publishing no friction signal and no traction event returned `false` — "no
/// ice" — which is a claim, not an absence.
bool? _iceRisk(VehicleConditionSignals s, double? temp) {
  final friction = s.roadFriction;

  // POSITIVE: a direct road measurement.
  if (friction != null && friction < kIcyFrictionThreshold) return true;

  // POSITIVE: traction loss that the temperature lets us attribute to ice.
  final tractionLoss =
      s.tcsEngaged == true || s.absEngaged == true || s.escEngaged == true;
  if (tractionLoss && temp != null && temp <= kColdSlipCelsius) return true;

  // NEGATIVE requires knowledge: only a real friction reading lets us say the
  // road is NOT icy.
  if (friction != null) return false;

  // No friction signal. A traction event we could not attribute (because the
  // temperature is absent) is not evidence of no-ice either.
  return null;
}

/// Pure, total, deterministic mapping: decoded vehicle signals → the
/// [WeatherCondition] the `driving_conditions` pipeline consumes.
///
/// ## The Measured-or-Absent contract (0.5.0)
///
/// Every field this function cannot substantiate from a real vehicle signal is
/// left **`null`**. It fabricates nothing.
///
///  * **temperature** = ambient air temp, or `null` when the vehicle does not
///    publish it. (0.4.0 substituted `kAssumedAboveFreezingCelsius` = 5.0 °C —
///    so a silent temperature sensor read as "not freezing".)
///  * **precipitation** — `null` type and `null` intensity when the vehicle
///    published neither wiper state nor rain sensor. When precipitation IS
///    reported but the temperature is absent, the *intensity* is carried and the
///    *type* is left `null`: we know it is precipitating, but only the
///    temperature can tell snow from rain, and we will not guess.
///  * **ice risk** — tri-state (see [_iceRisk]). `null` when no friction signal
///    exists; `true` only from a direct friction measurement or an attributable
///    traction-loss event.
///  * **visibility** = the [_visibilityMetersForLevel] proxy when precipitation
///    is known, `null` otherwise. It is a cue, not a measurement — hence
///    [ObservationSource.derived].
///  * **wind** = `null`, always. The snow-safety signal set does not carry wind.
///    (0.4.0 emitted `windSpeedKmh: 0.0` with a comment saying the signal set
///    does not carry wind — stating the absence, then filling it in anyway.)
WeatherCondition vehicleSignalsToWeatherCondition(
  VehicleConditionSignals s, {
  DateTime? timestamp,
}) {
  final temp = s.airTempC; // no fallback: null means NOT MEASURED
  final level = _precipitationLevel(s);

  final PrecipitationType? precipType;
  if (level == null) {
    precipType = null; // precipitation not reported at all
  } else if (level == 0) {
    precipType = PrecipitationType.none; // the vehicle says it is not raining
  } else if (temp == null) {
    // It IS precipitating, but without a temperature we cannot say whether it is
    // snow or rain. Carry the intensity; leave the type honestly absent.
    precipType = null;
  } else {
    precipType = temp <= 0 ? PrecipitationType.snow : PrecipitationType.rain;
  }

  return WeatherCondition(
    precipType: precipType,
    intensity: level == null ? null : _intensityForLevel(level),
    temperatureCelsius: temp,
    visibilityMeters: level == null ? null : _visibilityMetersForLevel(level),
    windSpeedKmh: null, // not in the snow-safety signal set — so we say nothing
    iceRisk: _iceRisk(s, temp),
    // Real exterior humidity, when the vehicle publishes it. With the ambient
    // temperature this lets the shared classifier catch radiative-frost black
    // ice offline — BEFORE friction/traction fire (they only reveal ice AFTER
    // the wheels have already slipped). Absent → null → the classifier abstains.
    humidityRH: s.humidityRH,
    // The visibility figure is a proxy and the precipitation type is inferred,
    // so this condition is DERIVED, not directly measured. Saying so is part of
    // the contract: a consumer can tell a road-authority reading from a cue.
    source: ObservationSource.derived,
    timestamp: timestamp ?? DateTime.now(),
  );
}
