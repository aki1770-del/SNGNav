/// Explore-phase interface for a pre-trip departure-timing advisor.
///
/// This library is interface-only. No concrete advisor is shipped from
/// this package. See `README.md` and `KNOWN_LIMITATIONS.md`.
library pretrip_decision_advisor;

export 'src/commute_shape.dart';
export 'src/driver_profile_spec.dart';
export 'src/pretrip_advisor.dart';
export 'src/pretrip_recommendation.dart';
export 'src/weather_forecast.dart';
