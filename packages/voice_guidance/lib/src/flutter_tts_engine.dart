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

  Future<void> _wireCompletionOnce() async {
    if (_completionWired) return;
    _completionWired = true;
    try {
      final dynamic ack = _flutterTts.awaitSpeakCompletion(true);
      if (ack is Future) await ack;
      _flutterTts.setCompletionHandler(() => _lastDelivery = SpeechDelivery.delivered);
      _flutterTts.setErrorHandler((dynamic _) => _lastDelivery = SpeechDelivery.failed);
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
    if (_disposed || !_pluginAvailable) return;
    if (text.trim().isEmpty) return;
    await _wireCompletionOnce();
    _lastDelivery = SpeechDelivery.unknown;
    if (!_deliveryObservable) {
      await _guardPluginCall(() => _flutterTts.speak(text));
      return;
    }
    try {
      await Future<void>(() => _guardPluginCall(() => _flutterTts.speak(text)))
          .timeout(deliveryBound);
    } on TimeoutException {
      _lastDelivery = SpeechDelivery.unknown;
    }
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
  }
}
