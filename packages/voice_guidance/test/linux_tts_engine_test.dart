import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_guidance/src/linux_tts_engine.dart';

class _MockProcess extends Mock implements Process {}

void main() {
  setUpAll(() {
    registerFallbackValue(ProcessSignal.sigterm);
  });

  group('LinuxTtsEngine', () {
    late List<List<String>> startedCommands;
    late List<List<String>> runCommands;
    late _MockProcess process;
    late LinuxTtsEngine engine;

    setUp(() {
      startedCommands = <List<String>>[];
      runCommands = <List<String>>[];
      process = _MockProcess();
      when(() => process.exitCode).thenAnswer((_) async => 0);
      when(() => process.kill(any())).thenReturn(true);

      engine = LinuxTtsEngine(
        resolveExecutable: (executable) => '/usr/bin/spd-say',
        runProcess: (executable, arguments) async {
          runCommands.add(<String>[executable, ...arguments]);
          return ProcessResult(1, 0, '', '');
        },
        startProcess: (executable, arguments) async {
          startedCommands.add(<String>[executable, ...arguments]);
          return process;
        },
      );
    });

    test('isAvailable returns true when executable resolves', () async {
      expect(await engine.isAvailable(), isTrue);
    });

    test('isAvailable returns false when executable is missing', () async {
      final missingEngine = LinuxTtsEngine(
        resolveExecutable: (_) => null,
      );

      expect(await missingEngine.isAvailable(), isFalse);
    });

    test('speak starts spd-say with normalized language and volume', () async {
      await engine.setLanguage('ja-JP');
      await engine.setVolume(0.75);

      await engine.speak('右折です。');

      expect(startedCommands, hasLength(1));
      expect(startedCommands.single.first, '/usr/bin/spd-say');
      expect(startedCommands.single, containsAllInOrder([
        '--application-name',
        'SNGNav',
        '--connection-name',
        'voice_guidance',
        '--priority',
        'important',
        '--language',
        'ja',
        '--volume',
        '50',
        '右折です。',
      ]));
    });

    test('stop terminates the active process and requests dispatcher stop', () async {
      await engine.speak('左折です。');

      await engine.stop();

      expect(
        runCommands.any(
          (command) =>
              command.length == 2 &&
              command[0] == '/usr/bin/spd-say' &&
              command[1] == '--stop',
        ),
        isTrue,
      );
    });

    test('dispose stops speaking and ignores future requests', () async {
      await engine.speak('目的地です。');

      await engine.dispose();
      await engine.speak('ignored');

      expect(startedCommands, hasLength(1));
      expect(
        runCommands.any(
          (command) =>
              command.length == 2 &&
              command[0] == '/usr/bin/spd-say' &&
              command[1] == '--stop',
        ),
        isTrue,
      );
    });
  });
}