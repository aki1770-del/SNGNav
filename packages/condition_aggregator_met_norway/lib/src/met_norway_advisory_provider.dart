/// MetNorwayAdvisoryProvider — `AdvisoryProvider` adapter for the MET
/// Norway (Meteorologisk institutt) locationforecast feed.
///
/// Fetches `https://api.met.no/weatherapi/locationforecast/2.0/compact`
/// (public endpoint; MET Norway terms require an identifying
/// User-Agent header naming the application and a contact email or
/// website) and maps the next-hour forecast slice for the requested
/// point to a source-neutral `Advisory` typed event when a
/// driver-relevant condition (freezing temperature or heavy
/// precipitation) is forecast. Pure Dart; only `http` +
/// `condition_aggregator` runtime dependencies.
library;

import 'dart:async';
import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:http/http.dart' as http;
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';

/// Default MET Norway locationforecast endpoint — the compact product
/// returning hourly + multi-hour-summary forecasts as GeoJSON Point.
const String kDefaultMetNorwayLocationForecastUrl =
    'https://api.met.no/weatherapi/locationforecast/2.0/compact';

/// Default heavy-precipitation threshold in mm per hour applied to
/// `next_1_hours.details.precipitation_amount`. ≥ 4 mm/h is the WMO
/// "heavy rain" floor and aligns with driver-actionable wet-road /
/// reduced-visibility surfacing in the Nordic-region context. The
/// threshold is integrator-overridable at construction time.
const double kDefaultMetNorwayHeavyPrecipitationMmPerHour = 4.0;

/// Default freezing-temperature threshold in Celsius applied to
/// `instant.details.air_temperature`. ≤ 0 °C with non-zero
/// precipitation is the canonical winter-road risk shape (snow /
/// freezing rain / ice). Integrator-overridable.
const double kDefaultMetNorwayFreezingTemperatureCelsius = 0.0;

/// Wall-clock budget for the HTTP fetch. A runaway publisher response
/// must not stall the driver-facing UI.
const Duration _kFetchBudget = Duration(seconds: 30);

/// Hard cap on the response body in bytes. The compact endpoint
/// response is observed at ~37 KB for a single point on 2026-05-24;
/// 4 MB leaves comfortable headroom while preventing an unbounded
/// payload from exhausting integrator memory.
const int _kMaxResponseBytes = 4 * 1024 * 1024;

/// Adapter implementing [AdvisoryProvider] against the MET Norway
/// locationforecast feed.
class MetNorwayAdvisoryProvider implements AdvisoryProvider {
  /// Endpoint URL. Default points at the public compact product.
  final String endpointUrl;

  /// User-Agent string. MET Norway terms require an identifying UA
  /// naming the application/domain plus a contact email or website
  /// link; non-compliance risks throttling or a permanent ban. The
  /// canonical form for this adapter when the integrator does not
  /// override is
  /// `condition_aggregator_met_norway/0.0.1 github.com/aki1770-del/sngnav`.
  /// Integrators publishing under their own identity SHOULD override
  /// to credit themselves rather than the SNGNav reference repo.
  final String userAgent;

  /// Heavy-precipitation threshold in mm per hour.
  final double heavyPrecipitationMmPerHour;

  /// Freezing-temperature threshold in Celsius.
  final double freezingTemperatureCelsius;

  /// Cloud ceiling above which the radiative mechanism is treated as
  /// suppressed. See [kDefaultMetNorwayClearSkyCloudPercentMax].
  final double clearSkyCloudPercentMax;


  /// HTTP client — injectable for testing. The adapter does not own
  /// the lifecycle of an injected client; the caller owns close().
  /// When the no-arg constructor is used, the adapter owns the client
  /// and `close()` releases it.
  final http.Client _client;
  final bool _ownsClient;

  bool _initialized = false;

  /// Constructs an adapter that owns its own [http.Client].
  MetNorwayAdvisoryProvider({
    this.endpointUrl = kDefaultMetNorwayLocationForecastUrl,
    this.userAgent =
        'condition_aggregator_met_norway/0.0.1 '
        'github.com/aki1770-del/sngnav',
    this.heavyPrecipitationMmPerHour =
        kDefaultMetNorwayHeavyPrecipitationMmPerHour,
    this.freezingTemperatureCelsius =
        kDefaultMetNorwayFreezingTemperatureCelsius,
    this.clearSkyCloudPercentMax =
        kDefaultMetNorwayClearSkyCloudPercentMax,
  }) : _client = http.Client(),
       _ownsClient = true;

