// Runnable demo for `vehicle_condition_fusion` — drive the safety-calibrated
// fusion through a full Akita whiteout using ONLY a laptop. No databroker, no
// vehicle, no SDK: a SYNTHETIC signal trace is replayed through the published
// fusion and the evolving hazard assessment is printed per step.
//
// This shipped example runs from a clone of this repository — `pub add` does
// NOT copy `example/` into your project (see the package README for the
// copy-paste, pub-add on-ramp). From a repo clone:
//   cd packages/vehicle_condition_fusion
//   dart pub get
//   dart run example/main.dart
//
// ⚠️ The drive is ILLUSTRATIVE / SYNTHETIC — hand-authored plausible values,
//    NOT a recording of any real vehicle or any real storm.
import 'dart:async';
import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:vehicle_condition_fusion/scenarios.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

Future<void> main() async {
  stdout
    ..writeln('=' * 78)
    ..writeln('vehicle_condition_fusion — ILLUSTRATIVE SYNTHETIC Akita heavy-snow drive')
    ..writeln('(hand-authored plausible signals replayed through the published fusion —')
    ..writeln(' NOT recorded sensor data, NOT a real vehicle, NOT a real storm)')
    ..writeln('=' * 78)
    ..writeln('The WHOLE assessment is hysteresis-debounced (anti-flicker): the surface')
    ..writeln('verdict, grip AND the visibility cue are HELD at the last stable reading')
    ..writeln('until a NEW surface state persists (HysteresisFilter window 3 / threshold')
    ..writeln('2 — a hold can span several steps, not just one noisy frame). Held steps')
    ..writeln('are marked "(held)": fresh inputs sit beside a stale verdict by design.')
    ..writeln('The hold is fail-safe on CLEARING (it keeps the hazard up until the')
    ..writeln('easing persists) but LAGS onset by design. Watch it escalate, then clear:')
    ..writeln('');

  // Partial-frame transport (KUKSA-style): a later frame re-sends only what
  // changed, so we use the carry-forward rail. The replay completes after the
  // last frame, which makes the fusion emit its honest end-of-stream marker.
  final fusion = VehicleConditionFusion.fromPartialFrames(
    partialFrames: replayWinterDrive(
      akitaWhiteoutDrive,
      step: const Duration(milliseconds: 200),
    ),
  );

  final done = Completer<void>();
  var step = 0;
  // Visibility metres of the LAST committed (non-held) assessment. The fusion
  // holds the WHOLE assessment — including visibility — while the surface
  // debounce has not yet flipped, so on a held step we report the held
  // assessment's visibility, not the fresh candidate's (faithful to what the
  // package actually emits). Set on the first (never-held) emission.
  double? committedVisMeters;

  fusion.conditions.listen((update) {
    if (update.isAvailable) {
      step++;
      final s = update.signals!;
      final a = update.assessment!;

      // Re-derive the FRESH candidate (pure, deterministic — reads only, never
      // mutates the fusion) to detect a debounce-held step: when the freshly
      // computed surface differs from the displayed (held) surface, the
      // HysteresisFilter is holding the verdict.
      final weather = vehicleSignalsToWeatherCondition(s);
      final candidate = DrivingConditionAssessment.fromCondition(weather);
      final held = candidate.surfaceState != a.surfaceState;
      if (!held) committedVisMeters = weather.visibilityMeters;
      final visMeters = committedVisMeters ?? weather.visibilityMeters;

      stdout.writeln(_describe(step, update, held: held, visMeters: visMeters));
    } else {
      // Honest end-of-stream (the drive finished). Never a fabricated scene.
      stdout
        ..writeln('')
        ..writeln('— drive ended — fusion now reports: ${update.unavailableReason}')
        ..writeln('  (no live signals → honest "unavailable", never a fabricated road)');
      if (!done.isCompleted) done.complete();
    }
  });

  await done.future;
  await fusion.dispose();
}

/// Two glanceable lines per emission, each ≤80 columns:
///   line 1 — the (carried-forward) input signals + the debounced surface
///            verdict and grip, with a `(held)` marker when the debounce is
///            holding a stale verdict against fresh inputs;
///   line 2 — the visibility cue (the package's documented precipitation proxy)
///            and the advisory message.
String _describe(
  int step,
  VehicleConditionUpdate update, {
  required bool held,
  required double visMeters,
}) {
  final s = update.signals!;
  final a = update.assessment!;

  final fric = s.roadFriction == null
      ? '   ? '
      : s.roadFriction!.toStringAsFixed(2).padLeft(5);
  final temp =
      s.airTempC == null ? '  ? ' : '${s.airTempC!.toStringAsFixed(0)}°C'.padLeft(5);
  final tcs = (s.tcsEngaged ?? false) ? 'ON ' : 'off';
  final wiper = (s.wiperIntensity ?? 0).toString();

  final surface = a.surfaceState.name.padRight(13);
  final grip = a.gripFactor.toStringAsFixed(2);
  final marker = held ? ' (held)' : '';

  final line1 = 'step ${step.toString().padLeft(2)}  '
      'fric=$fric temp=$temp tcs=$tcs wiper=$wiper'
      ' → $surface grip=$grip$marker';
  final line2 = '    ${_visibilityCue(visMeters)}  ${a.advisoryMessage}';

  return '$line1\n$line2';
}

/// Maps the assessment's visibility to a glanceable cue using the package's OWN
/// documented precipitation→visibility proxy metres (10000 / 5000 / 800 / 300 m
/// by precipitation level) — NOT a re-derivation from the rendered opacity. A
/// vehicle has no meteorological visibility sensor; treat this as a documented
/// hint, never a measurement.
String _visibilityCue(double meters) {
  if (meters >= 10000) return 'vis: clear   (~10 km)';
  if (meters >= 5000) return 'vis: clear   (~5 km) ';
  if (meters >= 800) return 'vis: reduced (~800 m)';
  return 'vis: LOW     (~300 m)';
}
