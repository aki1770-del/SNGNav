/// Snow Scene — offline-first 2D navigation with dead reckoning, weather
/// safety, and configurable providers.
///
/// This is the main entrypoint for the SNGNav Snow Scene application. It
/// demonstrates a full BLoC-based navigation stack on Flutter for Linux
/// desktop, including turn-by-turn guidance, live weather monitoring, fleet
/// awareness, and offline map tiles.
///
/// Run: flutter run -d linux -t lib/snow_scene.dart
///
/// Provider selection via --dart-define flags:
///   flutter run -d linux -t lib/snow_scene.dart                                           # defaults
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=WEATHER_PROVIDER=simulated   # demo weather
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=ROUTING_ENGINE=osrm          # OSRM routing
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=ROUTING_ENGINE=valhalla      # Valhalla routing
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=LOCATION_PROVIDER=geoclue    # real GPS
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=DEAD_RECKONING=false         # disable DR
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=DR_MODE=linear               # linear DR
///   flutter run -d linux -t lib/snow_scene.dart --dart-define=TILE_SOURCE=mbtiles           # offline tiles
///
/// The app wires 7 BLoCs:
///   LocationBloc → configurable: Simulated (default) or GeoClue2 (real GPS)
///   RoutingBloc  → configurable: Mock (default), OSRM, or Valhalla
///   NavigationBloc → turn-by-turn session
///   MapBloc      → viewport + layer visibility
///   WeatherBloc  → configurable: Open-Meteo (real) or Simulated (demo)
///   ConsentBloc  → fleet data consent gate — SQLite-backed
///   FleetBloc    → simulated fleet reports (5 vehicles, consent-gated)
///
/// Default: real weather (Open-Meteo), simulated location, Valhalla routing, fleet simulated.
/// Demo scenario: Sakae Station → Route 153 → Higashiokazaki Station.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bloc/consent_bloc.dart';
import 'bloc/consent_event.dart';
import 'bloc/fleet_bloc.dart';
import 'bloc/location_bloc.dart';
import 'bloc/location_event.dart';
import 'bloc/weather_bloc.dart';
import 'bloc/weather_event.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';
import 'config/provider_config.dart';
import 'providers/simulated_fleet_provider.dart';
import 'services/consent_database.dart';
import 'services/sqlite_consent_service.dart';
import 'widgets/snow_scene_scaffold.dart';

// ---------------------------------------------------------------------------
// Mock routing engine — Sakae Station → Higashiokazaki Station
//
// Maneuver positions MUST align with SimulatedLocationProvider waypoints.
// Both follow the same corridor: 栄駅 → 国道153号 → 岡崎方面 → 東岡崎駅.
// See OPS-RULE-005 in CLAUDE.md for the route consistency rule.
// ---------------------------------------------------------------------------

final _maneuvers = [
  RouteManeuver(index: 0, instruction: 'Depart Sakae Station heading east', type: 'depart', lengthKm: 1.8, timeSeconds: 160, position: const LatLng(35.1709, 136.9066)),
  RouteManeuver(index: 1, instruction: 'Continue east through Chikusa', type: 'straight', lengthKm: 3.5, timeSeconds: 310, position: const LatLng(35.1608, 136.9208)),
  RouteManeuver(index: 2, instruction: 'Merge onto Route 153 toward Okazaki', type: 'slight_right', lengthKm: 4.0, timeSeconds: 210, position: const LatLng(35.1376, 137.0000)),
  RouteManeuver(index: 3, instruction: 'Continue southeast on Route 153', type: 'straight', lengthKm: 5.5, timeSeconds: 290, position: const LatLng(35.1013, 137.0628)),
  RouteManeuver(index: 4, instruction: 'Enter tunnel — GPS may be lost', type: 'straight', lengthKm: 6.0, timeSeconds: 360, position: const LatLng(35.0824, 137.1088)),
  RouteManeuver(index: 5, instruction: 'Exit tunnel — GPS recovered', type: 'straight', lengthKm: 3.0, timeSeconds: 270, position: const LatLng(35.0182, 137.1698)),
  RouteManeuver(index: 6, instruction: 'Continue south toward Higashiokazaki', type: 'straight', lengthKm: 4.5, timeSeconds: 400, position: const LatLng(34.9896, 137.1707)),
  RouteManeuver(index: 7, instruction: 'Arrive at Higashiokazaki Station', type: 'arrive', lengthKm: 0.0, timeSeconds: 0, position: const LatLng(34.9554, 137.1791)),
];

/// Route shape follows the simulated location waypoints for visual consistency.
/// Every shape point corresponds to a waypoint in SimulatedLocationProvider.
final _demoShape = const [
  LatLng(35.1709, 136.9066),  // wp0:  Sakae Station (depart)
  LatLng(35.1713, 136.9146),  // wp1:  city
  LatLng(35.1608, 136.9208),  // wp2:  Chikusa
  LatLng(35.1607, 136.9491),  // wp3:  city
  LatLng(35.1513, 136.9837),  // wp4:  city exit
  LatLng(35.1376, 137.0000),  // wp5:  Route 153 merge
  LatLng(35.1291, 137.0150),  // wp6:  suburban
  LatLng(35.1121, 137.0352),  // wp7:  suburban
  LatLng(35.1013, 137.0628),  // wp8:  suburban
  LatLng(35.0889, 137.0846),  // wp9:  suburban
  LatLng(35.0824, 137.1088),  // wp10: tunnel entrance
  LatLng(35.0743, 137.1275),  // wp11: tunnel
  LatLng(35.0571, 137.1332),  // wp12: tunnel
  LatLng(35.0449, 137.1416),  // wp13: tunnel
  LatLng(35.0340, 137.1527),  // wp14: tunnel exit approach
  LatLng(35.0182, 137.1698),  // wp15: tunnel exit (GPS recovered)
  LatLng(35.0031, 137.1708),  // wp16: approach
  LatLng(34.9896, 137.1707),  // wp17: approach
  LatLng(34.9715, 137.1798),  // wp18: approach
  LatLng(34.9554, 137.1791),  // wp19: Higashiokazaki Station (arrive)
];