  /// Constructs an adapter against a caller-supplied [http.Client]
  /// (test injection).
  MetNorwayAdvisoryProvider.withClient(
    http.Client client, {
    this.endpointUrl = kDefaultMetNorwayLocationForecastUrl,
    this.userAgent =
        'condition_aggregator_met_norway/0.0.1 '
        'github.com/aki1770-del/sngnav',
    this.heavyPrecipitationMmPerHour =
        kDefaultMetNorwayHeavyPrecipitationMmPerHour,
    this.freezingTemperatureCelsius =
        kDefaultMetNorwayFreezingTemperatureCelsius,
    this.clearSkyCloudPercentMax =
        kDefaultMetNorwayClearSkyCloudPercentMax,
  }) : _client = client,
       _ownsClient = false;

  /// Names the publisher this adapter speaks for. The parent
  /// `condition_aggregator` interface enum carries
  /// `AdvisorySource.metNorway` and its verbatim CC-BY-4.0
  /// attribution string.
  @override
  AdvisorySource get source => AdvisorySource.metNorway;

  /// One-shot init. Validates that a non-empty User-Agent is
  /// configured (MET Norway terms require identification). No network
  /// handshake; pure configuration check.
  @override
  Future<void> init() async {
    if (userAgent.trim().isEmpty) {
      throw const MetNorwayConfigurationException(
        'MetNorwayAdvisoryProvider requires a non-empty User-Agent — '
        'MET Norway terms require an identifying User-Agent naming '
        'the application/domain plus a contact email or website link.',
      );
    }
    if (heavyPrecipitationMmPerHour < 0) {
      throw const MetNorwayConfigurationException(
        'heavyPrecipitationMmPerHour must be non-negative.',
      );
    }
    _initialized = true;
  }

  /// Fetches the locationforecast for the given point and returns a
  /// list of advisories derived from the next-hour forecast slice.
  ///
  /// MET Norway terms require truncating coordinates to at most 4
  /// decimal places; the adapter truncates before constructing the
  /// request URI.
  ///
  /// Returns an empty list when the next-hour slice does not match a
  /// driver-actionable threshold (no freezing temperature, no heavy
  /// precipitation). Throws [MetNorwayHttpException] on non-2xx
  /// response or [MetNorwayParseException] on malformed JSON.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.metNorway,
        message:
            'MetNorwayAdvisoryProvider.fetchActiveAdvisoriesAtPoint '
            'called before init(); the AdvisoryProvider contract '
            'requires init exactly once before any fetch.',
      );
    }

    final lat = _truncateToFourDecimals(latitude);
    final lon = _truncateToFourDecimals(longitude);
    final uri = Uri.parse(endpointUrl).replace(
      queryParameters: <String, String>{
        'lat': lat.toString(),
        'lon': lon.toString(),
      },
    );

    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'User-Agent': userAgent,
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
          },
        )
        .timeout(
          _kFetchBudget,
          onTimeout: () {
            throw MetNorwayHttpException(
              statusCode: 0,
              message:
                  'Wall-clock budget ${_kFetchBudget.inSeconds}s '
                  'exhausted before MET Norway response.',
            );
          },
        );

    if (response.statusCode != 200) {
      throw MetNorwayHttpException(
        statusCode: response.statusCode,
        message:
            'MET Norway locationforecast fetch failed: '
            'HTTP ${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > _kMaxResponseBytes) {
      throw MetNorwayHttpException(
        statusCode: response.statusCode,
        message:
            'MET Norway response exceeded $_kMaxResponseBytes-byte '
            'cap (${response.bodyBytes.length} bytes received).',
      );
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const MetNorwayParseException(
          'MET Norway response is not a JSON object',
        );
      }
      json = decoded;
    } on FormatException catch (e) {
      throw MetNorwayParseException(
        'MET Norway response is not valid JSON: ${e.message}',
      );
    }

    final advisory = mapLocationForecastResponseToAdvisory(
      response: json,
      heavyPrecipitationMmPerHour: heavyPrecipitationMmPerHour,
      freezingTemperatureCelsius: freezingTemperatureCelsius,
      clearSkyCloudPercentMax: clearSkyCloudPercentMax,
    );
    if (advisory == null) return const <Advisory>[];
    return <Advisory>[advisory];
  }

  /// Releases the underlying [http.Client] HTTP resources if this
  /// adapter constructed it; no-op if a caller-supplied client was
  /// injected via [MetNorwayAdvisoryProvider.withClient].
  void close() {
    if (_ownsClient) _client.close();
  }
}

