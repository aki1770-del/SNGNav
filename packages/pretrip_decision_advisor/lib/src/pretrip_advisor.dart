import 'commute_shape.dart';
import 'driver_profile_spec.dart';
import 'pretrip_recommendation.dart';
import 'weather_forecast.dart';

/// Abstract interface for a pre-trip departure-timing advisor.
///
/// Implementations consume an immediate-future weather forecast, a
/// description of the commute (including its flexibility), and a
/// lightweight driver profile spec, and may produce a
/// [PretripRecommendation] suggesting a departure adjustment.
///
/// Contract:
/// - Implementations MUST return either `null` or a recommendation whose
///   strength is [RecommendationStrength.honestyMode] when
///   [CommuteShape.flexibility] is [CommuteFlexibility.required]. A
///   required-attendance commute cannot be safely delayed by an advisory;
///   the only honest output is "we cannot improve this departure".
/// - Returning `null` from [advise] is always permitted and means
///   "no recommendation". This MUST NOT be used to silently suppress
///   safety-relevant signal; use [RecommendationStrength.honestyMode]
///   when there is something to say but no actionable delay.
/// - Implementations MUST NOT throw on missing or partial forecast data;
///   they should degrade to `null` or honesty-mode.
abstract class PretripAdvisor {
  const PretripAdvisor();

  /// Returns a recommendation, or `null` if no recommendation is
  /// appropriate. See class-level contract for required-commute and
  /// degraded-input behavior.
  PretripRecommendation? advise({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  });
}
