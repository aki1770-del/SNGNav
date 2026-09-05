/// REACH tests: the ROUTE BRIDGE caution on the shipped [PretripScreen].
///
/// The claim under test: when a REAL route delivered AND ≥ 1 mapped bridge
/// cluster lies on it AND the departure window is cold enough to matter, the driver
/// sees ONE honest, approximate line — この先、秋田県内の経路上に橋が約Nか所あります。橋は
/// 路面より先に凍結します。 — and in EVERY other arm (no route, zero clusters,
/// off-season with warm-or-no evidence) the section is simply ABSENT: no
/// error banner, no substitute claim, never an all-clear. In season (the
/// month band) a warm POINT reading never suppresses it — the decks are
/// elsewhere on the route.
///
/// The resolve contract is ONE-SHOT PER DESTINATION EPOCH: setting a NEW
/// destination clears the stale count IMMEDIATELY and fires exactly ONE
/// fresh resolve for the new epoch; clearing the destination clears and
/// fires NONE; a late result from a superseded epoch is dropped, never
/// rendered beside the new destination ((g)/(h)/(i) below).
///
/// Network IO is injected: the live briefing forecast via
/// [PretripScreen.metForecastFetchOverride], the route+asset resolve via
/// [PretripScreen.routeBridgesOverride] (which here runs the REAL
/// `resolvePretripRouteBridges` pipeline over fake shape + fake CSV, so the
/// corridor math is exercised, not stubbed), the season-band clock via
/// [PretripScreen.bridgeGateNowOverride]. No socket, no `--dart-define`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
import 'package:sngnav_snow_scene/providers/pretrip_route_bridges.dart';
import 'package:sngnav_snow_scene/services/bridge_corridor_read.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_screen.dart';

const _cautionKey = Key('pretrip-bridge-corridor-caution');

/// A ~2.2 km due-north route in Akita.
final List<LatLng> _route = [
  const LatLng(39.72000, 140.10000),
  const LatLng(39.74000, 140.10000),
];

/// Two on-route sites ~1.1 km apart, bearing-parallel ⇒ 2 clusters.
const String _csvTwoBridges =
    'way_id,lat,lon,bearing_deg\n'
    '1,39.72500,140.10000,0\n'
    '2,39.73500,140.10000,0\n';

/// Three on-route sites ~550 m apart (> the 120 m cluster radius) ⇒ 3
/// clusters. A DIFFERENT count from [_csvTwoBridges], so test (i) can tell
/// the NEW epoch's landed result (約3) apart from a resurrected stale one
/// (約2).
const String _csvThreeBridges =
    'way_id,lat,lon,bearing_deg\n'
    '1,39.72500,140.10000,0\n'
    '2,39.73000,140.10000,0\n'
    '3,39.73500,140.10000,0\n';

/// Sites BRACKETING the route (inside the data's coverage extent) but
/// kilometres off the 30 m corridor ⇒ a real resolve with clusterCount 0.
const String _csvFarBridge =
    'way_id,lat,lon,bearing_deg\n'
    '8,39.71000,140.05000,0\n'
    '9,39.75000,140.15000,0\n';

/// A live forecast covering "now" (the live departure) at [temp] °C.
WeatherForecast _cannedLive(double temp) {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(hour: base, tempCelsius: temp),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: temp,
      ),
    ],
  );
}

/// A fully OFFLINE fake DEST-AREA forecast provider (the dest_refetch_test
/// idiom): returns a canned forecast, optionally HELD on [gate] so a test can
/// land the read late — after the driver destination changed — and prove the stale
/// forecast is dropped, not fed into the bridge caution's cold gate.
class _GatedMetProvider extends MetNorwayHourlyForecastProvider {
  _GatedMetProvider(this._forecast, [this._gate]);

  final WeatherForecast _forecast;
  final Future<void>? _gate;

