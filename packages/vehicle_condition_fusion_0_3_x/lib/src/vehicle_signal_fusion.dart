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

/// Ambient temperature (°C) formerly assumed when the vehicle does not publish
/// `Vehicle.Exterior.AirTemperature`.
///
/// **Deprecated — this constant is a fabrication, not a safe default.** An
/// absent temperature is *unknown*, not "above freezing". Assuming +5 °C let a
/// missing signal *downgrade* a hazard: a car actively losing traction
/// (TCS/ABS/ESC engaged) on a road whose temperature it did not publish was
/// classified as `iceRisk: false` — "aquaplaning, not ice" — because the code
/// invented a warm reading. A real, present traction-loss event now keeps the
/// ice concern when the temperature is unknown (absence never downgrades a
/// hazard); the friction path was always temperature-independent.
///
/// The value (5.0) is retained for source compatibility and is still used ONLY
/// to disambiguate precipitation *type* (rain vs snow) when no ice hazard is at
/// stake. To model an unknown temperature as a first-class value rather than a
/// fabricated one, move to the `x.y` line where `airTempC` absence is carried
/// through the pipeline instead of being back-filled.
@Deprecated(
  'An absent temperature is unknown, not above-freezing. Assuming +5 °C '
  'downgraded ice hazards. A present traction-loss event now keeps the ice '
  'concern when temperature is unknown; move to the nullable-temperature x.y '
  'line to model absence as a first-class value.',
)
const double kAssumedAboveFreezingCelsius = 5.0;

/// Internal fallback used ONLY to disambiguate precipitation *type* (rain vs
/// snow) and to fill the non-nullable `WeatherCondition.temperatureCelsius`
/// field when the vehicle publishes no ambient temperature. It never decides
/// ice risk: ice is asserted from a direct friction measurement, or from a
/// present traction-loss event (which now stands on its own when the
/// temperature is unknown — see [vehicleSignalsToWeatherCondition]).
const double _kAbsentTempPrecipFallbackCelsius = 5.0;

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
///  * **precipitation** present iff wiper/rain-sensor say so; type is `snow`
///    when temperature ≤ 0 °C else `rain` (temperature disambiguates what the
///    wiper cannot); intensity from [_intensityForLevel]. When temperature is
///    absent, a non-hazard fallback is used ONLY for this rain/snow split (see
///    residual note below).
///  * **ice risk** iff a *direct* road measurement says so — friction below
///    [kIcyFrictionThreshold], OR a present traction-loss event (TCS/ABS/ESC
///    engaged) whose temperature is at/below [kColdSlipCelsius] **or unknown**.
///    Absence of temperature never *downgrades* this: a car losing grip on a
///    road whose temperature it did not publish keeps the ice concern rather
///    than being dismissed as aquaplaning (caution-add-only).
///  * **temperature** = ambient air temp, or a non-hazard fallback when absent
///    (fills the non-nullable field; never decides ice — see below).
///  * **visibility** = the documented [_visibilityMetersForLevel] proxy.
///
/// **Residual (fixed only on the nullable-temperature x.y line).** The
/// `WeatherCondition` this hands to the downstream classifier cannot express an
/// *unknown* temperature (`temperatureCelsius` is a non-nullable `double`), so
/// when `airTempC` is absent a fallback value still fills it and still drives
/// the rain-vs-snow split. That means a *freezing-rain* road with a dead
/// temperature sensor (no friction signal, no traction-loss event) can still be
/// classified `wet` rather than icy. The lethal path — a present traction-loss
/// event masked by an assumed-warm temperature — is closed here; the residual
/// requires modelling temperature-absence as a first-class value, which is a
/// breaking type change.
///
/// The result is handed to `DrivingConditionAssessment.fromCondition` — the
/// existing classifier — so road-surface classification logic is reused, not
/// duplicated.
WeatherCondition vehicleSignalsToWeatherCondition(
  VehicleConditionSignals s, {
  DateTime? timestamp,
}) {
  final airTemp = s.airTempC;
  // Non-hazard fallback: fills the non-nullable temperature field and the
  // rain/snow disambiguation ONLY. It never decides ice — see below.
  final temp = airTemp ?? _kAbsentTempPrecipFallbackCelsius;
  final level = _precipitationLevel(s);

  final precipType = level == 0
      ? PrecipitationType.none
      : (temp <= 0 ? PrecipitationType.snow : PrecipitationType.rain);

  // A present traction-loss event (TCS/ABS/ESC engaged) is a direct indicator
  // of grip loss. On a cold road it is ice; historically it was dismissed as
  // aquaplaning only when the ambient temperature read *above* freezing. But an
  // ABSENT temperature is unknown, not warm — assuming +5 °C once returned
  // `iceRisk: false` for a car that was actively skidding. Caution-add-only:
  // absence must never downgrade a hazard, so an unknown temperature keeps the
  // ice concern here (it does not clear it). The friction path below is
  // temperature-independent and unaffected.
  final tractionLoss =
      s.tcsEngaged == true || s.absEngaged == true || s.escEngaged == true;
  final coldOrUnknownTemp = airTemp == null || airTemp <= kColdSlipCelsius;

  final iceRisk =
      (s.roadFriction != null && s.roadFriction! < kIcyFrictionThreshold) ||
      (tractionLoss && coldOrUnknownTemp);

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
