import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/services/app_support_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The defect this covers, measured 2026-08-23 on the Toyota Connected
  // ivi-homescreen embedder running our own AOT bundle: path_provider has no
  // implementation there, main() called getApplicationSupportDirectory()
  // unguarded, and the app died before its first frame.
  group('resolveAppSupportDir — the platform may simply not answer', () {
    test('XDG_DATA_HOME is used when the platform has no plugin', () async {
      final got = await resolveAppSupportDir(
        environment: {'XDG_DATA_HOME': '/xdg/data', 'HOME': '/root'},
      );
      // In a plain `flutter test` VM there is no path_provider platform
      // implementation either — the same absence the embedder has — so this
      // exercises the real fallback path, not a mock of it.
      expect(got.isFallback, isTrue);
      expect(got.directory.path, '/xdg/data/sngnav_snow_scene');
      expect(got.source, AppSupportSource.xdgFallback);
    });

    test('HOME/.local/share is used when XDG_DATA_HOME is unset', () async {
      final got = await resolveAppSupportDir(environment: {'HOME': '/root'});
      expect(got.directory.path, '/root/.local/share/sngnav_snow_scene');
    });

    test('an empty XDG_DATA_HOME is not a directory — HOME wins', () async {
      final got = await resolveAppSupportDir(
        environment: {'XDG_DATA_HOME': '', 'HOME': '/root'},
      );
      expect(got.directory.path, '/root/.local/share/sngnav_snow_scene');
    });

    test('the fallback is DURABLE — never systemTemp', () async {
      final got = await resolveAppSupportDir(environment: {'HOME': '/root'});
      // The consent database and saved-place store both promise data survives
      // restart. A temp path would satisfy the type and break the promise.
      expect(got.directory.path, isNot(contains(Directory.systemTemp.path)));
      expect(got.directory.path, isNot(contains('/tmp')));
    });

    test('neither platform nor environment: it REPORTS, never substitutes',
        () async {
      await expectLater(
        () => resolveAppSupportDir(environment: const {}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
