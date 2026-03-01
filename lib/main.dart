/// SNGNav Getting Started — Minimal offline map demo.
///
/// This is the shortest path from `git clone` to a working offline map.
/// It demonstrates:
/// - flutter_map rendering on Linux desktop
/// - MBTiles offline tile loading (no network required)
/// - Fallback to online OSM tiles when MBTiles file is absent
///
///
/// Usage:
///   1. Place `offline_tiles.mbtiles` in the `data/` directory
///   2. Run: flutter run -d linux
///   3. See the Chūbu region map (Nagoya / Toyota City area)
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const SNGNavGettingStarted());
}

class SNGNavGettingStarted extends StatelessWidget {
  const SNGNavGettingStarted({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Getting Started',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        useMaterial3: true,
      ),
      home: const OfflineMapPage(),
    );
  }
}

class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({super.key});

  @override
  State<OfflineMapPage> createState() => _OfflineMapPageState();
}

class _OfflineMapPageState extends State<OfflineMapPage> {
  MbTilesTileProvider? _mbTilesProvider;
  bool _isOffline = false;
  String _statusMessage = 'Initializing...';

  // Nagoya Station — default center for Chūbu region tiles
  static const _nagoya = LatLng(35.1709, 136.8815);

  // MBTiles file path — relative to the project directory.
  // The edge developer places her .mbtiles file here.
  static const _mbtilesPath = 'data/offline_tiles.mbtiles';

  @override
  void initState() {
    super.initState();
    _initTileProvider();
  }

  Future<void> _initTileProvider() async {
    final file = File(_mbtilesPath);
    if (await file.exists()) {
      try {
        final provider = MbTilesTileProvider.fromPath(
          path: _mbtilesPath,
          silenceTileNotFound: true,
        );
        setState(() {
          _mbTilesProvider = provider;
          _isOffline = true;
          _statusMessage =
              'Offline — MBTiles loaded (${_formatSize(file.lengthSync())})';
        });
      } catch (e) {
        setState(() {
          _statusMessage = 'MBTiles error: $e — using online fallback';
        });
      }
    } else {
      setState(() {
        _statusMessage =
            'No MBTiles file at $_mbtilesPath — using online OSM tiles';
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _mbTilesProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Offline Map Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOffline ? Icons.wifi_off : Icons.wifi,
                    size: 16,
                    color: _isOffline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOffline ? 'OFFLINE' : 'ONLINE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _isOffline ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _nagoya,
              initialZoom: 11,
              minZoom: 6,
              maxZoom: 16,
            ),
            children: [
              TileLayer(
                tileProvider: _mbTilesProvider ?? NetworkTileProvider(),
                urlTemplate: _mbTilesProvider == null
                    ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                    : null,
                userAgentPackageName: 'com.sngnav.getting_started',
              ),
              const SimpleAttributionWidget(
                source: Text('\u00a9 OpenStreetMap contributors'),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
