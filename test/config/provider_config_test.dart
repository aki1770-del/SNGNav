import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/config/provider_config.dart';
import 'package:sngnav_snow_scene/providers/dead_reckoning_provider.dart';
import 'package:sngnav_snow_scene/providers/open_meteo_weather_provider.dart';
import 'package:sngnav_snow_scene/providers/osrm_routing_engine.dart';
import 'package:sngnav_snow_scene/providers/valhalla_routing_engine.dart';
import 'package:sngnav_snow_scene/providers/simulated_location_provider.dart';
import 'package:sngnav_snow_scene/providers/simulated_weather_provider.dart';

void main() {
  group('WeatherProviderType', () {
    test('has two values', () {
      expect(WeatherProviderType.values.length, 2);
    });

    test('includes simulated and openMeteo', () {
      expect(
        WeatherProviderType.values,
        containsAll([
          WeatherProviderType.simulated,
          WeatherProviderType.openMeteo,
        ]),
      );
    });
  });

  group('LocationProviderType', () {
    test('has two values', () {
      expect(LocationProviderType.values.length, 2);
    });

    test('includes simulated and geoclue', () {
      expect(
        LocationProviderType.values,
        containsAll([
          LocationProviderType.simulated,
          LocationProviderType.geoclue,
        ]),
      );
    });
  });

  group('ProviderConfig — weather defaults', () {
    test('defaults to openMeteo weather', () {
      const config = ProviderConfig();
      expect(config.weatherType, WeatherProviderType.openMeteo);
    });

    test('accepts explicit simulated weather', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.simulated,
      );
      expect(config.weatherType, WeatherProviderType.simulated);
    });

    test('accepts explicit openMeteo weather', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.openMeteo,
      );
      expect(config.weatherType, WeatherProviderType.openMeteo);
    });

    test('isSimulatedWeather returns true for simulated', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.simulated,
      );
      expect(config.isSimulatedWeather, isTrue);
      expect(config.isRealWeather, isFalse);
    });

    test('isRealWeather returns true for openMeteo', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.openMeteo,
      );
      expect(config.isRealWeather, isTrue);
      expect(config.isSimulatedWeather, isFalse);
    });
  });

  group('ProviderConfig — location defaults', () {
    test('defaults to simulated location', () {
      const config = ProviderConfig();
      expect(config.locationType, LocationProviderType.simulated);
    });

    test('defaults to dead reckoning enabled', () {
      const config = ProviderConfig();
      expect(config.deadReckoningEnabled, isTrue);
    });

    test('accepts explicit geoclue location', () {
      const config = ProviderConfig(
        locationType: LocationProviderType.geoclue,
      );
      expect(config.locationType, LocationProviderType.geoclue);
    });

    test('accepts dead reckoning disabled', () {
      const config = ProviderConfig(deadReckoningEnabled: false);
      expect(config.deadReckoningEnabled, isFalse);
    });

    test('isSimulatedLocation returns true for simulated', () {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
      );
      expect(config.isSimulatedLocation, isTrue);
      expect(config.isRealLocation, isFalse);
    });

    test('isRealLocation returns true for geoclue', () {
      const config = ProviderConfig(
        locationType: LocationProviderType.geoclue,
      );
      expect(config.isRealLocation, isTrue);
      expect(config.isSimulatedLocation, isFalse);
    });
  });

  group('ProviderConfig.fromEnvironment', () {
    // Note: --dart-define values are compile-time constants.
    // In tests without --dart-define, defaults apply.
    test('defaults to openMeteo weather when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.weatherType, WeatherProviderType.openMeteo);
    });

    test('defaults to simulated location when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.locationType, LocationProviderType.simulated);
    });

    test('defaults to dead reckoning enabled when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.deadReckoningEnabled, isTrue);
    });
  });

  group('createWeatherProvider', () {
    test('creates SimulatedWeatherProvider for simulated type', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.simulated,
      );
      final provider = config.createWeatherProvider();
      expect(provider, isA<SimulatedWeatherProvider>());
      provider.dispose();
    });

    test('creates OpenMeteoWeatherProvider for openMeteo type', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.openMeteo,
      );
      final provider = config.createWeatherProvider();
      expect(provider, isA<OpenMeteoWeatherProvider>());
      provider.dispose();
    });

    test('passes latitude and longitude to OpenMeteo', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.openMeteo,
      );
      final provider = config.createWeatherProvider(
        latitude: 34.0,
        longitude: 135.0,
      );
      expect(provider, isA<OpenMeteoWeatherProvider>());
      final openMeteo = provider as OpenMeteoWeatherProvider;
      expect(openMeteo.latitude, 34.0);
      expect(openMeteo.longitude, 135.0);
      provider.dispose();
    });

    test('uses default Nagoya coordinates for OpenMeteo', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.openMeteo,
      );
      final provider = config.createWeatherProvider();
      final openMeteo = provider as OpenMeteoWeatherProvider;
      expect(openMeteo.latitude, 35.18);
      expect(openMeteo.longitude, 136.91);
      provider.dispose();
    });

    test('passes custom poll interval to OpenMeteo', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.openMeteo,
      );
      final provider = config.createWeatherProvider(
        pollInterval: const Duration(minutes: 10),
      );
      final openMeteo = provider as OpenMeteoWeatherProvider;
      expect(openMeteo.pollInterval, const Duration(minutes: 10));
      provider.dispose();
    });

    test('passes custom interval to SimulatedWeatherProvider', () {
      const config = ProviderConfig(
        weatherType: WeatherProviderType.simulated,
      );
      final provider = config.createWeatherProvider(
        simulatedInterval: const Duration(seconds: 1),
      );
      expect(provider, isA<SimulatedWeatherProvider>());
      provider.dispose();
    });
  });

  group('createLocationProvider', () {
    test('creates SimulatedLocationProvider wrapped in DR by default', () async {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
      );
      final provider = config.createLocationProvider();
      expect(provider, isA<DeadReckoningProvider>());
      await provider.dispose();
    });

    test('creates raw SimulatedLocationProvider when DR disabled', () async {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        deadReckoningEnabled: false,
      );
      final provider = config.createLocationProvider();
      expect(provider, isA<SimulatedLocationProvider>());
      await provider.dispose();
    });

    test('passes custom interval to SimulatedLocationProvider', () async {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        deadReckoningEnabled: false,
      );
      final provider = config.createLocationProvider(
        simulatedInterval: const Duration(milliseconds: 500),
      );
      expect(provider, isA<SimulatedLocationProvider>());
      await provider.dispose();
    });

    test('passes includeTunnel to SimulatedLocationProvider', () async {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        deadReckoningEnabled: false,
      );
      final provider = config.createLocationProvider(includeTunnel: false);
      expect(provider, isA<SimulatedLocationProvider>());
      await provider.dispose();
    });
  });

  group('RoutingEngineType', () {
    test('has three values', () {
      expect(RoutingEngineType.values.length, 3);
    });

    test('includes mock, osrm, and valhalla', () {
      expect(
        RoutingEngineType.values,
        containsAll([
          RoutingEngineType.mock,
          RoutingEngineType.osrm,
          RoutingEngineType.valhalla,
        ]),
      );
    });
  });

  group('ProviderConfig — routing defaults', () {
    test('defaults to valhalla routing', () {
      const config = ProviderConfig();
      expect(config.routingType, RoutingEngineType.valhalla);
    });

    test('accepts explicit osrm routing', () {
      const config = ProviderConfig(
        routingType: RoutingEngineType.osrm,
      );
      expect(config.routingType, RoutingEngineType.osrm);
    });

    test('isMockRouting returns true for mock', () {
      const config = ProviderConfig(
        routingType: RoutingEngineType.mock,
      );
      expect(config.isMockRouting, isTrue);
      expect(config.isOsrmRouting, isFalse);
    });

    test('isOsrmRouting returns true for osrm', () {
      const config = ProviderConfig(
        routingType: RoutingEngineType.osrm,
      );
      expect(config.isOsrmRouting, isTrue);
      expect(config.isMockRouting, isFalse);
      expect(config.isValhallaRouting, isFalse);
    });

    test('accepts explicit valhalla routing', () {
      const config = ProviderConfig(
        routingType: RoutingEngineType.valhalla,
      );
      expect(config.routingType, RoutingEngineType.valhalla);
    });

    test('isValhallaRouting returns true for valhalla', () {
      const config = ProviderConfig(
        routingType: RoutingEngineType.valhalla,
      );
      expect(config.isValhallaRouting, isTrue);
      expect(config.isMockRouting, isFalse);
      expect(config.isOsrmRouting, isFalse);
    });
  });

  group('ProviderConfig.fromEnvironment — routing', () {
    test('defaults to valhalla routing when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.routingType, RoutingEngineType.valhalla);
    });
  });

  group('createRoutingEngine', () {
    test('returns null for mock type (caller provides mock)', () {
      const config = ProviderConfig(
        routingType: RoutingEngineType.mock,
      );
      final engine = config.createRoutingEngine();
      expect(engine, isNull);
    });

    test('creates OsrmRoutingEngine for osrm type', () async {
      const config = ProviderConfig(
        routingType: RoutingEngineType.osrm,
      );
      final engine = config.createRoutingEngine();
      expect(engine, isA<OsrmRoutingEngine>());
      await engine!.dispose();
    });

    test('passes custom base URL to OsrmRoutingEngine', () async {
      const config = ProviderConfig(
        routingType: RoutingEngineType.osrm,
      );
      final engine = config.createRoutingEngine(
        osrmBaseUrl: 'http://localhost:5000',
      );
      expect(engine, isA<OsrmRoutingEngine>());
      final osrm = engine! as OsrmRoutingEngine;
      expect(osrm.baseUrl, 'http://localhost:5000');
      await engine.dispose();
    });

    test('uses public demo URL by default for osrm', () async {
      const config = ProviderConfig(
        routingType: RoutingEngineType.osrm,
      );
      final engine = config.createRoutingEngine();
      final osrm = engine! as OsrmRoutingEngine;
      expect(osrm.baseUrl, 'https://router.project-osrm.org');
      await engine.dispose();
    });

    test('creates ValhallaRoutingEngine for valhalla type', () async {
      const config = ProviderConfig(
        routingType: RoutingEngineType.valhalla,
      );
      final engine = config.createRoutingEngine();
      expect(engine, isA<ValhallaRoutingEngine>());
      await engine!.dispose();
    });

    test('uses public OSM Valhalla URL by default', () async {
      const config = ProviderConfig(
        routingType: RoutingEngineType.valhalla,
      );
      final engine = config.createRoutingEngine();
      final valhalla = engine! as ValhallaRoutingEngine;
      expect(valhalla.baseUrl, 'https://valhalla1.openstreetmap.de');
      await engine.dispose();
    });

    test('passes custom base URL to ValhallaRoutingEngine', () async {
      const config = ProviderConfig(
        routingType: RoutingEngineType.valhalla,
      );
      final engine = config.createRoutingEngine(
        valhallaBaseUrl: 'http://localhost:8002',
      );
      final valhalla = engine! as ValhallaRoutingEngine;
      expect(valhalla.baseUrl, 'http://localhost:8002');
      await engine.dispose();
    });
  });

  // =========================================================================
  // DR mode — Sprint 10 Day 2
  // =========================================================================

  group('ProviderConfig — DR mode defaults', () {
    test('defaults to Kalman DR mode', () {
      const config = ProviderConfig();
      expect(config.drMode, DeadReckoningMode.kalman);
    });

    test('accepts explicit linear mode', () {
      const config = ProviderConfig(
        drMode: DeadReckoningMode.linear,
      );
      expect(config.drMode, DeadReckoningMode.linear);
    });

    test('isKalmanDr returns true for kalman + DR enabled', () {
      const config = ProviderConfig(
        drMode: DeadReckoningMode.kalman,
      );
      expect(config.isKalmanDr, isTrue);
      expect(config.isLinearDr, isFalse);
    });

    test('isLinearDr returns true for linear + DR enabled', () {
      const config = ProviderConfig(
        drMode: DeadReckoningMode.linear,
      );
      expect(config.isLinearDr, isTrue);
      expect(config.isKalmanDr, isFalse);
    });

    test('isKalmanDr returns false when DR disabled', () {
      const config = ProviderConfig(
        drMode: DeadReckoningMode.kalman,
        deadReckoningEnabled: false,
      );
      expect(config.isKalmanDr, isFalse);
    });
  });

  group('ProviderConfig — DR mode createLocationProvider', () {
    test('creates Kalman DR provider by default', () async {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
      );
      final provider = config.createLocationProvider();
      expect(provider, isA<DeadReckoningProvider>());
      final dr = provider as DeadReckoningProvider;
      expect(dr.mode, DeadReckoningMode.kalman);
      await provider.dispose();
    });

    test('creates linear DR provider when mode is linear', () async {
      const config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        drMode: DeadReckoningMode.linear,
      );
      final provider = config.createLocationProvider();
      expect(provider, isA<DeadReckoningProvider>());
      final dr = provider as DeadReckoningProvider;
      expect(dr.mode, DeadReckoningMode.linear);
      await provider.dispose();
    });
  });

  group('ProviderConfig.fromEnvironment — DR mode', () {
    test('defaults to kalman DR mode when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.drMode, DeadReckoningMode.kalman);
    });
  });

  // =========================================================================
  // Tile source — Sprint 10 Day 7
  // =========================================================================

  group('TileSourceType', () {
    test('has two values', () {
      expect(TileSourceType.values.length, 2);
    });

    test('includes online and mbtiles', () {
      expect(
        TileSourceType.values,
        containsAll([
          TileSourceType.online,
          TileSourceType.mbtiles,
        ]),
      );
    });
  });

  group('ProviderConfig — tile source defaults', () {
    test('defaults to online tiles', () {
      const config = ProviderConfig();
      expect(config.tileSource, TileSourceType.online);
    });

    test('defaults to standard MBTiles path', () {
      const config = ProviderConfig();
      expect(config.mbtilesPath, 'data/offline_tiles.mbtiles');
    });

    test('accepts explicit mbtiles source', () {
      const config = ProviderConfig(
        tileSource: TileSourceType.mbtiles,
      );
      expect(config.tileSource, TileSourceType.mbtiles);
    });

    test('accepts custom MBTiles path', () {
      const config = ProviderConfig(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '/tmp/custom.mbtiles',
      );
      expect(config.mbtilesPath, '/tmp/custom.mbtiles');
    });

    test('isOnlineTiles returns true for online', () {
      const config = ProviderConfig(
        tileSource: TileSourceType.online,
      );
      expect(config.isOnlineTiles, isTrue);
      expect(config.isMbtilesTiles, isFalse);
    });

    test('isMbtilesTiles returns true for mbtiles', () {
      const config = ProviderConfig(
        tileSource: TileSourceType.mbtiles,
      );
      expect(config.isMbtilesTiles, isTrue);
      expect(config.isOnlineTiles, isFalse);
    });
  });

  group('ProviderConfig.fromEnvironment — tile source', () {
    test('defaults to online tiles when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.tileSource, TileSourceType.online);
    });

    test('defaults to standard MBTiles path when no dart-define is set', () {
      final config = ProviderConfig.fromEnvironment();
      expect(config.mbtilesPath, 'data/offline_tiles.mbtiles');
    });
  });
}
