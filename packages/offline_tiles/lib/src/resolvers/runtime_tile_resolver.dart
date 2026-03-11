library;

import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:mbtiles/mbtiles.dart';

import '../models/tile_source_type.dart';

enum RuntimeTileSource {
  ramCache,
  mbtiles,
  lowerZoomFallback,
  online,
  placeholder,
}

class RuntimeTileResolution {
  const RuntimeTileResolution({
    required this.source,
    required this.requestedCoordinates,
    this.resolvedCoordinates,
    this.bytes,
    this.scaleFactor = 1,
    this.childX = 0,
    this.childY = 0,
  });

  final RuntimeTileSource source;
  final TileCoordinates requestedCoordinates;
  final TileCoordinates? resolvedCoordinates;
  final Uint8List? bytes;
  final int scaleFactor;
  final int childX;
  final int childY;

  bool get hasLocalBytes => bytes != null;
}

class RuntimeTileResolver {
  RuntimeTileResolver({
    required this.tileSource,
    MbTiles? mbtiles,
    this.allowOnlineFallback = true,
  }) : _mbtiles = mbtiles;

  final TileSourceType tileSource;
  final bool allowOnlineFallback;

  MbTiles? _mbtiles;
  final Map<String, Uint8List> _ramCache = <String, Uint8List>{};

  MbTiles? get mbtiles => _mbtiles;

  bool get hasMbtilesArchive => _mbtiles != null;

  void attachMbTiles(MbTiles mbtiles) {
    _mbtiles = mbtiles;
  }

  void seedMemoryCache(TileCoordinates coordinates, Uint8List bytes) {
    _ramCache[_cacheKey(coordinates)] = bytes;
  }

  void clearMemoryCache() {
    _ramCache.clear();
  }

  bool hasLocalCoverage(TileCoordinates coordinates) {
    if (_ramCache.containsKey(_cacheKey(coordinates))) {
      return true;
    }
    if (_lookupExact(coordinates) != null) {
      return true;
    }
    return _lookupLowerZoomFallback(coordinates) != null;
  }

  RuntimeTileResolution resolve(TileCoordinates coordinates) {
    if (tileSource == TileSourceType.online) {
      return RuntimeTileResolution(
        source: RuntimeTileSource.online,
        requestedCoordinates: coordinates,
      );
    }

    final cached = _ramCache[_cacheKey(coordinates)];
    if (cached != null) {
      return RuntimeTileResolution(
        source: RuntimeTileSource.ramCache,
        requestedCoordinates: coordinates,
        resolvedCoordinates: coordinates,
        bytes: cached,
      );
    }

    final exact = _lookupExact(coordinates);
    if (exact != null) {
      _ramCache[_cacheKey(coordinates)] = exact;
      return RuntimeTileResolution(
        source: RuntimeTileSource.mbtiles,
        requestedCoordinates: coordinates,
        resolvedCoordinates: coordinates,
        bytes: exact,
      );
    }

    final fallback = _lookupLowerZoomFallback(coordinates);
    if (fallback != null) {
      return fallback;
    }

    return RuntimeTileResolution(
      source: allowOnlineFallback
          ? RuntimeTileSource.online
          : RuntimeTileSource.placeholder,
      requestedCoordinates: coordinates,
    );
  }

  Uint8List? _lookupExact(TileCoordinates coordinates) {
    final archive = _mbtiles;
    if (archive == null) return null;
    return archive.getTile(
      z: coordinates.z,
      x: coordinates.x,
      y: _toTmsY(coordinates.y, coordinates.z),
    );
  }

  RuntimeTileResolution? _lookupLowerZoomFallback(TileCoordinates coordinates) {
    final archive = _mbtiles;
    if (archive == null) return null;

    for (var delta = 1; delta <= coordinates.z; delta++) {
      final scaleFactor = 1 << delta;
      final fallbackCoords = TileCoordinates(
        coordinates.x >> delta,
        coordinates.y >> delta,
        coordinates.z - delta,
      );
      final bytes = archive.getTile(
        z: fallbackCoords.z,
        x: fallbackCoords.x,
        y: _toTmsY(fallbackCoords.y, fallbackCoords.z),
      );
      if (bytes != null) {
        return RuntimeTileResolution(
          source: RuntimeTileSource.lowerZoomFallback,
          requestedCoordinates: coordinates,
          resolvedCoordinates: fallbackCoords,
          bytes: bytes,
          scaleFactor: scaleFactor,
          childX: coordinates.x % scaleFactor,
          childY: coordinates.y % scaleFactor,
        );
      }
    }

    return null;
  }

  int _toTmsY(int y, int z) => ((1 << z) - 1) - y;

  String _cacheKey(TileCoordinates coordinates) =>
      '${coordinates.z}/${coordinates.x}/${coordinates.y}';
}
