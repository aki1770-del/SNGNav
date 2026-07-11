/// Weather condition — the atomic unit of weather data for driving applications.
///
/// Models current weather at a vehicle's location. Fields cover
/// precipitation type, intensity, wind, visibility, and ice risk.
///
/// ## The Measured-or-Absent contract
///
/// Every MEASURED quantity on [WeatherCondition] is **nullable**, and `null`
/// means **NOT MEASURED**. It never means zero, never means benign, never
/// means "clear". No constructor substitutes a literal for a field the feed
/// did not supply.
///
/// Safety verdicts ([WeatherCondition.hazard] and friends) are therefore
/// **tri-state** ([SafetyVerdict]), not `bool`: a `bool` cannot express "I do
/// not know", so it silently resolves absence to its `false` branch — which,
/// for a hazard question, is the "clear road" branch. That was a real defect
/// in versions up to 0.4.4; see CHANGELOG.
///
/// The verdicts carry a deliberate **asymmetry**: POSITIVE evidence of a
/// hazard fires even when other fields are absent, but the NEGATIVE verdict
/// ("all clear") requires complete knowledge. Being offline does not mean
/// "hazard" — it means [SafetyVerdict.unknown], which is a state the driver
/// can be TOLD about, rather than a green light.
///
/// Weather sources are pluggable via [WeatherProvider], which delivers
/// readings as a sealed `WeatherReading` (observed / stale / unavailable).
library;

import 'package:equatable/equatable.dart';

/// Type of precipitation observed.
enum PrecipitationType {
  /// No precipitation.
  none,

  /// Rain.
  rain,

  /// Snow — the primary hazard scenario.
  snow,

  /// Sleet (mixed rain/snow).
  sleet,

  /// Hail.
  hail,
}

/// Intensity of precipitation.
enum PrecipitationIntensity {
  /// No precipitation.
  none,

  /// Light — minor impact on driving.
  light,

  /// Moderate — reduced visibility, increased stopping distance.
  moderate,

  /// Heavy — significant safety impact. May trigger safety alert.
  heavy,
}

/// Where the values on a [WeatherCondition] came from.
///
/// This records the PROVENANCE of the fields that are present. It says nothing
/// about the fields that are absent — absence is carried by `null`, always.
enum ObservationSource {
  /// The present fields originate in a real-world observation feed.
  ///
  /// Fields that feed did not supply are `null`, never filled in.
  measured,

  /// The present fields were computed or proxied from other signals rather
  /// than directly observed (e.g. a visibility estimate inferred from a
  /// coarse severity level).
  derived,

  /// The present fields are synthetic — a scenario ASSERTED by a simulator.
  ///
  /// A simulator asserting a scenario is honest: it is not a claim about the
  /// world. Never select a simulated source on a path a driver relies on.
  simulated,
}

/// A hazard DECLARED by an authority, as distinct from a hazard MEASURED by a
/// sensor.
///
/// Road-authority feeds (e.g. Fintraffic Digitraffic) publish *situations* with
/// a CAP-class severity. They measure no temperature, no visibility and no
/// wind. Carrying that declaration here — instead of laundering it into
/// invented sensor readings — is the whole point: the driver still gets the
/// alert, and the fields nobody measured stay honestly `null`.
enum HazardAssertion {
  /// An authority is reporting no hazard.
  none,

  /// An authority has published an advisory but did NOT state its severity.
  ///
  /// This is not [none] and it is not [minor] — downgrading an unstated
  /// severity to the benign end of the scale is the same defect this contract
  /// exists to remove. Something was declared; how bad it is was not.
  unknown,

  /// Minor severity (CAP).
  minor,

  /// Moderate severity (CAP).
  moderate,

  /// Severe severity (CAP).
  severe,

  /// Extreme severity (CAP).
  extreme,
}

/// A tri-state safety answer. The third state is the point.
enum SafetyVerdict {
  /// Positive evidence of the hazard. Fires on partial data.
  hazardous,

  /// Positive evidence of the ABSENCE of the hazard. Requires complete data.
  notHazardous,

  /// Not enough was measured to answer. This is NOT "no hazard" — it is
  /// "nobody looked". Surface it to the driver; do not resolve it silently.
  unknown,
}

class WeatherCondition extends Equatable {
  /// Type of precipitation, or `null` when the feed did not report it.
  ///
  /// `null` is NOT [PrecipitationType.none] — "we were not told" is not
  /// "there is no precipitation".
  final PrecipitationType? precipType;

