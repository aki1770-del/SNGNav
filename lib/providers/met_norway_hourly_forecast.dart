/// Re-export shim: the MET Norway hourly-forecast SOURCE now lives in the
/// pure-Dart package `pretrip_source_met_norway` (extracted 2026-06-14).
///
/// App importers of
/// `package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart`
/// keep resolving `MetNorwayHourlyForecastProvider`,
/// `mapLocationForecastToWeatherForecast`, `MetNorwayForecastException`, and
/// `kMetNorwayLocationForecastUrl` unchanged via this re-export. The honesty
/// rules (visibility NEVER estimated; an observation valid for the departure
/// hour only; null = the driver's own judgment, never a fabricated hazard)
/// live verbatim in the package source + its SAFETY-class README.
library;

export 'package:pretrip_source_met_norway/pretrip_source_met_norway.dart';
