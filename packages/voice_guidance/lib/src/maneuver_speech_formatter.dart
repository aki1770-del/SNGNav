/// Formats navigation and hazard messages into voice-friendly utterances.
library;

import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';

class ManeuverSpeechFormatter {
  const ManeuverSpeechFormatter();

  String formatManeuver(
    RouteManeuver maneuver, {
    required String languageTag,
  }) {
    final instruction = maneuver.instruction.trim();
    if (instruction.isNotEmpty) {
      return instruction;
    }

    final normalizedType = maneuver.type.trim().toLowerCase();
    if (languageTag.startsWith('ja')) {
      return switch (normalizedType) {
        'left' => '左折です。',
        'right' => '右折です。',
        'arrive' => '目的地に到着します。',
        'depart' => '出発します。',
        _ => '次の案内です。',
      };
    }

    return switch (normalizedType) {
      'left' => 'Turn left.',
      'right' => 'Turn right.',
      'arrive' => 'You will arrive at your destination.',
      'depart' => 'Start driving.',
      _ => 'Proceed to the next maneuver.',
    };
  }

  String formatArrival({
    required String? destinationLabel,
    required String languageTag,
  }) {
    if (languageTag.startsWith('ja')) {
      if (destinationLabel == null || destinationLabel.trim().isEmpty) {
        return '目的地に到着しました。';
      }
      return '$destinationLabel に到着しました。';
    }

    if (destinationLabel == null || destinationLabel.trim().isEmpty) {
      return 'You have arrived at your destination.';
    }
    return 'You have arrived at $destinationLabel.';
  }

  String formatDeviation({required String languageTag}) {
    if (languageTag.startsWith('ja')) {
      return 'ルートを外れました。再検索します。';
    }
    return 'You are off route. Re-routing now.';
  }

  String formatHazard({
    required String message,
    required AlertSeverity severity,
    required String languageTag,
  }) {
    final trimmed = message.trim();
    if (languageTag.startsWith('ja')) {
      return switch (severity) {
        AlertSeverity.critical => '危険。$trimmed',
        AlertSeverity.warning => '注意。$trimmed',
        AlertSeverity.info => trimmed,
      };
    }

    return switch (severity) {
      AlertSeverity.critical => 'Critical warning. $trimmed',
      AlertSeverity.warning => 'Warning. $trimmed',
      AlertSeverity.info => trimmed,
    };
  }
}
