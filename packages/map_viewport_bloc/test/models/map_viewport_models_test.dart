library;

import 'package:flutter_test/flutter_test.dart';
import 'package:map_viewport_bloc/map_viewport_bloc_core.dart';

void main() {
  group('CameraMode', () {
    test('has follow, freeLook, overview', () {
      expect(CameraMode.values, [
        CameraMode.follow,
        CameraMode.freeLook,
        CameraMode.overview,
      ]);
    });

    test('names remain stable for serialization', () {
      expect(CameraMode.follow.name, 'follow');
      expect(CameraMode.freeLook.name, 'freeLook');
      expect(CameraMode.overview.name, 'overview');
    });
  });

  group('MapLayerType', () {
    test('has six layers in canonical order', () {
      expect(MapLayerType.values, [
        MapLayerType.baseTile,
        MapLayerType.route,
        MapLayerType.fleet,
        MapLayerType.hazard,
        MapLayerType.weather,
        MapLayerType.safety,
      ]);
    });

    test('baseTile is not user-toggleable', () {
      expect(MapLayerType.baseTile.isUserToggleable, isFalse);
    });

    test('route is user-toggleable', () {
      expect(MapLayerType.route.isUserToggleable, isTrue);
    });

    test('fleet is user-toggleable', () {
      expect(MapLayerType.fleet.isUserToggleable, isTrue);
    });

    test('hazard is user-toggleable', () {
      expect(MapLayerType.hazard.isUserToggleable, isTrue);
    });

    test('weather is user-toggleable', () {
      expect(MapLayerType.weather.isUserToggleable, isTrue);
    });

    test('safety is not user-toggleable', () {
      expect(MapLayerType.safety.isUserToggleable, isFalse);
    });
  });

  group('MapLayerZ', () {
    test('constants expose Z0 through Z5', () {
      expect(MapLayerZ.z0, 0);
      expect(MapLayerZ.z1, 1);
      expect(MapLayerZ.z2, 2);
      expect(MapLayerZ.z3, 3);
      expect(MapLayerZ.z4, 4);
      expect(MapLayerZ.z5, 5);
    });

    test('layer ordering is strictly increasing', () {
      expect(MapLayerZ.baseTile, lessThan(MapLayerZ.route));
      expect(MapLayerZ.route, lessThan(MapLayerZ.fleet));
      expect(MapLayerZ.fleet, lessThan(MapLayerZ.hazard));
      expect(MapLayerZ.hazard, lessThan(MapLayerZ.weather));
      expect(MapLayerZ.weather, lessThan(MapLayerZ.safety));
    });

    test('zIndex maps baseTile to z0', () {
      expect(MapLayerType.baseTile.zIndex, MapLayerZ.z0);
    });

    test('zIndex maps route to z1', () {
      expect(MapLayerType.route.zIndex, MapLayerZ.z1);
    });

    test('zIndex maps fleet to z2', () {
      expect(MapLayerType.fleet.zIndex, MapLayerZ.z2);
    });

    test('zIndex maps hazard to z3', () {
      expect(MapLayerType.hazard.zIndex, MapLayerZ.z3);
    });

    test('zIndex maps weather to z4', () {
      expect(MapLayerType.weather.zIndex, MapLayerZ.z4);
    });

    test('zIndex maps safety to z5', () {
      expect(MapLayerType.safety.zIndex, MapLayerZ.z5);
    });
  });
}