double _truncateToFourDecimals(double v) {
  // MET Norway terms: "Truncate coordinates to max 4 decimals" — this
  // is both a cache-friendliness ask from the publisher AND a privacy
  // posture (the driver's exact location is not transmitted at sub-11m
  // resolution).
  final sign = v.isNegative ? -1.0 : 1.0;
  final abs = v.abs();
  final truncated = (abs * 10000).truncateToDouble() / 10000.0;
  return sign * truncated;
}

/// Maps a MET Norway locationforecast/2.0/compact response to a
/// source-neutral [Advisory], or returns `null` if the next-hour
/// forecast slice does not match a driver-actionable threshold.
///
/// Mapping (v0.0.1):
/// - `source` ← `AdvisorySource.metNorway`
/// - `eventClass` ← derived from the first matched condition:
///   - `Freezing precipitation` when air_temperature ≤
///     [freezingTemperatureCelsius] AND next-hour precipitation > 0
///   - `Heavy precipitation` when next-hour precipitation ≥
///     [heavyPrecipitationMmPerHour]
///   - `Subzero forecast` when air_temperature ≤
///     [freezingTemperatureCelsius] AND precipitation == 0
///   - else: returns null (no advisory)
/// - `severity` ← heuristic by combined temperature + precipitation
///   intensity (see [_deriveSeverity])
/// - `certainty` ← `likely` when a publisher symbol_code is present;
///   else `possible`
/// - `urgency` ← `expected` (next-1-hour slice is the canonical
///   next-hour horizon)
/// - `areaDescription` ← `Lat <lat>, Lon <lon>` formatted from the
///   GeoJSON geometry. MET Norway compact response is point-based
///   and does not carry an area description string.
/// - `effective` ← parsed `timeseries[0].time` (UTC)
/// - `expires` ← effective + 1 hour (the next-1-hours slice horizon)
/// - `headline` ← short publisher-derived string (see
///   [_composeHeadline]) including the symbol_code
/// - `description` ← multi-line publisher-derived string carrying
///   the air_temperature, precipitation_amount, symbol_code, and the
///   verbatim CC-BY-4.0 attribution
///
/// Visible at top level for direct-call testing.
Advisory? mapLocationForecastResponseToAdvisory({
  required Map<String, dynamic> response,
  double heavyPrecipitationMmPerHour =
      kDefaultMetNorwayHeavyPrecipitationMmPerHour,
  double freezingTemperatureCelsius =
      kDefaultMetNorwayFreezingTemperatureCelsius,
  double clearSkyCloudPercentMax =
      kDefaultMetNorwayClearSkyCloudPercentMax,
}) {
  final properties = response['properties'];
  if (properties is! Map<String, dynamic>) return null;
  final timeseriesRaw = properties['timeseries'];
  if (timeseriesRaw is! List || timeseriesRaw.isEmpty) return null;
  final firstSlice = timeseriesRaw.first;
  if (firstSlice is! Map<String, dynamic>) return null;

  final timeRaw = firstSlice['time'];
  final effective = _parseIsoOrNull(timeRaw);

  final data = firstSlice['data'];
  if (data is! Map<String, dynamic>) return null;

  final instant = data['instant'];
  Map<String, dynamic>? instantDetails;
  if (instant is Map<String, dynamic>) {
    final d = instant['details'];
    if (d is Map<String, dynamic>) instantDetails = d;
  }

  final next1 = data['next_1_hours'];
  Map<String, dynamic>? next1Details;
  String? next1Symbol;
  if (next1 is Map<String, dynamic>) {
    final d = next1['details'];
    if (d is Map<String, dynamic>) next1Details = d;
    final s = next1['summary'];
    if (s is Map<String, dynamic>) {
      final code = s['symbol_code'];
      if (code is String && code.isNotEmpty) next1Symbol = code;
    }
  }

  final temperature = _readNum(instantDetails?['air_temperature']);
  // NULLABLE. `null` means the feed did not carry `precipitation_amount` — it
  // does NOT mean 0.0 mm. Up to 0.0.5 the `?? 0.0` here did two things, both
  // fabrication: (1) with a freezing temperature and UNMEASURED precipitation
  // it silently classified "Subzero forecast" (moderate) instead of the
  // "Freezing precipitation" (severe) it would have reached had the value
  // actually been measured above zero — absence resolving to the benign branch;
  // (2) it printed "next_1_hours precipitation_amount 0.0 mm" into the
  // driver-facing description for a figure the feed never sent.
  final precipitation = _readNum(next1Details?['precipitation_amount']);
    // NULLABLE, and read from a payload we were ALREADY fetching and
    // discarding. `relative_humidity` is present in the `compact` product
    // (measured live at api.met.no on 2026-09-03), so this costs no extra
    // request and no extra byte. Up to 0.0.6 this adapter dropped it, and
    // with it the whole above-zero radiative-frost window — see [_classify].
    final humidityPercent = _readNum(instantDetails?['relative_humidity']);
  // The SKY, also already in the payload and also discarded up to 0.1.0.
  // Radiative cooling needs a clear one; cloud re-radiates longwave back to the
  // surface and suppresses the mechanism the black-ice class is named for.
  // Without this the class fired under overcast and said so in its own headline.
  final cloudPercent = _readNum(instantDetails?['cloud_area_fraction']);

  final verdict = _classify(
    temperature: temperature,
    precipitation: precipitation,
    humidityPercent: humidityPercent,
    cloudPercent: cloudPercent,
    heavyPrecipitationMmPerHour: heavyPrecipitationMmPerHour,
    freezingTemperatureCelsius: freezingTemperatureCelsius,
    clearSkyCloudPercentMax: clearSkyCloudPercentMax,
  );

  // EXHAUSTIVE over a sealed type. Adding a verdict without deciding what a
  // driver is told is a COMPILE ERROR, not a silent `null`. That is the whole
  // point of the type — see [_BandVerdict].
  final String eventClass;
  final String? missingInput;
  switch (verdict) {
    case _AssessedBenign():
      // The ONLY path permitted to become silence.
      return null;
    case _NotAssessed(missingInput: final input):
      eventClass = _radiativeFrostUnmeasured;
      missingInput = input;
    case _Hazard(eventClass: final hazard):
      eventClass = hazard;
      missingInput = null;
  }

  final severity = _deriveSeverity(
    eventClass: eventClass,
    temperature: temperature,
    precipitation: precipitation,
    heavyPrecipitationMmPerHour: heavyPrecipitationMmPerHour,
    freezingTemperatureCelsius: freezingTemperatureCelsius,
  );

  // The publisher's `symbol_code` says nothing about OUR derived inference, and
  // the classifier does not consult it - so it must not lend that inference the
  // publisher's confidence. The derived classes are model output and say
  // `possible`; the publisher-threshold classes keep the prior rule.
  final certainty = _derivedClasses.contains(eventClass)
      ? AdvisoryCertainty.possible
      : (next1Symbol != null
          ? AdvisoryCertainty.likely
          : AdvisoryCertainty.possible);

  final geometry = response['geometry'];
  final areaDescription = _composeAreaDescription(geometry);

  final headline = _composeHeadline(
    eventClass: eventClass,
    symbolCode: next1Symbol,
  );

  final description = _composeDescription(
    temperature: temperature,
    precipitation: precipitation,
    humidityPercent: humidityPercent,
    symbolCode: next1Symbol,
    derivedClaim: _derivedClasses.contains(eventClass),
    missingInput: missingInput,
  );

  return Advisory(
    source: AdvisorySource.metNorway,
    eventClass: eventClass,
    severity: severity,
    certainty: certainty,
    urgency: AdvisoryUrgency.expected,
    areaDescription: areaDescription,
    effective: effective,
    expires: effective?.add(const Duration(hours: 1)),
    headline: headline,
    description: description,
  );
}

