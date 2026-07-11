/// Quantitative analysis harness: real MET Norway winter forecasts → the
/// production pre-trip pipeline (mapLocationForecastToWeatherForecast →
/// SnowAwarePretripAdvisor).
///
/// Not a pass/fail regression test — a measurement instrument. It reads the
/// raw locationforecast JSONs fetched for current-winter points (Southern
/// Hemisphere + polar, June 2026) from QUANT_RAW_DIR, runs every slice
/// through the same code the app ships, and prints per-point and aggregate
/// tables: hazard-band distribution, icing/cold-rain rule fire rates,
/// departure-verdict simulation across the full horizon, icing-threshold
/// sensitivity sweep, forecast horizon/staleness. The one hard assertion is
/// the documented ceiling: compact-product data can NEVER reach
/// HourHazard.severe (no visibility, no surface state) — if that ever fails,
/// the honesty documentation is wrong and must be rewritten.
library;

// A measurement instrument: printed tables ARE the deliverable.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';

void main() {
  final rawDir = Platform.environment['QUANT_RAW_DIR'];

  test('quantitative winter analysis over real fetched forecasts', () {
    if (rawDir == null) {
      markTestSkipped('QUANT_RAW_DIR not set — measurement harness only');
      return;
    }
    final files =
        Directory(rawDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    const advisor = SnowAwarePretripAdvisor();
    final now = DateTime.now();
    var totalSevere = 0;
    var totalSlots = 0;
    final rows = <String>[];
    final sweepRows = <String>[];
    final verdictRows = <String>[];

    for (final file in files) {
      final name = file.uri.pathSegments.last.replaceAll('.json', '');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final forecast = mapLocationForecastToWeatherForecast(json);
      if (forecast == null) {
        rows.add('| $name | MAP-NULL | | | | | | | | |');
        continue;
      }
      final slots = forecast.hourly;
      totalSlots += slots.length;

      final temps = slots.map((s) => s.tempCelsius).toList();
      final tMin = temps.reduce((a, b) => a < b ? a : b);
      final tMax = temps.reduce((a, b) => a > b ? a : b);
      final precipSlots = slots
          .where((s) => (s.precipitationMmPerHour ?? 0) > 0)
          .length;
      final subzero = slots.where((s) => s.tempCelsius <= 0).length;

      final hazards = slots.map(advisor.hazardOf).toList();
      final nClear = hazards.where((h) => h == HourHazard.clear).length;
      final nCaution = hazards.where((h) => h == HourHazard.caution).length;
      final nElev = hazards.where((h) => h == HourHazard.elevated).length;
      final nSev = hazards.where((h) => h == HourHazard.severe).length;
      totalSevere += nSev;

      final horizonH = slots.last.hour.difference(slots.first.hour).inHours + 1;
      final staleness = now.difference(forecast.issuedAt);

      rows.add(
        '| $name | ${slots.length} | ${horizonH}h | '
        '${staleness.inMinutes}min | ${tMin.toStringAsFixed(1)}…'
        '${tMax.toStringAsFixed(1)} | $subzero | $precipSlots | '
        '$nClear/$nCaution/$nElev/$nSev |',
      );

      // Icing-threshold sensitivity: how many slots are elevated-or-worse
      // under alternative icing temperature cutoffs (the production rule is
      // precip>0 && temp <= 0.5).
      final sweep = [0.0, 0.5, 1.0, 2.0].map((th) {
        return slots
            .where(
              (s) => (s.precipitationMmPerHour ?? 0) > 0 && s.tempCelsius <= th,
            )
            .length;
      }).toList();
      sweepRows.add(
        '| $name | ${sweep[0]} | ${sweep[1]} | ${sweep[2]} | '
        '${sweep[3]} |',
      );

      // Departure-verdict simulation: a 30-min discretionary trip departing
      // at each hourly slot start across the whole horizon — what does the
      // surface actually tell a driver at this point this week?
      final verdictCounts = <PretripVerdict, int>{};
      for (final s in slots) {
        final b = advisor.brief(
          forecast: forecast,
          commute: CommuteShape(
            plannedDeparture: s.hour,
            plannedDuration: const Duration(minutes: 30),
            routeIdentifiers: const ['quant'],
            flexibility: CommuteFlexibility.discretionary,
          ),
          profile: const DriverProfileSpec(
            profileTag: 'quant',
            reactionTimeSeconds: 1.5,
          ),
        );
        verdictCounts[b.verdict] = (verdictCounts[b.verdict] ?? 0) + 1;
      }
      String c(PretripVerdict v) => '${verdictCounts[v] ?? 0}';
      verdictRows.add(
        '| $name | ${c(PretripVerdict.clear)} | '
        '${c(PretripVerdict.caution)} | ${c(PretripVerdict.waitAdvised)} | '
        '${c(PretripVerdict.hazardPersists)} | '
        '${c(PretripVerdict.noData)} |',
      );
    }

    print('=== PER-POINT: slices, horizon, staleness, temp, hazard bands ===');
    print(
      '| point | hourly | horizon | staleness | temp °C | subzero | '
      'precip>0 | clear/caution/elev/severe |',
    );
    rows.forEach(print);
    print('=== ICING THRESHOLD SWEEP (slots with precip>0 and temp<=th) ===');
    print('| point | th=0.0 | th=0.5 (prod) | th=1.0 | th=2.0 |');
    sweepRows.forEach(print);
    print(
      '=== DEPARTURE-VERDICT SIMULATION (30-min discretionary trip, '
      'departing each forecast hour) ===',
    );
    print(
      '| point | clear | caution | waitAdvised | hazardPersists | '
      'noData |',
    );
    verdictRows.forEach(print);
    print('=== AGGREGATE ===');
    print('total hourly slots analyzed: $totalSlots');
    print('severe-band slots from live compact data: $totalSevere');

    // The documented ceiling, asserted: live compact data (visibility null,
    // surface null) cannot reach the severe band.
    expect(
      totalSevere,
      0,
      reason:
          'compact product has no visibility/surface fields — if '
          'severe fired, the documented live-data ceiling is wrong',
    );
  });
}
