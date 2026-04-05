/// Snow rendering — weather-to-rendering computation for driving safety.
///
/// Converts a [WeatherCondition] from the `driving_weather` package into
/// the full driving condition picture an edge developer needs to produce
/// a weather-responsive map or navigation experience:
///
/// - [RoadSurfaceState] — road surface classification and grip factor.
/// - [PrecipitationConfig] — particle count, velocity, size, and lifetime.
/// - [VisibilityDegradation] — fog overlay opacity and blur sigma.
/// - [DrivingConditionAssessment] — aggregated result from a single condition.
///
/// This package is computation only. Rendering (Canvas, CustomPainter,
/// flutter_map layers) is the application's responsibility.
///
/// ```dart
/// final assessment = DrivingConditionAssessment.fromCondition(condition);
/// print(assessment.surfaceState);           // RoadSurfaceState.compactedSnow
/// print(assessment.precipitation.particleCount); // 500
/// print(assessment.visibility.blurSigma);  // 6.0
/// ```
library;

export 'src/assessment/driving_condition_assessment.dart';
export 'src/models/precipitation_config.dart';
export 'src/models/road_surface_state.dart';
export 'src/models/visibility_degradation.dart';
