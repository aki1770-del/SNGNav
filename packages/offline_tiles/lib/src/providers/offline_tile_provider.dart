library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../resolvers/runtime_tile_resolver.dart';

class OfflineTileProvider extends TileProvider {
  OfflineTileProvider({
    required this.resolver,
    NetworkTileProvider? onlineProvider,
    super.headers,
  }) : _onlineProvider = onlineProvider ?? NetworkTileProvider(headers: headers);

  final RuntimeTileResolver resolver;
  final NetworkTileProvider _onlineProvider;

  @override
  bool get supportsCancelLoading => _onlineProvider.supportsCancelLoading;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final resolution = resolver.resolve(coordinates);
    return _providerForResolution(resolution, coordinates, options, null);
  }

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final resolution = resolver.resolve(coordinates);
    return _providerForResolution(resolution, coordinates, options, cancelLoading);
  }

  ImageProvider _providerForResolution(
    RuntimeTileResolution resolution,
    TileCoordinates coordinates,
    TileLayer options,
    Future<void>? cancelLoading,
  ) {
    switch (resolution.source) {
      case RuntimeTileSource.online:
        if (cancelLoading != null) {
          return _onlineProvider.getImageWithCancelLoadingSupport(
            coordinates,
            options,
            cancelLoading,
          );
        }
        return _onlineProvider.getImage(coordinates, options);
      case RuntimeTileSource.placeholder:
        return MemoryImage(TileProvider.transparentImage);
      case RuntimeTileSource.ramCache:
      case RuntimeTileSource.mbtiles:
      case RuntimeTileSource.lowerZoomFallback:
        return _ResolvedTileImageProvider(resolution);
    }
  }

  @override
  Future<void> dispose() async {
    await _onlineProvider.dispose();
    super.dispose();
  }
}

class _ResolvedTileImageProvider extends ImageProvider<_ResolvedTileImageProvider> {
  const _ResolvedTileImageProvider(this.resolution);

  final RuntimeTileResolution resolution;

  @override
  Future<_ResolvedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_ResolvedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ResolvedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: 1,
      debugLabel: resolution.requestedCoordinates.toString(),
      informationCollector: () => [DiagnosticsProperty('Current provider', key)],
    );
  }

  Future<ui.Codec> _loadAsync(
    _ResolvedTileImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    final rawBytes = key.resolution.bytes ?? TileProvider.transparentImage;
    final bytes = key.resolution.source == RuntimeTileSource.lowerZoomFallback
        ? await _cropLowerZoomFallback(rawBytes)
        : rawBytes;
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<Uint8List> _cropLowerZoomFallback(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final scaleFactor = resolution.scaleFactor;
    if (scaleFactor <= 1) {
      return bytes;
    }

    final tileWidth = image.width / scaleFactor;
    final tileHeight = image.height / scaleFactor;
    final srcRect = ui.Rect.fromLTWH(
      resolution.childX * tileWidth,
      resolution.childY * tileHeight,
      tileWidth,
      tileHeight,
    );
    final dstRect = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(image, srcRect, dstRect, ui.Paint());
    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(image.width, image.height);
    final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
