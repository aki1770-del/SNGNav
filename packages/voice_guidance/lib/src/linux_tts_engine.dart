library;

import 'dart:async';
import 'dart:io';

import 'tts_engine.dart';

typedef LinuxProcessRun =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef LinuxProcessStart =
    Future<Process> Function(String executable, List<String> arguments);
typedef LinuxExecutableResolver = String? Function(String executable);

/// Linux TTS implementation backed by `spd-say`.
class LinuxTtsEngine implements TtsEngine {
  LinuxTtsEngine({
    String executable = 'spd-say',
    LinuxProcessRun? runProcess,
    LinuxProcessStart? startProcess,
    LinuxExecutableResolver? resolveExecutable,
  }) : _executable = executable,
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
  double _speechRate = 1.0;
  Process? _activeProcess;
  String? _resolvedExecutable;

  /// Resolve [executable] to a real, existing file, or null.
  ///
  /// INV-6 (availability is not a tautology). This returned its argument
  /// unchanged until 2026-09-02, which made [isAvailable] answer `true` for
  /// every non-disposed engine on every Linux host — including a Yocto IVI
  /// image with no speech-dispatcher installed at all. An integrator asking
  /// "can this device speak?" got `true` from a device that cannot, and the
  /// only later signal was a `ProcessException` that `speak` swallows.
  ///
  /// A `null` here is the honest answer, and it is the one the caller can act
  /// on: select another engine, or escalate to a channel that exists.
  static String? _defaultResolveExecutable(String executable) {
    if (executable.isEmpty) return null;
    if (executable.contains('/')) {
      return File(executable).existsSync() ? executable : null;
    }
    final pathVar = Platform.environment['PATH'];
    if (pathVar == null || pathVar.isEmpty) return null;
    for (final dir in pathVar.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = dir.endsWith('/')
          ? '$dir$executable'
          : '$dir/$executable';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
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
  Future<void> setSpeechRate(double rate) async {
    if (_disposed) return;
    // Speech-Dispatcher rate range is roughly -100 .. +100; we keep
    // the normalized rate locally and translate at speak() time.
    _speechRate = rate.clamp(0.25, 2.0).toDouble();
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
        '--rate',
        _toSpeechDispatcherRate(_speechRate).toString(),
        trimmed,
      ]);
      _activeProcess = process;
      unawaited(
        process.exitCode.then((_) {
          if (identical(_activeProcess, process)) {
            _activeProcess = null;
          }
        }),
      );
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

  /// Maps a normalized speaking rate (0.25 .. 2.0; 1.0 == base) onto
  /// Speech-Dispatcher's `-100 .. +100` rate scale where 0 == base.
  /// Slower-than-base rates produce negative values; faster produce
  /// positive.
  static int _toSpeechDispatcherRate(double normalizedRate) {
    final clamped = normalizedRate.clamp(0.25, 2.0).toDouble();
    // 0.25 -> -100; 1.0 -> 0; 2.0 -> +100.
    if (clamped <= 1.0) {
      // Linear from 0.25..1.0 mapping to -100..0.
      return (((clamped - 1.0) / 0.75) * 100).round();
    }
    // Linear from 1.0..2.0 mapping to 0..+100.
    return (((clamped - 1.0) / 1.0) * 100).round();
  }
}
