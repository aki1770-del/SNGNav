/// Pixel-capture harness for the pre-trip briefing surface.
///
/// An observable deliverable is verified by rendering it and looking at the
/// actual output — passing widget tests alone are not "seen". This harness
/// loads a real system TTF in place of the test-default Ahem block font so
/// the captured PNGs show actual legible text, renders the card in its three
/// load-bearing states (wait-advised / required-trip honesty / clear), and
/// writes real PNGs to test/widgets/_capture/ for a human to eyeball.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:driving_conditions/driving_conditions.dart'
    show RoadSurfaceState;
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/jma_briefing_merge.dart';
import 'package:sngnav_snow_scene/providers/jma_visibility.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

const _ttf = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';

Future<void> _loadRealFont() async {
  final bytes = File(_ttf).readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  final dep = DateTime(2026, 1, 1, 7, 15);
  final issued = DateTime(2026, 1, 1, 6, 0);

  // Hazard fixtures stay subzero; the clear fixture sits above the frost
  // band (subzero dry air is caution class since the 2026-06-12 quant fix).
  // ⚑ A FULLY MEASURED slot, since 2026-08-28 — see
  // `pretrip_briefing_card_test.dart` for the reasoning. These captures are a
  // visual record of the shipped card, so their inputs must be states the
  // advisor can actually decide; a captured all-clear that was never earned is
  // a picture of the defect `pretrip_decision_advisor` 0.6.1 closes.
  HourlyForecast slot(
    int hour, {
    double temp = -3,
    double vis = 8000,
    double precip = 0,
    double humidity = 60,
    RoadConditionEstimate road = RoadConditionEstimate.dry,
  }) => HourlyForecast(
    hour: DateTime(2026, 1, 1, hour),
    tempCelsius: temp,
    humidityRH: humidity,
    precipitationMmPerHour: precip,
    visibilityMeters: vis,
    estimatedRoadCondition: road,
  );

  final whiteoutThenClear = [
    slot(7, vis: 80, precip: 3),
    slot(8, vis: 250, precip: 1),
    slot(9, vis: 5000),
    slot(10, vis: 8000),
  ];
  // 4 C — above the radiative-frost ceiling (3 C), so the ladder decides it.
  final clear = [slot(7, temp: 4), slot(8, temp: 4)];
  // Dry subzero air — caution class with the frost/black-ice chip (the
  // 2026-06-12 quant fix: 70/620 real winter slots used to render "clear").
  final frostDry = [slot(7, temp: -8), slot(8, temp: -8)];

  final cases = <String, (List<HourlyForecast>, CommuteFlexibility)>{
    'wait_advised': (whiteoutThenClear, CommuteFlexibility.discretionary),
    'required_honesty': (whiteoutThenClear, CommuteFlexibility.required),
    'clear_depart': (clear, CommuteFlexibility.discretionary),
    'frost_caution': (frostDry, CommuteFlexibility.discretionary),
  };

  for (final entry in cases.entries) {
    testWidgets('capture: ${entry.key}', (tester) async {
      await _loadRealFont();
      final (hourly, flexibility) = entry.value;
      const advisor = SnowAwarePretripAdvisor();
      final commute = CommuteShape(
        plannedDeparture: dep,
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['demo'],
        flexibility: flexibility,
      );
      final briefing = advisor.brief(
        forecast: WeatherForecast(hourly: hourly, issuedAt: issued),
        commute: commute,
        profile: const DriverProfileSpec(
          profileTag: 'demo',
          reactionTimeSeconds: 1.5,
        ),
      );

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(620, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 600,
                  height: 740,
                  child: PretripBriefingCard(
                    briefing: briefing,
                    commute: commute,
                    forecastIssuedAt: issued,
                    tripRequired: flexibility == CommuteFlexibility.required,
                    onTripRequiredChanged: (_) {},
                    sourceCaption:
                        'Simulated forecast (demo) — offline, deterministic',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        final dir = Directory('test/widgets/_capture')..createSync();
        final file = File('${dir.path}/pretrip_${entry.key}.png');
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        expect(file.lengthSync(), greaterThan(0));
        // ignore: avoid_print
        print(
          'CAPTURE ${entry.key}: ${file.path} '
          '${file.lengthSync()} bytes ${image.width}x${image.height}',
        );
      });

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capture: jp_jma_snow', (tester) async {
    await _loadRealFont();
    // Japan-shaped live forecast: temperature only (the MET Norway compact
    // product gives Nagoya no visibility and no road state), with an official
    // JMA heavy-snow warning merged onto the departure window. Without the
    // merge this renders "no winter hazard"; with it the driver sees the snow.
    final jpForecast = WeatherForecast(
      hourly: [slot(7, temp: -2), slot(8, temp: -2)],
      issuedAt: issued,
    );
    final merged = mergeJmaWinterAdvisory(
      jpForecast,
      jmaEventName: '大雪警報',
      windowStart: dep,
      windowDuration: const Duration(minutes: 30),
    );
    const advisor = SnowAwarePretripAdvisor();
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['demo'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: merged,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 740,
                child: PretripBriefingCard(
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption:
                      'MET Norway forecast + JMA heavy-snow warning (official)',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_jp_jma_snow.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print('CAPTURE jp_jma_snow: ${file.path} ${file.lengthSync()} bytes');
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('capture: jp_live_akita', (tester) async {
    await _loadRealFont();
    // The Akita (Japan snow-zone) live-briefing case: a MET Norway temp-only
    // base merged with an OFFICIAL JMA heavy-snow warning on the departure
    // window. The verbatim 大雪警報 lives in the merge DATA driving the road
    // band; the on-card Text is English ONLY (DejaVuSans has no CJK glyphs, so
    // CJK on the card would render as tofu boxes).
    final base = WeatherForecast(
      hourly: [slot(7, temp: -2), slot(8, temp: -2)],
      issuedAt: issued,
    );
    final merged = mergeJmaWinterAdvisory(
      base,
      jmaEventName: '大雪警報',
      windowStart: dep,
      windowDuration: const Duration(minutes: 30),
    );
    const advisor = SnowAwarePretripAdvisor();
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['demo'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: merged,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 740,
                child: PretripBriefingCard(
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption:
                      'MET Norway forecast + JMA heavy-snow warning '
                      '(Akita, official)',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_jp_live_akita.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print('CAPTURE jp_live_akita: ${file.path} ${file.lengthSync()} bytes');
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('capture: jp_akita_measured_whiteout', (tester) async {
    await _loadRealFont();
    // The NEW Japan path: an Akita temp-only MET base with a REAL measured
    // AMeDAS visibility (80 m) merged into the departure hour. This is the only
    // channel that lights the WHITEOUT band for HER mother — the JMA warning
    // merge deliberately never writes a visibility number, so without a real
    // sensor the Japan briefing could never reach severe on measured data.
    final base = WeatherForecast(
      hourly: [slot(7, temp: -6), slot(8, temp: -6)],
      issuedAt: issued,
    );
    final obs = VisibilityObservation(
      meters: 80,
      stationId: 32402,
      stationName: 'Akita',
      measuredAt: dep,
      distanceKm: 0.4,
    );
    final merged = mergeObservedVisibility(base, obs, dep);
    const advisor = SnowAwarePretripAdvisor();
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['demo'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: merged,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 740,
                child: PretripBriefingCard(
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption:
                      'LIVE forecast — base: MET Norway (Akita). Departure-hour '
                      'visibility MEASURED: 80 m at Akita (0 km away) — data: '
                      'Japan Meteorological Agency / AMeDAS.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_jp_akita_measured_whiteout.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print(
        'CAPTURE jp_akita_measured_whiteout: ${file.path} '
        '${file.lengthSync()} bytes',
      );
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('capture: jp_live_akita_unavailable', (tester) async {
    await _loadRealFont();
    // The honest-degradation surface: same Akita temp-only base, but NO merge —
    // the JMA winter-warning check was UNAVAILABLE, so the card briefs on
    // temperature + precipitation only and SAYS SO. An official snow warning
    // may exist that is not reflected; the caption never claims "all clear".
    final base = WeatherForecast(
      hourly: [slot(7, temp: -2), slot(8, temp: -2)],
      issuedAt: issued,
    );
    const advisor = SnowAwarePretripAdvisor();
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['demo'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: base,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 740,
                child: PretripBriefingCard(
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption:
                      'MET Norway forecast (Akita). JMA winter-warning check '
                      'UNAVAILABLE — temperature + precipitation only; an '
                      'official snow warning may exist that is not shown here.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_jp_live_akita_unavailable.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print(
        'CAPTURE jp_live_akita_unavailable: ${file.path} '
        '${file.lengthSync()} bytes',
      );
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('capture: winter_card_black_ice', (tester) async {
    await _loadRealFont();
    // The new λ-RLM offline-guidance surface: a caution briefing that ALSO
    // carries the grounded black-ice action card baked from the open corpus.
    // We render with the REAL shipped asset's blackIce card so the PNG shows
    // exactly what HER would see, not a hand-written fixture.
    final wk = WinterKnowledge.fromJsonString(
      File('assets/winter_knowledge.json').readAsStringSync(),
    );
    final card = wk.cardFor(RoadSurfaceState.blackIce);
    expect(card, isNotNull, reason: 'blackIce card must be baked');

    final base = WeatherForecast(
      hourly: [slot(7, temp: -4), slot(8, temp: -4)],
      issuedAt: issued,
    );
    const advisor = SnowAwarePretripAdvisor();
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['demo'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: base,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 880,
                child: PretripBriefingCard(
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption: 'Simulated forecast (demo)',
                  winterCard: card,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_winter_card_black_ice.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print(
        'CAPTURE winter_card_black_ice: ${file.path} '
        '${file.lengthSync()} bytes',
      );
    });

    expect(tester.takeException(), isNull);
  });
}