  /// Intensity of precipitation, or `null` when the feed did not report it.
  final PrecipitationIntensity? intensity;

  /// Temperature in Celsius, or `null` when not measured. Snow threshold ≤ 0°C.
  ///
  /// `null` never means 0 °C and never means "above freezing".
  final double? temperatureCelsius;

  /// Visibility in metres, or `null` when not measured.
  /// 10000 = clear, < 1000 = reduced, < 200 = hazardous.
  ///
  /// `null` never means "clear".
  final double? visibilityMeters;

  /// Wind speed in km/h, or `null` when not measured.
  ///
  /// `null` never means "calm".
  final double? windSpeedKmh;

  /// Whether road icing / black-ice risk is present, or `null` when it could
  /// not be determined.
  ///
  /// `null` never means "no ice".
  final bool? iceRisk;

  /// Relative humidity in PERCENT `[0, 100]`, or `null` when the feed does not
  /// supply it.
  ///
  /// Load-bearing for radiative-frost black ice: clear-sky cooling can drop the
  /// road surface below freezing while the ambient air is still a few degrees
  /// above 0 °C, and detecting that window needs humidity. `null` means "not
  /// measured", never "dry": when it is absent the radiative-frost check simply
  /// ABSTAINS (it neither fabricates a black-ice hazard nor changes the other,
  /// non-humidity branches — freezing rain, sub-(-3 °C) residual ice, the
  /// explicit [iceRisk] flag — which classify exactly as before).
  ///
  /// This field was already honest in 0.4.4. The Measured-or-Absent contract
  /// did not invent a pattern; it FINISHED the one this field started.
  final double? humidityRH;

  /// A hazard DECLARED by an authority (not measured here), or `null` when no
  /// authority feed is involved.
  ///
  /// See [HazardAssertion]. [SafetyVerdict.hazardous] fires on
  /// [HazardAssertion.severe] and [HazardAssertion.extreme] even when every
  /// measured field is absent.
  final HazardAssertion? hazardAssertion;

  /// Where the present fields came from. See [ObservationSource].
  final ObservationSource source;

  /// When this condition was observed.
  final DateTime timestamp;

  const WeatherCondition({
    this.precipType,
    this.intensity,
    this.temperatureCelsius,
    this.visibilityMeters,
    this.windSpeedKmh,
    this.iceRisk,
    this.humidityRH,
    this.hazardAssertion,
    required this.source,
    required this.timestamp,
  });

  /// Nothing was measured.
  ///
  /// Every measured field is `null`. This is what an empty feed, a coverage
  /// gap, or a source that reports no observation actually means. It is NOT
  /// "the road is clear".
  const WeatherCondition.unknown({
    required this.timestamp,
    this.source = ObservationSource.measured,
    this.hazardAssertion,
  }) : precipType = null,
       intensity = null,
       temperatureCelsius = null,
       visibilityMeters = null,
       windSpeedKmh = null,
       iceRisk = null,
       humidityRH = null;

  /// Clear weather ASSERTED BY A SIMULATOR — no precipitation, good
  /// visibility, no ice.
  ///
  /// This is the honest successor to the removed `WeatherCondition.clear()`.
  /// The values are synthetic ([ObservationSource.simulated]) and are a claim
  /// about a *scenario*, never about the world. A live provider must never
  /// construct this: an absent measurement is [WeatherCondition.unknown].
  const WeatherCondition.simulatedClear({required this.timestamp})
    : precipType = PrecipitationType.none,
      intensity = PrecipitationIntensity.none,
      temperatureCelsius = 5.0,
      visibilityMeters = 10000.0,
      windSpeedKmh = 0.0,
      iceRisk = false,
      humidityRH = null,
      hazardAssertion = null,
      source = ObservationSource.simulated;

  // ---------------------------------------------------------------------------
  // Safety verdicts — tri-state, never bool.
  // ---------------------------------------------------------------------------

