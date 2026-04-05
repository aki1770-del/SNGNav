/// Combined driving condition assessment from weather data.
///
/// Bridge model: takes a [WeatherCondition] and produces the full
/// driving condition picture — surface state, grip factor, visibility
/// degradation, precipitation config, and advisory message.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';

import '../models/precipitation_config.dart';
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

  const DrivingConditionAssessment({
    required this.surfaceState,
    required this.gripFactor,
    required this.visibility,
    required this.precipitation,
    required this.advisoryMessage,
  });

  /// Build a full assessment from current weather conditions.
  factory DrivingConditionAssessment.fromCondition(
    WeatherCondition condition,
  ) {
    final surface = RoadSurfaceState.fromCondition(condition);
    final vis = VisibilityDegradation.compute(condition.visibilityMeters);
    final precip = PrecipitationConfig.fromCondition(condition);
    final advisory = _buildAdvisory(condition, surface);

    return DrivingConditionAssessment(
      surfaceState: surface,
      gripFactor: surface.gripFactor,
      visibility: vis,
      precipitation: precip,
      advisoryMessage: advisory,
    );
  }

  static String _buildAdvisory(
    WeatherCondition condition,
    RoadSurfaceState surface,
  ) {
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
      ];
}
