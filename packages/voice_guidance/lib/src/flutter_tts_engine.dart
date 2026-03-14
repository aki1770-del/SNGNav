/// flutter_tts-backed TTS implementation.
library;

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({FlutterTts? flutterTts}) : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;
  bool _disposed = false;

  @override
  Future<bool> isAvailable() async {
    if (_disposed) return false;
    try {
      final dynamic langs = await _flutterTts.getLanguages;
      if (langs is List) {
        return langs.isNotEmpty;
      }
      return langs != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setLanguage(String languageTag) async {
    if (_disposed) return;
    await _flutterTts.setLanguage(languageTag);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    await _flutterTts.setVolume(clamped);
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed) return;
    if (text.trim().isEmpty) return;
    await _flutterTts.speak(text);
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    await _flutterTts.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _flutterTts.stop();
    _disposed = true;
  }
}