/// Event classes this adapter can emit.
///
/// `Freezing, precipitation not measured` exists because absence must not be
/// sorted onto the benign end of the scale. With a freezing temperature and an
/// unmeasured precipitation figure, we do not know whether ice is falling —
/// and per the contract's asymmetry (positive evidence fires on partial data;
/// only the BENIGN verdict requires complete data) an unknown must not be
/// quietly filed as the milder "Subzero forecast".
const String _freezingPrecipitation = 'Freezing precipitation';
const String _freezingPrecipUnmeasured =
    'Freezing, precipitation not measured';
const String _heavyPrecipitation = 'Heavy precipitation';
const String _subzeroForecast = 'Subzero forecast';

/// Black ice forming while the air still reads ABOVE zero.
///
/// Added 0.1.0. Until then this adapter's coldest gate was
/// `air_temperature <= 0`, which is the exact threshold
/// `navigation_safety_calibration` documents as missing this window:
/// "a 'warn below 0 °C ambient' threshold misses this window". Under clear-sky
/// radiative cooling the road surface falls toward the dew point and surface
/// moisture freezes while the air reads +1…+3 °C. A driver reading a Norwegian
/// or Finnish forecast got nothing at all in that band.
///
/// The classification is NOT computed here. It is delegated to
/// [isRadiativeFrostBlackIce] in `navigation_safety_calibration`, whose own
/// documentation states why: "Two independently-maintained copies of this
/// threshold logic ARE that disagreement waiting to happen. Both surfaces call
/// this function so they cannot drift." This adapter WAS a third copy.
const String _radiativeFrostBlackIce = 'Radiative frost black ice';

