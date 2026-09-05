/// LIVE-REAL capture — the product rendered on a FRESH real MET Norway fetch.
///
/// The flutter-test sandbox has no outbound network, so the fetch is done in the
/// shell (curl, with the provider's User-Agent) and saved to /tmp/livereal/*.json;
/// this test parses those REAL responses with the product's own
/// `mapLocationForecastToWeatherForecast` and renders the briefing, so a human
/// can eyeball the product on real current data:
///   - nagoya  (the driver)        — MET Norway global case
///   - akita   (the driver's mother) — Japan snow-zone case (MET base; JMA live-check is a
///                            separate runtime step, NOT run here — June: ~23C, no snow)
///   - ushuaia (Argentina)  — a real Southern-Hemisphere winter point
/// Next-best OBSERVABLE rung toward evidenced service while the board is
/// unavailable. June expectation (honest): Japan reads clear (no fabricated snow).
/// If /tmp/livereal/<name>.json is absent the case is skipped (no fabrication).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
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
  const advisor = SnowAwarePretripAdvisor();
  const profile = DriverProfileSpec(
    profileTag: 'live',
    reactionTimeSeconds: 1.5,
  );
  final captions = <String, String>{
    'nagoya': 'LIVE — MET Norway, real fetch (Nagoya) · global case',
    'akita':
        'LIVE — MET Norway, real fetch (Akita) · Japan snow-zone case (JMA live-check is a separate runtime step)',
    'ushuaia':
        'LIVE — MET Norway, real fetch (Ushuaia) · Southern-Hemisphere winter',
    'remarkables_nz':
        'LIVE — MET Norway, real fetch (The Remarkables, NZ 1900m) · winter, near-freezing precipitation',
    'greenland_summit':
        'LIVE — MET Norway, real fetch (Greenland Summit, 3216m) · Northern-Hemisphere winter, subzero + precipitation',
  };
  // Departure override: aim the window at the real hazard slot where one exists
  // (the live near-freezing-precip slot), instead of the earliest slot.
  // Comparison is instant-based, so a UTC departure aligns with the parsed
  // (host-local) slots; only the DISPLAYED hour is in host TZ (known nuance).
  final depOverride = <String, DateTime>{
    'remarkables_nz': DateTime.utc(2026, 6, 14, 5, 0),
    'greenland_summit': DateTime.utc(2026, 6, 14, 4, 0),
  };

  // Edge-developer reuse: set LIVE_NAME (+ optional LIVE_CAPTION) and drop a
  // /tmp/livereal/<LIVE_NAME>.json (the `tool/live_briefing.sh` wrapper does the
  // fetch) to render the briefing for ANY location in one command — no need to
  // edit this file. Without LIVE_NAME, the built-in demo set renders.
  final envName = Platform.environment['LIVE_NAME'];
  final places = (envName != null && envName.isNotEmpty)
      ? <String>[envName]
      : const [
          'nagoya',
          'akita',
          'ushuaia',
          'remarkables_nz',
          'greenland_summit',
        ];
  if (envName != null && envName.isNotEmpty) {
    captions[envName] =
        Platform.environment['LIVE_CAPTION'] ??
        'LIVE — MET Norway, real fetch ($envName)';
  }

  for (final place in places) {
    testWidgets('live-real capture: $place', (tester) async {
      final src = File('/tmp/livereal/$place.json');
      if (!src.existsSync()) {
        // No real fetch on disk -> skip honestly, render nothing.
        // ignore: avoid_print
        print('SKIP $place: /tmp/livereal/$place.json absent');
        return;
      }
      await _loadRealFont();

      final forecast = mapLocationForecastToWeatherForecast(
        jsonDecode(src.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(forecast, isNotNull, reason: 'parser returned null for $place');
      // Departure = the real hazard slot where overridden, else the earliest slot.
      final dep = depOverride[place] ?? forecast!.hourly.first.hour;
      forecast!; // assert non-null for the analyzer below
      final commute = CommuteShape(
        plannedDeparture: dep,
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['live'],
        flexibility: CommuteFlexibility.discretionary,
      );
      final briefing = advisor.brief(
        forecast: forecast,
        commute: commute,
        profile: profile,
      );
      // ignore: avoid_print
      print(
        'LIVE-REAL $place: verdict=${briefing.verdict} '
        'peak=${briefing.peakHazard} slot0=${forecast.hourly.first.tempCelsius}C '
        'issued=${forecast.issuedAt.toIso8601String()}',
      );

      final key = GlobalKey();
      tester.view.physicalSize = const Size(620, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 600,
                  height: 740,
                  child: PretripBriefingCard(
                    briefing: briefing,
                    commute: commute,
                    forecastIssuedAt: forecast.issuedAt,
                    tripRequired: false,
                    onTripRequiredChanged: (_) {},
                    sourceCaption: captions[place]!,
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
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('test/widgets/_capture')..createSync();
        final file = File('${dir.path}/pretrip_livereal_$place.png');
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print(
          'CAPTURE livereal_$place: ${file.path} ${file.lengthSync()} bytes',
        );
      });
      expect(tester.takeException(), isNull);
    });
  }
}
