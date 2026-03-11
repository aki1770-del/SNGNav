library;

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tiles/offline_tiles_core.dart';

void main() {
  group('CoverageTier', () {
    test('contains the four ratified tiers', () {
      expect(CoverageTier.values, hasLength(4));
      expect(CoverageTier.values, containsAll(<CoverageTier>[
        CoverageTier.t1Corridor,
        CoverageTier.t2Metro,
        CoverageTier.t3Prefecture,
        CoverageTier.t4National,
      ]));
    });

    test('t1 is auto-cache with 30 day default expiry', () {
      expect(CoverageTier.t1Corridor.autoCache, isTrue);
      expect(CoverageTier.t1Corridor.defaultExpiryDays, 30);
    });

    test('regional tiers default to 90 day expiry', () {
      expect(CoverageTier.t2Metro.defaultExpiryDays, 90);
      expect(CoverageTier.t3Prefecture.defaultExpiryDays, 90);
      expect(CoverageTier.t4National.defaultExpiryDays, 90);
    });
  });

  group('TileCacheConfig', () {
    test('defaults to 5 km corridor buffer', () {
      const config = TileCacheConfig();
      expect(config.routeBufferKilometers, 5);
    });

    test('returns correct min and max zoom for t1', () {
      const config = TileCacheConfig();
      expect(config.minZoomFor(CoverageTier.t1Corridor), 10);
      expect(config.maxZoomFor(CoverageTier.t1Corridor), 16);
    });

    test('returns correct expiry durations', () {
      const config = TileCacheConfig();
      expect(config.expiryFor(CoverageTier.t1Corridor), const Duration(days: 30));
      expect(config.expiryFor(CoverageTier.t2Metro), const Duration(days: 90));
    });
  });

  group('TileSourceType', () {
    test('contains online and mbtiles', () {
      expect(TileSourceType.values, hasLength(2));
      expect(TileSourceType.values, containsAll(<TileSourceType>[
        TileSourceType.online,
        TileSourceType.mbtiles,
      ]));
    });
  });
}
