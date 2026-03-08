/// Provider configuration — runtime selection of data source implementations.
///
/// Uses `--dart-define` to select providers at build/run time:
///
///   flutter run -d linux --dart-define=WEATHER_PROVIDER=simulated
///   flutter run -d linux --dart-define=WEATHER_PROVIDER=open_meteo  (default)
///   flutter run -d linux --dart-define=LOCATION_PROVIDER=simulated  (default)
///   flutter run -d linux --dart-define=LOCATION_PROVIDER=geoclue
///   flutter run -d linux --dart-define=ROUTING_ENGINE=valhalla      (default)
///   flutter run -d linux --dart-define=ROUTING_ENGINE=osrm
///   flutter run -d linux --dart-define=ROUTING_ENGINE=mock
///   flutter run -d linux --dart-define=DR_MODE=kalman               (default)
///   flutter run -d linux --dart-define=DR_MODE=linear
///   flutter run -d linux --dart-define=TILE_SOURCE=online           (default)
///   flutter run -d linux --dart-define=TILE_SOURCE=mbtiles
///   flutter run -d linux --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles
///
/// Dead reckoning wraps the selected location provider by default. To disable:
///   flutter run -d linux --dart-define=DEAD_RECKONING=false
///
/// This enables the edge developer to switch between simulated and real data
/// without code changes. The simulated provider is useful for demos, testing,
/// and offline development. The real provider is the default for production.
///
/// Interface-first design: BLoCs are implementation-agnostic.
/// The config selects which implementation to inject.
///
/// 7 configurable flags covering weather, location, routing, dead reckoning,
/// and tile sources.
///
/// Example — run with real weather and Kalman dead reckoning:
///
/// ```bash
/// flutter run -d linux \
///   --dart-define=WEATHER_PROVIDER=open_meteo \
///   --dart-define=LOCATION_PROVIDER=simulated \
///   --dart-define=DR_MODE=kalman \
///   --dart-define=ROUTING_ENGINE=osrm
/// ```
///
/// Example — fully offline demo (no network, no GPS):
///
/// ```bash
/// flutter run -d linux \
///   --dart-define=WEATHER_PROVIDER=simulated \
///   --dart-define=TILE_SOURCE=mbtiles \
///   --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles
/// ```
library;

import 'package:http/http.dart' as http;

import 'package:kalman_dr/kalman_dr.dart';
import '../providers/geoclue_location_provider.dart';
import '../providers/open_meteo_weather_provider.dart';
import 'package:routing_engine/routing_engine.dart';
import '../providers/simulated_location_provider.dart';
import '../providers/simulated_weather_provider.dart';
import '../providers/weather_provider.dart';

/// Available weather provider implementations.
enum WeatherProviderType {
  /// Simulated Nagoya mountain pass scenario — no network required.
  simulated,

  /// Open-Meteo API — real weather data, no API key required.
  openMeteo,
}

/// Available location provider implementations.
enum LocationProviderType {
  /// Simulated Route 153 driving scenario — no GPS required.
  simulated,

  /// GeoClue2 D-Bus — real GPS from the operating system.
  geoclue,
}

/// Available routing engine implementations.
enum RoutingEngineType {
  /// Mock engine — pre-built route, no network required.
  mock,

  /// OSRM — real routing via HTTP API (local Docker or public demo).
  osrm,

  /// Valhalla — multi-modal routing, isochrones, Japanese kanji support.
  valhalla,
}

/// Available tile source types for the map layer.
enum TileSourceType {
  /// Online OSM tiles — requires network.
  online,

  /// MBTiles file — fully offline, no network required.
  mbtiles,
}

/// Configuration for provider selection.
///
/// Reads `--dart-define` values at compile time via [String.fromEnvironment].
/// Defaults to production values (Open-Meteo for weather, simulated for
/// location until GeoClue2 is validated on Day 5-6).
///
/// Example — creating providers from config:
///
/// ```dart
/// final config = ProviderConfig.fromEnvironment();
/// final weather = config.createWeatherProvider();
/// final location = config.createLocationProvider();
/// final routing = config.createRoutingEngine();
/// ```
class ProviderConfig {
  /// Weather provider type selected via `--dart-define=WEATHER_PROVIDER=...`.
  final WeatherProviderType weatherType;

  /// Location provider type selected via `--dart-define=LOCATION_PROVIDER=...`.
  final LocationProviderType locationType;

