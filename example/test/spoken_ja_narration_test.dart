/// End-to-end proof: the driver's Japanese narration reaches the TTS engine — the full
/// chain, end to end, with no seam narrated over:
///
///   OSRM HTTP bytes (mock server, ja-JP default request)
///     → routing_engine 0.5.0 localized `RouteManeuver.instruction`
///     → NavigationManeuver (the app's adapter boundary, duplicated verbatim)
///     → ManeuverSpeechFormatter (passes a non-empty instruction VERBATIM)
///     → VoiceGuidanceBloc(ManeuverAnnounced)
///     → TtsEngine.speak(text)   ← captured here and asserted Japanese.
///
/// The audible half (does the speaker produce sound the driver hears?) is honestly
/// out of scope for CI: this proves the exact utterance handed to the
/// platform TTS is the Japanese instruction, byte for byte.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:voice_guidance/voice_guidance.dart';

/// Captures every utterance the bloc hands to the platform TTS.
class _CapturingTtsEngine implements TtsEngine {
  final utterances = <String>[];
  String? languageTag;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> setLanguage(String tag) async => languageTag = tag;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async => utterances.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test('the Japanese instruction from OSRM is the exact utterance handed '
      'to the TTS engine (spoken-ja proof)', () async {
    // 1. Real OSRM engine against a mock server — DEFAULT request (ja-JP).
    final engine = OsrmRoutingEngine(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'geometry': '_p~iF~ps|U',
                'distance': 900.0,
                'duration': 120.0,
                'legs': [
                  {
                    'steps': [
                      {
                        'name': '山道',
                        'distance': 900.0,
                        'duration': 120.0,
                        'maneuver': {
                          'type': 'turn',
                          'modifier': 'sharp right',
                          'location': [140.12, 39.70],
                        },
                      },
                    ],
                  },
                ],
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await engine.calculateRoute(const RouteRequest(
      origin: LatLng(39.71, 140.10),
      destination: LatLng(39.65, 140.18),
    ));
    await engine.dispose();
    expect(result.maneuvers.single.instruction, '山道方面へ鋭角に右折');

    // 2. Across the app's adapter boundary (RouteManeuver → NavigationManeuver).
    final m = result.maneuvers.single;
    final navManeuver = NavigationManeuver(
      index: m.index,
      instruction: m.instruction,
      type: m.type,
      lengthKm: m.lengthKm,
      timeSeconds: m.timeSeconds,
      // routing_engine 0.6.0: nullable. This fixture's maneuver carries a real
      // position; a positionless one could not enter NavigationManeuver at all
      // (and must never be given a substitute coordinate).
      position: m.position!,
    );

    // 3. The formatter passes a non-empty instruction VERBATIM.
    const formatter = ManeuverSpeechFormatter();
    final spokenText =
        formatter.formatManeuver(navManeuver, languageTag: 'ja-JP');
    expect(spokenText, '山道方面へ鋭角に右折');

    // 4. Through the REAL VoiceGuidanceBloc to the (captured) TTS engine.
    final tts = _CapturingTtsEngine();
    final navStream = StreamController<NavigationState>.broadcast();
    final bloc = VoiceGuidanceBloc(
      ttsEngine: tts,
      navigationStateStream: navStream.stream,
    );
    bloc.add(const VoiceEnabled());
    await Future<void>.delayed(Duration.zero);
    bloc.add(ManeuverAnnounced(text: spokenText));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(tts.utterances, ['山道方面へ鋭角に右折'],
        reason: 'the exact Japanese instruction must be what the platform '
            'TTS is asked to speak — nothing translated, dropped, or mangled '
            'between the routing engine and the voice');

    await bloc.close();
    await navStream.close();
  });
}
