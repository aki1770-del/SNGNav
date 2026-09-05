/// The on-device store for the ONE destination AREA the driver chooses
/// for the family-thread pre-trip read.
///
/// WHY this exists (the compound-failure worst case — the driver test): the
/// family-thread destination-area read already shipped, but it was locked behind
/// build-time `--dart-define=PRETRIP_DEST_*` values an end driver can never set.
/// This store lets her name the area herself in the app, so the read reaches a
/// daughter deciding whether/when to drive to her mother's snow-zone area — the
/// guard that helps a driver act rightly before a compound-failure trip.
///
/// DIGNITY BOUNDARIES (binding — each holds by construction here):
///   * SUBJECT IS A PLACE, never a person. A [SavedPlace] is lat/lon + a
///     place LABEL the driver types. It carries no person, no whereabouts, no
///     arrival/safety status, no relationship field.
///   * EXACTLY ONE record, OVERWRITE-in-place. [save] writes a single JSON
///     object (`{v,lat,lon,label}`) with [File.writeAsString] (truncating
///     overwrite), NEVER an append. There is NO history, NO behavioral log, NO
///     `savedAt`/`editedAt`, NO counter, NO query log, NO model/ranking feed.
///   * A DELIBERATE removal is DURABLE. [clear] writes a single-record tombstone
///     (`{v,cleared:true}`, truncating overwrite — still no log/history/counter)
///     so a build-time `PRETRIP_DEST_*` seed can NOT resurrect a place the driver
///     removed on the next launch. `cleared` is a state flag, never a behavioral
///     log.
///   * LOCAL CONFIG ONLY. The default file lives under the app-support dir as a
///     plain `saved_place.json`. It is a standalone config file — it does NOT
///     reuse any other on-device database and carries no behavioral log.
///
/// This file is pure `dart:io` at its core; the only `path_provider`/`path`
/// dependency is isolated in [openDefaultSavedPlaceStore].
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'app_support_dir.dart';

/// One destination AREA the driver chose: a geographic POINT plus a readable
/// place LABEL she types. It is a PLACE — never a person, never an arrival or
/// safety status.
class SavedPlace {
  const SavedPlace({
    required this.lat,
    required this.lon,
    required this.label,
  });

  /// WGS84 latitude in [-90, 90].
  final double lat;

  /// WGS84 longitude in [-180, 180].
  final double lon;

  /// A place name the driver typed (may be empty — the name is optional). This
  /// is NEVER seeded with a person or relationship label.
  final String label;

  /// The single persisted shape. Versioned (`v:1`) so a future migration is a
  /// deliberate bump. There is intentionally NO timestamp / counter / history.
  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'lat': lat,
        'lon': lon,
        'label': label,
      };

  /// Parses a decoded JSON map, returning null (the honest floor) on any
  /// missing field, a non-finite number, or an out-of-range coordinate — never
  /// a guessed point.
  static SavedPlace? fromJson(Map<String, Object?> m) {
    final lat = m['lat'];
    final lon = m['lon'];
    final label = m['label'];
    if (lat is! num || lon is! num || label is! String) return null;
    final latD = lat.toDouble();
    final lonD = lon.toDouble();
    if (!latD.isFinite || !lonD.isFinite) return null;
    if (latD < -90 || latD > 90) return null;
    if (lonD < -180 || lonD > 180) return null;
    return SavedPlace(lat: latD, lon: lonD, label: label);
  }
}

/// The outcome of [SavedPlaceStore.load]: either a saved [place], a deliberate
/// [cleared] tombstone (the driver removed the place — a build-time seed must NOT
/// resurrect it), or neither (the store was never written — a seed may bootstrap).
///
/// This is read-state only; it carries NO behavioral log (no timestamp, counter,
/// history, or access record).
class SavedPlaceLoad {
  const SavedPlaceLoad({this.place, this.cleared = false});

  /// The saved place, or null when none is stored.
  final SavedPlace? place;

  /// True when the store holds a deliberate-removal tombstone (distinct from a
  /// never-written store, so the loader can suppress the build-time seed).
  final bool cleared;
}

/// The single-record, overwrite-only store for the chosen destination area.
///
/// Backed by one JSON file. [save] OVERWRITES (never appends); [clear] writes a
/// durable tombstone (so a deliberate removal survives a restart and the
/// build-time seed cannot resurrect it); [load] never throws — a missing / empty
/// / corrupt / non-object file reads as "absent" so the family-thread section
/// simply stays off (honest floor).
class SavedPlaceStore {
  SavedPlaceStore(this._file);

  final File _file;

  /// Reads the store state, never throwing: a saved place, a deliberate-removal
  /// tombstone, or "absent" (missing / empty / corrupt / non-object file).
  Future<SavedPlaceLoad> load() async {
    try {
      if (!await _file.exists()) return const SavedPlaceLoad();
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return const SavedPlaceLoad();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const SavedPlaceLoad();
      // A deliberate-removal tombstone — honored over any build-time seed.
      if (decoded['cleared'] == true) return const SavedPlaceLoad(cleared: true);
      return SavedPlaceLoad(place: SavedPlace.fromJson(decoded));
    } catch (_) {
      // Corrupt / unreadable file ⇒ honest floor: treat as absent.
      return const SavedPlaceLoad();
    }
  }

  /// Writes the ONE record, overwriting in place (a single JSON object, never an
  /// append). Creates the parent directory if needed.
  Future<void> save(SavedPlace p) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(p.toJson()), flush: true);
  }

  /// Records a DURABLE removal: overwrites the single record with a tombstone
  /// (`{v,cleared:true}`) so the deliberate clear survives a restart and a
  /// build-time `PRETRIP_DEST_*` seed cannot resurrect the place. Truncating
  /// overwrite (never an append); no log / history / counter. Idempotent.
  Future<void> clear() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(<String, Object?>{'v': 1, 'cleared': true}),
      flush: true,
    );
  }
}

/// Opens the production store at the app-support dir's
/// `sngnav/saved_place.json`. This is the ONLY place `path_provider`/`path` is
/// used; the rest of the store is pure `dart:io`.
Future<SavedPlaceStore> openDefaultSavedPlaceStore() async {
  // Same platform absence as main(): see app_support_dir.dart.
  final appSupport = await resolveAppSupportDir();
  final file =
      File(p.join(appSupport.directory.path, 'sngnav', 'saved_place.json'));
  return SavedPlaceStore(file);
}
