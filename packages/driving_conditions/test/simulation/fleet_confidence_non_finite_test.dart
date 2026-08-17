/// A non-finite fleet confidence must leave this package non-finite.
///
/// `num.clamp` maps NaN and `+Infinity` to the UPPER bound. So
/// `(total / totalWeight).clamp(0.0, 1.0)` converts "this could not be
/// computed" into `1.0` — which `FleetConfidenceProvider` documents as
/// "fleet reports consistently safe conditions" — and does so *before*
/// `navigation_safety_core`'s conservative-on-uncertain guard (GAP-1,
/// `safety_score.dart`: `if (!value.isFinite) return 0;`) can ever fire.
///
/// These tests fail if that sanitiser is reintroduced. Each failure message
/// states what was measured and why it matters, so a future author who trips
/// one is told what the guard is for rather than merely that it broke.
library;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.now();
  const position = LatLng(39.72, 140.10); // Akita.

  FleetReport report(
    RoadCondition condition, {
    required double confidence,
    Duration age = Duration.zero,
  }) => FleetReport(
    vehicleId: 'v1',
    position: position,
    timestamp: now.subtract(age),
    condition: condition,
    confidence: confidence,
  );

  // The three values `.clamp(0.0, 1.0)` silently absorbs.
  const nonFinite = <String, double>{
    'NaN': double.nan,
    '+Infinity': double.infinity,
    '-Infinity': double.negativeInfinity,
  };

  group('the Dart primitive this guard exists because of', () {
    test('num.clamp maps NaN and +Infinity to the UPPER bound', () {
      // Not an assumption — the reason the fix is a branch and not a clamp.
      expect(
        double.nan.clamp(0.0, 1.0),
        1.0,
        reason: 'If this ever stops being true the guard can be simplified.',
      );
      expect(double.nan.clamp(0.0, 1.0).isFinite, isTrue);
      expect(double.infinity.clamp(0.0, 1.0), 1.0);
    });
  });

  group('FleetHazardConfidenceAdapter — non-finite evidence stays non-finite', () {
    for (final entry in nonFinite.entries) {
      final label = entry.key;
      final value = entry.value;

      test(
        'an ICY report whose confidence is $label does not become a number',
        () {
          final adapter = FleetHazardConfidenceAdapter([
            report(RoadCondition.icy, confidence: value),
          ]);

          expect(
            adapter.confidence.isFinite,
            isFalse,
            reason:
                'A fleet report of ICE whose own confidence is $label cannot be '
                'reduced to a number. Returning a finite value here claims a '
                'measurement that was never made, and it consumes the only '
                'signal navigation_safety_core GAP-1 reads. Measured: '
                '${adapter.confidence}. Do not clamp a non-finite average.',
          );
        },
      );

      test(
        '...and specifically is not 1.0, "fleet reports consistently safe" ($label)',
        () {
          final adapter = FleetHazardConfidenceAdapter([
            report(RoadCondition.icy, confidence: value),
          ]);

          expect(
            adapter.confidence == 1.0,
            isFalse,
            reason:
                'FleetConfidenceProvider documents 1.0 as "fleet reports '
                'consistently safe conditions". The single report here says ICE '
                'and its confidence is $label. 1.0 is the most dangerous '
                'possible answer: it is maximum reassurance derived from '
                'unreadable evidence.',
          );
        },
      );
    }

    test('one unreadable report does not delete four honest reports of ice', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, confidence: 0.9),
        report(RoadCondition.icy, confidence: 0.9),
        report(RoadCondition.icy, confidence: 0.9),
        report(RoadCondition.icy, confidence: 0.9),
        report(RoadCondition.icy, confidence: double.nan),
      ]);

      expect(
        adapter.confidence == 1.0,
        isFalse,
        reason:
            'Four vehicles reported ice. Under the clamp, the fifth report — '
            'whose confidence was NaN — poisoned the weighted average and the '
            'adapter answered 1.0: consistently safe. Measured: '
            '${adapter.confidence}.',
      );
      expect(adapter.confidence.isFinite, isFalse);
    });
  });

  group('GAP-1 downstream can actually fire', () {
    test(
      'a non-finite adapter value reaches navigation_safety_core as 0 (alerts)',
      () {
        final adapter = FleetHazardConfidenceAdapter([
          report(RoadCondition.icy, confidence: double.nan),
        ]);

        final score = SafetyScore(
          overall: 0.5,
          gripScore: 0.5,
          visibilityScore: 0.5,
          fleetConfidenceScore: adapter.confidence,
        );

        expect(
          score.fleetConfidenceScore,
          0.0,
          reason:
              'navigation_safety_core maps a non-finite score to 0 so that it '
              'ALERTS conservatively (GAP-1). That guard is unreachable if this '
              'package clamps first — a sanitiser upstream disarming a safety '
              'guard downstream. Measured fleetConfidenceScore: '
              '${score.fleetConfidenceScore}.',
        );
      },
    );

    test(
      'the simulation engine alerts rather than reporting a confident score',
      () {
        final adapter = FleetHazardConfidenceAdapter([
          report(RoadCondition.icy, confidence: double.nan),
        ]);
        final engine = CpuSafetyScoreSimulationEngine(provider: adapter);

        final result = engine.simulate(
          speed: 60,
          gripFactor: 0.9,
          surface: RoadSurfaceState.dry,
          visibilityMeters: 1000,
          options: const SimulationOptions(runs: 50, seed: 42),
        );

        expect(
          result.score.overall,
          0.0,
          reason:
              'With grip and visibility good, a clamped 1.0 fleet score yields a '
              'comfortable overall and no incidents. Because the unreadable '
              'fleet evidence now stays non-finite, GAP-1 inside SafetyScore '
              'collapses it to worst case and the run alerts. Measured overall: '
              '${result.score.overall}, incidents: ${result.incidentCount}/50.',
        );
        expect(result.incidentCount, 50);
      },
    );
  });

  group('every finite path is unchanged — this fix is about NaN only', () {
    test('a dry report is still 1.0', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry, confidence: 1.0),
      ]);
      expect(adapter.confidence, closeTo(1.0, 1e-9));
    });

    test('an icy report is still 0.1', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, confidence: 1.0),
      ]);
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('no reports is still the 0.8 baseline', () {
      const adapter = FleetHazardConfidenceAdapter([]);
      expect(
        adapter.confidence,
        0.8,
        reason:
            'The neutral baseline is a separate question and is deliberately '
            'untouched by this change.',
      );
    });

    test('only stale reports is still the 0.8 baseline', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(
          RoadCondition.icy,
          confidence: 1.0,
          age: const Duration(hours: 1),
        ),
      ]);
      expect(adapter.confidence, 0.8);
    });

    test('zero total weight is still the 0.8 baseline', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, confidence: 0.0),
      ]);
      expect(adapter.confidence, 0.8);
    });

    test('a mixed finite set still averages by weight', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry, confidence: 1.0), // 1.0 * 1.0
        report(RoadCondition.icy, confidence: 1.0), // 0.1 * 1.0
      ]);
      expect(adapter.confidence, closeTo(0.55, 1e-9));
    });
  });
}