  /// Are conditions hazardous?
  ///
  /// [SafetyVerdict.hazardous] on positive evidence from ANY known field —
  /// ice risk, a severe/extreme authority assertion, heavy precipitation, or
  /// visibility below 200 m — even if every other field is absent.
  ///
  /// [SafetyVerdict.notHazardous] ONLY when ice risk, intensity and visibility
  /// are all known and none of them fired. A negative claim requires complete
  /// knowledge.
  ///
  /// [SafetyVerdict.unknown] otherwise. Unknown is not a green light: tell the
  /// driver the road could not be assessed.
  SafetyVerdict get hazard {
    // POSITIVE evidence fires even when other fields are absent.
    if (iceRisk == true) return SafetyVerdict.hazardous;
    if (hazardAssertion == HazardAssertion.severe ||
        hazardAssertion == HazardAssertion.extreme) {
      return SafetyVerdict.hazardous;
    }
    if (intensity == PrecipitationIntensity.heavy) {
      return SafetyVerdict.hazardous;
    }
    final v = visibilityMeters;
    if (v != null && v < 200) return SafetyVerdict.hazardous;

    // Nothing fired. But do we actually KNOW it is safe?
    if (iceRisk == null || intensity == null || visibilityMeters == null) {
      return SafetyVerdict.unknown;
    }
    // A road authority has declared SOMETHING (minor / moderate / unstated
    // severity), and no measurement we hold contradicts it. A complete set of
    // benign measurements must not overrule a declared advisory — the
    // authority may know something our sensors cannot see. Hold at unknown.
    final assertion = hazardAssertion;
    if (assertion != null && assertion != HazardAssertion.none) {
      return SafetyVerdict.unknown;
    }
    return SafetyVerdict.notHazardous;
  }

  /// Is snow falling?
  ///
  /// [SafetyVerdict.unknown] when the precipitation type is unreported, or
  /// when it is snow but the intensity is unreported.
  SafetyVerdict get snowing {
    final t = precipType;
    if (t == null) return SafetyVerdict.unknown;
    if (t != PrecipitationType.snow) return SafetyVerdict.notHazardous;
    final i = intensity;
    if (i == null) return SafetyVerdict.unknown;
    return i == PrecipitationIntensity.none
        ? SafetyVerdict.notHazardous
        : SafetyVerdict.hazardous;
  }

  /// Is visibility reduced (below 1 km)?
  ///
  /// [SafetyVerdict.unknown] when visibility was not measured — absence of a
  /// visibility reading is never "you can see fine".
  SafetyVerdict get reducedVisibility {
    final v = visibilityMeters;
    if (v == null) return SafetyVerdict.unknown;
    return v < 1000 ? SafetyVerdict.hazardous : SafetyVerdict.notHazardous;
  }

  /// Is the temperature at or below freezing?
  ///
  /// [SafetyVerdict.unknown] when the temperature was not measured — absence
  /// of a temperature reading is never "above freezing".
  SafetyVerdict get freezing {
    final t = temperatureCelsius;
    if (t == null) return SafetyVerdict.unknown;
    return t <= 0 ? SafetyVerdict.hazardous : SafetyVerdict.notHazardous;
  }

  /// True when nothing at all was measured or asserted.
  bool get isFullyUnknown =>
      precipType == null &&
      intensity == null &&
      temperatureCelsius == null &&
      visibilityMeters == null &&
      windSpeedKmh == null &&
      iceRisk == null &&
      humidityRH == null &&
      hazardAssertion == null;

  @override
  List<Object?> get props => [
    precipType,
    intensity,
    temperatureCelsius,
    visibilityMeters,
    windSpeedKmh,
    iceRisk,
    humidityRH,
    hazardAssertion,
    source,
    timestamp,
  ];

  @override
  String toString() {
    final parts = <String>[
      '${precipType?.name ?? "?"} ${intensity?.name ?? "?"}',
      temperatureCelsius == null
          ? 'temp=?'
          : '${temperatureCelsius!.toStringAsFixed(1)}°C',
      visibilityMeters == null
          ? 'vis=?'
          : 'vis=${visibilityMeters!.toStringAsFixed(0)}m',
      windSpeedKmh == null
          ? 'wind=?'
          : 'wind=${windSpeedKmh!.toStringAsFixed(0)}km/h',
      if (humidityRH != null) 'RH=${humidityRH!.toStringAsFixed(0)}%',
      if (hazardAssertion != null) 'assert=${hazardAssertion!.name}',
      if (iceRisk == true) 'ICE',
      if (iceRisk == null) 'ice=?',
      'src=${source.name}',
    ];
    return 'WeatherCondition(${parts.join(', ')})';
  }
}
