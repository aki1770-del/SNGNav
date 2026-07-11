/// Combined driving condition assessment from weather data.
///
/// Bridge model: takes a [WeatherCondition] and produces the full
/// driving condition picture — surface state, grip factor, visibility
/// degradation, precipitation config, and advisory message.
///
/// ## The Measured-or-Absent contract (0.3.0)
///
/// Every derived quantity here is **nullable**, because every quantity it is
/// derived FROM is nullable. `null` means the input was not measured — it never
/// means zero, benign, or clear.
///
/// This is the package that held the fatal path. Up to 0.2.7, a
/// [WeatherCondition] carrying no measurements classified as
/// `RoadSurfaceState.dry` (grip factor **1.0**), which produced
/// `RecommendedResponse.proceed` and the advisory **"Conditions normal"**. An
/// unmeasured road — the exact road a driver is on when the feed is gone — was
/// presented to her as a green light. See CHANGELOG 0.3.0.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';

import '../models/precipitation_config.dart';
import '../models/recommended_response.dart';
import '../models/road_surface_state.dart';
import '../models/visibility_degradation.dart';

class DrivingConditionAssessment extends Equatable {
  /// Classified road surface state, or `null` when the conditions did not
  /// permit a classification. `null` is not [RoadSurfaceState.dry].
  final RoadSurfaceState? surfaceState;

  /// Grip coefficient (0.0–1.0) for the current surface state, or `null` when
  /// the surface is unknown.
  ///
  /// An unknown surface has no grip coefficient. Inventing one (0.2.7 handed
  /// back **1.0**) is the same defect class as inventing a temperature.
  final double? gripFactor;

  /// Visibility degradation (opacity + blur), or `null` when visibility was not
  /// measured. `null` is not [VisibilityDegradation.clear].
  final VisibilityDegradation? visibility;

  /// Precipitation particle configuration, or `null` when precipitation was not
  /// reported. `null` is not [PrecipitationConfig.none] — "we were not told" is
  /// not "nothing is falling".
  final PrecipitationConfig? precipitation;

  /// Human-readable advisory message for the driver.
  final String advisoryMessage;

  /// Typed recommended response tier. [RecommendedResponse.considerTurningBack]
  /// makes trip-abandonment a first-class response in whiteout-class conditions
  /// — see `DRIVER_VOICES.md` (Sapporo→Shinshinotsu whiteout).
  ///
  /// [RecommendedResponse.conditionsUnknown] is the honest answer when the road
  /// could not be assessed. This parameter has NO default: up to 0.2.7 it
  /// defaulted to [RecommendedResponse.proceed], so an assessment that said
  /// nothing about the road silently claimed the road was fine.
  final RecommendedResponse recommendedResponse;

  const DrivingConditionAssessment({
    required this.surfaceState,
    required this.gripFactor,
    required this.visibility,
    required this.precipitation,
    required this.advisoryMessage,
    required this.recommendedResponse,
  });

  /// True when the conditions were actually assessed — i.e. this is a claim
  /// about the road, not an admission that the road is unknown.
  bool get isAssessed =>
      recommendedResponse != RecommendedResponse.conditionsUnknown;

  /// Build a full assessment from current weather conditions.
  ///
  /// When [condition] carries too little to classify, the result is an honest
  /// unknown — [surfaceState] and [gripFactor] are `null`, the response is
  /// [RecommendedResponse.conditionsUnknown], and the advisory says so.
  factory DrivingConditionAssessment.fromCondition(WeatherCondition condition) {
    final surface = RoadSurfaceState.fromCondition(condition);

    final visMeters = condition.visibilityMeters;
    final vis =
        visMeters == null ? null : VisibilityDegradation.compute(visMeters);

    final precip = PrecipitationConfig.fromCondition(condition);
    final response = _classifyResponse(condition, surface);
    final advisory = _buildAdvisory(condition, surface, response);

    return DrivingConditionAssessment(
      surfaceState: surface,
      gripFactor: surface?.gripFactor,
      visibility: vis,
      precipitation: precip,
      advisoryMessage: advisory,
      recommendedResponse: response,
    );
  }

