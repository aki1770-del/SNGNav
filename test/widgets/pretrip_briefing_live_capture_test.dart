/// Pixel-capture harness for the LIVE-forecast pre-trip briefing path.
///
/// Renders the card exactly as `_buildPretripView` feeds it in live mode —
/// forecast mapped by `mapLocationForecastToWeatherForecast`, the LIVE
/// MET Norway caption with CC-BY attribution — in two states:
/// - `live_real_nagoya`: the REAL captured 2026-06-12 Nagoya response
///   (clear June verdict — the honest no-hazard rendering);
/// - `live_winter_shaped`: a compact-product-shaped winter morning (snow at
///   −4 °C clearing later — wait-advised from temperature + precipitation
///   alone, since the product carries no visibility).
/// PNGs land in test/widgets/_capture/ for a human to eyeball.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/digitraffic_visibility.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

const _ttf = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
const _fixturePath =
    'test/providers/fixtures/met_norway_compact_nagoya_2026_06_12.json';

Future<void> _loadRealFont() async {
  final bytes = File(_ttf).readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

const _liveCaption =
    'LIVE forecast — data: MET Norway (CC BY 4.0), '
    'lat 35.1709 lon 136.8815. '
    'No visibility/surface data in this product — hazard signal from '
    'temperature + precipitation only.';

Map<String, dynamic> _winterShaped() => {
  'properties': {
    'meta': {'updated_at': '2026-01-01T05:30:00Z'},
    'timeseries': [
      for (final (h, t, p) in [
        (7, -4.0, 2.5),
        (8, -3.0, 1.0),
        (9, -1.0, 0.0),
        (10, 0.0, 0.0),
      ])
        {
          'time': '2026-01-01T0$h:00:00Z',
          'data': {
            'instant': {
              'details': {'air_temperature': t, 'relative_humidity': 85.0},
            },
            'next_1_hours': {
              'summary': {'symbol_code': p > 0 ? 'snow' : 'clearsky_day'},
              'details': {'precipitation_amount': p},
            },
          },
        },
    ],
  },
};

// The caption main.dart composes when a measured visibility observation is
// merged (Digitraffic, departure-hour only).
const _measuredCaption =
    'LIVE forecast — data: MET Norway (CC BY 4.0), '
    'lat 60.2 lon 24.6. '
    'No visibility/surface data in this product — hazard signal from '
    'temperature + precipitation. '
    'Departure-hour visibility MEASURED: 80 m at vt1_Espoo_Nupuri (3 km '
    'away) — data: Fintraffic / digitraffic.fi (CC BY 4.0).';

void main() {
  final cases = <String, (WeatherForecast, DateTime, String)>{};

  setUpAll(() {
    final real = mapLocationForecastToWeatherForecast(
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>,
    )!;
    final winter = mapLocationForecastToWeatherForecast(_winterShaped())!;
    cases['live_real_nagoya'] = (
      real,
      DateTime.utc(2026, 6, 12, 9, 15).toLocal(),
      _liveCaption,
    );
    cases['live_winter_shaped'] = (
      winter,
      DateTime.utc(2026, 1, 1, 7, 15).toLocal(),
      _liveCaption,
    );
    // Measured 80 m visibility merged into the departure hour: the severe
    // band a forecast alone can never reach (0/620, 2026-06-12 quant run).
    final dep = DateTime.utc(2026, 1, 1, 7, 15).toLocal();
    cases['live_winter_measured_vis'] = (
      mergeObservedVisibility(
        winter,
        VisibilityObservation(
          meters: 80,
          stationId: 1001,
          stationName: 'vt1_Espoo_Nupuri',
          measuredAt: dep.subtract(const Duration(minutes: 5)),
          distanceKm: 3.1,
        ),
        dep,
      ),
      dep,
      _measuredCaption,
    );
  });

  for (final name in [
    'live_real_nagoya',
    'live_winter_shaped',
    'live_winter_measured_vis',
  ]) {
    testWidgets('capture: $name', (tester) async {
      await _loadRealFont();
      final (forecast, departure, caption) = cases[name]!;
      const advisor = SnowAwarePretripAdvisor();
      final commute = CommuteShape(
        plannedDeparture: departure,
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['live-commute'],
        flexibility: CommuteFlexibility.discretionary,
      );
      final briefing = advisor.brief(
        forecast: forecast,
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
                    forecastIssuedAt: forecast.issuedAt,
                    tripRequired: false,
                    onTripRequiredChanged: (_) {},
                    sourceCaption: caption,
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
        final file = File('${dir.path}/pretrip_$name.png');
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        expect(file.lengthSync(), greaterThan(0));
        // ignore: avoid_print
        print(
          'CAPTURE $name: ${file.path} '
          '${file.lengthSync()} bytes ${image.width}x${image.height}',
        );
      });

      expect(tester.takeException(), isNull);
    });
  }
}
