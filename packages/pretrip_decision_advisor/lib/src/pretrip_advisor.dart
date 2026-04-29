import 'commute_shape.dart';
import 'driver_profile_spec.dart';
import 'pretrip_recommendation.dart';
import 'weather_forecast.dart';

/// Abstract advisor contract for pre-trip departure timing.
///
/// Given a forecast, a commute shape, and a driver profile spec, an
/// implementation returns a [PretripRecommendation], or `null` to mean
/// "no recommendation; the driver should depart on their own judgment".
///
/// Implementations must respect the honesty rule: if
/// [CommuteShape.flexibility] is [CommuteFlexibility.required], the
/// advisor must not return a strong "wait" recommendation. It must
/// return either `null` or a recommendation whose
/// [PretripRecommendation.strength] is
/// [RecommendationStrength.honestyMode].
///
/// Recommendation strength is forecast-driven. Driver profile feeds
/// into reaction-time calibration, not into how strongly the advisor
/// recommends waiting.
abstract class PretripAdvisor {
  /// Returns a recommendation, or `null` if the advisor declines
  /// to recommend.
  PretripRecommendation? advise({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  });
}