/// Saturated air above zero — a hazard this adapter can SEE but cannot ASSESS.
///
/// `isRadiativeFrostBlackIce` is a dew-point-depression model, so at saturation
/// the effective temperature converges on ambient and the predicate is `false`
/// exactly where the air is wettest. The calibration names the consequence
/// itself: "near-zero SATURATED FREEZING FOG above ~ +1 C ... is therefore NOT
/// detected by this model - a genuine hazard this function does not cover."
///
/// 0.1.0 returned bare `null` here, indistinguishable from "measured, benign" -
/// and 0.1.0 also CHANGED WHAT SILENCE MEANS in this band, so that silence was
/// worse than 0.0.6's. In fog, above zero, with ice forming and nothing
/// visible, that is D3's worst case. This names the gap instead of leaving it
/// in a CHANGELOG the driver never reads.
const String _freezingFogNotAssessed =
    'Freezing fog risk - above zero, saturated, not assessed by this model';

/// Freezing-risk band entered with no humidity reading.
///
/// Mirrors [_freezingPrecipUnmeasured]: the above-zero frost window cannot be
/// evaluated without humidity, and "we could not evaluate it" must not be
/// served to a driver as the benign silence this adapter returned up to 0.0.6.
const String _radiativeFrostUnmeasured =
    'Radiative frost, inputs not measured';

/// Cloud ceiling above which the radiative mechanism is suppressed.
///
/// Radiative frost REQUIRES a clear sky: cloud re-radiates longwave back to the
/// surface and the cooling this class is named for does not happen. 0.1.0 never
/// read the sky at all, and a gate measured the cost on 600 live api.met.no
/// slices - the severe channel fired on 64 of them and 54 of those 64 (84%)
/// were under cloud >= 80%, i.e. the state that refutes the mechanism.
/// Integrator-overridable — and as of this version that is TRUE. It was
/// documented as overridable in three places while being a bare const with no
/// constructor field, no mapper parameter and no export: a capability that did
/// not exist, shipped as the mitigation for a threshold the pen had already
/// admitted it invented. A gate proved the absence with a compile probe.
const double kDefaultMetNorwayClearSkyCloudPercentMax = 50.0;


/// Relative humidity at or above which the air is treated as saturated, so the
/// dew-point model is out of scope and [_freezingFogNotAssessed] applies. The
/// calibration's own worked example is +2 C / 95% RH -> dew point ~ +1.3 C,
/// i.e. not detected.
const double kMetNorwaySaturatedHumidityPercent = 95.0;

/// What this band can conclude — and it is SEALED so that "assessed, and there
/// is nothing to say" and "I could not assess this" can never again be the same
/// return value.
///
/// ⚑ THIS TYPE EXISTS BECAUSE A BARE `null` MEANT BOTH, AND THAT ONE
/// OVERLOADING PRODUCED EVERY DEFECT THREE ADVERSARIAL GATE ROUNDS FOUND.
/// Sakichi Vision 14: "a function that returns a success-shaped value while the
/// operation failed is a loom weaving through a broken warp." Vision 15 ranks
/// the remedies — "best is CANNOT BE DONE WRONG; next is detected instantly;
/// worst is found downstream" — and three rounds of re-ordering conditions was
/// `found downstream`, three times. Vision 89: a type checker is poka-yoke, it
/// makes a class of defect structurally impossible to commit. Dart's exhaustive
/// switch over a sealed type is that fixture: a path that forgets to say which
/// of the three it means will not compile.
sealed class _BandVerdict {
  const _BandVerdict();
}

/// A named hazard.
final class _Hazard extends _BandVerdict {
  const _Hazard(this.eventClass);
  final String eventClass;
}

