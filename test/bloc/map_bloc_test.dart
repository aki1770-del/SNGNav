/// MapBloc unit tests — declarative viewport + camera mode + layers.
///
/// Tests the pure state machine — no MapController, no Flutter widgets.
///
/// Sprint 7 Day 4 — MapBloc extraction.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/bloc/bloc.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);
// Route bounding box (SW corner, NE corner)
const _routeSw = LatLng(35.0504, 136.8815);
const _routeNe = LatLng(35.1709, 137.1566);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('MapState model', () {
    test('loading state has Nagoya center and default zoom', () {
      const state = MapState.loading();
      expect(state.status, equals(MapStatus.loading));
      expect(state.center, equals(_nagoya));
      expect(state.zoom, equals(12.0));
      expect(state.cameraMode, equals(CameraMode.freeLook));
      expect(state.isFollowing, isFalse);
      expect(state.isReady, isFalse);
      expect(state.hasFitBounds, isFalse);
    });

    test('isFollowing true in follow mode', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.follow,
      );
      expect(state.isFollowing, isTrue);
    });

    test('isReady true when ready', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
      );
      expect(state.isReady, isTrue);
    });

    test('hasFitBounds true when both corners set', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      );
      expect(state.hasFitBounds, isTrue);
    });

    test('hasFitBounds false when only one corner set', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        fitBoundsSw: _routeSw,
      );
      expect(state.hasFitBounds, isFalse);
    });

    test('isLayerVisible checks set membership', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        visibleLayers: {MapLayerType.route, MapLayerType.weather},
      );
      expect(state.isLayerVisible(MapLayerType.route), isTrue);
      expect(state.isLayerVisible(MapLayerType.weather), isTrue);
      expect(state.isLayerVisible(MapLayerType.safety), isFalse);
      expect(state.isLayerVisible(MapLayerType.fleet), isFalse);
    });

    test('default visibleLayers is {route}', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
      );
      expect(state.visibleLayers, equals({MapLayerType.route}));
    });

    test('copyWith preserves fields', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.follow,
        visibleLayers: {MapLayerType.route, MapLayerType.weather},
      );
      final updated = state.copyWith(zoom: 16.0);
      expect(updated.center, equals(_nagoya));
      expect(updated.zoom, equals(16.0));
      expect(updated.cameraMode, equals(CameraMode.follow));
      expect(updated.visibleLayers,
          equals({MapLayerType.route, MapLayerType.weather}));
    });

    test('copyWith clearFitBounds removes bounds', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      );
      final cleared = state.copyWith(clearFitBounds: true);
      expect(cleared.hasFitBounds, isFalse);
      expect(cleared.fitBoundsSw, isNull);
      expect(cleared.fitBoundsNe, isNull);
    });

    test('equality works (Equatable)', () {
      const a = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        cameraMode: CameraMode.follow,
      );
      const b = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        cameraMode: CameraMode.follow,
      );
      expect(a, equals(b));
    });

    test('toString includes status, mode, zoom, layers', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.follow,
      );
      final s = state.toString();
      expect(s, contains('ready'));
      expect(s, contains('follow'));
      expect(s, contains('14.0'));
    });
  });

  group('CameraMode enum', () {
    test('has three modes', () {
      expect(CameraMode.values.length, equals(3));
      expect(CameraMode.values,
          containsAll([CameraMode.follow, CameraMode.freeLook,
                       CameraMode.overview]));
    });
  });

  group('MapLayerType enum', () {
    test('has four layer types', () {
      expect(MapLayerType.values.length, equals(4));
      expect(MapLayerType.values,
          containsAll([MapLayerType.route, MapLayerType.weather,
                       MapLayerType.safety, MapLayerType.fleet]));
    });
  });

  group('MapEvent', () {
    test('events are equatable', () {
      expect(
        const MapInitialized(center: _nagoya, zoom: 12.0),
        equals(const MapInitialized(center: _nagoya, zoom: 12.0)),
      );
      expect(
        const CameraModeChanged(CameraMode.follow),
        equals(const CameraModeChanged(CameraMode.follow)),
      );
      expect(
        const CenterChanged(_toyota),
        equals(const CenterChanged(_toyota)),
      );
      expect(
        const ZoomChanged(15.0),
        equals(const ZoomChanged(15.0)),
      );
      expect(
        const FitToBounds(southWest: _routeSw, northEast: _routeNe),
        equals(const FitToBounds(southWest: _routeSw, northEast: _routeNe)),
      );
      expect(
        const LayerToggled(layer: MapLayerType.weather, visible: true),
        equals(const LayerToggled(layer: MapLayerType.weather, visible: true)),
      );
      expect(
        const UserPanDetected(),
        equals(const UserPanDetected()),
      );
    });
  });

  group('MapBloc — initial state', () {
    test('initial state is loading', () {
      final bloc = MapBloc();
      expect(bloc.state, equals(const MapState.loading()));
      expect(bloc.state.status, equals(MapStatus.loading));
      bloc.close();
    });
  });

  group('MapBloc — initialization', () {
    blocTest<MapBloc, MapState>(
      'loading → ready on MapInitialized',
      build: MapBloc.new,
      act: (bloc) => bloc.add(const MapInitialized(
        center: _nagoya,
        zoom: 14.0,
      )),
      expect: () => [
        isA<MapState>()
            .having((s) => s.status, 'status', MapStatus.ready)
            .having((s) => s.center, 'center', _nagoya)
            .having((s) => s.zoom, 'zoom', 14.0),
      ],
    );
  });

  group('MapBloc — camera mode', () {
    blocTest<MapBloc, MapState>(
      'freeLook → follow on CameraModeChanged',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
      ),
      act: (bloc) =>
          bloc.add(const CameraModeChanged(CameraMode.follow)),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.follow),
      ],
    );

    blocTest<MapBloc, MapState>(
      'follow → freeLook on UserPanDetected',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.freeLook),
      ],
    );

    blocTest<MapBloc, MapState>(
      'overview → freeLook on UserPanDetected (clears fitBounds)',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        cameraMode: CameraMode.overview,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.freeLook)
            .having((s) => s.hasFitBounds, 'bounds', isFalse),
      ],
    );

    blocTest<MapBloc, MapState>(
      'UserPanDetected ignored when already freeLook',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.freeLook,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      expect: () => <MapState>[],
    );
  });

  group('MapBloc — center and zoom', () {
    blocTest<MapBloc, MapState>(
      'CenterChanged updates center',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
      ),
      act: (bloc) => bloc.add(const CenterChanged(_toyota)),
      expect: () => [
        isA<MapState>()
            .having((s) => s.center, 'center', _toyota),
      ],
    );

    blocTest<MapBloc, MapState>(
      'ZoomChanged updates zoom',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
      ),
      act: (bloc) => bloc.add(const ZoomChanged(16.0)),
      expect: () => [
        isA<MapState>()
            .having((s) => s.zoom, 'zoom', 16.0),
      ],
    );
  });

  group('MapBloc — fit to bounds', () {
    blocTest<MapBloc, MapState>(
      'FitToBounds sets overview mode and stores bounds',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const FitToBounds(
        southWest: _routeSw,
        northEast: _routeNe,
      )),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.overview)
            .having((s) => s.fitBoundsSw, 'sw', _routeSw)
            .having((s) => s.fitBoundsNe, 'ne', _routeNe)
            .having((s) => s.hasFitBounds, 'hasBounds', isTrue),
      ],
    );

    blocTest<MapBloc, MapState>(
      'CameraModeChanged to follow clears fitBounds',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        cameraMode: CameraMode.overview,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      ),
      act: (bloc) =>
          bloc.add(const CameraModeChanged(CameraMode.follow)),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.follow)
            .having((s) => s.hasFitBounds, 'bounds', isFalse),
      ],
    );
  });

  group('MapBloc — layer visibility', () {
    blocTest<MapBloc, MapState>(
      'toggle weather layer on',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        visibleLayers: {MapLayerType.route},
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.weather,
        visible: true,
      )),
      expect: () => [
        isA<MapState>().having(
          (s) => s.visibleLayers,
          'layers',
          {MapLayerType.route, MapLayerType.weather},
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'toggle route layer off',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        visibleLayers: {MapLayerType.route, MapLayerType.weather},
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.route,
        visible: false,
      )),
      expect: () => [
        isA<MapState>().having(
          (s) => s.visibleLayers,
          'layers',
          {MapLayerType.weather},
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'toggle all four layers on',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        visibleLayers: {},
      ),
      act: (bloc) {
        bloc.add(const LayerToggled(
            layer: MapLayerType.route, visible: true));
        bloc.add(const LayerToggled(
            layer: MapLayerType.weather, visible: true));
        bloc.add(const LayerToggled(
            layer: MapLayerType.safety, visible: true));
        bloc.add(const LayerToggled(
            layer: MapLayerType.fleet, visible: true));
      },
      expect: () => [
        isA<MapState>().having((s) => s.visibleLayers, 'layers',
            {MapLayerType.route}),
        isA<MapState>().having((s) => s.visibleLayers, 'layers',
            {MapLayerType.route, MapLayerType.weather}),
        isA<MapState>().having((s) => s.visibleLayers, 'layers',
            {MapLayerType.route, MapLayerType.weather, MapLayerType.safety}),
        isA<MapState>().having((s) => s.visibleLayers, 'layers',
            {MapLayerType.route, MapLayerType.weather, MapLayerType.safety,
             MapLayerType.fleet}),
      ],
    );

    blocTest<MapBloc, MapState>(
      'toggling same layer on twice is idempotent (no emission)',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 12.0,
        visibleLayers: {MapLayerType.route},
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.route,
        visible: true,
      )),
      // Set {route} + route = {route} — Equatable sees no change, no emit.
      expect: () => <MapState>[],
    );
  });

  group('MapBloc — combined workflow', () {
    blocTest<MapBloc, MapState>(
      'init → follow → pan → freeLook (real user scenario)',
      build: MapBloc.new,
      act: (bloc) {
        bloc.add(const MapInitialized(center: _nagoya, zoom: 14.0));
        bloc.add(const CameraModeChanged(CameraMode.follow));
        bloc.add(const CenterChanged(_toyota)); // follow update
        bloc.add(const UserPanDetected()); // user drags
      },
      expect: () => [
        // initialized
        isA<MapState>()
            .having((s) => s.status, 'status', MapStatus.ready)
            .having((s) => s.zoom, 'zoom', 14.0),
        // follow mode
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.follow),
        // center updated (still follow)
        isA<MapState>()
            .having((s) => s.center, 'center', _toyota),
        // user pan → freeLook
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.freeLook),
      ],
    );

    blocTest<MapBloc, MapState>(
      'route received → overview → user pan → freeLook',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) {
        bloc.add(const FitToBounds(
          southWest: _routeSw,
          northEast: _routeNe,
        ));
        bloc.add(const UserPanDetected());
      },
      expect: () => [
        // overview with bounds
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.overview)
            .having((s) => s.hasFitBounds, 'bounds', isTrue),
        // user pan clears bounds
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.freeLook)
            .having((s) => s.hasFitBounds, 'bounds', isFalse),
      ],
    );
  });
}
