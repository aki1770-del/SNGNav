/// Fluorite API stubs unit tests.
///
/// Tests:
///   1. SceneConfig: default values
///   2. SceneConfig: custom values
///   3. SceneInfo: default values
///   4. SceneInfo: custom values
///   5. RouteStyle: default values
///   6. RouteStyle: custom values with dash pattern
///   7. FluoriteCameraMode: all enum values exist
///   8. NotImplementedHostApi: initializeScene throws UnimplementedError
///   9. NotImplementedHostApi: disposeScene throws UnimplementedError
///  10. NotImplementedHostApi: createEntity throws UnimplementedError
///  11. NotImplementedHostApi: destroyEntity throws UnimplementedError
///  12. NotImplementedHostApi: updateEntityPosition throws UnimplementedError
///  13. NotImplementedHostApi: setCameraMode throws UnimplementedError
///  14. NotImplementedHostApi: setRouteGeometry throws UnimplementedError
///  15. NotImplementedHostApi: clearRoute throws UnimplementedError
///  16. NotImplementedHostApi: getSceneInfo throws UnimplementedError
///  17. NotImplementedHostApi: error message references Phase A and A63
///
/// Sprint 7 Day 10 — FluoriteView scaffold.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/fluorite/fluorite_api.dart';

void main() {
  group('SceneConfig', () {
    test('default values', () {
      const config = SceneConfig(demAssetPath: 'assets/dem/test.tif');

      expect(config.demAssetPath, 'assets/dem/test.tif');
      expect(config.initialCenter.latitude, 35.1709);
      expect(config.initialCenter.longitude, 136.8815);
      expect(config.initialZoom, 10.0);
      expect(config.enablePbr, true);
      expect(config.maxTextureResolution, 2048);
    });

    test('custom values', () {
      final config = SceneConfig(
        demAssetPath: 'assets/dem/custom.tif',
        initialCenter: const LatLng(35.05, 137.30),
        initialZoom: 14.0,
        enablePbr: false,
        maxTextureResolution: 1024,
      );

      expect(config.demAssetPath, 'assets/dem/custom.tif');
      expect(config.initialCenter.latitude, 35.05);
      expect(config.initialCenter.longitude, 137.30);
      expect(config.initialZoom, 14.0);
      expect(config.enablePbr, false);
      expect(config.maxTextureResolution, 1024);
    });
  });

  group('SceneInfo', () {
    test('default values', () {
      const info = SceneInfo(isReady: false);

      expect(info.isReady, false);
      expect(info.entityCount, 0);
      expect(info.frameTimeMs, 0.0);
      expect(info.gpuMemoryMb, 0.0);
    });

    test('custom values', () {
      const info = SceneInfo(
        isReady: true,
        entityCount: 42,
        frameTimeMs: 16.6,
        gpuMemoryMb: 128.5,
      );

      expect(info.isReady, true);
      expect(info.entityCount, 42);
      expect(info.frameTimeMs, 16.6);
      expect(info.gpuMemoryMb, 128.5);
    });
  });

  group('RouteStyle', () {
    test('default values', () {
      const style = RouteStyle();

      expect(style.colorHex, 0xFF2196F3);
      expect(style.widthMeters, 8.0);
      expect(style.elevationOffsetMeters, 1.0);
      expect(style.dashPattern, isNull);
    });

    test('custom values with dash pattern', () {
      const style = RouteStyle(
        colorHex: 0xFFFF0000,
        widthMeters: 12.0,
        elevationOffsetMeters: 2.5,
        dashPattern: [10.0, 5.0],
      );

      expect(style.colorHex, 0xFFFF0000);
      expect(style.widthMeters, 12.0);
      expect(style.elevationOffsetMeters, 2.5);
      expect(style.dashPattern, [10.0, 5.0]);
    });
  });

  group('FluoriteCameraMode', () {
    test('all enum values exist', () {
      expect(FluoriteCameraMode.values, hasLength(3));
      expect(FluoriteCameraMode.values, contains(FluoriteCameraMode.freeOrbit));
      expect(
          FluoriteCameraMode.values, contains(FluoriteCameraMode.followVehicle));
      expect(FluoriteCameraMode.values, contains(FluoriteCameraMode.birdsEye));
    });
  });

  group('NotImplementedHostApi', () {
    const api = NotImplementedHostApi();
    const config = SceneConfig(demAssetPath: 'test.tif');

    test('initializeScene rejects with UnimplementedError', () {
      expectLater(
        api.initializeScene(config),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('disposeScene rejects with UnimplementedError', () {
      expectLater(
        api.disposeScene(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('createEntity rejects with UnimplementedError', () {
      expectLater(
        api.createEntity(
          type: 'vehicle',
          position: const LatLng(35.0, 137.0),
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('destroyEntity rejects with UnimplementedError', () {
      expectLater(
        api.destroyEntity(1),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('updateEntityPosition rejects with UnimplementedError', () {
      expectLater(
        api.updateEntityPosition(
          entityId: 1,
          position: const LatLng(35.0, 137.0),
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('setCameraMode rejects with UnimplementedError', () {
      expectLater(
        api.setCameraMode(FluoriteCameraMode.freeOrbit),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('setRouteGeometry rejects with UnimplementedError', () {
      expectLater(
        api.setRouteGeometry(points: [const LatLng(35.0, 137.0)]),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('clearRoute rejects with UnimplementedError', () {
      expectLater(
        api.clearRoute(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getSceneInfo rejects with UnimplementedError', () {
      expectLater(
        api.getSceneInfo(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('error message references native renderer unavailability', () async {
      try {
        await api.initializeScene(config);
      } on UnimplementedError catch (e) {
        expect(e.message, contains('native renderer not available'));
        expect(e.message, contains('CONTRIBUTING.md'));
        return;
      }
      fail('Expected UnimplementedError');
    });
  });
}
