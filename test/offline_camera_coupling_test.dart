import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbtiles/mbtiles.dart';

import 'package:sngnav_snow_scene/main.dart';

/// SDE — the loom that couples the entrypoint's camera to the archive it ships.
///
/// ## Why this file exists
///
/// Before it, `test/entrypoint_smoke_test.dart` was the only test that pumped
/// `main.dart`. It asserts a title and the word "Initializing" — **it would pass
/// unchanged with a tileset from any continent.** Nothing anywhere in the tree
/// compared the camera the app opens at with the bounds of the archive it just
/// loaded.
///
/// On 2026-08-29 that gap reached an ARM IVI target: with the Akita archive
/// installed, the badge read a green `OFFLINE MAP` and the status line read
/// `Offline — MBTiles loaded (15.6 MB)` over a blank grey rectangle. The archive
/// was fine. The camera was 580 km away, and the badge was measuring FILE
/// PRESENCE and reporting MAP PRESENCE.
///
/// ## What makes this a loom and not a decoration
///
/// The first test opens an archive that does NOT cover the app's fallback
/// camera and demands the badge say so. Against the entrypoint as it stood on
/// 2026-08-29 that test FAILS: the badge reads `OFFLINE MAP` because the file
/// exists. Three states are exercised in one file — no archive, an archive that
/// does not cover here, an archive that does — so a badge that always returned
/// one answer could not pass.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('offline_camera_coupling');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester, {String? mbtilesPath}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: OfflineMapPage(mbtilesPath: mbtilesPath),
      ),
    );
    // Let the async archive open + camera derivation settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('the badge must distinguish four states, not two', () {
    testWidgets('NO ARCHIVE  ->  "NO OFFLINE MAP"', (tester) async {
      await pumpPage(tester, mbtilesPath: '${tmp.path}/absent.mbtiles');

      expect(find.text('NO OFFLINE MAP'), findsOneWidget);
      expect(find.text('OFFLINE MAP'), findsNothing);
      expect(find.textContaining('No MBTiles file at'), findsOneWidget);
    });

    testWidgets(
      'ARCHIVE THAT DECLARES COVERAGE IT DOES NOT HOLD  ->  "MAP: NOT HERE"',
      (tester) async {
        // A truncated or half-written archive: the metadata table is intact and
        // claims the whole Akita extent, and there is not one tile behind it.
        // This is the state a file check cannot see — the file exists, opens,
        // and reports a size — and it is the state that put a green
        // "OFFLINE MAP" badge over a blank grey rectangle on the IVI target.
        final hollow = _writeArchive(
          tmp,
          'hollow.mbtiles',
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
          tileZooms: const [], // <- declares everything, holds nothing
        );

        await pumpPage(tester, mbtilesPath: hollow);

        // THE ASSERTION THAT FAILS AGAINST THE 2026-08-29 ENTRYPOINT.
        // A badge driven by `File.existsSync()` says `OFFLINE MAP` here.
        expect(
          find.text('OFFLINE MAP'),
          findsNothing,
          reason: 'an archive that holds no tile for the current view must '
              'never read as a usable offline map',
        );
        expect(find.text('MAP: NOT HERE'), findsOneWidget);
        expect(
          find.textContaining('holds no tiles for this view'),
          findsOneWidget,
          reason: 'and the status line must say what the badge means',
        );
      },
    );

    testWidgets(
      'LIVE: panning off the covered area flips the badge to "MAP: NOT HERE"',
      (tester) async {
        // The badge must answer "is there a map HERE", continuously — not "was
        // there a map where we started". This is the state HER reaches by
        // driving out of the covered corridor.
        final oneTile = _writeArchive(
          tmp,
          'one_tile.mbtiles',
          bounds: const MbTilesBounds(
            left: 139.4,
            bottom: 38.7,
            right: 141.2,
            top: 40.8,
          ),
          center: const LatLng(39.72, 140.10),
          centerZoom: 11,
          minZoom: 11,
          maxZoom: 11,
          tileZooms: const [11], // exactly one tile, at the archive centre
        );

        await pumpPage(tester, mbtilesPath: oneTile);
        expect(
          find.text('OFFLINE MAP'),
          findsOneWidget,
          reason: 'positive control: we start on the one covered tile',
        );

        // A short pan: the covered tile is still partly on screen, so the
        // honest answer is PARTIAL, not "NOT HERE". Claiming "NOT HERE" while
        // a third of the screen is a real map would be its own false alarm,
        // and a false alarm she learns to ignore is worse than no badge.
        await tester.drag(find.byType(FlutterMap), const Offset(-400, 0));
        await tester.pump();
        expect(
          find.text('OFFLINE MAP'),
          findsNothing,
          reason: 'the badge must follow the driver, not the startup camera',
        );
        expect(find.text('MAP: PARTIAL'), findsOneWidget);

        // Keep going until the covered tile is far behind: now nothing on
        // screen comes from the archive, and the badge must say so.
        await tester.drag(find.byType(FlutterMap), const Offset(-3000, 0));
        await tester.pump();
        expect(find.text('MAP: NOT HERE'), findsOneWidget);
        expect(find.text('OFFLINE MAP'), findsNothing);
        expect(find.text('MAP: PARTIAL'), findsNothing);
      },
    );

    testWidgets('ARCHIVE COVERS HERE  ->  "OFFLINE MAP"', (tester) async {
      // Built at the app's own fallback camera, so coverage is real.
      final here = _writeArchive(
        tmp,
        'here.mbtiles',
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

      await pumpPage(tester, mbtilesPath: here);

      expect(
        find.text('OFFLINE MAP'),
        findsOneWidget,
        reason: 'positive control: a covering archive MUST read as a usable '
            'offline map, or the assertion above proves nothing',
      );
      expect(find.text('NO OFFLINE MAP'), findsNothing);
    });
  });

  group('R1 — the prefetch ring must not take down the whole tile layer', () {
    testWidgets(
      'no tile in the pan buffer throws when the archive does not hold it',
      (tester) async {
        // ROOT CAUSE, root-caused by EIE from the on-target journal 2026-08-29:
        //
        //   Invalid argument(s): 'wmsOptions' or 'urlTemplate' must be provided
        //     NetworkTileProvider.getTileUrl
        //     <- OfflineTileProvider._providerForResolution
        //     <- TileImageManager.reloadImages
        //
        // The entrypoint passes `urlTemplate: null` whenever an offline manager
        // exists, and `allowOnlineFallback` defaulted to TRUE — so any tile the
        // archive lacked resolved to RuntimeTileSource.online, reached
        // NetworkTileProvider with no template, and threw. Confirmed in
        // flutter_map 8.2.2 at
        // `tile_provider/base_tile_provider.dart:233-237`, where the null
        // template is `(throw ArgumentError(...))`.
        //
        // ⚑ EIE's enumeration is the point: 0 of the VISIBLE tiles took that
        // branch and 18 tiles in the panBuffer ring did. The map was blank
        // because of eighteen tiles nobody could see. One throw in the ring
        // takes down the layer.
        //
        // An archive holding exactly one tile guarantees the ring misses.
        final oneTile = _writeArchive(
          tmp,
          'ring.mbtiles',
          bounds: const MbTilesBounds(
            left: 139.4,
            bottom: 38.7,
            right: 141.2,
            top: 40.8,
          ),
          center: const LatLng(39.72, 140.10),
          centerZoom: 11,
          minZoom: 11,
          maxZoom: 11,
          tileZooms: const [11],
        );

        await pumpPage(tester, mbtilesPath: oneTile);
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          tester.takeException(),
          isNull,
          reason: 'an uncovered tile must resolve to a transparent placeholder, '
              'never to a NetworkTileProvider with no urlTemplate',
        );
      },
    );
  });

  group('the camera the entrypoint opens at is the archive\'s own', () {
    testWidgets('a far-away archive moves the camera into its own bounds', (
      tester,
    ) async {
      final akita = _writeArchive(
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

      await pumpPage(tester, mbtilesPath: akita);

      final camera = _liveCamera(tester);
      expect(
        camera.center.latitude,
        closeTo(39.72, 0.05),
        reason: 'the camera must sit inside the archive it opened',
      );
      expect(camera.center.longitude, closeTo(140.10, 0.05));
    });

    testWidgets(
      'the SHIPPED archive still opens exactly where it always did',
      (tester) async {
        // D4: an edge developer following data/README.md today must see the
        // same first screen after this change as before it.
        await pumpPage(tester, mbtilesPath: 'data/offline_tiles.mbtiles');

        final camera = _liveCamera(tester);
        expect(camera.center.latitude, closeTo(35.1709, 1e-4));
        expect(camera.center.longitude, closeTo(136.8815, 1e-4));
        expect(camera.zoom, closeTo(11, 1e-6));
      },
      // testWidgets' `skip` is bool?, not Object? — no reason string here.
      skip: !File('data/offline_tiles.mbtiles').existsSync(),
    );
  });

  group('the camera may not travel where the archive is blank', () {
    testWidgets('minZoom is raised to the archive floor', (tester) async {
      final akita = _writeArchive(
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

      await pumpPage(tester, mbtilesPath: akita);

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.options.minZoom,
        8.0,
        reason: 'below the archive floor the resolver finds nothing and the '
            'map goes blank — the camera must not be allowed there',
      );
    });
  });
}

/// The camera as the map is ACTUALLY showing it, not the `initialCenter` the
/// options were first built with. `initialCenter` is read once; a camera that
/// resolves after the archive opens has to be read from the live map state.
MapCamera _liveCamera(WidgetTester tester) {
  final mapContext = tester.element(
    find.descendant(
      of: find.byType(FlutterMap),
      matching: find.byType(TileLayer),
    ),
  );
  return MapCamera.of(mapContext);
}

/// Writes a real MBTiles file with one tile at the centre for each of
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
  LatLng? alsoTileAt,
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
  for (final point in <LatLng>{center, ?alsoTileAt}) {
    for (final z in tileZooms) {
      final coords = _tileFor(point, z);
      archive.putTile(
        z: z,
        x: coords.$1,
        // MBTiles stores rows TMS-flipped; RuntimeTileResolver flips back.
        y: ((1 << z) - 1) - coords.$2,
        bytes: Uint8List.fromList(TileProvider.transparentImage),
      );
    }
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