  @override
  Future<WeatherForecast?> fetchForecast({
    required double latitude,
    required double longitude,
  }) async {
    final gate = _gate;
    if (gate != null) await gate;
    return _forecast;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  /// Turns the real event loop (store File I/O, injected futures) and flushes
  /// the resulting fake-zone continuations + rebuilds (the dest_refetch_test
  /// idiom).
  Future<void> flush(WidgetTester tester, [int cycles = 12]) async {
    for (var i = 0; i < cycles; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }
    final ex = tester.takeException();
    if (ex != null && ex is! MissingPluginException) throw ex as Object;
  }

  /// Pumps the shipped [PretripScreen] (ja locale — the surface the driver sees) with
  /// injected bridge resolve / live forecast / season clock, and flushes the
  /// one-shot inits on the real event loop. [savedPlace] pre-seeds the store
  /// (a destination SHE saved on a prior run). Pass EITHER [routeBridges]
  /// (whole-resolve stub) OR the production-arm seams
  /// ([routeShapeFetch]/[csvLoad]/[osrmUrl]) — the latter run the REAL gate +
  /// saved-place + coordinate-threading wiring.
  Future<void> pumpBridge(
    WidgetTester tester, {
    Future<BridgeCorridorResult?> Function()? routeBridges,
    Future<List<LatLng>> Function({
      required double originLat,
      required double originLon,
      required double destLat,
      required double destLon,
    })?
    routeShapeFetch,
    Future<String> Function()? csvLoad,
    String? osrmUrl,
    Future<WeatherForecast?> Function()? metFetch,
    MetNorwayHourlyForecastProvider Function()? destForecastFactory,
    String? forecastSource,
    DateTime? gateNow,
    SavedPlace? savedPlace,
  }) async {
    late Directory tmp;
    late SavedPlaceStore store;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('bridge_caution_test');
      store = SavedPlaceStore(File('${tmp.path}/sngnav/saved_place.json'));
      if (savedPlace != null) await store.save(savedPlace);
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Scaffold(
          body: PretripScreen(
            savedPlaceStore: store,
            metForecastFetchOverride: metFetch,
            destForecastProviderFactory: destForecastFactory,
            forecastSourceOverride: forecastSource,
            routeBridgesOverride: routeBridges,
            routeShapeFetchOverride: routeShapeFetch,
            bridgeCsvLoadOverride: csvLoad,
            routeOsrmUrlOverride: osrmUrl,
            bridgeGateNowOverride: gateNow,
            surfaceState: RoadSurfaceState.compactedSnow,
          ),
        ),
      ),
    );
    await tester.pump();
    await flush(tester);
  }

  /// Drives the in-app typed-place entry (the driver-action _setDestination
  /// path) on the ja surface: tile → dialog → coordinates → save.
  Future<void> setPlaceJa(
    WidgetTester tester,
    double lat,
    double lon,
    String label,
  ) async {
    final editIcon = find.byIcon(Icons.edit_outlined).first;
    await tester.ensureVisible(editIcon); // tile may be below the scroll fold
    await tester.pump();
    await tester.tap(editIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // dialog in
    await tester.tap(find.text(BriefingStrings.ja.placeEntryModeCoordinates));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, BriefingStrings.ja.placeEntryLatLabel),
      '$lat',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, BriefingStrings.ja.placeEntryLonLabel),
      '$lon',
    );
    await tester.enterText(
      find.widgetWithText(TextField, BriefingStrings.ja.placeEntryLabelLabel),
      label,
    );
    await tester.pump();
    await tester.tap(find.text(BriefingStrings.ja.placeEntrySave));
    await tester.pump(); // pop + _setDestination begins (awaits File I/O)
    await flush(tester); // dialog pop + store.save complete
    await flush(tester); // re-fetch + setState lands
  }

  testWidgets(
    '(a) route + 2 bridge clusters + FREEZING live window → the driver sees 約2',
    (tester) async {
      await pumpBridge(
        tester,
        routeBridges: () => resolvePretripRouteBridges(
          fetchRouteShape: () async => _route,
          loadBridgeCsv: () async => _csvTwoBridges,
        ),
        metFetch: () async => _cannedLive(-2),
      );

      expect(find.byKey(_cautionKey), findsOneWidget);
      expect(
        find.textContaining('この先、秋田県内の経路上に橋が約2か所あります'),
        findsOneWidget,
        reason: 'the approximate (約) bridge count must reach the driver in Japanese',
      );
      expect(find.textContaining('橋は路面より先に凍結します'), findsOneWidget);
      // ODbL produced-work notice reaches the same surface as the count.
      expect(
        find.textContaining('橋データ © OpenStreetMap contributors'),
        findsOneWidget,
        reason:
            'the pre-trip surface never shows the map tile credit, so the '
            'card must carry its own OSM/ODbL notice',
      );
      // No English leak on the Japanese surface.
      expect(find.textContaining('bridges on your route'), findsNothing);
    },
  );

  testWidgets('(b) NO route (empty shape) → section absent, no substitute', (
    tester,
  ) async {
    await pumpBridge(
      tester,
      routeBridges: () => resolvePretripRouteBridges(
        fetchRouteShape: () async => <LatLng>[],
        loadBridgeCsv: () async => _csvTwoBridges,
      ),
      // January band on purpose: absence must come from the missing route,
      // not from the season gate.
      gateNow: DateTime(2026, 1, 15, 7),
    );

    expect(find.byKey(_cautionKey), findsNothing);
    expect(find.textContaining('経路上に橋が約'), findsNothing);
  });

  testWidgets('(c) route but clusterCount 0 → absent (never an all-clear)', (
    tester,
  ) async {
    await pumpBridge(
      tester,
      routeBridges: () => resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => _csvFarBridge,
      ),
      gateNow: DateTime(2026, 1, 15, 7),
    );

    expect(find.byKey(_cautionKey), findsNothing);
    expect(find.textContaining('経路上に橋が約'), findsNothing);
  });

  testWidgets(
    '(d) WARM live window (+10 °C) + January clock → PRESENT (a warm point '
    'reading is not corridor evidence; the season band is a floor)',
    (tester) async {
      await pumpBridge(
        tester,
        routeBridges: () => resolvePretripRouteBridges(
          fetchRouteShape: () async => _route,
          loadBridgeCsv: () async => _csvTwoBridges,
        ),
        metFetch: () async => _cannedLive(10),
        // The decks are elsewhere on the route: origin warmth must NOT
        // suppress the winter band (the founding under-warn shape — warm
        // coastal kitchen table, frozen inland pass).
        gateNow: DateTime(2026, 1, 15, 7),
      );

      expect(find.byKey(_cautionKey), findsOneWidget);
      expect(find.textContaining('経路上に橋が約'), findsOneWidget);
    },
  );

  testWidgets(
    '(d2) WARM live window (+10 °C) + July clock → absent (warm evidence '
    'plus off-season: quiet)',
    (tester) async {
      await pumpBridge(
        tester,
        routeBridges: () => resolvePretripRouteBridges(
          fetchRouteShape: () async => _route,
          loadBridgeCsv: () async => _csvTwoBridges,
        ),
        metFetch: () async => _cannedLive(10),
        gateNow: DateTime(2026, 7, 15, 7),
      );

      expect(find.byKey(_cautionKey), findsNothing);
      expect(find.textContaining('経路上に橋が約'), findsNothing);
    },
  );

  testWidgets('(e) NO forecast + January → present (compound-failure band)', (
    tester,
  ) async {
    await pumpBridge(
      tester,
      routeBridges: () => resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => _csvTwoBridges,
      ),
      gateNow: DateTime(2026, 1, 15, 7),
    );

    expect(find.byKey(_cautionKey), findsOneWidget);
    expect(find.textContaining('この先、秋田県内の経路上に橋が約2か所あります'), findsOneWidget);
  });

  testWidgets('(f) NO forecast + July → absent', (tester) async {
    await pumpBridge(
      tester,
      routeBridges: () => resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => _csvTwoBridges,
      ),
      gateNow: DateTime(2026, 7, 15, 7),
    );

    expect(find.byKey(_cautionKey), findsNothing);
    expect(find.textContaining('経路上に橋が約'), findsNothing);
  });

  testWidgets(
    '(g) the driver destination change clears the stale count IMMEDIATELY and '
    'fires exactly ONE fresh resolve for the new epoch',
    (tester) async {
      var calls = 0;
      // Holds the SECOND (new-epoch) resolve in flight, so the cleared state is
      // observable BEFORE the fresh result lands.
      final holdSecond = Completer<void>();
      await pumpBridge(
        tester,
        routeBridges: () async {
          calls++;
          if (calls == 2) await holdSecond.future;
          return resolvePretripRouteBridges(
            fetchRouteShape: () async => _route,
            loadBridgeCsv: () async => _csvTwoBridges,
          );
        },
        gateNow: DateTime(2026, 1, 15, 7),
      );
      expect(find.byKey(_cautionKey), findsOneWidget);
      expect(calls, 1);

      // SHE sets a different destination area in the app.
      await setPlaceJa(tester, 39.9, 140.2, 'エリアA');

      // The stale count is gone IMMEDIATELY — the fresh resolve (held above) has
      // not landed yet, so this absence is the CLEAR, not the new result.
      expect(
        find.byKey(_cautionKey),
        findsNothing,
        reason:
            'the old count described the route to the PRIOR destination — '
            'it must clear before the new resolve lands',
      );
      expect(find.textContaining('経路上に橋が約'), findsNothing);
      expect(
        calls,
        2,
        reason: 'exactly ONE fresh resolve fires for the new epoch',
      );
      await flush(tester);
      expect(
        calls,
        2,
        reason:
            'and no further resolve fires — one per epoch, '
            'never a poll',
      );

      // The new epoch's resolve lands: the caution returns, for the driver new route.
      holdSecond.complete();
      await flush(tester);
      expect(
        find.byKey(_cautionKey),
        findsOneWidget,
        reason: 'the fresh resolve for the NEW destination epoch must land',
      );
      expect(find.textContaining('この先、秋田県内の経路上に橋が約2か所あります'), findsOneWidget);
    },
  );

  testWidgets(
    '(h) the driver clearing the destination CLEARS the count and fires ZERO new '
    'resolves (no route ⇒ nothing to resolve)',
    (tester) async {
      var calls = 0;
      // Hold the resolve until the saved-place load has landed, so the result's
      // setState rebuild renders the tile with the clear affordance (the place
      // loader seeds its fields without a rebuild of its own, by design).
      final gate = Completer<void>();
      await pumpBridge(
        tester,
        routeBridges: () async {
          calls++;
          await gate.future;
          return resolvePretripRouteBridges(
            fetchRouteShape: () async => _route,
            loadBridgeCsv: () async => _csvTwoBridges,
          );
        },
        gateNow: DateTime(2026, 1, 15, 7),
        // A saved destination from a prior run, so the tile shows the clear
        // affordance.
        savedPlace: const SavedPlace(lat: 39.9, lon: 140.2, label: 'エリアA'),
      );
      gate.complete();
      await flush(tester);
      expect(find.byKey(_cautionKey), findsOneWidget);

      final clearIcon = find.byIcon(Icons.delete_outline);
      await tester.ensureVisible(clearIcon);
      await tester.pump();
      await tester.tap(clearIcon);
      await tester.pump();
      await flush(tester);

      expect(find.byKey(_cautionKey), findsNothing);
      expect(find.textContaining('経路上に橋が約'), findsNothing);
      expect(
        calls,
        1,
        reason:
            'a clear fires ZERO new resolves — cleared, and the epoch '
            'ends there',
      );
    },
  );

  testWidgets('(i) destination change MID-FLIGHT: the late OLD-epoch result is '
      'dropped, and the NEW epoch\'s own resolve still lands (the OSRM fetch '
      'can be in flight ~15 s)', (tester) async {
    // One gate per epoch's resolve; DIFFERENT counts per epoch (2 vs 3
    // clusters) so a resurrected stale result (約2) cannot masquerade as the
    // new one (約3).
    final gates = [Completer<void>(), Completer<void>()];
    var calls = 0;
    await pumpBridge(
      tester,
      routeBridges: () async {
        final n = calls++;
        await gates[n].future; // hold this epoch's resolve in flight
        return resolvePretripRouteBridges(
          fetchRouteShape: () async => _route,
          loadBridgeCsv: () async => n == 0 ? _csvTwoBridges : _csvThreeBridges,
        );
      },
      gateNow: DateTime(2026, 1, 15, 7),
    );
    expect(
      find.byKey(_cautionKey),
      findsNothing,
      reason: 'resolve still in flight',
    );

    // SHE changes the destination while the OLD resolve is in flight.
    await setPlaceJa(tester, 39.9, 140.2, 'エリアB');
    expect(
      calls,
      2,
      reason: 'the change fires exactly ONE fresh resolve for the new epoch',
    );
    expect(find.byKey(_cautionKey), findsNothing);

    // The resolve for the PRIOR destination's route now completes — LATE.
    gates[0].complete();
    await flush(tester);
    expect(
      find.byKey(_cautionKey),
      findsNothing,
      reason:
          'the late result describes a route SHE is not taking — '
          'it must be dropped, not rendered beside the new destination',
    );
    expect(find.textContaining('経路上に橋が約'), findsNothing);

    // The NEW epoch's resolve lands: the driver caution shows the NEW route's count.
    gates[1].complete();
    await flush(tester);
    expect(
      find.textContaining('この先、秋田県内の経路上に橋が約3か所あります'),
      findsOneWidget,
      reason:
          'the new epoch\'s result (約3) must land — and NOT the stale '
          '約2',
    );
    expect(find.textContaining('橋が約2'), findsNothing);
  });

  testWidgets(
    '(i2) a stale FREEZING dest-area forecast landing AFTER the driver destination '
    'change must NOT feed the new destination\'s cold gate',
    (tester) async {
      // Arm everything EXCEPT the cold gate: July + warm origin + 2 clusters
      // resolved (the (d2) arm — caution hidden). The FIRST destination's area
      // read is FREEZING but held in flight; the second destination's read is
      // warm and lands normally. If the late freezing read for the PRIOR area
      // were allowed to land, it would arm the cold gate (cold-at-either-
      // endpoint) and show a caution justified by an area SHE is no longer
      // driving to — exactly the resurrection the epoch guard forbids.
      final staleGate = Completer<void>();
      var destCalls = 0;
      await pumpBridge(
        tester,
        routeBridges: () => resolvePretripRouteBridges(
          fetchRouteShape: () async => _route,
          loadBridgeCsv: () async => _csvTwoBridges,
        ),
        metFetch: () async => _cannedLive(10), // warm origin window
        gateNow: DateTime(2026, 7, 15, 7), // off-season: the band stays quiet
        forecastSource: 'met_norway',
        destForecastFactory: () {
          destCalls++;
          return destCalls == 1
              // Epoch 0's read: FREEZING, held in flight.
              ? _GatedMetProvider(_cannedLive(-5), staleGate.future)
              // Epoch 1's read: warm, lands immediately.
              : _GatedMetProvider(_cannedLive(12));
        },
        // Non-Japan points so the dest read never consults JMA (no socket).
        savedPlace: const SavedPlace(lat: 60.0, lon: 10.0, label: 'エリアA'),
      );
      expect(destCalls, 1);
      expect(
        find.byKey(_cautionKey),
        findsNothing,
        reason: 'July + warm origin + no dest evidence: hidden (the (d2) arm)',
      );

      // SHE changes the destination while the freezing read is in flight.
      await setPlaceJa(tester, 61.0, 11.0, 'エリアB');
      expect(destCalls, 2, reason: 'the change fires its own fresh area read');
      expect(
        find.byKey(_cautionKey),
        findsNothing,
        reason: 'the NEW area\'s warm read arms nothing',
      );

      // The freezing read for the PRIOR area now lands — LATE.
      staleGate.complete();
      await flush(tester);
      expect(
        find.byKey(_cautionKey),
        findsNothing,
        reason:
            'the freezing forecast describes エリアA, which SHE is no '
            'longer driving to — it must be dropped, never fed into the new '
            'destination\'s cold gate',
      );
      expect(find.textContaining('経路上に橋が約'), findsNothing);
    },
  );

  // --- PRODUCTION-ARM wiring (the narrow seams; routeBridgesOverride
  // bypasses this whole arm, so these pin what it cannot: the opt-in gate,
  // the saved-place await, and WHICH coordinates get routed). -------------

  testWidgets(
    '(j) production arm threads (origin == briefing point, dest == the '
    'SAVED place) into the route fetch — end-to-end to the rendered count',
    (tester) async {
      final requests =
          <({double oLat, double oLon, double dLat, double dLon})>[];
      await pumpBridge(
        tester,
        osrmUrl: 'http://osrm.test', // opt-in gate OPEN
        routeShapeFetch:
            ({
              required double originLat,
              required double originLon,
              required double destLat,
              required double destLon,
            }) async {
              requests.add((
                oLat: originLat,
                oLon: originLon,
                dLat: destLat,
                dLon: destLon,
              ));
              return _route;
            },
        csvLoad: () async => _csvTwoBridges,
        gateNow: DateTime(2026, 1, 15, 7),
        savedPlace: const SavedPlace(lat: 39.9, lon: 140.2, label: 'エリアA'),
      );

      expect(requests, hasLength(1), reason: 'EXACTLY ONE route fetch');
      // Origin = the briefing point (the PRETRIP_LAT/LON defaults in tests).
      expect(requests.single.oLat, closeTo(35.1709, 1e-9));
      expect(requests.single.oLon, closeTo(136.8815, 1e-9));
      // Destination = the driver-SAVED place, not a seed and not the origin
      // (a swapped pair would route the wrong trip and ship a plausible but
      // WRONG count).
      expect(requests.single.dLat, closeTo(39.9, 1e-9));
      expect(requests.single.dLon, closeTo(140.2, 1e-9));
      // And the real wiring delivered all the way to the driver surface.
      expect(find.byKey(_cautionKey), findsOneWidget);
      expect(find.textContaining('経路上に橋が約2'), findsOneWidget);
    },
  );

  testWidgets(
    '(k) production arm: NO destination at initState ⇒ NO fetch; the driver FIRST '
    'set fires exactly ONE fetch, for the just-set place',
    (tester) async {
      final requests = <({double dLat, double dLon})>[];
      await pumpBridge(
        tester,
        osrmUrl: 'http://osrm.test',
        routeShapeFetch:
            ({
              required double originLat,
              required double originLon,
              required double destLat,
              required double destLon,
            }) async {
              requests.add((dLat: destLat, dLon: destLon));
              return _route;
            },
        csvLoad: () async => _csvTwoBridges,
        gateNow: DateTime(2026, 1, 15, 7),
        // No savedPlace, no PRETRIP_DEST_* defines in a plain flutter test.
      );

      expect(requests, isEmpty, reason: 'no destination ⇒ nothing to route');
      expect(find.byKey(_cautionKey), findsNothing);

      // the driver first destination: initState resolved nothing, so the set fires
      // exactly ONE fetch total — no initState/first-set double-fetch.
      await setPlaceJa(tester, 39.9, 140.2, 'エリアA');
      await flush(tester);
      expect(
        requests,
        hasLength(1),
        reason:
            'the first set fires exactly ONE fetch (no double-fetch from '
            'the initState + first-set interaction)',
      );
      expect(requests.single.dLat, closeTo(39.9, 1e-9));
      expect(requests.single.dLon, closeTo(140.2, 1e-9));
      expect(
        find.byKey(_cautionKey),
        findsOneWidget,
        reason: 'and the fresh resolve reaches the driver surface',
      );
    },
  );

  testWidgets(
    '(l) production arm: no PRETRIP_ROUTE_OSRM_URL opt-in ⇒ NO fetch — at '
    'initState with a destination saved, AND on a destination change',
    (tester) async {
      var calls = 0;
      await pumpBridge(
        tester,
        // osrmUrl deliberately NOT passed: the compile-time define is empty in
        // a plain flutter test, so the opt-in gate is CLOSED.
        routeShapeFetch:
            ({
              required double originLat,
              required double originLon,
              required double destLat,
              required double destLon,
            }) async {
              calls++;
              return _route;
            },
        csvLoad: () async => _csvTwoBridges,
        gateNow: DateTime(2026, 1, 15, 7),
        savedPlace: const SavedPlace(lat: 39.9, lon: 140.2, label: 'エリアA'),
      );

      expect(calls, 0, reason: 'not opted in ⇒ the feature is absent');
      expect(find.byKey(_cautionKey), findsNothing);

      // The per-epoch trigger honours the SAME gate: a destination change with
      // no opt-in still fetches nothing.
      await setPlaceJa(tester, 39.8, 140.3, 'エリアB');
      await flush(tester);
      expect(
        calls,
        0,
        reason: 'the setter-path resolve is behind the same opt-in gate',
      );
      expect(find.byKey(_cautionKey), findsNothing);
    },
  );
}
