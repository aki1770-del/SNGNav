import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';

/// FUNCTIONAL — the single-record, overwrite-only destination-area store.
/// Pure dart:io against a temp dir (no path_provider). Verifies the binding
/// persistence shape: ONE record, overwrite-in-place, never an append, and an
/// honest floor (null, never throw) on every bad-input path.
void main() {
  late Directory tmp;
  late File file;
  late SavedPlaceStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('saved_place_store_test');
    file = File('${tmp.path}/sngnav/saved_place.json');
    store = SavedPlaceStore(file);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('SavedPlaceStore', () {
    test('save -> load round-trip', () async {
      const place = SavedPlace(lat: 39.69, lon: 140.34, label: 'Akita');
      await store.save(place);
      final loaded = (await store.load()).place;
      expect(loaded, isNotNull);
      expect(loaded!.lat, 39.69);
      expect(loaded.lon, 140.34);
      expect(loaded.label, 'Akita');
    });

    test(
      'overwrite-in-place: save A then B => load==B AND a single Map',
      () async {
        await store.save(const SavedPlace(lat: 1, lon: 2, label: 'A'));
        await store.save(const SavedPlace(lat: 3, lon: 4, label: 'B'));
        final loaded = (await store.load()).place;
        expect(loaded!.label, 'B');
        expect(loaded.lat, 3);
        expect(loaded.lon, 4);

        // The file decodes to a SINGLE Map, never a List (no append/accumulation).
        final decoded = jsonDecode(await file.readAsString());
        expect(decoded, isA<Map<String, Object?>>());
        expect(decoded, isNot(isA<List<Object?>>()));
      },
    );

    test('save never appends: file length not monotonically growing across '
        'repeated identical saves', () async {
      const place = SavedPlace(lat: 39.69, lon: 140.34, label: 'Akita');
      await store.save(place);
      final len1 = await file.length();
      await store.save(place);
      final len2 = await file.length();
      await store.save(place);
      final len3 = await file.length();
      expect(len2, len1);
      expect(len3, len1);
    });

    test('load missing => absent, not cleared (never throws)', () async {
      final r = await store.load();
      expect(r.place, isNull);
      expect(r.cleared, isFalse);
    });

    test('load empty / whitespace => absent (place null)', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('');
      expect((await store.load()).place, isNull);
      await file.writeAsString('   \n  ');
      expect((await store.load()).place, isNull);
    });

    test('load corrupt JSON => absent (never throws)', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('{ not json ]');
      expect((await store.load()).place, isNull);
    });

    test('load non-Map (a JSON array) => absent', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('[1,2,3]');
      expect((await store.load()).place, isNull);
    });

    // Finding 11 (durable clear): a deliberate removal must survive a restart as
    // a TOMBSTONE — distinct from a never-written store — so the build-time
    // PRETRIP_DEST_* seed can NOT resurrect a place the driver removed.
    test(
      'clear writes a durable tombstone: load reports cleared, not absent',
      () async {
        await store.save(const SavedPlace(lat: 1, lon: 2, label: 'x'));
        expect((await store.load()).place, isNotNull);
        await store.clear();
        // The record persists (so the removal is durable across a restart) and is
        // a tombstone: NO place, AND `cleared` is true (distinguishable from a
        // fresh, never-written store which is absent + not cleared).
        expect(await file.exists(), isTrue);
        final afterClear = await store.load();
        expect(afterClear.place, isNull);
        expect(afterClear.cleared, isTrue);
        // The tombstone carries no place fields, no behavioral log.
        final decoded = jsonDecode(await file.readAsString()) as Map;
        expect(decoded['cleared'], isTrue);
        expect(decoded.containsKey('lat'), isFalse);
        expect(decoded.containsKey('lon'), isFalse);
        // Idempotent: clear again does not throw and stays a tombstone.
        await store.clear();
        final afterSecond = await store.load();
        expect(afterSecond.place, isNull);
        expect(afterSecond.cleared, isTrue);
      },
    );

    // The tombstone is reversible: saving a real place again overwrites it.
    test(
      'save after clear overwrites the tombstone with a real place',
      () async {
        await store.clear();
        expect((await store.load()).cleared, isTrue);
        await store.save(const SavedPlace(lat: 5, lon: 6, label: 'y'));
        final r = await store.load();
        expect(r.cleared, isFalse);
        expect(r.place!.label, 'y');
      },
    );
  });

  group('SavedPlace.fromJson rejects bad input', () {
    test('missing lat/lon/label => null', () {
      expect(SavedPlace.fromJson({'lon': 1, 'label': 'a'}), isNull);
      expect(SavedPlace.fromJson({'lat': 1, 'label': 'a'}), isNull);
      expect(SavedPlace.fromJson({'lat': 1, 'lon': 2}), isNull);
    });

    test('NaN / inf => null', () {
      expect(
        SavedPlace.fromJson({'lat': double.nan, 'lon': 2, 'label': 'a'}),
        isNull,
      );
      expect(
        SavedPlace.fromJson({'lat': 1, 'lon': double.infinity, 'label': 'a'}),
        isNull,
      );
    });

    test('out-of-range lat/lon => null', () {
      expect(SavedPlace.fromJson({'lat': 91, 'lon': 0, 'label': 'a'}), isNull);
      expect(SavedPlace.fromJson({'lat': -91, 'lon': 0, 'label': 'a'}), isNull);
      expect(SavedPlace.fromJson({'lat': 0, 'lon': 181, 'label': 'a'}), isNull);
      expect(
        SavedPlace.fromJson({'lat': 0, 'lon': -181, 'label': 'a'}),
        isNull,
      );
    });

    test('valid (incl. empty label) => SavedPlace', () {
      final p = SavedPlace.fromJson({'lat': 39.69, 'lon': 140.34, 'label': ''});
      expect(p, isNotNull);
      expect(p!.label, '');
    });

    test('toJson keys are EXACTLY {v,lat,lon,label}', () {
      final keys = const SavedPlace(
        lat: 1,
        lon: 2,
        label: 'a',
      ).toJson().keys.toSet();
      expect(keys, {'v', 'lat', 'lon', 'label'});
    });
  });
}
