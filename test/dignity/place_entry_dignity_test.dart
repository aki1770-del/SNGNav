import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/place_entry_dialog.dart';

/// DIGNITY PROPERTY TESTS (MANDATORY) for the in-app typed-place entry.
///
/// These encode the binding dignity corrections as machine-checked invariants:
/// the dest path watches NO person, persists exactly ONE record with no
/// behavioral log, does NOT couple to the consent database, and frames a PLACE
/// never a person. A regression that re-introduces a person signal fails here.
void main() {
  String read(String path) => File(path).readAsStringSync();

  final featureSources = <String, String>{
    'saved_place_store.dart': read('lib/services/saved_place_store.dart'),
    'place_entry_dialog.dart': read('lib/widgets/place_entry_dialog.dart'),
    'briefing_strings.dart': read('lib/widgets/briefing_strings.dart'),
  };

  group('no person-location signal import', () {
    // Any of these tokens appearing in the feature source would mean a person
    // signal (or the means to acquire one) leaked onto the dest path.
    const forbidden = <String>[
      'contacts',
      'flutter_contacts',
      'geolocator',
      'find_my',
      'findmy',
      'geofenc',
      'presence',
      'location_share',
      'nearby',
    ];

    for (final entry in featureSources.entries) {
      test('${entry.key} contains no person-signal token', () {
        final lower = entry.value.toLowerCase();
        for (final token in forbidden) {
          expect(
            lower.contains(token),
            isFalse,
            reason: '${entry.key} must not contain "$token"',
          );
        }
      });
    }
  });

  group('single-record persistence shape', () {
    late Directory tmp;
    late File file;
    late SavedPlaceStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('place_entry_dignity');
      file = File('${tmp.path}/sngnav/saved_place.json');
      store = SavedPlaceStore(file);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('file key set is EXACTLY {v,lat,lon,label}', () async {
      await store.save(const SavedPlace(lat: 39.69, lon: 140.34, label: 'A'));
      final decoded = jsonDecode(await file.readAsString());
      expect(decoded, isA<Map<String, Object?>>());
      expect((decoded as Map).keys.toSet(), {'v', 'lat', 'lon', 'label'});
    });

    test('toJson carries no timestamp / counter (no behavioral log)', () {
      final json = const SavedPlace(lat: 1, lon: 2, label: 'a').toJson();
      expect(json.keys.toSet(), {'v', 'lat', 'lon', 'label'});
      for (final k in json.keys) {
        final kl = k.toLowerCase();
        expect(kl.contains('time'), isFalse);
        expect(kl.contains('saved'), isFalse);
        expect(kl.contains('edited'), isFalse);
        expect(kl.contains('count'), isFalse);
        expect(kl.contains('log'), isFalse);
      }
    });

    test('store public method surface is EXACTLY {load, save, clear}', () {
      final src = featureSources['saved_place_store.dart']!;
      // The three signatures are present (load now returns the richer
      // load-state so a deliberate clear is distinguishable from a fresh store).
      expect(src.contains('Future<SavedPlaceLoad> load('), isTrue);
      expect(src.contains('Future<void> save('), isTrue);
      expect(src.contains('Future<void> clear('), isTrue);
      // No append-class WRITE and no list/history accessor.
      expect(src.contains('FileMode.append'), isFalse);
      expect(RegExp(r'\bappend\s*\(').hasMatch(src), isFalse);
      expect(RegExp(r'Future<List<').hasMatch(src), isFalse);

      // Enforce the 'only' guarantee: enumerate the public method declarations
      // in the SavedPlaceStore class BODY and assert the name set ⊆ {load, save,
      // clear}. Without this, a regression adding a behavioral-log accessor
      // (recordAccess / queryCount / lastSaved / history / ...) would pass.
      final classStart = src.indexOf('class SavedPlaceStore');
      expect(classStart, greaterThan(-1));
      final after = src.indexOf('\nFuture<SavedPlaceStore>', classStart);
      final classBody = src.substring(
        classStart,
        after > -1 ? after : src.length,
      );
      final methodNames = RegExp(
        r'Future<[^>]+>\s+(\w+)\s*\(',
      ).allMatches(classBody).map((m) => m.group(1)!).toSet();
      expect(methodNames, isNotEmpty);
      expect(
        methodNames.difference({'load', 'save', 'clear'}),
        isEmpty,
        reason:
            'store public surface must be EXACTLY {load, save, clear}; '
            'found extra: $methodNames',
      );
      for (final name in methodNames) {
        final n = name.toLowerCase();
        for (final banned in const [
          'time',
          'saved',
          'edited',
          'count',
          'log',
          'history',
          'list',
          'append',
          'query',
          'access',
        ]) {
          expect(
            n.contains(banned),
            isFalse,
            reason: 'no behavioral-log method name ($banned) in "$name"',
          );
        }
      }
    });

    test('only saved_place.json is created on save', () async {
      await store.save(const SavedPlace(lat: 1, lon: 2, label: 'a'));
      final dir = Directory('${tmp.path}/sngnav');
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList()
        ..removeWhere((n) => n.isEmpty);
      expect(names, ['saved_place.json']);
    });
  });

  group('no consent.db coupling', () {
    test('saved_place_store source has no consent/sqlite3/audit_log', () {
      final src = featureSources['saved_place_store.dart']!.toLowerCase();
      expect(src.contains('consent'), isFalse);
      expect(src.contains('openconsentdatabase'), isFalse);
      expect(src.contains('audit_log'), isFalse);
      expect(src.contains('sqlite3'), isFalse);
    });

    test('default store basename is saved_place.json', () {
      final src = featureSources['saved_place_store.dart']!;
      expect(src.contains("'saved_place.json'"), isTrue);
      // It must not reuse the consent database filename.
      expect(src.contains('consent.db'), isFalse);
    });
  });

  group('subject is a PLACE, never a person', () {
    test('no person-status word in feature sources', () {
      const forbidden = <String>[
        'mom',
        'お母さん',
        'arrived',
        'is home',
        '安否',
        '見守',
      ];
      for (final entry in featureSources.entries) {
        final lower = entry.value.toLowerCase();
        for (final token in forbidden) {
          expect(
            lower.contains(token.toLowerCase()),
            isFalse,
            reason: '${entry.key} must not contain "$token"',
          );
        }
      }
    });

    testWidgets('PlaceEntryDialog seeds an EMPTY default label', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PlaceEntryDialog(strings: BriefingStrings.en)),
        ),
      );
      await tester.pump();

      // Switch to the coordinates mode (where the label field lives).
      await tester.tap(find.text(BriefingStrings.en.placeEntryModeCoordinates));
      await tester.pump();

      // The label field default is EMPTY — never a seeded person/relationship word.
      final labelField = tester.widget<TextField>(
        find.widgetWithText(TextField, BriefingStrings.en.placeEntryLabelHint),
      );
      expect(labelField.controller?.text ?? '', '');
    });
  });

  // The dest path now runs through lib/widgets/pretrip_screen.dart
  // (_loadSavedPlace / _setDestination / _clearDestination /
  // _initDestAreaCondition + the DestinationEntryTile/showPlaceEntryDialog
  // wiring) after the pre-trip lift, and is still re-driven by lib/main.dart —
  // exactly where a future regression would wire a person-location plugin. The
  // 3-file feature scan above would NOT catch it, so encode the binding "zero
  // person-location import" invariant where the dest path actually lives.
  group('no person-location signal on the dest path (lib-wide + dest-path files)', () {
    // Match the PACKAGE-IMPORT shape, not bare tokens: 'location' appears 300+×
    // in the legitimate serial-NMEA vehicle GPS and 'presence' twice in
    // disavowal comments — a blanket substring scan would false-positive on
    // today's clean code.
    final personPackage = RegExp(
      r'package:(geolocator|flutter_contacts|contacts|location_share|geofence|nearby|find_?my|presence)',
    );

    bool isImportLine(String line) {
      final t = line.trimLeft();
      return t.startsWith('import ') || t.startsWith('export ');
    }

    test('no lib/ file imports a person-location package', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final line in const LineSplitter().convert(f.readAsStringSync())) {
          if (isImportLine(line) && personPackage.hasMatch(line)) {
            offenders.add('${f.path}: ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'a person-location package anywhere in lib/ would put a person '
            'signal on the dest path; found: $offenders',
      );
    });

    test('dest-path files import/export lines carry no person-signal token', () {
      // Scan only the import/export DIRECTIVE lines so the legitimate 'presence'
      // disavowal comment (and the 'location' in the vehicle-GPS code) does not
      // false-positive. Both files matter: the dest path was LIFTED into
      // lib/widgets/pretrip_screen.dart (where her mother's area read now lives),
      // and lib/main.dart still re-drives it — a person-location plugin wired in
      // either would slip the token nets, so scan both.
      const forbidden = <String>[
        'contacts',
        'flutter_contacts',
        'geolocator',
        'find_my',
        'findmy',
        'geofenc',
        'presence',
        'location_share',
        'nearby',
      ];
      const destPathFiles = <String>[
        'lib/main.dart',
        'lib/widgets/pretrip_screen.dart',
      ];
      for (final file in destPathFiles) {
        final src = read(file);
        for (final line in const LineSplitter().convert(src)) {
          if (!isImportLine(line)) continue;
          final lower = line.toLowerCase();
          for (final token in forbidden) {
            expect(
              lower.contains(token),
              isFalse,
              reason:
                  '$file must not import a person-signal package '
                  '($token): ${line.trim()}',
            );
          }
        }
      }
    });
  });

  // The feature's single most load-bearing dignity claim is that the dest-area
  // read is ON-DEMAND ONLY — initState + the single HER-action setter, with NO
  // Timer/Stream/scheduled refresh. A poller added to the dest path turns a
  // once-only read into recurring surveillance of her mother's area
  // (見守り-by-proxy) and contains NO person token, so the token scans miss it.
  group('no scheduled/background re-read of the area (見守り-by-proxy refusal)', () {
    test('the dest-area path has no recurring-read primitive', () {
      // The dest-path methods were lifted into the shared PretripScreen; the
      // dignity claim binds wherever the code lives.
      final src = read('lib/widgets/pretrip_screen.dart');
      // CODE only: strip line comments so a doc comment that legitimately
      // disavows scheduling ("ONE-SHOT (no Timer/Stream)") is not a false
      // positive — we are asserting the code, not the prose.
      String stripComments(String s) => s
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i >= 0 ? l.substring(0, i) : l;
          })
          .join('\n');
      // Slice each dest-path method body from its declaration to the next
      // top-level method declaration (a STRUCTURAL boundary, not a sibling name).
      String bodyOf(String declStr) {
        final start = src.indexOf(declStr);
        expect(
          start,
          greaterThan(-1),
          reason: 'expected $declStr in lib/main.dart',
        );
        final next = RegExp(
          r'\n  (?:Future<[^>]*>|void|Widget)\s+\w+\(',
        ).firstMatch(src.substring(start + 1));
        expect(
          next,
          isNotNull,
          reason: 'a following method declaration must bound $declStr',
        );
        return stripComments(src.substring(start, start + 1 + next!.start));
      }

      for (final declStr in const [
        'Future<void> _initDestAreaCondition()',
        'Future<void> _setDestination(',
        'Future<void> _loadSavedPlace()',
      ]) {
        final body = bodyOf(declStr);
        for (final bg in const [
          'Timer',
          '.periodic',
          'Stream',
          '.listen(',
          'Notification',
          'scheduleRefresh',
        ]) {
          expect(
            body.contains(bg),
            isFalse,
            reason:
                'the dest path ($declStr) must have no background '
                'scheduling ($bg) — polling her area is 見守り-by-proxy',
          );
        }
      }
    });
  });
}
