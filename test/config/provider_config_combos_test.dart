import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/config/provider_config.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/providers/open_meteo_weather_provider.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:sngnav_snow_scene/providers/simulated_location_provider.dart';
import 'package:sngnav_snow_scene/providers/simulated_weather_provider.dart';

/// FDD-8 — Config combination tests.
///
/// Verifies that all documented --dart-define flag combinations produce
/// the expected provider types without runtime errors.
void main() {
  // =========================================================================
  // Combo 1: Default config (all defaults)
  //   WEATHER_PROVIDER=open_meteo, LOCATION_PROVIDER=simulated,
  //   DEAD_RECKONING=true, DR_MODE=kalman, ROUTING_ENGINE=mock,
  //   TILE_SOURCE=online
  // =========================================================================
  group('Combo: defaults (no flags)', () {
    const config = ProviderConfig();

    test('weather = openMeteo', () {
      expect(config.isRealWeather, isTrue);
    });

    test('location = simulated + Kalman DR', () {
      expect(config.isSimulatedLocation, isTrue);
      expect(config.isKalmanDr, isTrue);
    });

    test('routing = valhalla', () {
      expect(config.isValhallaRouting, isTrue);
    });

    test('tiles = online', () {
      expect(config.isOnlineTiles, isTrue);
    });

    test('creates all providers without error', () async {
      final weather = config.createWeatherProvider();
      final location = config.createLocationProvider();
      final routing = config.createRoutingEngine();

      expect(weather, isA<OpenMeteoWeatherProvider>());
      expect(location, isA<DeadReckoningProvider>());
      expect(routing, isNotNull); // valhalla returns real engine

      weather.dispose();
      await location.dispose();
      await routing!.dispose();
    });
  });

  // =========================================================================
  // Combo 2: Full demo (run_demo.sh)
  //   WEATHER_PROVIDER=simulated, LOCATION_PROVIDER=simulated,
  //   ROUTING_ENGINE=mock, DEAD_RECKONING=true, DR_MODE=kalman
  // =========================================================================
  group('Combo: full demo (simulated everything + Kalman)', () {
    const config = ProviderConfig(
      weatherType: WeatherProviderType.simulated,
      locationType: LocationProviderType.simulated,
      routingType: RoutingEngineType.mock,
      deadReckoningEnabled: true,
      drMode: DeadReckoningMode.kalman,
      tileSource: TileSourceType.online,
    );

    test('all getters consistent', () {
      expect(config.isSimulatedWeather, isTrue);
      expect(config.isSimulatedLocation, isTrue);
      expect(config.isKalmanDr, isTrue);
      expect(config.isMockRouting, isTrue);
      expect(config.isOnlineTiles, isTrue);
    });

    test('creates all providers without error', () async {
      final weather = config.createWeatherProvider();
      final location = config.createLocationProvider();
      final routing = config.createRoutingEngine();

      expect(weather, isA<SimulatedWeatherProvider>());
      expect(location, isA<DeadReckoningProvider>());
      final dr = location as DeadReckoningProvider;
      expect(dr.mode, DeadReckoningMode.kalman);
      expect(routing, isNull);

      weather.dispose();
      await location.dispose();
    });
  });

  // =========================================================================
  // Combo 3: Offline mode (run_offline.sh)
  //   TILE_SOURCE=mbtiles, WEATHER_PROVIDER=simulated
  // =========================================================================
  group('Combo: offline (mbtiles + simulated weather)', () {
    const config = ProviderConfig(
      weatherType: WeatherProviderType.simulated,
      tileSource: TileSourceType.mbtiles,
      mbtilesPath: 'data/offline_tiles.mbtiles',
    );

    test('tiles = mbtiles with correct path', () {
      expect(config.isMbtilesTiles, isTrue);
      expect(config.mbtilesPath, 'data/offline_tiles.mbtiles');
    });

    test('weather = simulated (no network)', () {
      expect(config.isSimulatedWeather, isTrue);
    });

    test('location still has DR enabled', () {
      expect(config.deadReckoningEnabled, isTrue);
      expect(config.isKalmanDr, isTrue);
    });
  });

  // =========================================================================
  // Combo 4: Real weather + simulated location (run_real_weather.sh)
  //   WEATHER_PROVIDER=open_meteo, LOCATION_PROVIDER=simulated
  // =========================================================================
  group('Combo: real weather + simulated location', () {
    const config = ProviderConfig(
      weatherType: WeatherProviderType.openMeteo,
      locationType: LocationProviderType.simulated,
    );

    test('weather = real, location = simulated', () {
      expect(config.isRealWeather, isTrue);
      expect(config.isSimulatedLocation, isTrue);
    });

    test('creates both providers without error', () async {
      final weather = config.createWeatherProvider();
      final location = config.createLocationProvider();

      expect(weather, isA<OpenMeteoWeatherProvider>());
      expect(location, isA<DeadReckoningProvider>());

      weather.dispose();
      await location.dispose();
    });
  });

  // =========================================================================
  // Combo 5: OSRM routing + Kalman DR
  //   ROUTING_ENGINE=osrm, DR_MODE=kalman
  // =========================================================================
  group('Combo: OSRM routing + Kalman DR', () {
    const config = ProviderConfig(
      routingType: RoutingEngineType.osrm,
      drMode: DeadReckoningMode.kalman,
    );

    test('routing = osrm, DR = kalman', () {
      expect(config.isOsrmRouting, isTrue);
      expect(config.isKalmanDr, isTrue);
    });

    test('creates OSRM engine with default URL', () async {
      final engine = config.createRoutingEngine();
      expect(engine, isA<OsrmRoutingEngine>());
      final osrm = engine! as OsrmRoutingEngine;
      expect(osrm.baseUrl, 'https://router.project-osrm.org');
      await engine.dispose();
    });
  });

  // =========================================================================
  // Combo 6: Valhalla routing + linear DR
  //   ROUTING_ENGINE=valhalla, DR_MODE=linear
  // =========================================================================
  group('Combo: Valhalla routing + linear DR', () {
    const config = ProviderConfig(
      routingType: RoutingEngineType.valhalla,
      drMode: DeadReckoningMode.linear,
    );

    test('routing = valhalla, DR = linear', () {
      expect(config.isValhallaRouting, isTrue);
      expect(config.isLinearDr, isTrue);
    });

    test('creates Valhalla engine and linear DR provider', () async {
      final engine = config.createRoutingEngine();
      final location = config.createLocationProvider();

      expect(engine, isA<ValhallaRoutingEngine>());
      expect(location, isA<DeadReckoningProvider>());
      final dr = location as DeadReckoningProvider;
      expect(dr.mode, DeadReckoningMode.linear);

      await engine!.dispose();
      await location.dispose();
    });
  });

  // =========================================================================
  // Combo 7: No DR (DEAD_RECKONING=false)
  //   DEAD_RECKONING=false, LOCATION_PROVIDER=simulated
  // =========================================================================
  group('Combo: DR disabled', () {
    const config = ProviderConfig(
      deadReckoningEnabled: false,
      locationType: LocationProviderType.simulated,
    );

    test('DR disabled flags', () {
      expect(config.deadReckoningEnabled, isFalse);
      expect(config.isKalmanDr, isFalse);
      expect(config.isLinearDr, isFalse);
    });

    test('creates raw SimulatedLocationProvider', () async {
      final location = config.createLocationProvider();
      expect(location, isA<SimulatedLocationProvider>());
      await location.dispose();
    });
  });

  // =========================================================================
  // Combo 8: Full production (all real providers)
  //   WEATHER_PROVIDER=open_meteo, LOCATION_PROVIDER=geoclue,
  //   ROUTING_ENGINE=osrm, DR_MODE=kalman, TILE_SOURCE=mbtiles
  // =========================================================================
  group('Combo: full production (all real)', () {
    const config = ProviderConfig(
      weatherType: WeatherProviderType.openMeteo,
      locationType: LocationProviderType.geoclue,
      routingType: RoutingEngineType.osrm,
      deadReckoningEnabled: true,
      drMode: DeadReckoningMode.kalman,
      tileSource: TileSourceType.mbtiles,
      mbtilesPath: '/opt/sngnav/tiles/chubu.mbtiles',
    );

    test('all production flags set', () {
      expect(config.isRealWeather, isTrue);
      expect(config.isRealLocation, isTrue);
      expect(config.isOsrmRouting, isTrue);
      expect(config.isKalmanDr, isTrue);
      expect(config.isMbtilesTiles, isTrue);
      expect(config.mbtilesPath, '/opt/sngnav/tiles/chubu.mbtiles');
    });
  });

  // =========================================================================
  // Combo 9: Custom MBTiles path with online weather
  //   TILE_SOURCE=mbtiles, MBTILES_PATH=/custom/path.mbtiles,
  //   WEATHER_PROVIDER=open_meteo
  // =========================================================================
  group('Combo: custom MBTiles path + real weather', () {
    const config = ProviderConfig(
      tileSource: TileSourceType.mbtiles,
      mbtilesPath: '/tmp/test_tiles.mbtiles',
      weatherType: WeatherProviderType.openMeteo,
    );

    test('custom path preserved with real weather', () {
      expect(config.isMbtilesTiles, isTrue);
      expect(config.mbtilesPath, '/tmp/test_tiles.mbtiles');
      expect(config.isRealWeather, isTrue);
    });
  });

  // =========================================================================
  // Combo 10: Mutual exclusion checks
  // =========================================================================
  group('Mutual exclusion invariants', () {
    test('weather: exactly one of simulated/real', () {
      for (final wt in WeatherProviderType.values) {
        final config = ProviderConfig(weatherType: wt);
        expect(
          config.isSimulatedWeather != config.isRealWeather,
          isTrue,
          reason: 'Weather must be exactly one of simulated/real',
        );
      }
    });

    test('location: exactly one of simulated/real', () {
      for (final lt in LocationProviderType.values) {
        final config = ProviderConfig(locationType: lt);
        expect(
          config.isSimulatedLocation != config.isRealLocation,
          isTrue,
          reason: 'Location must be exactly one of simulated/real',
        );
      }
    });

    test('routing: exactly one of mock/osrm/valhalla', () {
      for (final rt in RoutingEngineType.values) {
        final config = ProviderConfig(routingType: rt);
        final count = [
          config.isMockRouting,
          config.isOsrmRouting,
          config.isValhallaRouting,
        ].where((b) => b).length;
        expect(count, 1, reason: 'Routing must be exactly one type');
      }
    });

    test('tiles: exactly one of online/mbtiles', () {
      for (final ts in TileSourceType.values) {
        final config = ProviderConfig(tileSource: ts);
        expect(
          config.isOnlineTiles != config.isMbtilesTiles,
          isTrue,
          reason: 'Tiles must be exactly one of online/mbtiles',
        );
      }
    });
  });
}
