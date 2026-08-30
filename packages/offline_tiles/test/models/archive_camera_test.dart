import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:offline_tiles/offline_tiles.dart';

/// ArchiveCamera — the loom that couples a host app's camera to the archive it
/// actually ships.
///
/// ## The defect this exists to catch, in one sentence
///
/// On 2026-08-29 an ARM IVI target showed a green "OFFLINE MAP" badge over a
/// blank grey rectangle: the app's hardcoded camera was 580 km outside the
/// bounds of the archive it had just loaded, and nothing in the codebase
/// compared the two.
///
/// The first group below is the RED case, kept permanently: it asserts that the
/// legacy hardcoded camera resolves to NOTHING against a far-away archive. If
/// someone deletes ArchiveCamera and goes back to a constant, that group still
/// documents exactly what breaks.
void main() {
  // The camera SNGNav's entrypoint hardcoded before this loom existed.
  const legacyCenter = LatLng(35.1709, 136.8815); // Nagoya Station
  const legacyZoom = 11.0;
  const legacyMinZoom = 6.0;
  const legacyMaxZoom = 16.0;

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('archive_camera_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('the defect: a hardcoded camera against a far-away archive', () {
    test(
      'legacy Nagoya camera resolves to NO archive tile on an Akita archive',
      () {
        final path = _writeArchive(
          tmp,
          'akita.mbtiles',
          // Measured from the real shipped Akita archive, 2026-08-29:
          //   bounds = 139.40000,38.70000,141.20000,40.80000
          //   center = 140.10000,39.72000,11
          //   minzoom = 8   maxzoom = 13
          bounds: const MbTilesBounds(
            left: 139.4,
            bottom: 38.7,
            right: 141.2,
            top: 40.8,
          ),
          center: const LatLng(39.72, 140.10),
          centerZoom: 11,
          minZoom: 8,
          maxZoom: 13,
          tileZooms: const [8, 9, 10, 11, 12, 13],
        );

        final manager = OfflineTileManager(
          tileSource: TileSourceType.mbtiles,
          mbtilesPath: path,
        );
        addTearDown(manager.dispose);

        // POSITIVE CONTROL — the instrument must be able to say "covered".
        // Without this, a resolver that returned false for everything would
        // make the negative assertion below meaningless (CLAUDE.md §0: if the
        // method could not have surfaced a counter-example, it measured
        // nothing).
        expect(
          manager.hasLocalCoverageForPoint(
            const LatLng(39.72, 140.10),
            zoom: 11,
          ),
          isTrue,
          reason: 'positive control: the archive centre must be covered',
        );

        // THE DEFECT. Every zoom the legacy camera allowed, at the legacy
        // centre, finds nothing at all.
        for (var z = legacyMinZoom.toInt(); z <= legacyMaxZoom.toInt(); z++) {
          expect(
            manager.hasLocalCoverageForPoint(legacyCenter, zoom: z),
            isFalse,
            reason: 'legacy camera at z$z must find no Akita tile',
          );
        }
      },
    );

    test('the derived camera IS covered by the same archive', () {
      final path = _writeArchive(
        tmp,
        'akita.mbtiles',
        bounds: const MbTilesBounds(
          left: 139.4,
          bottom: 38.7,
          right: 141.2,
          top: 40.8,
        ),
        center: const LatLng(39.72, 140.10),
        centerZoom: 11,
        minZoom: 8,
        maxZoom: 13,
        tileZooms: const [8, 9, 10, 11, 12, 13],
      );

      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final camera = manager.archiveCamera(
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );

      expect(camera.derivedFromArchive, isTrue);
      expect(
        manager.hasLocalCoverageForPoint(
          camera.center,
          zoom: camera.zoom.round(),
        ),
        isTrue,
        reason: 'the camera derived from the archive must be inside it',
      );

      // Every zoom the derived camera ALLOWS must be a zoom the archive can
      // serve at the derived centre. This is the property the badge depends on.
      for (
        var z = camera.minZoom.toInt();
        z <= camera.maxZoom.toInt();
        z++
      ) {
        expect(
          manager.hasLocalCoverageForPoint(camera.center, zoom: z),
          isTrue,
          reason: 'derived camera allows z$z, so z$z must resolve',
        );
      }
    });
  });

  group('the zoom floor is a blankness boundary; the ceiling is not', () {
    test('minZoom is RAISED to the archive floor, never left below it', () {
      final path = _writeArchive(
        tmp,
        'floor.mbtiles',
        bounds: const MbTilesBounds(
          left: 139.4,
          bottom: 38.7,
          right: 141.2,
          top: 40.8,
        ),
        center: const LatLng(39.72, 140.10),
        centerZoom: 11,
        minZoom: 8,
        maxZoom: 13,
        tileZooms: const [8, 9, 10, 11, 12, 13],
      );
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final camera = manager.archiveCamera(
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: 6, // the caller asks for a floor the archive lacks
        fallbackMaxZoom: legacyMaxZoom,
      );

      expect(camera.minZoom, 8.0);

      // And the reason: below the floor the resolver's downward walk finds
      // nothing, even at the archive's own centre.
      expect(
        manager.hasLocalCoverageForPoint(camera.center, zoom: 7),
        isFalse,
        reason: 'z7 is below the archive floor and must be blank',
      );
      expect(
        manager.hasLocalCoverageForPoint(camera.center, zoom: 6),
        isFalse,
        reason: 'z6 is below the archive floor and must be blank',
      );
    });

    test('maxZoom is never LOWERED below what the caller asked for', () {
      final path = _writeArchive(
        tmp,
        'ceiling.mbtiles',
        bounds: const MbTilesBounds(
          left: 136.70,
          bottom: 35.00,
          right: 137.05,
          top: 35.32,
        ),
        center: const LatLng(35.1709, 136.8815),
        centerZoom: 11,
        minZoom: 10,
        maxZoom: 12,
        tileZooms: const [10, 11, 12],
      );
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final camera = manager.archiveCamera(
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: 16, // above the archive's 12
      );

      expect(
        camera.maxZoom,
        16.0,
        reason: 'above the archive ceiling the resolver upscales a parent '
            'tile — blurry, never blank — so the ceiling must not be lowered',
      );
      // And that is true, not merely asserted:
      expect(
        manager.hasLocalCoverageForPoint(camera.center, zoom: 16),
        isTrue,
        reason: 'z16 must still resolve via the lower-zoom walk',
      );
    });

    test('maxZoom is RAISED when the archive holds more than the caller asked',
        () {
      final path = _writeArchive(
        tmp,
        'deep.mbtiles',
        bounds: const MbTilesBounds(
          left: 139.4,
          bottom: 38.7,
          right: 141.2,
          top: 40.8,
        ),
        center: const LatLng(39.72, 140.10),
        centerZoom: 11,
        minZoom: 8,
        maxZoom: 15,
        tileZooms: const [8, 15],
      );
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: path,
      );
      addTearDown(manager.dispose);

      final camera = manager.archiveCamera(
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: 13, // caller asks for less than the archive holds
      );
      expect(camera.maxZoom, 15.0);
    });
  });

  group('no archive, or a silent one, degrades to the caller and says so', () {
    test('null metadata returns the caller values unchanged', () {
      final camera = ArchiveCamera.resolve(
        metadata: null,
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );
      expect(camera.center, legacyCenter);
      expect(camera.zoom, legacyZoom);
      expect(camera.minZoom, legacyMinZoom);
      expect(camera.maxZoom, legacyMaxZoom);
      expect(camera.bounds, isNull);
      expect(
        camera.derivedFromArchive,
        isFalse,
        reason: 'a fallback camera is a guess; the host must be able to say so',
      );
    });

    test('a manager with no archive reports no metadata and no camera derivation',
        () {
      final manager = OfflineTileManager(
        tileSource: TileSourceType.mbtiles,
        mbtilesPath: '${tmp.path}/does_not_exist.mbtiles',
      );
      addTearDown(manager.dispose);

      expect(manager.hasOfflineArchive, isFalse);
      expect(manager.archiveMetadata, isNull);
      expect(
        manager
            .archiveCamera(
              fallbackCenter: legacyCenter,
              fallbackZoom: legacyZoom,
              fallbackMinZoom: legacyMinZoom,
              fallbackMaxZoom: legacyMaxZoom,
            )
            .derivedFromArchive,
        isFalse,
      );
    });

    test('metadata with no bounds/center/zoom leaves every field alone', () {
      const bare = MbTilesMetadata(name: 'bare', format: 'png');
      final camera = ArchiveCamera.resolve(
        metadata: bare,
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );
      expect(camera.center, legacyCenter);
      expect(camera.zoom, legacyZoom);
      expect(camera.minZoom, legacyMinZoom);
      expect(camera.maxZoom, legacyMaxZoom);
      expect(camera.derivedFromArchive, isFalse);
    });
  });

  group('a malformed archive cannot produce a malformed camera', () {
    test('NaN and infinite metadata are rejected, not propagated', () {
      final camera = ArchiveCamera.resolve(
        metadata: MbTilesMetadata(
          name: 'broken',
          format: 'png',
          defaultCenter: const LatLng(double.nan, double.infinity),
          defaultZoom: double.nan,
          minZoom: double.negativeInfinity,
          maxZoom: double.nan,
        ),
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );
      expect(camera.center.latitude.isFinite, isTrue);
      expect(camera.center.longitude.isFinite, isTrue);
      expect(camera.zoom.isFinite, isTrue);
      expect(camera.minZoom.isFinite, isTrue);
      expect(camera.maxZoom.isFinite, isTrue);
      expect(camera.center, legacyCenter);
      expect(camera.zoom, legacyZoom);
    });

    test('an inverted zoom range is widened, not inverted', () {
      final camera = ArchiveCamera.resolve(
        metadata: const MbTilesMetadata(
          name: 'inverted',
          format: 'png',
          minZoom: 14,
          maxZoom: 4,
        ),
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );
      expect(camera.minZoom <= camera.maxZoom, isTrue);
      expect(camera.zoom >= camera.minZoom, isTrue);
      expect(camera.zoom <= camera.maxZoom, isTrue);
    });

    test('a centre outside the archive bounds loses to the bounds', () {
      final camera = ArchiveCamera.resolve(
        metadata: const MbTilesMetadata(
          name: 'contradictory',
          format: 'png',
          bounds: MbTilesBounds(
            left: 139.4,
            bottom: 38.7,
            right: 141.2,
            top: 40.8,
          ),
          // Declares Nagoya as the default view of an Akita archive.
          defaultCenter: LatLng(35.1709, 136.8815),
          defaultZoom: 11,
          minZoom: 8,
          maxZoom: 13,
        ),
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );
      expect(camera.bounds, isNotNull);
      expect(
        camera.bounds!.contains(camera.center),
        isTrue,
        reason: 'the bounds are the claim about where tiles exist; a declared '
            'centre outside them is a broken archive and must not be trusted',
      );
      expect(camera.center.latitude, closeTo(39.75, 0.01));
      expect(camera.center.longitude, closeTo(140.30, 0.01));
    });

    test('a latitude beyond the Web-Mercator domain is clamped', () {
      final camera = ArchiveCamera.resolve(
        metadata: const MbTilesMetadata(
          name: 'polar',
          format: 'png',
          defaultCenter: LatLng(89.9, 200.0),
          defaultZoom: 5,
        ),
        fallbackCenter: legacyCenter,
        fallbackZoom: legacyZoom,
        fallbackMinZoom: legacyMinZoom,
        fallbackMaxZoom: legacyMaxZoom,
      );
      expect(camera.center.latitude, lessThanOrEqualTo(85.06));
      expect(camera.center.longitude, lessThanOrEqualTo(180.0));
    });
  });

  group('the archive SNGNav actually ships', () {
    // Path is relative to the package under test, so it holds wherever the
    // monorepo is checked out.
    final shipped = File('../../data/offline_tiles.mbtiles');

    test(
      'the derived camera resolves to a real tile in the shipped archive',
      () {
        final manager = OfflineTileManager(
          tileSource: TileSourceType.mbtiles,
          mbtilesPath: shipped.path,
        );
        addTearDown(manager.dispose);

        expect(
          manager.hasOfflineArchive,
          isTrue,
          reason: 'the shipped archive must open',
        );

        final camera = manager.archiveCamera(
          fallbackCenter: legacyCenter,
          fallbackZoom: legacyZoom,
          fallbackMinZoom: legacyMinZoom,
          fallbackMaxZoom: legacyMaxZoom,
        );

        for (
          var z = camera.minZoom.toInt();
          z <= camera.maxZoom.toInt();
          z++
        ) {
          expect(
            manager.hasLocalCoverageForPoint(camera.center, zoom: z),
            isTrue,
            reason: 'shipped archive must serve its own camera at z$z',
          );
        }
      },
      skip: shipped.existsSync()
          ? false
          : 'data/offline_tiles.mbtiles not present in this checkout',
    );

    test(
      'the shipped archive declares the same centre the app hardcoded — so '
      'adopting ArchiveCamera does not move the documented demo',
      () {
        final manager = OfflineTileManager(
          tileSource: TileSourceType.mbtiles,
          mbtilesPath: shipped.path,
        );
        addTearDown(manager.dispose);

        final camera = manager.archiveCamera(
          fallbackCenter: legacyCenter,
          fallbackZoom: legacyZoom,
          fallbackMinZoom: legacyMinZoom,
          fallbackMaxZoom: legacyMaxZoom,
        );

        expect(camera.center.latitude, closeTo(legacyCenter.latitude, 1e-6));
        expect(camera.center.longitude, closeTo(legacyCenter.longitude, 1e-6));
        expect(camera.zoom, closeTo(legacyZoom, 1e-6));
        expect(camera.maxZoom, closeTo(legacyMaxZoom, 1e-6));

        // NOT a no-op, and deliberately so: the floor rises to the archive's
        // own minzoom. Below it the shipped demo has ALWAYS rendered blank.
        expect(
          camera.minZoom,
          greaterThan(legacyMinZoom),
          reason: 'the floor is the one field this change moves, on purpose',
        );
        expect(
          manager.hasLocalCoverageForPoint(
            camera.center,
            zoom: legacyMinZoom.toInt(),
          ),
          isFalse,
          reason: 'the floor the app used to allow was already blank',
        );
      },
      skip: shipped.existsSync()
          ? false
          : 'data/offline_tiles.mbtiles not present in this checkout',
    );
  });
}

