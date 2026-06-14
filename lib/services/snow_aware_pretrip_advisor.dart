/// Re-export shim: the pre-trip advisor brain now lives in the published
/// pure-Dart package `pretrip_decision_advisor` (0.2.0+), which ships the
/// `SnowAwarePretripAdvisor` reference implementation, the `PretripBriefing`
/// / `PretripVerdict` / `HourHazard` verdict shapes, and the full contract
/// (`PretripAdvisor`, `PretripRecommendation`, `RecommendationStrength`,
/// `WeatherForecast`, `HourlyForecast`, `RoadConditionEstimate`,
/// `CommuteShape`, `CommuteFlexibility`, `DriverProfileSpec`).
///
/// App code that imports
/// `package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart`
/// keeps resolving every symbol it used to, unchanged, via this re-export.
library;

export 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
