// WS2 · G2.2 — proves the app survives an embedder with NO path_provider
// registrant (the ivi-homescreen ARM-IVI case), reproducing the on-target
// MissingPluginException semantics rather than the host's happy path.
//
//   Boot symptom (measured): "MissingPluginException: No implementation found
//   for method getApplicationSupportDirectory / getApplicationCacheDirectory on
//   channel plugins.flutter.io/path_provider" — path_provider is unregistered
//   in the embedder, so the raw platform call throws.
//
// Run: flutter test test/services/path_provider_absent_fallback_test.dart
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:sngnav_snow_scene/services/saved_place_store.dart';

/// Stands in for the ivi-homescreen embedder: every path_provider call throws
/// MissingPluginException, exactly as the unregistered plugin does on target.
class _AbsentPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('path_provider not registered on embedder');
  @override
  Future<String?> getApplicationCachePath() async =>
      throw MissingPluginException('path_provider not registered on embedder');
  @override
  Future<String?> getTemporaryPath() async =>
      throw MissingPluginException('path_provider not registered on embedder');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openDefaultSavedPlaceStore falls back instead of throwing when '
      'path_provider is absent (embedder without the plugin)', () async {
    PathProviderPlatform.instance = _AbsentPathProvider();

    // Before the WS2 guard this threw MissingPluginException; it must now
    // return a usable store backed by a writable fallback dir.
    final store = await openDefaultSavedPlaceStore();
    expect(store, isNotNull);

    // And the store must actually work (pure dart:io past the dir lookup).
    await store.save(const SavedPlace(lat: 39.72, lon: 140.10, label: 'Akita'));
    final loaded = await store.load();
    expect(loaded.place?.label, 'Akita');
  });

  // The locked-rootfs case the fallback above exists for. Before 2026-07-22 the
  // candidate loop probed with `createSync(recursive: true)` alone, which
  // SUCCEEDS on a directory that already exists but is not writable — so the
  // loop accepted it, `break`ed, and the failure surfaced later at
  // `writeAsString`, i.e. after HER destination had been entered.
  //
  // This test fails against that old probe and passes against the real write
  // probe, which is the only reason to trust the guard.
  group('isDirectoryWritable — the probe the fallback chain depends on', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('writable_probe_test');
    });

    tearDown(() async {
      // Restore permissions first or the recursive delete cannot descend.
      // RECURSIVE (-R) and applied to the root: a direct-children-only pass
      // was sufficient when every chmod'ed dir sat at depth 1, but the
      // parent-vs-target test below locks a dir at depth 2, and a leaked
      // 0500 directory would strand a temp tree on every run.
      await Process.run('chmod', <String>['-R', '700', tmp.path]);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('returns true for a writable directory, and leaves no probe file '
        'behind', () async {
      final ok = Directory('${tmp.path}/writable');
      expect(isDirectoryWritable(ok), isTrue);
      // A probe that leaks a file would accumulate on a read-mostly target.
      expect(ok.listSync(), isEmpty);
    });

    test('returns true for a directory that does not exist yet (it is created)',
        () async {
      final fresh = Directory('${tmp.path}/deep/nested/fresh');
      expect(isDirectoryWritable(fresh), isTrue);
      expect(fresh.existsSync(), isTrue);
    });

    test('returns FALSE for an existing directory that is not writable — the '
        'case createSync cannot detect (locked rootfs)', () async {
      final ro = Directory('${tmp.path}/readonly')..createSync(recursive: true);
      final chmod = await Process.run('chmod', <String>['500', ro.path]);
      expect(chmod.exitCode, 0, reason: 'chmod must succeed for this to test');

      // Guard: if this process can write regardless (running as root), the
      // test proves nothing — say so rather than pass vacuously.
      final canWriteAnyway = () {
        try {
          File('${ro.path}/.root-check').writeAsStringSync('x');
          return true;
        } catch (_) {
          return false;
        }
      }();
      if (canWriteAnyway) {
        markTestSkipped('running with write access to a 0500 dir (root?) — '
            'the unwritable case cannot be constructed here');
        return;
      }

      // The old probe: createSync alone SUCCEEDS here. That is the defect.
      expect(
        () => ro.createSync(recursive: true),
        returnsNormally,
        reason: 'documents why createSync is not a writability test',
      );

      // The real probe must reject it.
      expect(isDirectoryWritable(ro), isFalse);
    });

    test('a WRITABLE parent holding an UNWRITABLE sngnav/ must be rejected — '
        'probing the parent is not probing the target', () async {
      // The defect the 2026-07-22 adversarial review found in the first cut of
      // this fix: the loop probed the candidate, but the store writes to
      // <candidate>/sngnav/saved_place.json. A writable parent containing an
      // unwritable sngnav passed the parent-probe and then threw at save()
      // time — the same late failure, one directory down.
      final parent = Directory('${tmp.path}/parent')
        ..createSync(recursive: true);
      final target = Directory('${parent.path}/sngnav')
        ..createSync(recursive: true);
      final chmod = await Process.run('chmod', <String>['500', target.path]);
      expect(chmod.exitCode, 0, reason: 'chmod must succeed for this to test');

      final canWriteAnyway = () {
        try {
          File('${target.path}/.root-check').writeAsStringSync('x');
          return true;
        } catch (_) {
          return false;
        }
      }();
      if (canWriteAnyway) {
        markTestSkipped('running with write access to a 0500 dir (root?) — '
            'the unwritable case cannot be constructed here');
        return;
      }

      // The PARENT looks fine — this is why a parent-probe passed.
      expect(isDirectoryWritable(parent), isTrue);
      // The directory actually written must be rejected.
      expect(isDirectoryWritable(target), isFalse);
    });

    // The test above checks the FUNCTION. This one checks the CALL SITE, and it
    // is the one with teeth: reverting openDefaultSavedPlaceStore to probe the
    // candidate instead of <candidate>/sngnav leaves the function untouched, so
    // only an end-to-end assertion can see that defect. The first version of
    // this suite missed exactly that and would have passed over the bug.
    test('openDefaultSavedPlaceStore falls THROUGH a candidate whose sngnav/ '
        'is unwritable, and the returned store can actually save', () async {
      final home = Directory('${tmp.path}/home')..createSync(recursive: true);
      final blocked = Directory('${home.path}/.local/share/sngnav')
        ..createSync(recursive: true);
      final chmod = await Process.run('chmod', <String>['500', blocked.path]);
      expect(chmod.exitCode, 0);

      final canWriteAnyway = () {
        try {
          File('${blocked.path}/.root-check').writeAsStringSync('x');
          return true;
        } catch (_) {
          return false;
        }
      }();
      if (canWriteAnyway) {
        markTestSkipped('running with write access to a 0500 dir (root?)');
        return;
      }

      final store = await openDefaultSavedPlaceStore(
        debugEnvOverride: <String, String>{'HOME': home.path},
      );

      // The binding assertion: the store must WORK. Against a parent-probe the
      // blocked candidate is selected and this save throws PathAccessException.
      await store.save(
        const SavedPlace(lat: 39.72, lon: 140.10, label: 'Akita'),
      );
      expect((await store.load()).place?.label, 'Akita');

      // And nothing was written into the blocked directory.
      expect(blocked.listSync(), isEmpty);
    });
  });
}
