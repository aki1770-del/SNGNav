import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  const formatter = ManeuverSpeechFormatter();

  group('ManeuverSpeechFormatter', () {
    test('returns existing instruction when present', () {
      const maneuver = NavigationManeuver(
        index: 0,
        instruction: '200m ahead, turn right',
        type: 'right',
        lengthKm: 0.2,
        timeSeconds: 30,
        position: LatLng(35.0, 136.0),
      );

      final text = formatter.formatManeuver(
        maneuver,
        languageTag: 'ja-JP',
      );

      expect(text, '200m ahead, turn right');
    });

    test('falls back to japanese type phrase when instruction is empty', () {
      const maneuver = NavigationManeuver(
        index: 0,
        instruction: ' ',
        type: 'left',
        lengthKm: 0.2,
        timeSeconds: 30,
        position: LatLng(35.0, 136.0),
      );

      final text = formatter.formatManeuver(
        maneuver,
        languageTag: 'ja-JP',
      );

      expect(text, '左折です。');
    });

    test('formats arrival in english with destination', () {
      final text = formatter.formatArrival(
        destinationLabel: 'Toyota HQ',
        languageTag: 'en-US',
      );

      expect(text, 'You have arrived at Toyota HQ.');
    });

    test('formats deviation in japanese', () {
      final text = formatter.formatDeviation(languageTag: 'ja-JP');
      expect(text, 'ルートを外れました。再検索します。');
    });

    test('prefixes critical hazard', () {
      final text = formatter.formatHazard(
        message: 'Black ice detected',
        severity: AlertSeverity.critical,
        languageTag: 'en-US',
      );

      expect(text, 'Critical warning. Black ice detected');
    });
  });
}
