/// flutter_tts-backed TTS implementation.
library;

import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

import 'tts_engine.dart';

class FlutterTtsEngine implements TtsEngine, DeliveryObservable {
  FlutterTtsEngine({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  SpeechDelivery _lastDelivery = SpeechDelivery.unknown;
  bool _completionWired = false;

  @override
  SpeechDelivery get lastDelivery => _lastDelivery;

  /// Bound on how long we will wait for the engine to confirm an utterance.
  ///
  /// flutter_tts can leave the speak future unresolved when the platform side
  /// errors, so waiting without a bound would stall the alert path — worse for
  /// the driver than not knowing. On expiry we report [SpeechDelivery.unknown],
  /// never [SpeechDelivery.delivered].
  static const Duration deliveryBound = Duration(seconds: 8);

  /// True once the platform has agreed to report utterance completion.
  ///
  /// An engine that cannot do so is not a failure and must not throw: it is
  /// simply unobservable, and [lastDelivery] stays [SpeechDelivery.unknown].
  /// Reporting "unknown" is the honest state; crashing the alert path, or
  /// letting "queued" read as "heard", are both worse for the driver.
  bool _deliveryObservable = false;

  /// Sequence number of the utterance currently awaiting a platform verdict,
  /// or null when nothing is open.
  ///
  /// The platform callbacks carry NO utterance identity (flutter_tts calls
  /// `completionHandler!()` with no arguments), so identity is held here or
  /// nowhere. Without it a late verdict for utterance N silently credits
  /// utterance N+1 — a warning she never heard reading as delivered.
  int? _openUtterance;
  int _utteranceSeq = 0;

  /// Verdicts still owed by utterances we already gave up on.
  ///
  /// A timed-out or superseded utterance may still produce a callback later.
  /// That callback belongs to the dead utterance, not to the live one, so it
  /// is consumed and discarded rather than allowed to resolve anything.
  int _unclaimedVerdicts = 0;

  /// Apply a platform verdict to the open utterance, or discard it.
  ///
  /// INV-2 (attribution): a verdict resolves at most one utterance, and only
  /// the one that is open. INV-3 (no upgrade after giving up): an abandoned
  /// utterance can never be revived into [SpeechDelivery.delivered].
  void _resolve(SpeechDelivery outcome) {
    if (_unclaimedVerdicts > 0) {
      _unclaimedVerdicts--;
      return;
    }
    if (_openUtterance == null) return;
    _openUtterance = null;
    _lastDelivery = outcome;
  }

  /// Give up on the open utterance: it becomes [SpeechDelivery.unknown] and
  /// its future verdict is owed-and-discarded.
  void _abandonOpenUtterance() {
    if (_openUtterance == null) return;
    _openUtterance = null;
    _unclaimedVerdicts++;
    _lastDelivery = SpeechDelivery.unknown;
  }

  Future<void> _wireCompletionOnce() async {
    if (_completionWired) return;
    _completionWired = true;
    try {
      // ⚑ WDA-D4-OBS O-3, 2026-09-02. `awaitSpeakCompletion(true)` USED TO BE
      // CALLED HERE and it was a break we very nearly published.
      // flutter_tts-4.2.5:330 declares `static const MethodChannel _channel`:
      // ONE platform handler per process. Flipping that mode changes the
      // resolution contract of EVERY FlutterTts in the host app — including
      // instances the consumer constructed themselves, which never touch this
      // package, and the instance they injected into our own constructor.
      // No version number of ours can describe a change to someone else's API.
      // Observation must not move the thing observed: handlers alone report
      // delivery, and they do it without altering anyone's timing.
      _flutterTts.setCompletionHandler(() => _resolve(SpeechDelivery.delivered));
      _flutterTts.setErrorHandler((dynamic _) => _resolve(SpeechDelivery.failed));
      // INV-5 (cancel is not silence): the platform reports a cancelled
      // utterance on its OWN channel (`speak.onCancel`), which neither the
      // completion nor the error handler receives. Leaving it unwired made a
      // KNOWN non-delivery read as `unknown` ("not observable"), which is a
      // different and less actionable claim than "we know it did not finish".
      _flutterTts.setCancelHandler(() => _resolve(SpeechDelivery.failed));
      _deliveryObservable = true;
    } catch (_) {
      _deliveryObservable = false;
    }
  }
  bool _disposed = false;
  bool _pluginAvailable = true;

  bool get pluginAvailable => _pluginAvailable;

  T? _guardPluginCall<T>(T? Function() action) {
    if (_disposed || !_pluginAvailable) return null;
    try {
      return action();
    } on MissingPluginException {
      _pluginAvailable = false;
      return null;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (_disposed || !_pluginAvailable) return false;
    try {
      final dynamic langs = await _flutterTts.getLanguages;
      if (langs is List) {
        return langs.isNotEmpty;
      }
      return langs != null;
    } on MissingPluginException {
      _pluginAvailable = false;
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setLanguage(String languageTag) async {
    await _guardPluginCall(() => _flutterTts.setLanguage(languageTag));
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    await _guardPluginCall(() => _flutterTts.setVolume(clamped));
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    // flutter_tts accepts a normalized 0.0..1.0 default-rate scale on
    // most platforms (with platform-specific interpretations). We map
    // our 0.25..2.0 normalized scale into 0.0..1.0 by clamping +
    // halving; 1.0 (our base) -> 0.5 (flutter_tts default-rate).
    final clamped = rate.clamp(0.25, 2.0).toDouble();
    final flutterTtsRate = (clamped / 2.0).clamp(0.0, 1.0);
    await _guardPluginCall(() => _flutterTts.setSpeechRate(flutterTtsRate));
  }

  @override
  Future<void> speak(String text) async {
    // INV-1 (freshness): `lastDelivery` describes THIS call or nothing. The
    // reset precedes every early return, because the dangerous case is the
    // one that returns early: a critical warning the platform never received
    // must not inherit the previous utterance's success.
    _abandonOpenUtterance();
    _lastDelivery = SpeechDelivery.unknown;

    if (_disposed || !_pluginAvailable) return;
    if (text.trim().isEmpty) return;
    await _wireCompletionOnce();
    if (!_deliveryObservable) {
      await _guardPluginCall(() => _flutterTts.speak(text));
      return;
    }
    // ⚑ WDA-D4-OBS O-2, 2026-09-02. This USED TO await completion under an 8s
    // bound. Signature unchanged, timing changed — invisible to the analyzer
    // and to a green suite. Measured against the real bloc: the maneuver
    // handler's late `emit(idle)` landed INSIDE the hazard announcement,
    // widening a ~2ms false-idle window to 401ms on HER hazard path, and up to
    // seconds under the real bound. `bloc` 9.2.x processes events concurrently
    // by default, so the two handlers interleave.
    // speak() therefore resolves on QUEUE exactly as it always did. Delivery is
    // reported ASYNCHRONOUSLY through the handlers into `lastDelivery`; a
    // reader consults it, and nothing waits on it.
    _openUtterance = ++_utteranceSeq;
    await _guardPluginCall(() => _flutterTts.speak(text));
  }

  @override
  Future<void> stop() async {
    await _guardPluginCall(() => _flutterTts.stop());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _guardPluginCall(() => _flutterTts.stop());
    _disposed = true;
    // INV-4 (terminal state): a disposed engine delivers nothing. Leaving the
    // last success readable lets a torn-down engine answer "delivered" about
    // a drive that has ended.
    _abandonOpenUtterance();
    _lastDelivery = SpeechDelivery.unknown;
  }
}