final _demoRoute = RouteResult(
  shape: _demoShape,
  maneuvers: _maneuvers,
  totalDistanceKm: 28.3,
  totalTimeSeconds: 2000,
  summary: 'Sakae Station → Route 153 → Higashiokazaki Station',
  engineInfo: const EngineInfo(name: 'mock', version: 'snow-scene-v0.3.1', queryLatency: Duration(milliseconds: 5)),
);

const _offlineCoverageValidationZoom = 12;

class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => _demoRoute.engineInfo;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _demoRoute;
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// App entry point
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open persistent consent database.
  // Data survives app restart — consent state is durable across sessions.
  final appDir = await getApplicationSupportDirectory();
  final dbDir = Directory(p.join(appDir.path, 'sngnav'));
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }
  final dbPath = p.join(dbDir.path, 'consent.db');
  final consentDb = openConsentDatabase(dbPath);

  final config = ProviderConfig.fromEnvironment();

  // Create the tile provider through the extracted offline tile package.
  offline_tiles.OfflineTileManager? offlineTileManager;
  TileProvider? tileProvider;
  if (config.isMbtilesTiles) {
    try {
      offlineTileManager = offline_tiles.OfflineTileManager(
        tileSource: offline_tiles.TileSourceType.mbtiles,
        mbtilesPath: config.mbtilesPath,
      );
      tileProvider = offlineTileManager.tileProvider;
      final uncovered = offlineTileManager.uncoveredPoints(
        _demoRoute.shape,
        zoom: _offlineCoverageValidationZoom,
      );
      if (uncovered.isNotEmpty) {
        final preview = uncovered
            .take(3)
            .map((point) =>
                '(${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})')
            .join(', ');
        debugPrint(
          'Warning: MBTiles coverage is incomplete for the mock route at zoom '
          '$_offlineCoverageValidationZoom. Hybrid online fallback will be used. '
          'Uncovered sample: $preview',
        );
      }
    } catch (_) {
      // Fallback to online tiles if the archive fails to load.
      offlineTileManager = null;
      tileProvider = null;
    }
  }

  runApp(SnowSceneApp(
    consentDb: consentDb,
    config: config,
    offlineTileManager: offlineTileManager,
    tileProvider: tileProvider,
  ));
}

class SnowSceneApp extends StatefulWidget {
  const SnowSceneApp({
    super.key,
    required this.consentDb,
    required this.config,
    this.offlineTileManager,
    this.tileProvider,
  });

  final Database consentDb;
  final ProviderConfig config;
  final offline_tiles.OfflineTileManager? offlineTileManager;
  final TileProvider? tileProvider;

  @override
  State<SnowSceneApp> createState() => _SnowSceneAppState();
}

class _SnowSceneAppState extends State<SnowSceneApp> {
  @override
  void dispose() {
    widget.offlineTileManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Snow Scene v0.3.1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => LocationBloc(
              // Provider selected via --dart-define=LOCATION_PROVIDER=...
              // Default: Simulated (Route 19 with tunnel scenario).
              // Dead reckoning wraps automatically unless DEAD_RECKONING=false.
              provider: widget.config.createLocationProvider(),
            )..add(const LocationStartRequested()),
          ),
          BlocProvider(
            create: (_) => RoutingBloc(
              engine: widget.config.createRoutingEngine() ?? _MockRoutingEngine(),
            )
              ..add(const RoutingEngineCheckRequested())
              ..add(const RouteRequested(
                origin: LatLng(35.1709, 136.9066),
                destination: LatLng(34.9554, 137.1791),
                destinationLabel: 'Higashiokazaki Station',
              )),
          ),
          BlocProvider(create: (_) => NavigationBloc()),
          BlocProvider(
            create: (_) => MapBloc(),
          ),
          BlocProvider(
            create: (_) => WeatherBloc(
              // Provider selected via --dart-define=WEATHER_PROVIDER=...
              // Default: Open-Meteo (real Nagoya weather, no API key).
              // Simulated: 6-phase mountain pass scenario.
              provider: widget.config.createWeatherProvider(),
            )..add(const WeatherMonitorStarted()),
          ),
          BlocProvider(
            create: (_) => ConsentBloc(
              service: SqliteConsentService(widget.consentDb),
            )..add(const ConsentLoadRequested()),
          ),
          BlocProvider(
            create: (_) => FleetBloc(
              provider: SimulatedFleetProvider(),
            ),
          ),
        ],
        child: SnowSceneScaffold(tileProvider: widget.tileProvider),
      ),
    );
  }
}