/// Assessed, and there is nothing to report. **The only verdict permitted to
/// become silence.**
final class _AssessedBenign extends _BandVerdict {
  const _AssessedBenign();
}

/// NOT assessed, and [missingInput] names the reading that stopped us. This can
/// never become silence — it becomes an advisory that says so.
final class _NotAssessed extends _BandVerdict {
  const _NotAssessed(this.missingInput);
  final String missingInput;
}

/// The classes THIS PACKAGE infers, as opposed to the ones it relays from a
/// publisher threshold. They carry `possible` certainty and are marked in the
/// description as ours.
const Set<String> _derivedClasses = <String>{
  _radiativeFrostBlackIce,
  _radiativeFrostUnmeasured,
  _freezingFogNotAssessed,
};

/// Full classification: the colder, publisher-threshold branches first, then
/// the above-zero band. Returns a [_BandVerdict] so no caller can mistake
/// "assessed benign" for "could not assess".
_BandVerdict _classify({
  required double? temperature,
  required double? precipitation,
  required double? humidityPercent,
  required double? cloudPercent,
  required double heavyPrecipitationMmPerHour,
  required double freezingTemperatureCelsius,
  required double clearSkyCloudPercentMax,
}) {
  final freezing =
      temperature != null && temperature <= freezingTemperatureCelsius;

  // An unmeasured precipitation figure can never make `heavy` true, and it must
  // never make it FALSE either — it simply is not evidence.
  final heavy =
      precipitation != null && precipitation >= heavyPrecipitationMmPerHour;

  if (freezing && precipitation != null && precipitation > 0) {
    return const _Hazard(_freezingPrecipitation);
  }
  if (heavy) return const _Hazard(_heavyPrecipitation);
  if (freezing && precipitation == null) {
    return const _Hazard(_freezingPrecipUnmeasured);
  }
  if (freezing && precipitation == 0) {
    return const _Hazard(_subzeroForecast);
  }

  return _classifyBand(
    temperature: temperature,
    precipitation: precipitation,
    humidityPercent: humidityPercent,
    cloudPercent: cloudPercent,
    freezingTemperatureCelsius: freezingTemperatureCelsius,
    clearSkyCloudPercentMax: clearSkyCloudPercentMax,
  );
}

_BandVerdict _classifyBand({
  required double? temperature,
  required double? precipitation,
  required double? humidityPercent,
  required double? cloudPercent,
  required double freezingTemperatureCelsius,
  required double clearSkyCloudPercentMax,
}) {
  // FLOOR IS THE STRICTER OF TWO BOUNDS: `freezingTemperatureCelsius` keeps
  // this band from overlapping the colder branches and an integrator may move
  // it; 0 °C is what the black-ice class NAME asserts. Binding only to the
  // configurable one let an integrator who LOWERED it to warn less get black
  // ice at -1.0 °C.
  final radiativeFloor =
      freezingTemperatureCelsius > 0.0 ? freezingTemperatureCelsius : 0.0;
  if (temperature == null ||
      !temperature.isFinite ||
      temperature <= radiativeFloor ||
      temperature > radiativeFrostAmbientCeilingCelsius) {
    // Genuinely outside what this band assesses — the colder branches above
    // own it, or it is simply warm. Assessed.
    return const _AssessedBenign();
  }

  final wet = precipitation != null && precipitation > 0;
  final saturated = humidityPercent != null &&
      humidityPercent >= kMetNorwaySaturatedHumidityPercent;
  final frost = isRadiativeFrostBlackIce(
    ambientCelsius: temperature,
    humidityRHPercent: humidityPercent,
  );

  // Humidity is the input nothing here can proceed without.
  if (humidityPercent == null) return const _NotAssessed('relative_humidity');

  // SATURATED AND THE MODEL SAYS NOT-FROST IS THE MODEL'S OWN BLIND SPOT, by
  // construction rather than by a chosen number. The calibration states it:
  // "near-zero SATURATED FREEZING FOG above ~ +1 °C (dew point >= 0) is
  // therefore NOT detected by this model — a genuine hazard this function does
  // not cover." A previous form gated this at `temperature <= 1.0`, which is
  // the COMPLEMENT of that sentence: it spoke only where the model DOES assess
  // and fell silent across the whole band the citation calls uncovered.
  //
  // ⚑ NOT gated on the sky. RADIATION FOG FORMS BECAUSE THE SKY IS CLEAR — the
  // same longwave loss the black-ice class is named for — so a `!clearSky`
  // condition here was anti-correlated with the hazard. Measured at the
  // publisher: `fog_area_fraction` is a field DISTINCT from
  // `cloud_area_fraction`, so "fog is cloud at ground level" was false.
  //
  // ⚑ NOT gated on rain. Freezing drizzle in fog just above zero is the
  // canonical glaze-ice generator and D3's compound case: she cannot see AND
  // ice is forming.
  if (saturated && !frost) return const _Hazard(_freezingFogNotAssessed);

  if (frost) {
    // Measured rain rules out the RADIATIVE mechanism — a dry surface cooling
    // to the dew point. That is an assessment, not an absence.
    if (wet) return const _AssessedBenign();
    // The sky is part of the mechanism, so an unread sky is an unread input —
    // and it can no longer become silence.
    if (cloudPercent == null) return const _NotAssessed('cloud_area_fraction');
    // Cloud re-radiates longwave back to the surface and suppresses the
    // cooling. Assessed, and suppressed.
    if (cloudPercent > clearSkyCloudPercentMax) return const _AssessedBenign();
    return const _Hazard(_radiativeFrostBlackIce);
  }

  return const _AssessedBenign();
}

