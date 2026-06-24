import 'package:driving_weather/driving_weather.dart';

import 'vehicle_condition_signals.dart';

// ---------------------------------------------------------------------------
// Deterministic fusion thresholds (typed, named — no magic numbers inline).
// ---------------------------------------------------------------------------

/// Road-friction estimate (0.0–1.0) below which the surface is treated as
/// icy/snowy. Matches the threshold documented on
/// `kRoadFrictionMostProbable` in `kuksa_dart_sdk`.
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
// Deterministic vehicle-signal → existing-pipeline mapping.
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
/// The result is handed to `DrivingConditionAssessment.fromCondition` — the
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
