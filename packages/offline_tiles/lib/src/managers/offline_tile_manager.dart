library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:mbtiles/mbtiles.dart';

import '../models/coverage_tier.dart';
import '../models/tile_cache_config.dart';
import '../models/tile_source_type.dart';
import '../providers/offline_tile_provider.dart';
import '../resolvers/runtime_tile_resolver.dart';

typedef TileFetchCallback = Future<Uint8List?> Function(TileCoordinates coordinates);

class CachedCoverageRegion {
  const CachedCoverageRegion({
    required this.tier,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.cachedAt,
    required this.expiresAt,
  });

  final CoverageTier tier;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final DateTime cachedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class OfflineTileManager {
  OfflineTileManager({
    required this.tileSource,
    this.mbtilesPath,
    TileCacheConfig? cacheConfig,
    bool allowOnlineFallback = true,
  }) : cacheConfig = cacheConfig ?? const TileCacheConfig() {
    final archive = _openArchive(mbtilesPath);
    _resolver = RuntimeTileResolver(
      tileSource: tileSource,
      mbtiles: archive,
      allowOnlineFallback: allowOnlineFallback,
    );
    _tileProvider = OfflineTileProvider(resolver: _resolver);
  }

  final TileSourceType tileSource;
  final String? mbtilesPath;
  final TileCacheConfig cacheConfig;

  late final RuntimeTileResolver _resolver;
  late final OfflineTileProvider _tileProvider;
  final List<CachedCoverageRegion> _cachedRegions = <CachedCoverageRegion>[];

  OfflineTileProvider get tileProvider => _tileProvider;

  RuntimeTileResolver get resolver => _resolver;

  List<CachedCoverageRegion> get cachedRegions =>
      List<CachedCoverageRegion>.unmodifiable(_cachedRegions);

  bool get hasOfflineArchive => _resolver.hasMbtilesArchive;

  bool hasLocalCoverageForPoint(LatLng point, {int zoom = 12}) {
    return _resolver.hasLocalCoverage(_tileCoordinatesForPoint(point, zoom));
  }

  bool hasLocalCoverageForPoints(Iterable<LatLng> points, {int zoom = 12}) {
    for (final point in points) {
      if (!hasLocalCoverageForPoint(point, zoom: zoom)) {
        return false;
      }
    }
    return true;
  }

  List<LatLng> uncoveredPoints(Iterable<LatLng> points, {int zoom = 12}) {
    final uncovered = <LatLng>[];
    for (final point in points) {
      if (!hasLocalCoverageForPoint(point, zoom: zoom)) {
        uncovered.add(point);
      }
    }
    return uncovered;
  }

  Future<int> cacheRoute({
    required List<LatLng> routeShape,
    CoverageTier tier = CoverageTier.t1Corridor,
    TileFetchCallback? tileFetcher,
  }) async {
    if (routeShape.isEmpty) return 0;

    final rawBounds = LatLngBounds.fromPoints(routeShape);
    final bufferedBounds = _expandBoundsByKilometers(
      rawBounds,
      cacheConfig.routeBufferKilometers,
    );

    return cacheRegion(
      bounds: bufferedBounds,
      tier: tier,
      tileFetcher: tileFetcher,
    );
  }

  Future<int> cacheRegion({
    required LatLngBounds bounds,
    required CoverageTier tier,
    TileFetchCallback? tileFetcher,
  }) async {
    cleanupExpiredRegions();

    final now = DateTime.now();
    final minZoom = cacheConfig.minZoomFor(tier);
    final maxZoom = cacheConfig.maxZoomFor(tier);

    CachedCoverageRegion buildRegion() => CachedCoverageRegion(
          tier: tier,
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
          cachedAt: now,
          expiresAt: now.add(cacheConfig.expiryFor(tier)),
        );

    if (tileFetcher == null) {
      _cachedRegions.add(buildRegion());
      return 0;
    }

    // Validate archive access before recording coverage.
    final archive = _ensureWritableArchive(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    _cachedRegions.add(buildRegion());

    var storedTileCount = 0;
    for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
      final range = _tileRangeForBounds(bounds, zoom);
      for (var x = range.minX; x <= range.maxX; x++) {
        for (var y = range.minY; y <= range.maxY; y++) {
          final coordinates = TileCoordinates(x, y, zoom);
          final bytes = await tileFetcher(coordinates);
          if (bytes == null) continue;
          archive.putTile(
            z: zoom,
            x: x,
            y: _toTmsY(y, zoom),
            bytes: bytes,
          );
          _resolver.seedMemoryCache(coordinates, bytes);
          storedTileCount++;
        }
      }
    }

    return storedTileCount;
  }

  void cleanupExpiredRegions() {
    final now = DateTime.now();
    final hadRegions = _cachedRegions.isNotEmpty;
    _cachedRegions.removeWhere((region) => region.expiresAt.isBefore(now));
    if (hadRegions && _cachedRegions.isEmpty) {
      _resolver.clearMemoryCache();
    }
  }

  Future<void> dispose() async {
    final archive = _resolver.mbtiles;
    if (archive != null) {
      archive.close();
    }
    _resolver.clearMemoryCache();
    await _tileProvider.dispose();
  }

  static MbTiles? _openArchive(String? path) {
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return MbTiles(path: path, editable: true);
  }

  MbTiles _ensureWritableArchive({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    final existing = _resolver.mbtiles;
    if (existing != null) {
      return existing;
    }
    final path = mbtilesPath;
    if (path == null) {
      throw StateError('cacheRegion requires an mbtilesPath when tiles are written');
    }

    final file = File(path);
    if (file.existsSync()) {
      final archive = MbTiles(path: path, editable: true);
      _resolver.attachMbTiles(archive);
      return archive;
    }

    file.parent.createSync(recursive: true);
    final archive = MbTiles.create(
      path: path,
      metadata: MbTilesMetadata(
        name: 'offline_tiles cache',
        format: 'png',
        bounds: MbTilesBounds(
          bottom: bounds.south,
          left: bounds.west,
          top: bounds.north,
          right: bounds.east,
        ),
        defaultCenter: LatLng(
          (bounds.north + bounds.south) / 2,
          (bounds.east + bounds.west) / 2,
        ),
        defaultZoom: maxZoom.toDouble(),
        minZoom: minZoom.toDouble(),
        maxZoom: maxZoom.toDouble(),
        type: TileLayerType.baseLayer,
        version: 1.0,
        description: 'Generated by offline_tiles',
      ),
    );
    _resolver.attachMbTiles(archive);
    return archive;
  }

  LatLngBounds _expandBoundsByKilometers(LatLngBounds bounds, double bufferKm) {
    final averageLatitude = (bounds.north + bounds.south) / 2;
    final latitudeBuffer = bufferKm / 111.0;
    final longitudeBuffer = bufferKm /
        math.max(1.0, 111.320 * math.cos(averageLatitude * math.pi / 180).abs());

    return LatLngBounds.unsafe(
      north: math.min(LatLngBounds.maxLatitude, bounds.north + latitudeBuffer),
      south: math.max(LatLngBounds.minLatitude, bounds.south - latitudeBuffer),
      east: math.min(LatLngBounds.maxLongitude, bounds.east + longitudeBuffer),
      west: math.max(LatLngBounds.minLongitude, bounds.west - longitudeBuffer),
    );
  }

  _TileRange _tileRangeForBounds(LatLngBounds bounds, int zoom) {
    final minX = _longitudeToTileX(bounds.west, zoom);
    final maxX = _longitudeToTileX(bounds.east, zoom);
    final minY = _latitudeToTileY(bounds.north, zoom);
    final maxY = _latitudeToTileY(bounds.south, zoom);
    return _TileRange(
      minX: math.min(minX, maxX),
      maxX: math.max(minX, maxX),
      minY: math.min(minY, maxY),
      maxY: math.max(minY, maxY),
    );
  }

  int _longitudeToTileX(double longitude, int zoom) {
    final tileCount = 1 << zoom;
    final normalized = ((longitude + 180.0) / 360.0 * tileCount).floor();
    return normalized.clamp(0, tileCount - 1);
  }

  int _latitudeToTileY(double latitude, int zoom) {
    final radians = latitude * math.pi / 180.0;
    final tileCount = 1 << zoom;
    final mercator = (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2;
    final value = (mercator * tileCount).floor();
    return value.clamp(0, tileCount - 1);
  }

  TileCoordinates _tileCoordinatesForPoint(LatLng point, int zoom) {
    return TileCoordinates(
      _longitudeToTileX(point.longitude, zoom),
      _latitudeToTileY(point.latitude, zoom),
      zoom,
    );
  }

  int _toTmsY(int y, int zoom) => ((1 << zoom) - 1) - y;
}

class _TileRange {
  const _TileRange({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
}