  /// Whether to wrap the location provider with dead reckoning.
  /// Controlled via `--dart-define=DEAD_RECKONING=false` to disable.
  final bool deadReckoningEnabled;

  /// Dead reckoning algorithm: linear extrapolation or Kalman filter.
  /// Controlled via `--dart-define=DR_MODE=kalman` (default) or `linear`.
  final DeadReckoningMode drMode;

  /// Routing engine type selected via `--dart-define=ROUTING_ENGINE=...`.
  final RoutingEngineType routingType;

  /// Tile source type selected via `--dart-define=TILE_SOURCE=...`.
  final TileSourceType tileSource;

  /// Path to the MBTiles file for offline tiles.
  /// Only used when [tileSource] is [TileSourceType.mbtiles].
  /// Default: 'data/offline_tiles.mbtiles'.
  final String mbtilesPath;

  const ProviderConfig({
    this.weatherType = WeatherProviderType.openMeteo,
    this.locationType = LocationProviderType.simulated,
    this.deadReckoningEnabled = true,
    this.drMode = DeadReckoningMode.kalman,
    this.routingType = RoutingEngineType.valhalla,
    this.tileSource = TileSourceType.online,
    this.mbtilesPath = 'data/offline_tiles.mbtiles',
  });

  /// Creates a [ProviderConfig] from `--dart-define` environment values.
  factory ProviderConfig.fromEnvironment() {
    const weatherEnv = String.fromEnvironment(
      'WEATHER_PROVIDER',
      defaultValue: 'open_meteo',
    );

    const locationEnv = String.fromEnvironment(
      'LOCATION_PROVIDER',
      defaultValue: 'simulated',
    );

    const drEnv = String.fromEnvironment(
      'DEAD_RECKONING',
      defaultValue: 'true',
    );

    const routingEnv = String.fromEnvironment(
      'ROUTING_ENGINE',
      defaultValue: 'valhalla',
    );

    const drModeEnv = String.fromEnvironment(
      'DR_MODE',
      defaultValue: 'kalman',
    );

    const tileSourceEnv = String.fromEnvironment(
      'TILE_SOURCE',
      defaultValue: 'online',
    );

    const mbtilesPathEnv = String.fromEnvironment(
      'MBTILES_PATH',
      defaultValue: 'data/offline_tiles.mbtiles',
    );

    return ProviderConfig(
      weatherType: _parseWeatherType(weatherEnv),
      locationType: _parseLocationType(locationEnv),
      deadReckoningEnabled: drEnv.toLowerCase() != 'false',
      drMode: _parseDrMode(drModeEnv),
      routingType: _parseRoutingType(routingEnv),
      tileSource: _parseTileSource(tileSourceEnv),
      mbtilesPath: mbtilesPathEnv,
    );
  }

  /// Creates the configured [WeatherProvider] instance.
  ///
  /// For Open-Meteo: real Nagoya weather (35.18°N, 136.91°E), 5-minute poll.
  /// For Simulated: 5-second cycle through the mountain pass scenario.
  WeatherProvider createWeatherProvider({
    double latitude = 35.18,
    double longitude = 136.91,
    Duration? pollInterval,
    Duration? simulatedInterval,
  }) {
    switch (weatherType) {
      case WeatherProviderType.simulated:
        return SimulatedWeatherProvider(
          interval: simulatedInterval ?? const Duration(seconds: 5),
        );
      case WeatherProviderType.openMeteo:
        return OpenMeteoWeatherProvider(
          latitude: latitude,
          longitude: longitude,
          pollInterval: pollInterval ?? const Duration(minutes: 5),
        );
    }
  }

  /// Creates the configured [LocationProvider] instance.
  ///
  /// If [deadReckoningEnabled] is true (default), wraps the provider with
  /// [DeadReckoningProvider] for tunnel fallback.
  LocationProvider createLocationProvider({
    Duration? simulatedInterval,
    bool? includeTunnel,
  }) {
    final LocationProvider inner;

    switch (locationType) {
      case LocationProviderType.simulated:
        inner = SimulatedLocationProvider(
          interval: simulatedInterval ?? const Duration(seconds: 1),
          includeTunnel: includeTunnel ?? true,
        );
      case LocationProviderType.geoclue:
        inner = GeoClueLocationProvider();
    }

    if (deadReckoningEnabled) {
      return DeadReckoningProvider(inner: inner, mode: drMode);
    }
    return inner;
  }