AdvisorySeverity _deriveSeverity({
  required String eventClass,
  required double? temperature,
  required double? precipitation,
  required double heavyPrecipitationMmPerHour,
  required double freezingTemperatureCelsius,
}) {
  // Heuristic severity at v0.0.1:
  // - extreme: freezing precipitation AND precipitation ≥ heavy floor
  //   (combined ice-and-heavy-fall is the canonical winter-road
  //   high-impact shape).
  // - severe: freezing precipitation OR heavy precipitation alone
  //   (either condition alone is driver-actionable).
  // - moderate: subzero forecast without precipitation (cold-road
  //   risk but no active fall).
  // - minor: otherwise (defensive default; classify() would have
  //   returned null in that case).
  if (eventClass == _freezingPrecipitation &&
      precipitation != null &&
      precipitation >= heavyPrecipitationMmPerHour) {
    return AdvisorySeverity.extreme;
  }
  if (eventClass == _freezingPrecipitation) return AdvisorySeverity.severe;
  if (eventClass == _heavyPrecipitation) return AdvisorySeverity.severe;
  // Freezing, and nobody measured whether anything is falling. This is NOT the
  // milder "subzero, dry" case — we do not know that it is dry. The severity is
  // therefore UNSTATED (never `moderate` by default): an unmeasured field must
  // not buy a downgrade. `AdvisorySeverity.unknown` ranks above minor/moderate
  // in every consumer that ranks honestly.
  if (eventClass == _freezingPrecipUnmeasured) return AdvisorySeverity.unknown;
  // SEVERE, and the comment that used to sit here said the opposite of what
  // shipped: it claimed this was ranked away from `Subzero forecast` while
  // returning the same `moderate`. It also asserted "not a cry-wolf channel",
  // which was a governing claim authored without measurement and refuted 54/64.
  //
  // Why severe, measured rather than argued:
  //  * `severe` puts this above `Advisory.isHighImpact`, and in the in-drive
  //    advisor that is `_advisoryConcern` 2 — which alone yields
  //    `heightenedCaution`, NEVER `considerStopping`. It escalates by one ONLY
  //    when the position×visibility core is already degraded. `moderate` (1)
  //    escalates nothing, ever.
  //  * This package's doctrine is "a false alarm is contradicted by the
  //    windscreen; a false all-clear removes the prompt to look out of it" —
  //    and BLACK ICE IS DEFINED BY HER NOT BEING ABLE TO SEE IT. The windscreen
  //    cannot contradict it, so the asymmetry is stronger here, not weaker.
  //  * The cry-wolf risk that argued for `moderate` is now carried at the
  //    GATING layer (dry surface, clear sky, band bounded at both ends).
  //    Discounting severity as well double-counts the same uncertainty.
  //  * VSS `Vehicle.Safety.RoadIcingState` — built on signals from this
  //    catalogue — makes `RISK` ("conditions favor ice formation") a
  //    first-class safety state beside `DETECTED`. This class is RISK exactly.
  if (eventClass == _radiativeFrostBlackIce) return AdvisorySeverity.severe;
  // A hazard whose conditions we can see and explicitly cannot assess. Never
  // `minor`, never silence - UNSTATED, like every other unmeasured verdict here.
  if (eventClass == _freezingFogNotAssessed) return AdvisorySeverity.unknown;
  // Unmeasured: severity UNSTATED, never `moderate` by default. Same rule as
  // [_freezingPrecipUnmeasured] — absence buys no downgrade.
  if (eventClass == _radiativeFrostUnmeasured) return AdvisorySeverity.unknown;
  if (eventClass == _subzeroForecast) return AdvisorySeverity.moderate;
  return AdvisorySeverity.minor;
}

