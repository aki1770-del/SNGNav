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
/// Default: real weather (Open-Meteo), simulated location+routing, fleet simulated.
/// Demo scenario: Route 153 Nagoya -> Toyota -> Mikawa Highlands.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'bloc/consent_bloc.dart';
import 'bloc/consent_event.dart';
import 'bloc/fleet_bloc.dart';
import 'bloc/fleet_event.dart';
import 'bloc/location_bloc.dart';
import 'bloc/location_event.dart';
import 'bloc/map_bloc.dart';
import 'bloc/map_event.dart';
import 'bloc/map_state.dart';
import 'bloc/navigation_bloc.dart';
import 'bloc/routing_bloc.dart';
import 'bloc/routing_event.dart';
import 'bloc/weather_bloc.dart';
import 'bloc/weather_event.dart';
import 'models/route_result.dart';
import 'providers/routing_engine.dart';
import 'config/provider_config.dart';
import 'providers/simulated_fleet_provider.dart';
import 'services/consent_database.dart';
import 'services/sqlite_consent_service.dart';
import 'widgets/snow_scene_scaffold.dart';

// ---------------------------------------------------------------------------
// Mock routing engine — pre-built Nagoya → Mikawa route
// ---------------------------------------------------------------------------

final _maneuvers = [
  RouteManeuver(index: 0, instruction: 'Depart Nagoya Station via Route 153 East', type: 'depart', lengthKm: 2.1, timeSeconds: 180, position: const LatLng(35.1709, 136.8815)),
  RouteManeuver(index: 1, instruction: 'Continue east on Route 153', type: 'straight', lengthKm: 4.5, timeSeconds: 270, position: const LatLng(35.1680, 136.9100)),
  RouteManeuver(index: 2, instruction: 'Bear right toward Toyota', type: 'slight_right', lengthKm: 5.2, timeSeconds: 310, position: const LatLng(35.1450, 136.9600)),
  RouteManeuver(index: 3, instruction: 'Continue through Toyota City', type: 'straight', lengthKm: 6.0, timeSeconds: 430, position: const LatLng(35.1200, 137.0100)),
  RouteManeuver(index: 4, instruction: 'Turn left toward mountains', type: 'left', lengthKm: 8.0, timeSeconds: 690, position: const LatLng(35.0831, 137.1559)),
  RouteManeuver(index: 5, instruction: 'Begin mountain ascent — snow possible', type: 'straight', lengthKm: 5.5, timeSeconds: 570, position: const LatLng(35.0600, 137.2500)),
  RouteManeuver(index: 6, instruction: 'Pass summit — descend to highlands', type: 'straight', lengthKm: 6.8, timeSeconds: 610, position: const LatLng(35.0500, 137.3200)),
  RouteManeuver(index: 7, instruction: 'Arrive at Mikawa Highlands', type: 'arrive', lengthKm: 0.0, timeSeconds: 0, position: const LatLng(35.0700, 137.4000)),
];

final _demoRoute = RouteResult(
  shape: _maneuvers.map((m) => m.position).toList(),
  maneuvers: _maneuvers,
  totalDistanceKm: 38.1,
  totalTimeSeconds: 3060,
  summary: 'Route 153: Nagoya → Toyota → Mikawa Highlands',
  engineInfo: const EngineInfo(name: 'mock', version: 'snow-scene-v0.3.1', queryLatency: Duration(milliseconds: 5)),
);

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

  // Try loading MBTiles for offline map tiles.
  TileProvider? tileProvider;
  if (config.isMbtilesTiles) {
    final file = File(config.mbtilesPath);
    if (file.existsSync()) {
      try {
        tileProvider = MbTilesTileProvider.fromPath(
          path: config.mbtilesPath,
        );
      } catch (_) {
        // Fallback to online tiles if MBTiles fails to load.
      }
    }
  }

  runApp(SnowSceneApp(
    consentDb: consentDb,
    config: config,
    tileProvider: tileProvider,
  ));
}

class SnowSceneApp extends StatelessWidget {
  final Database consentDb;
  final ProviderConfig config;
  final TileProvider? tileProvider;

  const SnowSceneApp({
    super.key,
    required this.consentDb,
    required this.config,
    this.tileProvider,
  });

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
              provider: config.createLocationProvider(),
            )..add(const LocationStartRequested()),
          ),
          BlocProvider(
            create: (_) => RoutingBloc(
              engine: config.createRoutingEngine() ?? _MockRoutingEngine(),
            )
              ..add(const RoutingEngineCheckRequested())
              ..add(const RouteRequested(
                origin: LatLng(35.1709, 136.9066),
                destination: LatLng(34.9551, 137.1771),
                destinationLabel: 'Higashiokazaki Station',
              )),
          ),
          BlocProvider(create: (_) => NavigationBloc()),
          BlocProvider(
            create: (_) => MapBloc()
              ..add(const CameraModeChanged(CameraMode.follow))
              ..add(const LayerToggled(
                layer: MapLayerType.weather,
                visible: true,
              ))
              ..add(const LayerToggled(
                layer: MapLayerType.safety,
                visible: true,
              ))
              ..add(const LayerToggled(
                layer: MapLayerType.fleet,
                visible: true,
              )),
          ),
          BlocProvider(
            create: (_) => WeatherBloc(
              // Provider selected via --dart-define=WEATHER_PROVIDER=...
              // Default: Open-Meteo (real Nagoya weather, no API key).
              // Simulated: 6-phase mountain pass scenario.
              provider: config.createWeatherProvider(),
            )..add(const WeatherMonitorStarted()),
          ),
          BlocProvider(
            create: (_) => ConsentBloc(
              service: SqliteConsentService(consentDb),
            )..add(const ConsentLoadRequested()),
          ),
          BlocProvider(
            create: (_) => FleetBloc(
              provider: SimulatedFleetProvider(),
            )..add(const FleetListenStarted()),
          ),
        ],
        child: SnowSceneScaffold(tileProvider: tileProvider),
      ),
    );
  }
}
