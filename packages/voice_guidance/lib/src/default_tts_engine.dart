library;

import 'default_tts_engine_stub.dart'
    if (dart.library.io) 'default_tts_engine_io.dart' as implementation;

import 'tts_engine.dart';

/// Returns the default engine for the current platform.
TtsEngine createDefaultTtsEngine() => implementation.createDefaultTtsEngine();