  /// Classify the typed response tier from the live conditions.
  ///
  /// Whiteout-class (→ [RecommendedResponse.considerTurningBack]) is reached
  /// when visibility collapses to the point the driver can no longer see far
  /// enough to react — near-zero visibility (`< 100 m`, the whiteout / dense-fog
  /// end of the model, where a `visibilityMeters` of `0` denotes a full
  /// whiteout). This mirrors the recorded driver decision (`DRIVER_VOICES.md`,
  /// the Sapporo→Shinshinotsu whiteout): the trigger to turn back is that you
  /// cannot *see*, not that the surface is slippery.
  ///
  /// Low-grip hazards (black ice, snow) on a *still-visible* road stay
  /// [RecommendedResponse.reduceSpeed]. Turning back is the response to a
  /// whiteout, not to every hazard — firing it while the road is still visible
  /// would cry wolf and erode the advisory's trust.
  ///
  /// The ORDERING is the contract's asymmetry, and it is load-bearing: every
  /// POSITIVE hazard test runs first and fires on partial data, so an absent
  /// field can never *suppress* a warning that a known field already justifies.
  /// Only after all of them decline do we ask whether we actually KNOW the road
  /// is benign — and if we do not, the answer is
  /// [RecommendedResponse.conditionsUnknown], never
  /// [RecommendedResponse.proceed].
  static RecommendedResponse _classifyResponse(
    WeatherCondition condition,
    RoadSurfaceState? surface,
  ) {
    final vis = condition.visibilityMeters;

    // --- POSITIVE evidence: fires even when other fields are absent. ---
    if (vis != null && vis < 100) {
      return RecommendedResponse.considerTurningBack;
    }
    if (condition.iceRisk == true ||
        (surface != null && surface != RoadSurfaceState.dry) ||
        condition.hazard == SafetyVerdict.hazardous ||
        condition.snowing == SafetyVerdict.hazardous ||
        condition.reducedVisibility == SafetyVerdict.hazardous) {
      return RecommendedResponse.reduceSpeed;
    }

    // A road AUTHORITY has declared a hazard. That is positive evidence, and by
    // the contract's own asymmetry it must fire on partial data — even though
    // (this being an authority declaration, not a sensor reading) every measured
    // field on the condition may be absent. Without this branch a real, live,
    // published Digitraffic advisory of minor/moderate severity fell through to
    // "conditions unknown / no data received": the road authority said something
    // and our app told the driver we had nothing.
    final assertion = condition.hazardAssertion;
    if (assertion != null && assertion != HazardAssertion.none) {
      return RecommendedResponse.reduceSpeed;
    }

    // --- Nothing fired. But do we actually KNOW the road is benign? ---
    // A NEGATIVE claim requires complete knowledge. Without a classified
    // surface, or with an unresolved hazard verdict, we do not have it.
    if (surface == null || condition.hazard != SafetyVerdict.notHazardous) {
      return RecommendedResponse.conditionsUnknown;
    }

    return RecommendedResponse.proceed;
  }

  static String _buildAdvisory(
    WeatherCondition condition,
    RoadSurfaceState? surface,
    RecommendedResponse response,
  ) {
    if (response == RecommendedResponse.conditionsUnknown) {
      // The D3 compound-failure answer. When the feed is gone, the app SAYS SO
      // rather than painting "Conditions normal" over a road nobody measured.
      // Her own eyes are the sensor that still works.
      //
      // But say what is ACTUALLY absent. Claiming "no data received" when a
      // feed DID answer and merely omitted one field is our own fabrication
      // rule broken in mirror image — asserting an absence we did not observe —
      // and a driver who sees "no data received" on ordinary days learns the
      // whole advisory band is noise, and disbelieves it on the night it is
      // real.
      return condition.isFullyUnknown
          ? 'No conditions data — drive to what you can see'
          : 'Road surface not measured here — drive to what you can see';
    }
    if (response == RecommendedResponse.considerTurningBack) {
      return 'Whiteout-class conditions — consider turning back while you '
          'safely can';
    }
    if (condition.iceRisk == true || surface == RoadSurfaceState.blackIce) {
      return 'Black ice risk — reduce speed significantly';
    }
    if (surface == RoadSurfaceState.compactedSnow) {
      return 'Compacted snow — use winter tyres, reduce speed';
    }
    if (surface == RoadSurfaceState.slush) {
      return 'Slushy conditions — maintain safe following distance';
    }
    if (surface == RoadSurfaceState.standingWater) {
      return 'Standing water — risk of aquaplaning at speed';
    }
    // Near-whiteout band (100–200 m, the model's hazardous-visibility line):
    // give the driver the negative-evidence test for whiteout onset, not just a
    // label. A first-time snow driver identifies the regime change by what she
    // can NO LONGER see — "If you can't see the next arrow, you're in a real
    // whiteout" (`DRIVER_VOICES.md`, Niseko first-snow instructional voice) —
    // and the response is JAF's "stop at a safe place". This is the band where
    // her own eyes must catch the escalation, because the data feed may lag or
    // be gone entirely.
    final vis = condition.visibilityMeters;
    if (vis != null && vis < 200) {
      return 'Very low visibility — if you can\'t see the next arrow or '
          'snow pole, that is a whiteout: stop at a safe place';
    }
    if (condition.reducedVisibility == SafetyVerdict.hazardous) {
      return 'Reduced visibility — use fog lights, reduce speed';
    }
    if (surface == RoadSurfaceState.wet) {
      return 'Wet road — increased stopping distance';
    }

    // A road-authority declaration with no measured field to describe it. The
    // alert is REAL — an authority published it — and the road itself is
    // genuinely unmeasured. Say both, and say neither more strongly than it is.
    final assertion = condition.hazardAssertion;
    if (assertion != null && assertion != HazardAssertion.none) {
      return 'A road advisory is in force; the road itself is not measured — '
          'drive to what you can see';
    }

    // Snow is falling and nobody measured the temperature: the surface cannot
    // be classified, but the snow is not in doubt.
    if (condition.snowing != SafetyVerdict.notHazardous &&
        condition.precipType == PrecipitationType.snow) {
      return 'Snow falling — reduce speed';
    }

    // FINAL GUARD. "Conditions normal" is a POSITIVE claim about the road. It
    // may be spoken only when the classifier positively concluded `proceed`.
    // Reaching this line on any other tier means a hazard fired that no branch
    // above described — and the honest answer is then that we do not know what
    // the road is, never that it is normal. This is the line by which a bare
    // authority assertion once shipped to a driver in Akita reading
    // "Conditions normal" while the tier said reduceSpeed.
    if (response != RecommendedResponse.proceed) {
      return 'Hazardous conditions — reduce speed; drive to what you can see';
    }

    return 'Conditions normal';
  }

  @override
  List<Object?> get props => [
    surfaceState,
    gripFactor,
    visibility,
    precipitation,
    advisoryMessage,
    recommendedResponse,
  ];
}
