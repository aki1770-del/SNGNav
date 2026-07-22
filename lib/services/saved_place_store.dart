/// The on-device store for the ONE destination AREA the driver (HER) chooses
/// for the family-thread pre-trip read.
///
/// WHY this exists (mission anchor — D3 worst-case, PHIL-001 Driver Test): the
/// family-thread destination-area read already shipped, but it was locked behind
/// build-time `--dart-define=PRETRIP_DEST_*` values an end driver can never set.
/// This store lets HER name the area herself in the app, so the read reaches a
/// daughter deciding whether/when to drive to her mother's snow-zone area — the
/// loom that helps a driver act rightly before a compound-failure trip.
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
import 'package:path_provider/path_provider.dart';

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

/// The single directory name the store lives under, in every fallback root.
/// Named once so the writability probe and the file path can never drift apart
/// — the drift is what let a parent-probe pass while the real target failed.
const String _storeDirName = 'sngnav';

/// Whether [dir] can be created AND actually written to.
///
/// `Directory.createSync(recursive: true)` is NOT a writability test, and using
/// it as one is why the fallback chain below silently picked a directory it
/// could not write. On a directory that ALREADY EXISTS but is not writable —
/// the locked ARM-IVI rootfs this fallback exists for — `createSync` returns
/// normally, so the `catch` labelled "not writable" never fires, the loop
/// accepts the bad candidate and `break`s, and the systemTemp fallback below it
/// becomes unreachable. The throw then surfaces at `writeAsString` time — after
/// the driver has already entered her destination area.
///
/// Measured 2026-07-22 (`dart run`, existing dir at chmod 500):
/// `createSync(recursive: true)` → returned normally; the subsequent
/// `writeAsStringSync` → threw `PathAccessException`.
///
/// So probe with a real write, and remove the probe file afterwards.
///
/// HONEST BOUNDS — what this probe does NOT promise:
///  * Cleanup is NOT crash-safe. A kill between the write and the `finally`
///    strands one 1-byte dotfile. The name is pid-suffixed, so the residue is
///    bounded by the pid space and a later run with the same pid overwrites
///    rather than adds — but it is residue, and calling it crash-safe would be
///    a claim we have not earned.
///  * It answers only for [dir] itself. Callers must probe the directory they
///    will actually WRITE, not its parent — see [_storeDirName] and the loop in
///    [openDefaultSavedPlaceStore], where probing the parent was exactly the
///    defect this function was introduced to remove.
///  * It is a point-in-time answer. A directory writable at boot can be
///    remounted read-only afterwards; nothing here detects that later.
bool isDirectoryWritable(Directory dir) {
  File? probe;
  try {
    dir.createSync(recursive: true);
    probe = File(
      p.join(dir.path, '.sngnav-write-probe-$pid'),
    );
    probe.writeAsStringSync('w', flush: true);
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      if (probe != null && probe.existsSync()) probe.deleteSync();
    } catch (_) {
      // Best-effort cleanup: a probe we could write but not delete still
      // proves the directory is writable, which is the question asked.
    }
  }
}

/// Opens the production store at the app-support dir's
/// `sngnav/saved_place.json`. This is the ONLY place `path_provider`/`path` is
/// used; the rest of the store is pure `dart:io`.
///
/// [debugEnvOverride] is a TEST SEAM ONLY; production passes nothing and reads
/// the real environment. It exists because the fallback chain keys off `HOME`,
/// and under `flutter test` the real `HOME` is always writable — which makes
/// the fall-through branch (a candidate REJECTED, the next one taken) the one
/// branch no test could reach. That branch is the whole point of the chain, so
/// leaving it unreachable is how a probe defect survives a green suite. Same
/// reason and shape as `debugMbtilesEnvOverride` in main.dart.
Future<SavedPlaceStore> openDefaultSavedPlaceStore({
  Map<String, String>? debugEnvOverride,
}) async {
  Directory appDir;
  try {
    if (debugEnvOverride != null) {
      // A test is exercising the fallback chain; do not consult the host's
      // real path_provider, whose answer would bypass the chain entirely.
      throw const FileSystemException('debugEnvOverride: forcing fallback');
    }
    appDir = await getApplicationSupportDirectory();
  } catch (_) {
    // Embedder without a path_provider registrant (e.g. ivi-homescreen on the
    // ARM-IVI head unit): fall back to a writable app-data dir so saved places
    // still persist on target instead of throwing MissingPluginException. Try
    // HOME first, then systemTemp — and if NEITHER is actually writable (a
    // locked rootfs), land on systemTemp itself as the last resort.
    //
    // Writability is probed with a real write ([isDirectoryWritable]), never
    // with `createSync` alone — see that function for why.
    final env = debugEnvOverride ?? Platform.environment;
    final home = env['HOME'];
    final candidates = <Directory>[
      if (home != null && home.isNotEmpty)
        Directory(p.join(home, '.local', 'share')),
      Directory(p.join(Directory.systemTemp.path, 'sngnav-data')),
    ];
    Directory? chosen;
    for (final c in candidates) {
      // Probe the directory the store ACTUALLY writes into — `<candidate>/
      // sngnav` — never its parent. A writable parent holding an unwritable
      // (or file-occupied) `sngnav` passes a parent-probe and then throws at
      // save() time: the very late failure this probe exists to prevent,
      // reachable one level down. Measured 2026-07-22: with `sngnav` present
      // at chmod 500, probing the PARENT returned true while the real write
      // threw PathAccessException.
      if (isDirectoryWritable(Directory(p.join(c.path, _storeDirName)))) {
        chosen = c;
        break;
      }
    }
    // Last resort, deliberately UNPROBED: if neither candidate is writable
    // there is nowhere further to fall back to, so probing this would only
    // tell us we are stuck. Persistence is best-effort by contract — both
    // callers wrap save()/clear() in try/catch so a failure here costs the
    // driver her saved area across a restart, never the read in front of her.
    appDir = chosen ?? Directory.systemTemp;
  }
  final file = File(p.join(appDir.path, _storeDirName, 'saved_place.json'));
  return SavedPlaceStore(file);
}
