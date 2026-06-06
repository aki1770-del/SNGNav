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

import 'dart:async';
import 'dart:io';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:snow_rendering/snow_rendering.dart';

import 'bloc/location_state.dart';
import 'config/provider_config.dart';
import 'fluorite/snow_scene_3d_view.dart';

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

/// Which view fills the main body: the existing top-down 2D map, or the
/// perspective forward-looking 3D snow scene.
enum _ViewMode { map, forward }

class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({super.key});

  @override
  State<OfflineMapPage> createState() => _OfflineMapPageState();
}

class _OfflineMapPageState extends State<OfflineMapPage> {
  offline_tiles.OfflineTileManager? _offlineTileManager;
  bool _isOffline = false;
  String _statusMessage = 'Initializing...';

  // Default view is the existing 2D map — the toggle is opt-in, the app's
  // default behaviour is unchanged.
  _ViewMode _viewMode = _ViewMode.map;

  // The driving-condition picture fed to the 3D forward-view.
  //
  // OFFLINE-FIRST (D3 worst-case — non-negotiable): this field is initialised
  // to a SIMULATED default so the forward-view renders IMMEDIATELY with zero
  // network and zero GPS. The compound-failure case (Google Maps fails AND GPS
  // fails) must still show a meaningful Snow Scene — so the default is always a
  // valid assessment and is the permanent fallback.
  //
  // LIVE WIRING (additive, never load-bearing for offline): when the edge
  // developer selects the live Digitraffic provider
  // (`--dart-define=WEATHER_PROVIDER=digitraffic`, ONLINE only) we subscribe to
  // its `Stream<WeatherCondition>` and update `_assessment` via setState as real
  // winter-road severity arrives — reusing the exact provider/stream pattern the
  // full `snow_scene.dart` app uses (ProviderConfig.createWeatherProvider →
  // WeatherProvider.conditions). On ANY failure (no provider configured,
  // network error, parse error, disposed) the scene KEEPS the last-good /
  // default assessment and keeps rendering — no uncaught exception, no blank
  // scene, no hard network dependency. The non-digitraffic providers (simulated
  // default, open_meteo) are left untouched here: this minimal getting-started
  // entrypoint only opts in to the live winter-severity feed, and otherwise
  // stays purely offline-renderable.
  DrivingConditionAssessment _assessment =
      DrivingConditionAssessment.fromCondition(
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.moderate,
      temperatureCelsius: -3.0,
      visibilityMeters: 600.0, // reduced — fog wall visible
      windSpeedKmh: 18.0,
      iceRisk: true,
      timestamp: DateTime(2026, 1, 1, 7, 15),
    ),
  );

  // The live weather provider (only constructed when WEATHER_PROVIDER=digitraffic).
  // Null on every offline/default path — the scene never depends on it existing.
  WeatherProvider? _weatherProvider;
  StreamSubscription<WeatherCondition>? _weatherSub;

  // True once a live condition has actually arrived from the feed, so the
  // caption can tell the truth about whether the scene reflects live severity
  // or the simulated default.
  bool _liveConditionReceived = false;

  // HONEST GPS-LOSS DEGRADATION (D3 worst-case — GPS fails).
  //
  // The 3D forward-view is driven by weather alone; on its own it would keep
  // painting a confident, crisp road even when GPS is lost and the real
  // position is drifting — the dishonest failure D4 forbids. The fix is to feed
  // SnowScene3DView a LocationState so it degrades honestly (uncertainty fog +
  // "GPS lost" banner; "POSITION UNAVAILABLE" at the 500 m DR safety cap).
  //
  // A Linux desktop host has no real GPS provider, so this minimal
  // getting-started entrypoint lets the edge developer SEE the degradation by
  // cycling a SIMULATED location quality from the AppBar (the GPS icon). A
  // production app wires a real LocationBloc + DeadReckoningProvider here
  // instead — the SnowScene3DView contract is identical.
  int _gpsSimIndex = 0;
  late final List<LocationState> _gpsSimStates = [
    // 0: healthy navigation-grade fix (±8 m) → confident scene, no overlay.
    LocationState(
      quality: LocationQuality.fix,
      position: GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 8,
        speed: 14,
        heading: 90,
        timestamp: DateTime(2026, 1, 1, 7, 15),
      ),
    ),
    // 1: GPS lost → dead reckoning, ±220 m uncertainty → fog + "GPS lost" banner.
    LocationState(
      quality: LocationQuality.degraded,
      isDeadReckoning: true,
      position: GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 220,
        speed: 14,
        heading: 90,
        timestamp: DateTime(2026, 1, 1, 7, 15),
      ),
    ),
    // 2: DR exceeded the 500 m safety cap → honesty floor: position unavailable.
    const LocationState(
      quality: LocationQuality.error,
      errorMessage: 'Dead reckoning exceeded 500 m safety cap',
    ),
  ];

  LocationState get _location => _gpsSimStates[_gpsSimIndex];

  // Nagoya Station — default center for Chūbu region tiles
  static const _nagoya = LatLng(35.1709, 136.8815);

  // MBTiles file path — relative to the project directory.
  // The edge developer places her .mbtiles file here.
  static const _mbtilesPath = 'data/offline_tiles.mbtiles';

  @override
  void initState() {
    super.initState();
    _initTileProvider();
    _initLiveWeather();
  }

  /// Subscribes the held [_assessment] to a LIVE winter-road severity feed,
  /// but ONLY when the edge developer has opted in via
  /// `--dart-define=WEATHER_PROVIDER=digitraffic`. On every other path
  /// (the default offline/simulated path) this is a no-op and the scene keeps
  /// rendering the simulated default — preserving the offline-first invariant.
  ///
  /// All failures are swallowed into the default-fallback: if the provider can
  /// not be built, can not start, or the feed errors, [_assessment] simply
  /// stays at its last-good value and the scene never blanks.
  Future<void> _initLiveWeather() async {
    try {
      final config = ProviderConfig.fromEnvironment();

      // Offline-first gate: only the explicit live Digitraffic selection wires
      // a network stream. simulated/open_meteo defaults stay purely local here.
      if (config.weatherType != WeatherProviderType.digitraffic) {
        return;
      }

      final provider = config.createWeatherProvider();
      _weatherProvider = provider;

      _weatherSub = provider.conditions.listen(
        (condition) {
          // Reuse the proven mapping the rest of the app uses:
          // WeatherCondition -> DrivingConditionAssessment.
          if (!mounted) return;
          setState(() {
            _assessment =
                DrivingConditionAssessment.fromCondition(condition);
            _liveConditionReceived = true;
          });
        },
        // Stream errors fall back to the existing assessment — no rethrow.
        onError: (Object _) {/* keep last-good assessment */},
        cancelOnError: false,
      );

      await provider.startMonitoring();
    } catch (_) {
      // Any failure constructing/starting the live feed -> stay on the default
      // simulated assessment. The offline scene is never compromised.
    }
  }

  Future<void> _initTileProvider() async {
    final file = File(_mbtilesPath);
    try {
      if (await file.exists()) {
        final manager = offline_tiles.OfflineTileManager(
          tileSource: offline_tiles.TileSourceType.mbtiles,
          mbtilesPath: _mbtilesPath,
        );
        setState(() {
          _offlineTileManager = manager;
          _isOffline = true;
          _statusMessage =
              'Offline — MBTiles loaded (${_formatSize(file.lengthSync())})';
        });
      } else {
        setState(() {
          _offlineTileManager = null;
          _isOffline = false;
          _statusMessage =
              'No MBTiles file at $_mbtilesPath — using online fallback';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'MBTiles error: $e — using online fallback';
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
    _weatherSub?.cancel();
    _weatherProvider?.dispose();
    _offlineTileManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Offline Map Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // View-mode toggle: 2D map <-> 3D forward-view. The control lives in
          // the AppBar (idiomatic for a top-level mode switch) and drives the
          // _viewMode field via setState \u2014 matching this page's existing
          // setState-based state pattern (no app-shell BLoC here).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<_ViewMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                segments: const [
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.map,
                    icon: Icon(Icons.map_outlined, size: 16),
                    label: Text('2D map'),
                  ),
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.forward,
                    icon: Icon(Icons.landscape_outlined, size: 16),
                    label: Text('Forward'),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) {
                  setState(() => _viewMode = selection.first);
                },
              ),
            ),
          ),
          // Honest GPS-loss demo: cycle the simulated location quality the 3D
          // forward-view is fed (fix → dead-reckoning → position-unavailable),
          // so the honest degradation is actually visible on this host.
          IconButton(
            tooltip: 'Simulate GPS quality (fix → estimated → lost)',
            icon: Icon(switch (_location.quality) {
              LocationQuality.fix => Icons.gps_fixed,
              LocationQuality.error => Icons.gps_off,
              _ => Icons.gps_not_fixed,
            }),
            onPressed: () => setState(() {
              _gpsSimIndex = (_gpsSimIndex + 1) % _gpsSimStates.length;
            }),
          ),
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
      body: switch (_viewMode) {
        _ViewMode.map => _buildMapView(),
        _ViewMode.forward => _buildForwardView(),
      },
    );
  }

  /// The existing top-down 2D offline map (unchanged behaviour; now extracted
  /// so the body can switch between view modes).
  Widget _buildMapView() {
    return Stack(
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
              tileProvider:
                  _offlineTileManager?.tileProvider ?? NetworkTileProvider(),
              urlTemplate: _offlineTileManager == null
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
    );
  }

  /// The perspective forward-looking 3D snow scene.
  ///
  /// Honest bounds (see [SnowScene3DView] doc-comment): this is a CPU-projected
  /// still-frame pixel \u2014 no GPU/PBR/lighting; the fog is a linear gradient and
  /// precipitation a deterministic glance-cue sample, not a physics sim. It is
  /// fed by [_assessment], which is a SIMULATED default (rendered immediately,
  /// offline) and updates to LIVE Digitraffic winter-road severity only when the
  /// edge developer opts in with `--dart-define=WEATHER_PROVIDER=digitraffic`
  /// AND the feed is reachable; on any failure it stays on the simulated
  /// default. The advisory chip's text legibility at small sizes is a known gap.
  Widget _buildForwardView() {
    final caption = _liveConditionReceived
        ? 'Forward-view \u2014 CPU-projected still frame, '
            'live Digitraffic winter-road severity'
        : 'Forward-view \u2014 CPU-projected still frame, simulated default '
            '(live Digitraffic severity when WEATHER_PROVIDER=digitraffic and online)';
    return Stack(
      children: [
        SnowScene3DView(assessment: _assessment, location: _location),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              caption,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
