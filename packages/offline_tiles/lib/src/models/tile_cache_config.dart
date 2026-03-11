library;

import 'coverage_tier.dart';

class TileCacheConfig {
  const TileCacheConfig({
    this.routeBufferKilometers = 5,
    this.corridorExpiry = const Duration(days: 30),
    this.regionalExpiry = const Duration(days: 90),
    this.corridorMinZoom = 10,
    this.corridorMaxZoom = 16,
    this.metroMinZoom = 9,
    this.metroMaxZoom = 15,
    this.prefectureMinZoom = 7,
    this.prefectureMaxZoom = 13,
    this.nationalMinZoom = 5,
    this.nationalMaxZoom = 10,
  });

  final double routeBufferKilometers;
  final Duration corridorExpiry;
  final Duration regionalExpiry;
  final int corridorMinZoom;
  final int corridorMaxZoom;
  final int metroMinZoom;
  final int metroMaxZoom;
  final int prefectureMinZoom;
  final int prefectureMaxZoom;
  final int nationalMinZoom;
  final int nationalMaxZoom;

  Duration expiryFor(CoverageTier tier) {
    return switch (tier) {
      CoverageTier.t1Corridor => corridorExpiry,
      CoverageTier.t2Metro ||
      CoverageTier.t3Prefecture ||
      CoverageTier.t4National => regionalExpiry,
    };
  }

  int minZoomFor(CoverageTier tier) {
    return switch (tier) {
      CoverageTier.t1Corridor => corridorMinZoom,
      CoverageTier.t2Metro => metroMinZoom,
      CoverageTier.t3Prefecture => prefectureMinZoom,
      CoverageTier.t4National => nationalMinZoom,
    };
  }

  int maxZoomFor(CoverageTier tier) {
    return switch (tier) {
      CoverageTier.t1Corridor => corridorMaxZoom,
      CoverageTier.t2Metro => metroMaxZoom,
      CoverageTier.t3Prefecture => prefectureMaxZoom,
      CoverageTier.t4National => nationalMaxZoom,
    };
  }
}
