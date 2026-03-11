library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tiles/offline_tiles.dart';

final Uint8List _pngTileBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wn8sKkAAAAASUVORK5CYII=',
);

void main() {
  group('S52 tile resolution cascade gaps', () {
    test('resolver returns RAM cache hit before consulting MBTiles', () {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
      );
      addTearDown(manager.dispose);

      const coordinates = TileCoordinates(3, 4, 5);
      manager.resolver.seedMemoryCache(coordinates, _pngTileBytes);

      final result = manager.resolver.resolve(coordinates);

      expect(result.source, RuntimeTileSource.ramCache);
      expect(result.requestedCoordinates, coordinates);
      expect(result.resolvedCoordinates, coordinates);
      expect(result.bytes, isNotNull);
    });

    test('resolver returns placeholder when local sources miss and online fallback is disabled', () {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        allowOnlineFallback: false,
      );
      addTearDown(manager.dispose);

      const coordinates = TileCoordinates(0, 0, 0);
      final result = manager.resolver.resolve(coordinates);

      expect(result.source, RuntimeTileSource.placeholder);
      expect(result.requestedCoordinates, coordinates);
      expect(result.bytes, isNull);
    });
  });
}