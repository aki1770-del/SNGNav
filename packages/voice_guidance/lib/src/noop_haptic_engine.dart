/// Silent haptic implementation for tests and headless / motor-less
/// environments.
library;

import 'dart:collection';

import 'package:navigation_safety_enums/navigation_safety_enums.dart';

import 'haptic_engine.dart';

/// A [HapticEngine] that produces no physical sensation and records the cues
/// it was asked to render.
///
/// Used for tests (the recorded [cues] let a test assert what the bloc fired
/// without a real vibration motor) and for headless / motor-less hosts where
/// no tactile sensation is possible. It never throws.
///
/// Honesty: this engine reports [isAvailable] as `true` while not disposed —
/// it is "available" in the sense that it accepts and records cues, but it
/// produces NO tactile sensation. It must not be used in production as a
/// stand-in for a real device haptic; it is a test / fallback double. The
/// Flutter implementation ([FlutterHapticEngine]) is the production engine.
class NoOpHapticEngine implements HapticEngine {
  bool _disposed = false;
  final List<HapticCuePattern> _cues = <HapticCuePattern>[];

  /// The cues this engine was asked to render, in order. `none` cues are
  /// recorded too (so a test can assert set-parity precisely).
  UnmodifiableListView<HapticCuePattern> get cues =>
      UnmodifiableListView<HapticCuePattern>(_cues);

  /// The subset of recorded cues that produced an actual tactile sensation.
  UnmodifiableListView<HapticCuePattern> get tactileCues =>
      UnmodifiableListView<HapticCuePattern>(
        _cues.where((c) => c.isTactile),
      );

  @override
  Future<bool> isAvailable() async => !_disposed;

  @override
  Future<void> cue(HapticCuePattern pattern) async {
    if (_disposed) return;
    _cues.add(pattern);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cues.clear();
  }
}
