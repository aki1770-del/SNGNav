library;

import 'package:flutter_test/flutter_test.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart' as map_full;
import 'package:map_viewport_bloc/map_viewport_bloc_core.dart' as map_core;
import 'package:navigation_safety/navigation_safety.dart' as nav_full;
import 'package:navigation_safety/navigation_safety_core.dart' as nav_core;
import 'package:offline_tiles/offline_tiles.dart' as tiles_full;
import 'package:offline_tiles/offline_tiles_core.dart' as tiles_core;
import 'package:routing_bloc/routing_bloc.dart' as routing_full;
import 'package:routing_bloc/routing_bloc_core.dart' as routing_core;

void main() {
  group('S52 _core contract validation', () {
    test('navigation_safety_core symbols stay mirrored by the parent package barrel', () {
      final nav_core.NavigationSafetyConfig configFromFull =
          const nav_full.NavigationSafetyConfig();
      final nav_full.NavigationSafetyConfig configFromCore =
          const nav_core.NavigationSafetyConfig(
        safeScoreFloor: 0.9,
        infoScoreFloor: 0.6,
        warningScoreFloor: 0.4,
      );
      final nav_core.SafetyScore scoreFromFull = nav_full.SafetyScore(
        overall: 0.35,
        gripScore: 0.5,
        visibilityScore: 0.4,
        fleetConfidenceScore: 0.6,
      );
      final nav_full.SafetyScore scoreFromCore = nav_core.SafetyScore(
        overall: 0.25,
        gripScore: 0.3,
        visibilityScore: 0.2,
        fleetConfidenceScore: 0.4,
      );

      expect(configFromFull.safeScoreFloor, 0.8);
      expect(configFromCore.warningScoreFloor, 0.4);
      expect(nav_full.AlertSeverity.warning, same(nav_core.AlertSeverity.warning));
      expect(
        scoreFromFull.toAlertSeverity(configFromFull),
        nav_core.AlertSeverity.warning,
      );
      expect(
        scoreFromCore.toAlertSeverity(configFromCore),
        nav_full.AlertSeverity.critical,
      );
    });

    test('routing_bloc_core symbols stay mirrored by the parent package barrel', () {
      final routing_core.RoutingState idleFromFull =
          const routing_full.RoutingState.idle(engineAvailable: true);
      final routing_full.RoutingState idleFromCore =
          const routing_core.RoutingState.idle();
      final copied = idleFromFull.copyWith(
        status: routing_core.RoutingStatus.loading,
        destinationLabel: 'Nagoya Station',
      );

      expect(idleFromFull.engineAvailable, isTrue);
      expect(idleFromCore.status, routing_full.RoutingStatus.idle);
      expect(copied.isLoading, isTrue);
      expect(copied.destinationLabel, 'Nagoya Station');
      expect(
        routing_full.RouteProgressStatus.arrived,
        same(routing_core.RouteProgressStatus.arrived),
      );
    });

    test('map_viewport_bloc_core symbols stay mirrored by the parent package barrel', () {
      final map_core.CameraMode modeFromFull = map_full.CameraMode.follow;
      final map_full.MapLayerType layerFromCore = map_core.MapLayerType.weather;

      expect(modeFromFull, map_core.CameraMode.follow);
      expect(layerFromCore.zIndex, map_full.MapLayerZ.weather);
      expect(map_full.MapLayerZ.of(layerFromCore), map_core.MapLayerZ.weather);
      expect(map_full.MapLayerType.safety.isUserToggleable, isFalse);
      expect(map_core.MapLayerType.route.isUserToggleable, isTrue);
    });

    test('offline_tiles_core symbols stay mirrored by the parent package barrel', () {
      final tiles_core.CoverageTier tierFromFull = tiles_full.CoverageTier.t1Corridor;
      final tiles_full.TileCacheConfig configFromCore =
          const tiles_core.TileCacheConfig();
      final tiles_core.TileSourceType sourceFromFull = tiles_full.TileSourceType.mbtiles;

      expect(tierFromFull.autoCache, isTrue);
      expect(configFromCore.minZoomFor(tiles_full.CoverageTier.t2Metro), 9);
      expect(configFromCore.maxZoomFor(tiles_core.CoverageTier.t4National), 10);
      expect(sourceFromFull, tiles_core.TileSourceType.mbtiles);
      expect(
        configFromCore.expiryFor(tiles_core.CoverageTier.t1Corridor),
        const Duration(days: 30),
      );
    });
  });
}