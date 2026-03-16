/// flutter_tts-backed TTS implementation.
library;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

import 'tts_engine.dart';

class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({FlutterTts? flutterTts}) : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;
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
  Future<void> speak(String text) async {
    if (_disposed || !_pluginAvailable) return;
    if (text.trim().isEmpty) return;
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
  }
}
