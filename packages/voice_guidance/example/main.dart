// ignore_for_file: avoid_print
//
// Minimal example for voice_guidance.
//
// Demonstrates the platform-agnostic NoOpTtsEngine — the silent
// fallback engine used in CI and tests. Production builds substitute
// FlutterTtsEngine (mobile) or LinuxTtsEngine (Linux IVI) at the
// integration seam.

import 'package:voice_guidance/voice_guidance.dart';

Future<void> main() async {
  final engine = NoOpTtsEngine();
  await engine.speak('300 meters ahead, turn right.');
  await engine.speak('You have arrived.');
  print(
    'NoOpTtsEngine speak: silent (CI / test fallback) — '
    'substitute FlutterTtsEngine or LinuxTtsEngine in production.',
  );
}
