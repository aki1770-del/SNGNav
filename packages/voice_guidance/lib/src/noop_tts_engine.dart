/// Silent TTS implementation for tests and headless environments.
library;

import 'dart:collection';

import 'tts_engine.dart';

class NoOpTtsEngine implements TtsEngine {
  bool _disposed = false;
  String _languageTag = 'ja-JP';
  double _volume = 1.0;
  final List<String> _spokenTexts = <String>[];

  String get languageTag => _languageTag;
  double get volume => _volume;
  UnmodifiableListView<String> get spokenTexts =>
      UnmodifiableListView<String>(_spokenTexts);

  @override
  Future<bool> isAvailable() async => !_disposed;

  @override
  Future<void> setLanguage(String languageTag) async {
    if (_disposed) return;
    _languageTag = languageTag;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed) return;
    if (text.trim().isEmpty) return;
    _spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    _spokenTexts.clear();
  }
}
