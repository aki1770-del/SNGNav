/// Edge-case tests for MapBloc — double events, state accessors,
/// layer toggle restrictions, and copyWith edge cases.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);

void main() {
  group('MapBloc — layer toggle restrictions', () {
    blocTest<MapBloc, MapState>(
      'toggling baseTile (non-toggleable) is silently ignored',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
      ),
      act: (bloc) => bloc.add(
        const LayerToggled(layer: MapLayerType.baseTile, visible: false),
      ),
      expect: () => [],
    );

    blocTest<MapBloc, MapState>(
      'toggling safety (non-toggleable) is silently ignored',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
      ),
      act: (bloc) => bloc.add(
        const LayerToggled(layer: MapLayerType.safety, visible: false),
      ),
      expect: () => [],
    );

    blocTest<MapBloc, MapState>(
      'toggling already-visible layer on is a no-op',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        visibleLayers: const {
          MapLayerType.baseTile,
          MapLayerType.route,
          MapLayerType.fleet,
        },
      ),
      act: (bloc) => bloc.add(
        const LayerToggled(layer: MapLayerType.route, visible: true),
      ),
      expect: () => [],
    );

    blocTest<MapBloc, MapState>(
      'toggling already-hidden layer off is a no-op',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        visibleLayers: const {MapLayerType.baseTile},
      ),
      act: (bloc) => bloc.add(
        const LayerToggled(layer: MapLayerType.weather, visible: false),
      ),
      expect: () => [],
    );

    blocTest<MapBloc, MapState>(
      'toggling a visible toggleable layer off emits new state',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        visibleLayers: const {
          MapLayerType.baseTile,
          MapLayerType.route,
          MapLayerType.hazard,
        },
      ),
      act: (bloc) => bloc.add(
        const LayerToggled(layer: MapLayerType.hazard, visible: false),
      ),
      expect: () => [
        isA<MapState>().having(
          (s) => s.visibleLayers.contains(MapLayerType.hazard),
          'hazard visible',
          isFalse,
        ),
      ],
    );
  });

  group('MapBloc — camera mode transitions', () {
    blocTest<MapBloc, MapState>(
      'switching to overview preserves existing fit bounds',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const CameraModeChanged(CameraMode.overview)),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.overview),
      ],
    );

    blocTest<MapBloc, MapState>(
      'switching from overview to follow clears fit bounds',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.overview,
        fitBoundsSw: _nagoya,
        fitBoundsNe: _toyota,
      ),
      act: (bloc) => bloc.add(const CameraModeChanged(CameraMode.follow)),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.follow)
            .having((s) => s.hasFitBounds, 'hasFitBounds', isFalse),
      ],
    );

    blocTest<MapBloc, MapState>(
      'double UserPanDetected in freeLook only emits once',
      build: () => MapBloc(freeLookTimeout: const Duration(seconds: 30)),
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.freeLook,
      ),
      act: (bloc) {
        bloc.add(const UserPanDetected());
        bloc.add(const UserPanDetected());
      },
      expect: () => [],
    );

    blocTest<MapBloc, MapState>(
      'FreeLookTimeoutElapsed ignored when not in freeLook',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const FreeLookTimeoutElapsed()),
      expect: () => [],
    );
  });

  group('MapBloc — FitToBounds', () {
    blocTest<MapBloc, MapState>(
      'FitToBounds sets overview mode and bounds',
      build: MapBloc.new,
      seed: () => MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.follow,
      ),
      act: (bloc) => bloc.add(const FitToBounds(
        southWest: _nagoya,
        northEast: _toyota,
      )),
      expect: () => [
        isA<MapState>()
            .having((s) => s.cameraMode, 'mode', CameraMode.overview)
            .having((s) => s.fitBoundsSw, 'sw', _nagoya)
            .having((s) => s.fitBoundsNe, 'ne', _toyota),
      ],
    );
  });

  group('MapState — accessors', () {
    test('isReady false for loading', () {
      final state = MapState.loading();
      expect(state.isReady, isFalse);
    });

    test('isReady true for ready', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
      );
      expect(state.isReady, isTrue);
    });

    test('isFollowing true in follow mode', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.follow,
      );
      expect(state.isFollowing, isTrue);
    });

    test('isFollowing false in freeLook', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        cameraMode: CameraMode.freeLook,
      );
      expect(state.isFollowing, isFalse);
    });

    test('hasFitBounds true when both bounds present', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        fitBoundsSw: _nagoya,
        fitBoundsNe: _toyota,
      );
      expect(state.hasFitBounds, isTrue);
    });

    test('hasFitBounds false when only one bound', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        fitBoundsSw: _nagoya,
      );
      expect(state.hasFitBounds, isFalse);
    });

    test('isLayerVisible checks layer presence', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        visibleLayers: {MapLayerType.baseTile, MapLayerType.route},
      );
      expect(state.isLayerVisible(MapLayerType.route), isTrue);
      expect(state.isLayerVisible(MapLayerType.weather), isFalse);
    });

    test('toString includes mode and layers', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        visibleLayers: {MapLayerType.baseTile},
      );
      final str = state.toString();
      expect(str, contains('ready'));
      expect(str, contains('follow'));
      expect(str, contains('baseTile'));
    });
  });

  group('MapState — copyWith', () {
    test('clearFitBounds nullifies both bounds', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 15.0,
        fitBoundsSw: _nagoya,
        fitBoundsNe: _toyota,
      );
      final cleared = state.copyWith(clearFitBounds: true);
      expect(cleared.fitBoundsSw, isNull);
      expect(cleared.fitBoundsNe, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      const state = MapState(
        status: MapStatus.ready,
        center: _nagoya,
        zoom: 14.0,
        visibleLayers: {MapLayerType.baseTile, MapLayerType.route},
        errorMessage: 'test error',
      );
      final updated = state.copyWith(zoom: 16.0);
      expect(updated.center, _nagoya);
      expect(updated.zoom, 16.0);
      expect(updated.visibleLayers, state.visibleLayers);
      expect(updated.errorMessage, 'test error');
    });
  });
}