String _composeAreaDescription(Object? geometry) {
  if (geometry is! Map<String, dynamic>) return '';
  final type = geometry['type'];
  final coords = geometry['coordinates'];
  if (type == 'Point' && coords is List && coords.length >= 2) {
    final lon = _readNum(coords[0]);
    final lat = _readNum(coords[1]);
    if (lon != null && lat != null) {
      return 'Lat ${lat.toStringAsFixed(4)}, '
          'Lon ${lon.toStringAsFixed(4)}';
    }
  }
  return '';
}

String _composeHeadline({
  required String eventClass,
  required String? symbolCode,
}) {
  if (symbolCode == null) return eventClass;
  return '$eventClass — $symbolCode';
}

String _composeDescription({
  required double? temperature,
  required double? precipitation,
  required double? humidityPercent,
  required String? symbolCode,
  required bool derivedClaim,
  required String? missingInput,
}) {
  final parts = <String>[];
  if (temperature != null) {
    parts.add('air_temperature ${temperature.toStringAsFixed(1)} °C');
  }
  // A figure the feed did not send is not printed. Up to 0.0.5 this line
  // unconditionally emitted "precipitation_amount 0.0 mm" into the text a
  // driver reads — for a value nobody measured.
  if (precipitation != null) {
    parts.add(
      'next_1_hours precipitation_amount '
      '${precipitation.toStringAsFixed(1)} mm',
    );
  } else {
    parts.add('next_1_hours precipitation_amount not reported');
  }
  // Same rule as precipitation: a figure the feed did not send is named as
  // absent rather than omitted, because a reader cannot tell an omitted line
  // from a measured benign one.
  if (humidityPercent != null) {
    parts.add('relative_humidity ${humidityPercent.toStringAsFixed(1)} %');
  } else {
    parts.add('relative_humidity not reported');
  }
  if (symbolCode != null) parts.add('symbol_code $symbolCode');
  // WHOSE CLAIM IS THIS. The measured fields above are MET Norway's; the
  // radiative classes are an inference THIS PACKAGE draws from them and the
  // institute never made. Saying so is dignity toward a publisher whose byline
  // follows on the very next line, it is what CC BY 4.0 asks when a source is
  // modified, and it lets a driver weigh a national institute's warning
  // differently from a third party's model.
  // Name the reading that stopped the assessment. "Not assessed" without
  // saying WHAT was missing is a smaller version of the same silence.
  if (missingInput != null) {
    parts.add('not assessed: $missingInput was not reported');
  }
  if (derivedClaim) {
    parts.add(
      'Derived by condition_aggregator_met_norway from the fields above; '
      'not an advisory issued by the publisher',
    );
  }
  parts.add(AdvisorySource.metNorway.attributionString);
  return parts.join('. ');
}

double? _readNum(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

DateTime? _parseIsoOrNull(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    return null;
  }
}

/// Raised when the MET Norway HTTP fetch returns a non-200 status or
/// exceeds a documented byte / wall-clock cap.
class MetNorwayHttpException implements Exception {
  /// HTTP status code observed on the failing response. Set to 0 for
  /// pre-response failures (wall-clock timeout, transport error).
  final int statusCode;

  /// Human-readable description of the failure.
  final String message;

  const MetNorwayHttpException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() =>
      'MetNorwayHttpException(statusCode: $statusCode): $message';
}

/// Raised when the MET Norway response body cannot be parsed as the
/// expected GeoJSON-Point JSON shape.
class MetNorwayParseException implements Exception {
  /// Human-readable description of the contract violation.
  final String message;

  const MetNorwayParseException(this.message);

  @override
  String toString() => 'MetNorwayParseException: $message';
}

/// Raised when [MetNorwayAdvisoryProvider.init] is called with an
/// invalid configuration (empty User-Agent, negative threshold).
class MetNorwayConfigurationException implements AdvisoryProviderInitException {
  /// Human-readable description of the configuration failure.
  @override
  final String message;

  const MetNorwayConfigurationException(this.message);

  @override
  AdvisorySource get source => AdvisorySource.metNorway;

  @override
  String toString() => 'MetNorwayConfigurationException: $message';
}
