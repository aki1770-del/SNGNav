/// FluoriteView widget tests.
///
/// Tests:
///   1. Shows initializing indicator on startup
///   2. Shows unavailable fallback with NotImplementedHostApi (Phase A)
///   3. Shows custom placeholder when provided and unavailable
///   4. Shows 3D active indicator when mock host returns ready
///   5. Calls onStatusChanged callback through lifecycle
///   6. State exposes status and error message
///   7. onSceneReady callback updates state
///   8. onFrameStats callback updates scene info
///   9. dispose calls disposeScene on host API
///
/// Sprint 7 Day 10 — FluoriteView scaffold.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/fluorite/fluorite_api.dart';
import 'package:sngnav_snow_scene/fluorite/fluorite_view.dart';

// ---------------------------------------------------------------------------
// Mock host API — succeeds
// ---------------------------------------------------------------------------

class MockSuccessHostApi implements FluoriteHostApi {
  bool disposeCalled = false;

  @override
  Future<SceneInfo> initializeScene(SceneConfig config) async {
    return const SceneInfo(isReady: true, entityCount: 0);
  }

  @override
  Future<void> disposeScene() async {
    disposeCalled = true;
  }

  @override
  Future<int> createEntity({
    required String type,
    required LatLng position,
    Map<String, dynamic>? properties,
  }) async =>
      1;

  @override
  Future<void> destroyEntity(int entityId) async {}

  @override
  Future<void> updateEntityPosition({
    required int entityId,
    required LatLng position,
    double? heading,
  }) async {}

  @override
  Future<void> setCameraMode(FluoriteCameraMode mode) async {}

  @override
  Future<void> setRouteGeometry({
    required List<LatLng> points,
    RouteStyle style = const RouteStyle(),
  }) async {}

  @override
  Future<void> clearRoute() async {}

  @override
  Future<SceneInfo> getSceneInfo() async =>
      const SceneInfo(isReady: true, entityCount: 5, frameTimeMs: 16.0);
}

// ---------------------------------------------------------------------------
// Mock host API — fails with generic error
// ---------------------------------------------------------------------------

class MockFailHostApi implements FluoriteHostApi {
  @override
  Future<SceneInfo> initializeScene(SceneConfig config) async {
    throw Exception('GPU not available');
  }

  @override
  Future<void> disposeScene() async {}

