import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/providers/forecast_case.dart';

void main() {
  group('forecastCaseForLocation', () {
    test('a snow-zone prefecture point is the Japan case', () {
      // Niigata (in the 150000 bounding box).
      expect(
        forecastCaseForLocation(latitude: 37.9, longitude: 139.0),
        ForecastCase.japanSnowZone,
      );
      // Sapporo / Hokkaido (010000).
      expect(
        forecastCaseForLocation(latitude: 43.06, longitude: 141.35),
        ForecastCase.japanSnowZone,
      );
    });

    test('Nagoya is the MET Norway case — it is south of the snow belt', () {
      // The app's default pre-trip point. The honest division: Nagoya is NOT a
      // JMA-catalogued snow-zone prefecture, so it is served globally, never
      // forced into the Japan case.
      expect(
        forecastCaseForLocation(latitude: 35.1709, longitude: 136.8815),
        ForecastCase.metNorwayGlobal,
      );
    });

    test('a Nordic point is the MET Norway case', () {
      // Oslo.
      expect(
        forecastCaseForLocation(latitude: 59.91, longitude: 10.75),
        ForecastCase.metNorwayGlobal,
      );
    });
  });

  group('japanPrefectureCodeForLocation', () {
    test('returns the prefecture code for a snow-zone point', () {
      expect(
        japanPrefectureCodeForLocation(latitude: 37.9, longitude: 139.0),
        '150000', // Niigata
      );
    });

    test('returns null for a non-snow-zone point', () {
      expect(
        japanPrefectureCodeForLocation(latitude: 35.1709, longitude: 136.8815),
        isNull, // Nagoya
      );
    });
  });
}
