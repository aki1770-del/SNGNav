/// flutter/services HapticFeedback-backed haptic implementation.
library;

import 'package:flutter/services.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart';

import 'haptic_engine.dart';

/// One physical impact at the urgency implied by [pattern].
///
/// Injectable so tests can drive the engine (assert plugin-degradation,
/// pulse counts) without a real vibration motor — the same seam shape
/// `FlutterTtsEngine` uses by accepting an injectable `FlutterTts`.
typedef HapticImpact = Future<void> Function(HapticCuePattern pattern);

/// Default impact: maps an announced cue onto flutter/services
/// `HapticFeedback`. Warning renders as a medium impact; critical as a
/// heavier impact. `none` performs no platform call.
Future<void> _defaultImpact(HapticCuePattern pattern) {
  switch (pattern) {
    case HapticCuePattern.none:
      return Future<void>.value();
    case HapticCuePattern.warning:
      return HapticFeedback.mediumImpact();
    case HapticCuePattern.critical:
      return HapticFeedback.heavyImpact();
  }
}

/// A [HapticEngine] that renders cues through flutter/services
/// `HapticFeedback`.
///
/// The cue grammar (number of pulses) comes from
/// [HapticCuePatternRendering.pulseCount] on the pure enum: a warning is a
/// measured double-pulse (2 medium impacts), a critical is an urgent
/// triple-pulse (3 heavier impacts), so a deaf driver can tell "reduce
/// speed" from "consider turning back". The two tiers are doubly
/// distinguishable — by count (2 vs 3) and by intensity (medium vs heavy).
///
/// **Honest degradation** (mirrors [FlutterTtsEngine]): the engine guards
/// every platform call with the same `MissingPluginException` → unavailable
/// pattern. Once the haptic platform reports itself missing,
/// [pluginAvailable] flips false and [isAvailable] returns false; further
/// cues are no-ops. Any other platform error is also swallowed — a haptic
/// cue is advisory and additive, so a haptic failure must NEVER throw into
/// or delay the audio channel.
///
/// **Truthfulness bound** (see `KNOWN_LIMITATIONS.md`): "available" here
/// means the haptic platform channel did not report itself missing. It does
/// NOT guarantee a physical vibration motor is present and felt — there is
/// no flutter/services API to probe for a motor. On a desktop / motor-less
/// host where `HapticFeedback` silently no-ops, [isAvailable] may report
/// true while producing no sensation. The integrator chooses
/// [NoOpHapticEngine] for hosts known to lack a motor, exactly as it
/// chooses `NoOpTtsEngine` for headless audio.
class FlutterHapticEngine implements HapticEngine {
  FlutterHapticEngine({
    HapticImpact? impact,
    Duration interPulseGap = const Duration(milliseconds: 80),
  }) : _impact = impact ?? _defaultImpact,
       _interPulseGap = interPulseGap;

  final HapticImpact _impact;
  final Duration _interPulseGap;
  bool _disposed = false;
  bool _pluginAvailable = true;

  /// True until the haptic platform has reported itself missing via
  /// `MissingPluginException`.
  bool get pluginAvailable => _pluginAvailable;

  @override
  Future<bool> isAvailable() async => !_disposed && _pluginAvailable;

  @override
  Future<void> cue(HapticCuePattern pattern) async {
    if (_disposed || !_pluginAvailable) return;
    final pulses = pattern.pulseCount;
    for (var i = 0; i < pulses; i++) {
      if (_disposed || !_pluginAvailable) return;
      try {
        await _impact(pattern);
      } on MissingPluginException {
        // Honest degradation: the haptic platform is absent. Flip to
        // unavailable so isAvailable() tells the truth and future cues
        // are cheap no-ops.
        _pluginAvailable = false;
        return;
      } catch (_) {
        // Any other haptic failure is swallowed so the audio channel is
        // never affected. The cue is advisory and additive, never
        // load-bearing.
        return;
      }
      if (i + 1 < pulses) {
        await Future<void>.delayed(_interPulseGap);
      }
    }
  }

  @override
  Future<void> stop() async {
    // HapticFeedback impacts are instantaneous fire-and-forget events; there
    // is no in-progress sensation to cancel at the platform layer.
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
