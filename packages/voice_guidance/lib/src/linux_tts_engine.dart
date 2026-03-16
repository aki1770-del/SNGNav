library;

import 'dart:async';
import 'dart:io';

import 'tts_engine.dart';

typedef LinuxProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
typedef LinuxProcessStart = Future<Process> Function(
  String executable,
  List<String> arguments,
);
typedef LinuxExecutableResolver = String? Function(String executable);

/// Linux TTS implementation backed by `spd-say`.
class LinuxTtsEngine implements TtsEngine {
  LinuxTtsEngine({
    String executable = 'spd-say',
    LinuxProcessRun? runProcess,
    LinuxProcessStart? startProcess,
    LinuxExecutableResolver? resolveExecutable,
  })  : _executable = executable,
        _runProcess = runProcess ?? Process.run,
        _startProcess = startProcess ?? Process.start,
        _resolveExecutable = resolveExecutable ?? _defaultResolveExecutable;

  final String _executable;
  final LinuxProcessRun _runProcess;
  final LinuxProcessStart _startProcess;
  final LinuxExecutableResolver _resolveExecutable;

  bool _disposed = false;
  String _languageCode = 'en';
  double _volume = 1.0;
  Process? _activeProcess;
  String? _resolvedExecutable;

  static String? _defaultResolveExecutable(String executable) {
    return executable;
  }

  @override
  Future<bool> isAvailable() async {
    if (_disposed) return false;

    final resolved = _resolvedExecutable ?? _resolveExecutable(_executable);
    if (resolved == null || resolved.isEmpty) {
      _resolvedExecutable = null;
      return false;
    }

    _resolvedExecutable = resolved;
    return true;
  }

  @override
  Future<void> setLanguage(String languageTag) async {
    if (_disposed) return;
    _languageCode = _normalizeLanguageTag(languageTag);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final executable = await _resolveAvailableExecutable();
    if (executable == null) return;

    await _stopActiveProcess();

    try {
      final process = await _startProcess(executable, [
        '--application-name',
        'SNGNav',
        '--connection-name',
        'voice_guidance',
        '--priority',
        'important',
        '--language',
        _languageCode,
        '--volume',
        _toSpeechDispatcherVolume(_volume).toString(),
        trimmed,
      ]);
      _activeProcess = process;
      unawaited(process.exitCode.then((_) {
        if (identical(_activeProcess, process)) {
          _activeProcess = null;
        }
      }));
    } on ProcessException {
      _resolvedExecutable = null;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    final executable = await _resolveAvailableExecutable();
    await _stopActiveProcess();
    if (executable == null) return;

    try {
      await _runProcess(executable, const ['--stop']);
    } on ProcessException {
      _resolvedExecutable = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
  }

  Future<String?> _resolveAvailableExecutable() async {
    if (!await isAvailable()) return null;
    return _resolvedExecutable;
  }

  Future<void> _stopActiveProcess() async {
    final process = _activeProcess;
    _activeProcess = null;
    if (process == null) return;

    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 250));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      // Ignore process lifecycle failures while tearing down speech requests.
    }
  }

  static String _normalizeLanguageTag(String languageTag) {
    final trimmed = languageTag.trim();
    if (trimmed.isEmpty) return 'en';
    return trimmed.split(RegExp('[-_]')).first.toLowerCase();
  }

  static int _toSpeechDispatcherVolume(double normalizedVolume) {
    final clamped = normalizedVolume.clamp(0.0, 1.0).toDouble();
    return ((clamped * 200) - 100).round();
  }
}