  /// Whether this config uses simulated weather (no network required).
  bool get isSimulatedWeather =>
      weatherType == WeatherProviderType.simulated;

  /// Whether this config uses real weather data (requires network).
  bool get isRealWeather =>
      weatherType == WeatherProviderType.openMeteo;

  /// Whether this config uses simulated location (no GPS required).
  bool get isSimulatedLocation =>
      locationType == LocationProviderType.simulated;

  /// Whether this config uses real GPS (GeoClue2 D-Bus).
  bool get isRealLocation =>
      locationType == LocationProviderType.geoclue;

  /// Whether this config uses mock routing (no network required).
  bool get isMockRouting =>
      routingType == RoutingEngineType.mock;

  /// Whether this config uses OSRM routing (requires network).
  bool get isOsrmRouting =>
      routingType == RoutingEngineType.osrm;

  /// Whether this config uses Valhalla routing (requires network).
  bool get isValhallaRouting =>
      routingType == RoutingEngineType.valhalla;

  /// Whether this config uses Kalman filter for dead reckoning.
  bool get isKalmanDr =>
      deadReckoningEnabled && drMode == DeadReckoningMode.kalman;

  /// Whether this config uses linear extrapolation for dead reckoning.
  bool get isLinearDr =>
      deadReckoningEnabled && drMode == DeadReckoningMode.linear;

  /// Whether this config uses online OSM tiles (requires network).
  bool get isOnlineTiles =>
      tileSource == TileSourceType.online;

  /// Whether this config uses MBTiles offline tiles (no network required).
  bool get isMbtilesTiles =>
      tileSource == TileSourceType.mbtiles;

  /// Creates the configured [RoutingEngine] instance.
  ///
  /// For mock: returns `null` — caller must provide their own mock engine.
  /// For OSRM: creates [OsrmRoutingEngine] pointing at [osrmBaseUrl].
  ///
  /// Returns `null` for mock type so the caller can supply a pre-built
  /// demo route (as snow_scene.dart does). OSRM returns a real engine.
  RoutingEngine? createRoutingEngine({
    String osrmBaseUrl = 'https://router.project-osrm.org',
    String valhallaBaseUrl = 'https://valhalla1.openstreetmap.de',
    http.Client? httpClient,
  }) {
    switch (routingType) {
      case RoutingEngineType.mock:
        return null; // caller provides mock
      case RoutingEngineType.osrm:
        return OsrmRoutingEngine(
          baseUrl: osrmBaseUrl,
          client: httpClient,
        );
      case RoutingEngineType.valhalla:
        return ValhallaRoutingEngine(
          baseUrl: valhallaBaseUrl,
          client: httpClient,
        );
    }
  }

  static WeatherProviderType _parseWeatherType(String value) {
    switch (value.toLowerCase()) {
      case 'simulated':
      case 'sim':
        return WeatherProviderType.simulated;
      case 'open_meteo':
      case 'openmeteo':
      case 'real':
        return WeatherProviderType.openMeteo;
      default:
        return WeatherProviderType.openMeteo;
    }
  }

  static LocationProviderType _parseLocationType(String value) {
    switch (value.toLowerCase()) {
      case 'simulated':
      case 'sim':
        return LocationProviderType.simulated;
      case 'geoclue':
      case 'geoclue2':
      case 'real':
        return LocationProviderType.geoclue;
      default:
        return LocationProviderType.simulated;
    }
  }

  static DeadReckoningMode _parseDrMode(String value) {
    switch (value.toLowerCase()) {
      case 'linear':
        return DeadReckoningMode.linear;
      case 'kalman':
      case 'ekf':
        return DeadReckoningMode.kalman;
      default:
        return DeadReckoningMode.kalman;
    }
  }

  static TileSourceType _parseTileSource(String value) {
    switch (value.toLowerCase()) {
      case 'mbtiles':
      case 'offline':
        return TileSourceType.mbtiles;
      case 'online':
      case 'osm':
        return TileSourceType.online;
      default:
        return TileSourceType.online;
    }
  }

  static RoutingEngineType _parseRoutingType(String value) {
    switch (value.toLowerCase()) {
      case 'mock':
      case 'demo':
        return RoutingEngineType.mock;
      case 'osrm':
        return RoutingEngineType.osrm;
      case 'valhalla':
        return RoutingEngineType.valhalla;
      default:
        return RoutingEngineType.valhalla;
    }
  }
}
