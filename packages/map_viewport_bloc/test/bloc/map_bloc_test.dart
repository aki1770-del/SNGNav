library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0831, 137.1559);
const _routeSw = LatLng(35.0400, 136.8700);
const _routeNe = LatLng(35.1800, 137.4200);

void main() {
  group('MapState', () {
    test('loading defaults to follow mode', () {
      final state = MapState.loading();

      expect(state.status, MapStatus.loading);
      expect(state.cameraMode, CameraMode.follow);
      expect(state.center, kDefaultMapCenter);
      expect(state.zoom, kDefaultFollowZoom);
    });

    test('loading defaults to all layers visible', () {
      final state = MapState.loading();

      expect(state.visibleLayers, kDefaultVisibleLayers);
    });

    test('isReady true when status is ready', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      );

      expect(state.isReady, isTrue);
    });

    test('hasFitBounds true when both corners are set', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      );

      expect(state.hasFitBounds, isTrue);
    });

    test('copyWith clears fit bounds when requested', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.overview,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      );

      final updated = state.copyWith(clearFitBounds: true);
      expect(updated.hasFitBounds, isFalse);
    });
  });

  group('MapEvent equality', () {
    test('events remain equatable', () {
      expect(
        const MapInitialized(center: _nagoya, zoom: 15),
        const MapInitialized(center: _nagoya, zoom: 15),
      );
      expect(
        const CameraModeChanged(CameraMode.follow),
        const CameraModeChanged(CameraMode.follow),
      );
      expect(const CenterChanged(_toyota), const CenterChanged(_toyota));
      expect(const ZoomChanged(14), const ZoomChanged(14));
      expect(
        const FitToBounds(southWest: _routeSw, northEast: _routeNe),
        const FitToBounds(southWest: _routeSw, northEast: _routeNe),
      );
      expect(
        const LayerToggled(layer: MapLayerType.weather, visible: true),
        const LayerToggled(layer: MapLayerType.weather, visible: true),
      );
      expect(const UserPanDetected(), const UserPanDetected());
    });
  });

  group('MapBloc', () {
    test('initial state is loading with all layers on', () {
      final bloc = MapBloc();

      expect(bloc.state, MapState.loading());
      expect(bloc.state.visibleLayers, kDefaultVisibleLayers);

      bloc.close();
    });

    blocTest<MapBloc, MapState>(
      'MapInitialized moves loading to ready',
      build: MapBloc.new,
      act: (bloc) => bloc.add(const MapInitialized(center: _nagoya, zoom: 14)),
      expect: () => [
        isA<MapState>()
            .having((state) => state.status, 'status', MapStatus.ready)
            .having((state) => state.center, 'center', _nagoya)
            .having((state) => state.zoom, 'zoom', 14.0),
      ],
    );

    blocTest<MapBloc, MapState>(
      'CameraModeChanged follows route to overview',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const CameraModeChanged(CameraMode.overview)),
      expect: () => [
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.overview,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'FitToBounds stores bounds and enters overview',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const FitToBounds(
        southWest: _routeSw,
        northEast: _routeNe,
      )),
      expect: () => [
        isA<MapState>()
            .having((state) => state.cameraMode, 'cameraMode', CameraMode.overview)
            .having((state) => state.fitBoundsSw, 'fitBoundsSw', _routeSw)
            .having((state) => state.fitBoundsNe, 'fitBoundsNe', _routeNe),
      ],
    );

    blocTest<MapBloc, MapState>(
      'CameraModeChanged to follow clears fit bounds',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.overview,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      ),
      act: (bloc) => bloc.add(const CameraModeChanged(CameraMode.follow)),
      expect: () => [
        isA<MapState>()
            .having((state) => state.cameraMode, 'cameraMode', CameraMode.follow)
            .having((state) => state.hasFitBounds, 'hasFitBounds', isFalse),
      ],
    );

    blocTest<MapBloc, MapState>(
      'CenterChanged updates center',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const CenterChanged(_toyota)),
      expect: () => [
        isA<MapState>().having((state) => state.center, 'center', _toyota),
      ],
    );

    blocTest<MapBloc, MapState>(
      'ZoomChanged updates zoom',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const ZoomChanged(12.5)),
      expect: () => [
        isA<MapState>().having((state) => state.zoom, 'zoom', 12.5),
      ],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled hides route layer',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.route,
        visible: false,
      )),
      expect: () => [
        isA<MapState>().having(
          (state) => state.isLayerVisible(MapLayerType.route),
          'routeVisible',
          false,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled hides fleet layer',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.fleet,
        visible: false,
      )),
      expect: () => [
        isA<MapState>().having(
          (state) => state.isLayerVisible(MapLayerType.fleet),
          'fleetVisible',
          false,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled hides hazard layer',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.hazard,
        visible: false,
      )),
      expect: () => [
        isA<MapState>().having(
          (state) => state.isLayerVisible(MapLayerType.hazard),
          'hazardVisible',
          false,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled hides weather layer',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.weather,
        visible: false,
      )),
      expect: () => [
        isA<MapState>().having(
          (state) => state.isLayerVisible(MapLayerType.weather),
          'weatherVisible',
          false,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled ignores safety layer changes',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.safety,
        visible: false,
      )),
      expect: () => <MapState>[],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled ignores base tile changes',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.baseTile,
        visible: false,
      )),
      expect: () => <MapState>[],
    );

    blocTest<MapBloc, MapState>(
      'LayerToggled is idempotent when route already visible',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
      ),
      act: (bloc) => bloc.add(const LayerToggled(
        layer: MapLayerType.route,
        visible: true,
      )),
      expect: () => <MapState>[],
    );

    blocTest<MapBloc, MapState>(
      'UserPanDetected moves follow to freeLook',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      expect: () => [
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.freeLook,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'UserPanDetected from overview clears fit bounds and enters freeLook',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.overview,
        fitBoundsSw: _routeSw,
        fitBoundsNe: _routeNe,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      expect: () => [
        isA<MapState>()
            .having((state) => state.cameraMode, 'cameraMode', CameraMode.freeLook)
            .having((state) => state.hasFitBounds, 'hasFitBounds', isFalse),
      ],
    );

    blocTest<MapBloc, MapState>(
      'repeated UserPanDetected while freeLook does not emit duplicate state',
      build: () => MapBloc(freeLookTimeout: const Duration(milliseconds: 30)),
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.freeLook,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      expect: () => <MapState>[],
    );

    blocTest<MapBloc, MapState>(
      'auto-return timer moves freeLook back to follow',
      build: () => MapBloc(freeLookTimeout: const Duration(milliseconds: 20)),
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const UserPanDetected()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.freeLook,
        ),
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.follow,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'second pan resets the freeLook timer',
      build: () => MapBloc(freeLookTimeout: const Duration(milliseconds: 20)),
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) async {
        bloc.add(const UserPanDetected());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const UserPanDetected());
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.freeLook,
        ),
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.follow,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'route fit to overview then user pan then timeout returns to follow without fit bounds',
      build: () => MapBloc(freeLookTimeout: const Duration(milliseconds: 20)),
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) async {
        bloc.add(const FitToBounds(
          southWest: _routeSw,
          northEast: _routeNe,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const UserPanDetected());
      },
      wait: const Duration(milliseconds: 60),
      expect: () => [
        isA<MapState>()
            .having((state) => state.cameraMode, 'cameraMode', CameraMode.overview)
            .having((state) => state.hasFitBounds, 'hasFitBounds', isTrue),
        isA<MapState>()
            .having((state) => state.cameraMode, 'cameraMode', CameraMode.freeLook)
            .having((state) => state.hasFitBounds, 'hasFitBounds', isFalse),
        isA<MapState>()
            .having((state) => state.cameraMode, 'cameraMode', CameraMode.follow)
            .having((state) => state.hasFitBounds, 'hasFitBounds', isFalse),
      ],
    );

    blocTest<MapBloc, MapState>(
      'manual follow override cancels pending freeLook timeout',
      build: () => MapBloc(freeLookTimeout: const Duration(milliseconds: 20)),
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.freeLook,
      ),
      act: (bloc) => bloc.add(const CameraModeChanged(CameraMode.follow)),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.follow,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'safety consumer can force follow from freeLook',
      build: MapBloc.new,
      seed: () => const MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15,
        cameraMode: CameraMode.freeLook,
      ),
      act: (bloc) => bloc.add(const CameraModeChanged(CameraMode.follow)),
      expect: () => [
        isA<MapState>().having(
          (state) => state.cameraMode,
          'cameraMode',
          CameraMode.follow,
        ),
      ],
    );

    blocTest<MapBloc, MapState>(
      'custom constructor values become loading defaults',
      build: () => MapBloc(
        initialCenter: _toyota,
        initialZoom: 13,
        initialVisibleLayers: const {
          MapLayerType.baseTile,
          MapLayerType.route,
        },
      ),
      verify: (bloc) {
        expect(bloc.state.center, _toyota);
        expect(bloc.state.zoom, 13.0);
        expect(bloc.state.visibleLayers, const {
          MapLayerType.baseTile,
          MapLayerType.route,
        });
      },
    );
  });
}