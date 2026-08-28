/// Native (C FFI) implementation of [SafetyScoreSimulationEngine].
///
/// Delegates Monte Carlo safety-score simulation to a compiled C library
/// for higher throughput than the pure-Dart [CpuSafetyScoreSimulationEngine].
library;

import '../models/road_surface_state.dart';
import 'measured_inputs.dart';
import 'simulated_safety_score.dart';
import 'native_simulation_bindings.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_options.dart';
import 'simulation_result.dart';

/// Runs safety-score Monte Carlo simulation via a native C library.
///
/// Uses [NativeSimulationBindings] to call the compiled
/// `simulation_run_batch` function through `dart:ffi`.
///
/// **0.7.0 removed the `provider:` parameter, and with it the CPU fallback.**
/// On 0.6.x this engine silently delegated to [CpuSafetyScoreSimulationEngine]
/// whenever the fleet term was absent, because the C kernel's weighted mean
/// took a non-nullable fleet confidence and could not express an absent one —
/// so `SimulationResult.executionMs` came back `null` and the FFI kernel was
/// never entered on the default path. The score no longer has a fleet term at
/// all (see [SimulatedSafetyScore]), the kernel's signature no longer carries
/// one, and this engine now always runs the native path.
///
/// ⚑ `native/native_simulation.c` changed in 0.7.0 — its weights are `0.5/0.5`
/// and `simulation_run_batch` takes six arguments instead of seven. **Rebuild
/// the shared library.** An `0.6.x` binary left in `native/build/` is an ABI
/// mismatch, not a slightly-stale one.
class NativeSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates an engine backed by [bindings] (defaults to platform library).
  NativeSafetyScoreSimulationEngine({NativeSimulationBindings? bindings})
    : _bindings = bindings ?? NativeSimulationBindings();

  final NativeSimulationBindings _bindings;

  /// Throws [ArgumentError] if [speed], [gripFactor] or [visibilityMeters] is
  /// non-finite. Checked on the Dart side deliberately: the C kernel clamps
  /// with `<` / `>` comparisons, and every comparison against a `NaN` is
  /// false, so a non-finite value would pass straight through `clampf_range`
  /// and poison the batch mean.
  @override
  SimulationResult simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  }) {
    requireMeasured(speed, 'speed');
    requireMeasured(gripFactor, 'gripFactor');
    requireMeasured(visibilityMeters, 'visibilityMeters');

    final response = _bindings.runBatch(
      runs: options.runs,
      seed: options.seed ?? 0,
      speed: speed,
      gripFactor: gripFactor,
      surfaceCode: surface.index,
      visibilityMeters: visibilityMeters,
    );

    return SimulationResult(
      score: SimulatedSafetyScore(
        overall: response.overallMean,
        gripScore: response.gripMean,
        visibilityScore: response.visibilityMean,
      ),
      variance: response.overallVariance,
      incidentCount: response.incidentCount,
      executionMs: response.executionMs,
    );
  }
}