/// Writes a real MBTiles file with one tile at the archive centre for each of
/// [tileZooms], so coverage questions have a truthful answer.
String _writeArchive(
  Directory dir,
  String name, {
  required MbTilesBounds bounds,
  required LatLng center,
  required double centerZoom,
  required double minZoom,
  required double maxZoom,
  required List<int> tileZooms,
}) {
  final path = '${dir.path}/$name';
  final archive = MbTiles.create(
    path: path,
    metadata: MbTilesMetadata(
      name: name,
      format: 'png',
      bounds: bounds,
      defaultCenter: center,
      defaultZoom: centerZoom,
      minZoom: minZoom,
      maxZoom: maxZoom,
    ),
  );
  for (final z in tileZooms) {
    final coords = _tileFor(center, z);
    archive.putTile(
      z: z,
      x: coords.$1,
      // MBTiles stores rows TMS-flipped; RuntimeTileResolver flips back.
      y: ((1 << z) - 1) - coords.$2,
      bytes: Uint8List.fromList(TileProvider.transparentImage),
    );
  }
  archive.close();
  return path;
}

/// Slippy-map tile containing [point] at [zoom] — the same arithmetic
/// OfflineTileManager uses internally.
(int, int) _tileFor(LatLng point, int zoom) {
  final n = 1 << zoom;
  final x = ((point.longitude + 180.0) / 360.0 * n).floor();
  final latRad = point.latitude * math.pi / 180.0;
  final y =
      ((1.0 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2.0 *
              n)
          .floor();
  return (x.clamp(0, n - 1), y.clamp(0, n - 1));
}
