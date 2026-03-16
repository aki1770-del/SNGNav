library;

import 'dart:io' show Platform;

import 'flutter_tts_engine.dart';
import 'linux_tts_engine.dart';
import 'tts_engine.dart';

TtsEngine createDefaultTtsEngine() {
  if (Platform.isLinux) {
    return LinuxTtsEngine();
  }

  return FlutterTtsEngine();
}