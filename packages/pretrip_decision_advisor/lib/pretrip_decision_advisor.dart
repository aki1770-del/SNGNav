/// Pre-trip departure-timing decision advisor.
///
/// Ships the abstract [PretripAdvisor] contract + data shapes AND a working
/// reference implementation ([SnowAwarePretripAdvisor]) plus a source-neutral
/// measured-visibility merge ([mergeObservedVisibility]). Pure Dart — no
/// network, no Flutter. See `README.md` and `KNOWN_LIMITATIONS.md`.
library;

export 'src/area_condition_read.dart';
export 'src/commute_shape.dart';
export 'src/daylight.dart';
export 'src/driver_profile_spec.dart';
export 'src/pretrip_advisor.dart';
export 'src/pretrip_messages.dart';
export 'src/pretrip_recommendation.dart';
export 'src/snow_aware_pretrip_advisor.dart';
export 'src/trip_geo.dart';
export 'src/visibility_observation.dart';
export 'src/weather_forecast.dart';
