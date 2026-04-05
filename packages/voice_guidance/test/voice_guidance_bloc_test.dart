import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

class _MockTtsEngine extends Mock implements TtsEngine {}

NavigationRoute _buildRoute() {
  return const NavigationRoute(
    shape: [LatLng(35.1709, 136.8815), LatLng(35.0504, 137.1566)],
    maneuvers: [
      NavigationManeuver(
        index: 0,
        instruction: 'Nagoya Station を出発します。',
        type: 'depart',
        lengthKm: 5.0,
        timeSeconds: 300,
        position: LatLng(35.1709, 136.8815),
      ),
      NavigationManeuver(
        index: 1,
        instruction: '右折です。',
        type: 'right',
        lengthKm: 2.0,
        timeSeconds: 120,
        position: LatLng(35.1200, 137.0100),
      ),
    ],
    totalDistanceKm: 7.0,
    totalTimeSeconds: 420,
    summary: '7km',
  );
}

Future<void> _drain() async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

void main() {
  late _MockTtsEngine ttsEngine;
  late StreamController<NavigationState> navController;

  setUp(() {
    ttsEngine = _MockTtsEngine();
    navController = StreamController<NavigationState>.broadcast();

    when(() => ttsEngine.setLanguage(any())).thenAnswer((_) async {});
    when(() => ttsEngine.setVolume(any())).thenAnswer((_) async {});
    when(() => ttsEngine.speak(any())).thenAnswer((_) async {});
    when(() => ttsEngine.stop()).thenAnswer((_) async {});
    when(() => ttsEngine.dispose()).thenAnswer((_) async {});
    when(() => ttsEngine.isAvailable()).thenAnswer((_) async => true);
  });

  tearDown(() async {
    await navController.close();
  });

  test('initializes TTS with config language and volume', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
      config: const VoiceGuidanceConfig(languageTag: 'ja-JP', volume: 0.8),
    );

    await _drain();

    verify(() => ttsEngine.setLanguage('ja-JP')).called(1);
    verify(() => ttsEngine.setVolume(0.8)).called(1);
    await bloc.close();
  });

  test('announces maneuver when index changes', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
    );
    final route = _buildRoute();

    navController.add(NavigationState(
      status: NavigationStatus.navigating,
      route: route,
      currentManeuverIndex: 0,
    ));
    await _drain();

    navController.add(NavigationState(
      status: NavigationStatus.navigating,
      route: route,
      currentManeuverIndex: 0,
    ));
    await _drain();

    navController.add(NavigationState(
      status: NavigationStatus.navigating,
      route: route,
      currentManeuverIndex: 1,
    ));
    await _drain();

    verify(() => ttsEngine.speak('Nagoya Station を出発します。')).called(1);
    verify(() => ttsEngine.speak('右折です。')).called(1);
    await bloc.close();
  });

  test('announces arrival transition', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
    );

    navController.add(const NavigationState(
      status: NavigationStatus.arrived,
      destinationLabel: 'Toyota HQ',
    ));
    await _drain();

    verify(() => ttsEngine.speak('Toyota HQ に到着しました。')).called(1);
    await bloc.close();
  });

  test('announces deviation as hazard and interrupts speech', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
    );

    navController.add(const NavigationState(status: NavigationStatus.deviated));
    await _drain();

    verifyInOrder([
      () => ttsEngine.stop(),
      () => ttsEngine.speak('ルートを外れました。再検索します。'),
    ]);
    await bloc.close();
  });

  test('announces safety alert changes', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
    );

    navController.add(const NavigationState(
      status: NavigationStatus.navigating,
      alertMessage: '圧雪路です。速度を落としてください。',
      alertSeverity: AlertSeverity.warning,
    ));
    await _drain();

    verifyInOrder([
      () => ttsEngine.stop(),
      () => ttsEngine.speak('注意。圧雪路です。速度を落としてください。'),
    ]);
    await bloc.close();
  });

  blocTest<VoiceGuidanceBloc, VoiceGuidanceState>(
    'enters muted state on VoiceDisabled and resumes on VoiceEnabled',
    build: () => VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
    ),
    act: (bloc) async {
      bloc
        ..add(const VoiceDisabled())
        ..add(const VoiceEnabled());
    },
    expect: () => [
      isA<VoiceGuidanceState>()
          .having((state) => state.status, 'status', VoiceGuidanceStatus.muted),
      isA<VoiceGuidanceState>()
          .having((state) => state.status, 'status', VoiceGuidanceStatus.idle),
    ],
  );
}
