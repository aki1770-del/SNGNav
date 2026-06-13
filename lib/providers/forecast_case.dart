/// Which of the two driver-cases a pre-trip location falls into.
///
/// Komada's proposal (2026-06-13): HER drives in two distinct regions served by
/// two distinct authoritative sources — divide them explicitly rather than
/// stretching one global product over both. This does NOT mean covering every
/// Japanese local area: the Japan case is honestly scoped to the snow-zone
/// prefectures the JMA adapter actually catalogs (Hokkaido / Aomori / Iwate /
/// Akita / Yamagata / Niigata at 0.1.0). Every other point — including Nagoya
/// itself, which sits south of that snow belt — is the global MET Norway case
/// (plus Digitraffic visibility where the Finnish road network reaches). A
/// point is never forced into the Japan case it is not catalogued for.
///
/// This reuses the JMA adapter's own `prefectureCodeForPoint` (the bounding-box
/// catalog is the single source of truth — it is not duplicated here).
library;

import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';

/// The two authoritative-source cases for HER pre-trip forecast.
enum ForecastCase {
  /// A JMA-catalogued snow-zone prefecture: the Japan Meteorological Agency's
  /// official winter warnings are the authoritative source.
  japanSnowZone,

  /// Everywhere else: the global MET Norway forecast (with Digitraffic
  /// visibility where the road-weather network reaches).
  metNorwayGlobal,
}

/// The driver-case for a WGS84 point. [ForecastCase.japanSnowZone] when the
/// point falls in a JMA-catalogued snow-zone prefecture; otherwise
/// [ForecastCase.metNorwayGlobal] — the honest default, which is where every
/// uncatalogued Japanese area (Nagoya included) and every non-Japanese point
/// land. A point outside the catalog is never fabricated into the Japan case.
ForecastCase forecastCaseForLocation({
  required double latitude,
  required double longitude,
}) =>
    prefectureCodeForPoint(latitude: latitude, longitude: longitude) != null
        ? ForecastCase.japanSnowZone
        : ForecastCase.metNorwayGlobal;

/// The JMA prefecture code for a [ForecastCase.japanSnowZone] point (the code
/// the caller uses to fetch that prefecture's JMA report), or null for a
/// [ForecastCase.metNorwayGlobal] point.
String? japanPrefectureCodeForLocation({
  required double latitude,
  required double longitude,
}) =>
    prefectureCodeForPoint(latitude: latitude, longitude: longitude);
