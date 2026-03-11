import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart';

const _nagoya = LatLng(35.1709, 136.9066);

void main() {
  runApp(const OfflineTilesExampleApp());
}

class OfflineTilesExampleApp extends StatelessWidget {
  const OfflineTilesExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const _OfflineTilesExampleScreen(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
    );
  }
}

class _OfflineTilesExampleScreen extends StatefulWidget {
  const _OfflineTilesExampleScreen();

  @override
  State<_OfflineTilesExampleScreen> createState() => _OfflineTilesExampleScreenState();
}

class _OfflineTilesExampleScreenState extends State<_OfflineTilesExampleScreen> {
  late final OfflineTileManager _onlineManager;
  late final OfflineTileManager _offlineManager;
  bool _preferOffline = true;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _onlineManager = OfflineTileManager(tileSource: TileSourceType.online);
    _offlineManager = OfflineTileManager(
      tileSource: TileSourceType.mbtiles,
      mbtilesPath: 'data/offline_tiles.mbtiles',
    );
    _status = _offlineManager.hasOfflineArchive
        ? 'MBTiles archive detected'
        : 'No MBTiles archive found, online fallback will be used';
  }

  @override
  void dispose() {
    _onlineManager.dispose();
    _offlineManager.dispose();
    super.dispose();
  }

  OfflineTileManager get _currentManager =>
      _preferOffline ? _offlineManager : _onlineManager;

  Future<void> _cacheCurrentViewport() async {
    final bounds = LatLngBounds.unsafe(
      north: 35.24,
      south: 35.10,
      east: 137.02,
      west: 136.84,
    );
    final planned = await _offlineManager.cacheRegion(
      bounds: bounds,
      tier: CoverageTier.t2Metro,
    );
    setState(() {
      _status = 'Viewport cache planned: ${_offlineManager.cachedRegions.length} region(s), $planned tiles written';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('offline_tiles example'),
        actions: [
          Switch(
            value: _preferOffline,
            onChanged: (value) {
              setState(() {
                _preferOffline = value;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: _nagoya,
                initialZoom: 11,
              ),
              children: [
                TileLayer(
                  tileProvider: _currentManager.tileProvider,
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.sngnav.offline_tiles.example',
                ),
                const SimpleAttributionWidget(
                  source: Text('\u00a9 OpenStreetMap contributors'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_status),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _cacheCurrentViewport,
                  child: const Text('Cache Current Viewport (Plan)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
