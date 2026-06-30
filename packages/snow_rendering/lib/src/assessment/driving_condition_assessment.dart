/// Combined driving condition assessment from weather data.
///
/// Bridge model: takes a [WeatherCondition] and produces the full
/// driving condition picture — surface state, grip factor, visibility
/// degradation, precipitation config, and advisory message.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';

import '../models/precipitation_config.dart';
import '../models/recommended_response.dart';
import '../models/road_surface_state.dart';
import '../models/visibility_degradation.dart';

class DrivingConditionAssessment extends Equatable {
  /// Classified road surface state.
  final RoadSurfaceState surfaceState;

  /// Grip coefficient (0.0–1.0) for current surface state.
  final double gripFactor;

  /// Visibility degradation (opacity + blur) from current visibility.
  final VisibilityDegradation visibility;

  /// Precipitation particle configuration for current conditions.
  final PrecipitationConfig precipitation;

  /// Human-readable advisory message for the driver.
  final String advisoryMessage;

  /// Typed recommended response tier. [RecommendedResponse.considerTurningBack]
  /// makes trip-abandonment a first-class response in whiteout-class conditions
  /// — see `DRIVER_VOICES.md` (Sapporo→Shinshinotsu whiteout).
  final RecommendedResponse recommendedResponse;

  const DrivingConditionAssessment({
    required this.surfaceState,
    required this.gripFactor,
    required this.visibility,
    required this.precipitation,
    required this.advisoryMessage,
    this.recommendedResponse = RecommendedResponse.proceed,
  });

  /// Build a full assessment from current weather conditions.
  factory DrivingConditionAssessment.fromCondition(WeatherCondition condition) {
    final surface = RoadSurfaceState.fromCondition(condition);
    final vis = VisibilityDegradation.compute(condition.visibilityMeters);
    final precip = PrecipitationConfig.fromCondition(condition);
    final response = _classifyResponse(condition, surface);
    final advisory = _buildAdvisory(condition, surface, response);

    return DrivingConditionAssessment(
      surfaceState: surface,
      gripFactor: surface.gripFactor,
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
  static RecommendedResponse _classifyResponse(
    WeatherCondition condition,
    RoadSurfaceState surface,
  ) {
    if (condition.visibilityMeters < 100) {
      return RecommendedResponse.considerTurningBack;
    }
    if (condition.iceRisk ||
        surface != RoadSurfaceState.dry ||
        condition.hasReducedVisibility) {
      return RecommendedResponse.reduceSpeed;
    }
    return RecommendedResponse.proceed;
  }

  static String _buildAdvisory(
    WeatherCondition condition,
    RoadSurfaceState surface,
    RecommendedResponse response,
  ) {
    if (response == RecommendedResponse.considerTurningBack) {
      return 'Whiteout-class conditions — consider turning back while you '
          'safely can';
    }
    if (condition.iceRisk || surface == RoadSurfaceState.blackIce) {
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
    // Near-whiteout band (100–200 m, the model's `isHazardous` visibility
    // line): give the driver the negative-evidence test for whiteout onset,
    // not just a label. A first-time snow driver identifies the regime change
    // by what she can NO LONGER see — "If you can't see the next arrow,
    // you're in a real whiteout" (`DRIVER_VOICES.md`, Niseko first-snow
    // instructional voice) — and the response is JAF's "stop at a safe
    // place". This is the band where her own eyes must catch the escalation,
    // because the data feed may lag or be gone entirely.
    if (condition.visibilityMeters < 200) {
      return 'Very low visibility — if you can\'t see the next arrow or '
          'snow pole, that is a whiteout: stop at a safe place';
    }
    if (condition.hasReducedVisibility) {
      return 'Reduced visibility — use fog lights, reduce speed';
    }
    if (surface == RoadSurfaceState.wet) {
      return 'Wet road — increased stopping distance';
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