  @override
  Future<int> createEntity({
    required String type,
    required LatLng position,
    Map<String, dynamic>? properties,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> destroyEntity(int entityId) async {}

  @override
  Future<void> updateEntityPosition({
    required int entityId,
    required LatLng position,
    double? heading,
  }) async {}

  @override
  Future<void> setCameraMode(FluoriteCameraMode mode) async {}

  @override
  Future<void> setRouteGeometry({
    required List<LatLng> points,
    RouteStyle style = const RouteStyle(),
  }) async {}

  @override
  Future<void> clearRoute() async {}

  @override
  Future<SceneInfo> getSceneInfo() async => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Slow host API — hangs to test initializing state
// ---------------------------------------------------------------------------

class MockSlowHostApi implements FluoriteHostApi {
  final Completer<SceneInfo> completer = Completer();

  @override
  Future<SceneInfo> initializeScene(SceneConfig config) => completer.future;

  @override
  Future<void> disposeScene() async {}

  @override
  Future<int> createEntity({
    required String type,
    required LatLng position,
    Map<String, dynamic>? properties,
  }) async =>
      1;

  @override
  Future<void> destroyEntity(int entityId) async {}

  @override
  Future<void> updateEntityPosition({
    required int entityId,
    required LatLng position,
    double? heading,
  }) async {}

  @override
  Future<void> setCameraMode(FluoriteCameraMode mode) async {}

  @override
  Future<void> setRouteGeometry({
    required List<LatLng> points,
    RouteStyle style = const RouteStyle(),
  }) async {}

  @override
  Future<void> clearRoute() async {}

  @override
  Future<SceneInfo> getSceneInfo() async => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildView({
  FluoriteHostApi? hostApi,
  ValueChanged<FluoriteViewStatus>? onStatusChanged,
  Widget? placeholder,
  GlobalKey<FluoriteViewState>? key,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FluoriteView(
        key: key,
        hostApi: hostApi,
        onStatusChanged: onStatusChanged,
        placeholder: placeholder,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FluoriteView', () {
    testWidgets('shows initializing indicator on startup', (tester) async {
      final api = MockSlowHostApi();

      await tester.pumpWidget(_buildView(hostApi: api));
      // First pump: initState triggers _initializeScene, sets initializing
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Initializing 3D scene...'), findsOneWidget);

      // Clean up
      api.completer.complete(const SceneInfo(isReady: true));
      await tester.pumpAndSettle();
    });

    testWidgets('shows unavailable fallback with NotImplementedHostApi',
        (tester) async {
      await tester.pumpWidget(_buildView());
      await tester.pumpAndSettle();

      expect(find.text('3D Renderer Unavailable'), findsOneWidget);
      expect(find.text('Using 2D map fallback'), findsOneWidget);
      expect(find.byIcon(Icons.terrain), findsOneWidget);
    });

    testWidgets('shows custom placeholder when provided and unavailable',
        (tester) async {
      await tester.pumpWidget(_buildView(
        placeholder: const Text('Custom Fallback'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Custom Fallback'), findsOneWidget);
      expect(find.text('3D Renderer Unavailable'), findsNothing);
    });

    testWidgets('shows 3D active indicator when mock host returns ready',
        (tester) async {
      final api = MockSuccessHostApi();

      await tester.pumpWidget(_buildView(hostApi: api));
      await tester.pumpAndSettle();

      expect(find.text('Fluorite 3D Scene Active'), findsOneWidget);
      expect(find.byIcon(Icons.view_in_ar), findsOneWidget);
    });

    testWidgets('calls onStatusChanged callback through lifecycle',
        (tester) async {
      final statuses = <FluoriteViewStatus>[];

      await tester.pumpWidget(_buildView(
        onStatusChanged: statuses.add,
      ));
      await tester.pumpAndSettle();

      // Phase A: initializing → unavailable
      expect(statuses, contains(FluoriteViewStatus.initializing));
      expect(statuses, contains(FluoriteViewStatus.unavailable));
    });

    testWidgets('state exposes status and error message', (tester) async {
      final key = GlobalKey<FluoriteViewState>();

      await tester.pumpWidget(_buildView(key: key));
      await tester.pumpAndSettle();

      expect(key.currentState!.status, FluoriteViewStatus.unavailable);
      expect(key.currentState!.errorMessage, isNotNull);
      expect(key.currentState!.errorMessage, contains('native renderer not available'));
    });

    testWidgets('shows error message for generic failures', (tester) async {
      final api = MockFailHostApi();

      await tester.pumpWidget(_buildView(hostApi: api));
      await tester.pumpAndSettle();

      expect(find.text('3D Renderer Unavailable'), findsOneWidget);
      // Error message contains the exception text
      expect(find.textContaining('GPU not available'), findsOneWidget);
    });

    testWidgets('onSceneReady callback updates state', (tester) async {
      final key = GlobalKey<FluoriteViewState>();
      final api = MockSlowHostApi();

      await tester.pumpWidget(_buildView(key: key, hostApi: api));
      await tester.pump();

      expect(key.currentState!.status, FluoriteViewStatus.initializing);

      // Simulate native callback
      key.currentState!.onSceneReady(const SceneInfo(
        isReady: true,
        entityCount: 10,
        frameTimeMs: 8.3,
      ));
      await tester.pump();

      expect(key.currentState!.status, FluoriteViewStatus.ready);
      expect(key.currentState!.sceneInfo?.entityCount, 10);

      // Clean up
      api.completer.complete(const SceneInfo(isReady: true));
      await tester.pumpAndSettle();
    });

    testWidgets('onFrameStats callback updates scene info', (tester) async {
      final key = GlobalKey<FluoriteViewState>();
      final api = MockSuccessHostApi();

      await tester.pumpWidget(_buildView(key: key, hostApi: api));
      await tester.pumpAndSettle();

      // Scene is ready, now simulate frame stats
      key.currentState!.onFrameStats(
        frameTimeMs: 12.5,
        gpuMemoryMb: 64.0,
        entityCount: 7,
      );
      await tester.pump();

      expect(key.currentState!.sceneInfo?.frameTimeMs, 12.5);
      expect(key.currentState!.sceneInfo?.gpuMemoryMb, 64.0);
      expect(key.currentState!.sceneInfo?.entityCount, 7);
    });

    testWidgets('dispose calls disposeScene on host API', (tester) async {
      final api = MockSuccessHostApi();

      await tester.pumpWidget(_buildView(hostApi: api));
      await tester.pumpAndSettle();

      // Dispose by removing from tree
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      expect(api.disposeCalled, true);
    });
  });
}
