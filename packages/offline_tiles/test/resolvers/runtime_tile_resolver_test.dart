/// Unit tests for RuntimeTileResolver resolution logic.
library;

import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tiles/src/models/tile_source_type.dart';
import 'package:offline_tiles/src/resolvers/runtime_tile_resolver.dart';

void main() {
  group('RuntimeTileResolver — online mode', () {
    test('online source returns online resolution for all coordinates', () {
      final resolver = RuntimeTileResolver(tileSource: TileSourceType.online);
      final result = resolver.resolve(const TileCoordinates(10, 20, 14));

      expect(result.source, RuntimeTileSource.online);
      expect(result.requestedCoordinates, const TileCoordinates(10, 20, 14));
      expect(result.bytes, isNull);
    });

    test('hasLocalCoverage false without mbtiles archive', () {
      final resolver = RuntimeTileResolver(tileSource: TileSourceType.mbtiles);
      expect(resolver.hasLocalCoverage(const TileCoordinates(10, 20, 14)),
          isFalse);
    });
  });

  group('RuntimeTileResolver — RAM cache', () {
    test('seeded tile resolves from RAM cache', () {
      final resolver = RuntimeTileResolver(tileSource: TileSourceType.mbtiles);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      const coords = TileCoordinates(5, 10, 12);

      resolver.seedMemoryCache(coords, bytes);
      final result = resolver.resolve(coords);

      expect(result.source, RuntimeTileSource.ramCache);
      expect(result.bytes, equals(bytes));
      expect(result.resolvedCoordinates, equals(coords));
    });

    test('clearMemoryCache empties the RAM cache', () {
      final resolver = RuntimeTileResolver(tileSource: TileSourceType.mbtiles);
      final bytes = Uint8List.fromList([1, 2, 3]);
      const coords = TileCoordinates(5, 10, 12);

      resolver.seedMemoryCache(coords, bytes);
      expect(resolver.hasLocalCoverage(coords), isTrue);

      resolver.clearMemoryCache();
      // Without archive, falls through to online/placeholder.
      expect(resolver.hasLocalCoverage(coords), isFalse);
    });

    test('RAM cache takes priority over mbtiles lookup', () {
      final resolver = RuntimeTileResolver(tileSource: TileSourceType.mbtiles);
      final ramBytes = Uint8List.fromList([10, 20, 30]);
      const coords = TileCoordinates(3, 7, 10);

      resolver.seedMemoryCache(coords, ramBytes);
      final result = resolver.resolve(coords);

      expect(result.source, RuntimeTileSource.ramCache);
      expect(result.bytes, equals(ramBytes));
    });
  });

  group('RuntimeTileResolver — fallback behavior', () {
    test('without archive and online allowed returns online', () {
      final resolver = RuntimeTileResolver(
        tileSource: TileSourceType.mbtiles,
        allowOnlineFallback: true,
      );
      final result = resolver.resolve(const TileCoordinates(5, 10, 12));

      expect(result.source, RuntimeTileSource.online);
    });

    test('without archive and online disallowed returns placeholder', () {
      final resolver = RuntimeTileResolver(
        tileSource: TileSourceType.mbtiles,
        allowOnlineFallback: false,
      );
      final result = resolver.resolve(const TileCoordinates(5, 10, 12));

      expect(result.source, RuntimeTileSource.placeholder);
    });
  });

  group('RuntimeTileResolver — archive management', () {
    test('hasMbtilesArchive false initially', () {
      final resolver = RuntimeTileResolver(tileSource: TileSourceType.mbtiles);
      expect(resolver.hasMbtilesArchive, isFalse);
      expect(resolver.mbtiles, isNull);
    });
  });

  group('RuntimeTileResolution model', () {
    test('hasLocalBytes true when bytes present', () {
      final resolution = RuntimeTileResolution(
        source: RuntimeTileSource.mbtiles,
        requestedCoordinates: const TileCoordinates(5, 10, 12),
        bytes: Uint8List.fromList([1]),
      );
      expect(resolution.hasLocalBytes, isTrue);
    });

    test('hasLocalBytes false when bytes null', () {
      const resolution = RuntimeTileResolution(
        source: RuntimeTileSource.online,
        requestedCoordinates: TileCoordinates(5, 10, 12),
      );
      expect(resolution.hasLocalBytes, isFalse);
    });

    test('defaults have expected values', () {
      const resolution = RuntimeTileResolution(
        source: RuntimeTileSource.placeholder,
        requestedCoordinates: TileCoordinates(0, 0, 0),
      );
      expect(resolution.scaleFactor, 1);
      expect(resolution.childX, 0);
      expect(resolution.childY, 0);
      expect(resolution.resolvedCoordinates, isNull);
    });

    test('lower zoom fallback has scale factor and child offsets', () {
      final resolution = RuntimeTileResolution(
        source: RuntimeTileSource.lowerZoomFallback,
        requestedCoordinates: const TileCoordinates(10, 20, 14),
        resolvedCoordinates: const TileCoordinates(5, 10, 13),
        bytes: Uint8List.fromList([99]),
        scaleFactor: 2,
        childX: 0,
        childY: 0,
      );
      expect(resolution.source, RuntimeTileSource.lowerZoomFallback);
      expect(resolution.scaleFactor, 2);
      expect(resolution.hasLocalBytes, isTrue);
    });
  });

  group('RuntimeTileSource enum', () {
    test('has five sources', () {
      expect(RuntimeTileSource.values, hasLength(5));
    });

    test('values in expected order', () {
      expect(RuntimeTileSource.values, [
        RuntimeTileSource.ramCache,
        RuntimeTileSource.mbtiles,
        RuntimeTileSource.lowerZoomFallback,
        RuntimeTileSource.online,
        RuntimeTileSource.placeholder,
      ]);
    });
  });
}
