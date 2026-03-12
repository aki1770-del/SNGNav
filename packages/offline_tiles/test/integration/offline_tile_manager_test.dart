library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:offline_tiles/offline_tiles.dart';

final Uint8List _pngTileBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wn8sKkAAAAASUVORK5CYII=',
);

void main() {
  group('OfflineTileManager', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('offline_tiles_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves exact MBTiles tile at requested zoom', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 0, x: 0, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final result = manager.resolver.resolve(const TileCoordinates(0, 0, 0));
      expect(result.source, RuntimeTileSource.mbtiles);
      expect(result.bytes, isNotNull);
    });

    test('resolves lower-zoom fallback when exact zoom tile is missing', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 0, x: 0, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final result = manager.resolver.resolve(const TileCoordinates(1, 1, 1));
      expect(result.source, RuntimeTileSource.lowerZoomFallback);
      expect(result.resolvedCoordinates, const TileCoordinates(0, 0, 0));
      expect(result.scaleFactor, 2);
      expect(result.bytes, isNotNull);
    });

    test('reports local coverage for points with exact and fallback tiles', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 0, x: 0, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      expect(
        manager.hasLocalCoverageForPoint(const LatLng(0, 0), zoom: 0),
        isTrue,
      );
      expect(
        manager.hasLocalCoverageForPoint(const LatLng(45, 45), zoom: 1),
        isTrue,
      );
      expect(
        manager.hasLocalCoverageForPoints(
          const [LatLng(0, 0), LatLng(45, 45)],
          zoom: 1,
        ),
        isTrue,
      );
    });

    test('route coverage returns false when any waypoint is missing', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 1, x: 1, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      expect(
        manager.hasLocalCoverageForPoints(
          const [LatLng(0, 0), LatLng(-70, -170)],
          zoom: 1,
        ),
        isFalse,
      );
    });

    test('uncoveredPoints returns the missing waypoints along a route shape', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 1, x: 1, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final uncovered = manager.uncoveredPoints(
        const [LatLng(0, 0), LatLng(-70, -170)],
        zoom: 1,
      );

      expect(uncovered, hasLength(1));
      expect(uncovered.single, const LatLng(-70, -170));
    });

    test('route coverage returns true when all waypoints are locally covered', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 0, x: 0, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      expect(
        manager.hasLocalCoverageForPoints(
          const [LatLng(0, 0), LatLng(45, 45)],
          zoom: 1,
        ),
        isTrue,
      );
    });

    test('uncoveredPoints is empty when a route shape is fully covered', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 0, x: 0, y: 0, bytes: _pngTileBytes);
        },
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      expect(
        manager.uncoveredPoints(
          const [LatLng(0, 0), LatLng(45, 45)],
          zoom: 1,
        ),
        isEmpty,
      );
    });

    test('online tile source reports no local coverage for route waypoints', () {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.online,
      );
      addTearDown(manager.dispose);

      expect(
        manager.hasLocalCoverageForPoints(
          const [LatLng(35.1709, 136.9066), LatLng(34.9554, 137.1791)],
          zoom: 12,
        ),
        isFalse,
      );
    });

    test('online tile source reports all route waypoints as uncovered', () {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.online,
      );
      addTearDown(manager.dispose);

      expect(
        manager.uncoveredPoints(
          const [LatLng(35.1709, 136.9066), LatLng(34.9554, 137.1791)],
          zoom: 12,
        ),
        hasLength(2),
      );
    });

    test('cacheRoute with tileFetcher makes route points locally coverable', () async {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '${tempDir.path}/route_cover.mbtiles',
      );
      addTearDown(manager.dispose);

      const routeShape = <LatLng>[
        LatLng(35.1709, 136.9066),
        LatLng(34.9554, 137.1791),
      ];

      final stored = await manager.cacheRoute(
        routeShape: routeShape,
        tileFetcher: (coordinates) async => _pngTileBytes,
      );

      expect(stored, greaterThan(0));
      expect(manager.hasLocalCoverageForPoints(routeShape), isTrue);
    });

    test('degrades to online when MBTiles archive is missing', () {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '${tempDir.path}/missing.mbtiles',
      );
      addTearDown(manager.dispose);

      final result = manager.resolver.resolve(const TileCoordinates(0, 0, 0));
      expect(result.source, RuntimeTileSource.online);
    });

    test('cacheRegion writes tiles into a generated MBTiles archive', () async {
      final path = '${tempDir.path}/generated.mbtiles';
      TileCoordinates? firstFetched;
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final stored = await manager.cacheRegion(
        bounds: LatLngBounds.unsafe(
          north: 35.1709,
          south: 35.1609,
          east: 136.9166,
          west: 136.9066,
        ),
        tier: CoverageTier.t4National,
        tileFetcher: (coordinates) async {
          firstFetched ??= coordinates;
          return _pngTileBytes;
        },
      );

      expect(stored, greaterThan(0));
      expect(File(path).existsSync(), isTrue);
      expect(firstFetched, isNotNull);

      final archive = MbTiles(mbtilesPath: path);
      addTearDown(archive.dispose);
      final metadata = archive.getMetadata();
      expect(metadata.name, 'offline_tiles cache');
      expect(
        archive.getTile(
          z: firstFetched!.z,
          x: firstFetched!.x,
          y: _toTmsY(firstFetched!.y, firstFetched!.z),
        ),
        isNotNull,
      );
    });

    test('cacheRoute registers corridor coverage entry', () async {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '${tempDir.path}/route_cache.mbtiles',
      );
      addTearDown(manager.dispose);

      final stored = await manager.cacheRoute(
        routeShape: const <LatLng>[
          LatLng(35.1709, 136.9066),
          LatLng(34.9554, 137.1791),
        ],
      );

      expect(stored, 0);
      expect(manager.cachedRegions, hasLength(1));
      expect(manager.cachedRegions.single.tier, CoverageTier.t1Corridor);
    });

    test('cleanupExpiredRegions removes immediately expired entries', () async {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '${tempDir.path}/cleanup.mbtiles',
        cacheConfig: const TileCacheConfig(
          regionalExpiry: Duration.zero,
        ),
      );
      addTearDown(manager.dispose);

      await manager.cacheRegion(
        bounds: LatLngBounds.unsafe(
          north: 35.1709,
          south: 35.1609,
          east: 136.9166,
          west: 136.9066,
        ),
        tier: CoverageTier.t2Metro,
      );

      expect(manager.cachedRegions, hasLength(1));
      manager.cleanupExpiredRegions();
      expect(manager.cachedRegions, isEmpty);
    });

    // F1 regression: write into a pre-existing archive must succeed.
    test('cacheRegion writes tiles into a pre-existing archive', () async {
      final path = await _createFixtureMbtiles(
        tempDir,
        writeTile: (archive) {
          archive.putTile(z: 0, x: 0, y: 0, bytes: _pngTileBytes);
        },
      );

      // Manager opens the existing archive (now editable).
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      // Verify original tile is present.
      final before = manager.resolver.resolve(const TileCoordinates(0, 0, 0));
      expect(before.source, RuntimeTileSource.mbtiles);

      // Write a new tile into the same archive.
      final stored = await manager.cacheRegion(
        bounds: LatLngBounds.unsafe(
          north: 35.1709,
          south: 35.1609,
          east: 136.9166,
          west: 136.9066,
        ),
        tier: CoverageTier.t4National,
        tileFetcher: (coordinates) async => _pngTileBytes,
      );

      expect(stored, greaterThan(0));
    });

    // F3 regression: coverage must not be recorded when archive validation fails.
    test('cacheRegion does not record phantom coverage on write failure', () async {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        // No mbtilesPath — write path will throw.
      );
      addTearDown(manager.dispose);

      expect(
        () => manager.cacheRegion(
          bounds: LatLngBounds.unsafe(
            north: 35.17,
            south: 35.16,
            east: 136.92,
            west: 136.91,
          ),
          tier: CoverageTier.t2Metro,
          tileFetcher: (coordinates) async => _pngTileBytes,
        ),
        throwsStateError,
      );

      expect(manager.cachedRegions, isEmpty);
    });

    // F2 regression: expired tiles must not be served from RAM cache.
    test('expired region tiles are not served from RAM cache', () async {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '${tempDir.path}/expiry_ram.mbtiles',
        cacheConfig: const TileCacheConfig(
          regionalExpiry: Duration.zero,
        ),
      );
      addTearDown(manager.dispose);

      // Cache a region, which seeds RAM cache through tileFetcher.
      TileCoordinates? firstFetched;
      await manager.cacheRegion(
        bounds: LatLngBounds.unsafe(
          north: 35.1709,
          south: 35.1609,
          east: 136.9166,
          west: 136.9066,
        ),
        tier: CoverageTier.t4National,
        tileFetcher: (coordinates) async {
          firstFetched ??= coordinates;
          return _pngTileBytes;
        },
      );

      expect(firstFetched, isNotNull);

      // Tile should resolve from RAM cache right now.
      final before = manager.resolver.resolve(firstFetched!);
      expect(before.source, RuntimeTileSource.ramCache);

      // Expire and clean up.
      manager.cleanupExpiredRegions();
      expect(manager.cachedRegions, isEmpty);

      // After cleanup the tile should no longer resolve from RAM.
      // It will fall through to MBTiles (archive still on disk).
      final after = manager.resolver.resolve(firstFetched!);
      expect(after.source, isNot(RuntimeTileSource.ramCache));
    });
  });
}

int _toTmsY(int y, int zoom) => ((1 << zoom) - 1) - y;

Future<String> _createFixtureMbtiles(
  Directory tempDir, {
  required void Function(MbTiles archive) writeTile,
}) async {
  final path = '${tempDir.path}/fixture.mbtiles';
  final archive = MbTiles.create(
    mbtilesPath: path,
    metadata: const MbTilesMetadata(
      name: 'fixture',
      format: 'png',
      minZoom: 0,
      maxZoom: 1,
      type: TileLayerType.baseLayer,
    ),
  );
  try {
    writeTile(archive);
  } finally {
    archive.dispose();
  }
  return path;
}
