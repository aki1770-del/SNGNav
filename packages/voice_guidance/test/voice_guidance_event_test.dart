import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('VoiceGuidanceEvent', () {
    test('VoiceEnabled and VoiceDisabled are value-equal', () {
      expect(const VoiceEnabled(), const VoiceEnabled());
      expect(const VoiceDisabled(), const VoiceDisabled());
    });

    test('ManeuverAnnounced equality uses text', () {
      const a = ManeuverAnnounced(text: 'Turn right');
      const b = ManeuverAnnounced(text: 'Turn right');
      const c = ManeuverAnnounced(text: 'Turn left');

      expect(a, b);
      expect(a == c, isFalse);
    });

    test('HazardAnnounced equality uses message and severity', () {
      const a = HazardAnnounced(
        message: 'Ice ahead',
        severity: AlertSeverity.warning,
      );
      const b = HazardAnnounced(
        message: 'Ice ahead',
        severity: AlertSeverity.warning,
      );
      const c = HazardAnnounced(
        message: 'Ice ahead',
        severity: AlertSeverity.critical,
      );

      expect(a, b);
      expect(a == c, isFalse);
    });

    test('NavigationStateObserved equality uses navigation state', () {
      const route = NavigationRoute(
        shape: [LatLng(35.17, 136.88), LatLng(35.05, 137.15)],
        maneuvers: [
          NavigationManeuver(
            index: 0,
            instruction: 'Depart',
            type: 'depart',
            lengthKm: 1.0,
            timeSeconds: 60,
            position: LatLng(35.17, 136.88),
          ),
        ],
        totalDistanceKm: 1.0,
        totalTimeSeconds: 60,
        summary: '1km',
      );

      const state = NavigationState(
        status: NavigationStatus.navigating,
        route: route,
        currentManeuverIndex: 0,
      );

      const a = NavigationStateObserved(navigationState: state);
      const b = NavigationStateObserved(navigationState: state);

      expect(a, b);
    });
  });
}
