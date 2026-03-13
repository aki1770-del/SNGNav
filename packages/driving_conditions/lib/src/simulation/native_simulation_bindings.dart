/// FFI bindings to the native C simulation library.
///
/// Loads a platform-specific shared library and exposes
/// [NativeSimulationBindings.runBatch] for Monte Carlo simulation.
library;

import 'dart:ffi';
import 'dart:io';

/// Raw result struct returned by the native `simulation_run_batch` function.
final class NativeSimulationResponse extends Struct {
  /// Mean overall safety score across all Monte Carlo runs.
  @Float()
  external double overallMean;

  /// Mean grip contribution score.
  @Float()
  external double gripMean;

  /// Mean visibility contribution score.
  @Float()
  external double visibilityMean;

  /// Mean fleet-confidence contribution score.
  @Float()
  external double fleetMean;

  /// Variance of overall safety score across runs.
  @Float()
  external double overallVariance;

  /// Number of simulated incidents (score < threshold).
  @Uint32()
  external int incidentCount;

  /// Wall-clock execution time in milliseconds.
  @Float()
  external double executionMs;
}

/// Native C function signature for `simulation_run_batch`.
typedef _RunBatchNative = NativeSimulationResponse Function(
  Uint32 runs,
  Uint32 seed,
  Float speed,
  Float gripFactor,
  Uint32 surfaceCode,
  Float visibilityMeters,
);

/// Dart-side signature after marshalling.
typedef _RunBatchDart = NativeSimulationResponse Function(
  int runs,
  int seed,
  double speed,
  double gripFactor,
  int surfaceCode,
  double visibilityMeters,
);

/// Loads the platform-specific native simulation library and provides
/// a typed [runBatch] method for Monte Carlo safety-score computation.
class NativeSimulationBindings {
  /// Creates bindings, loading [library] or the platform default.
  NativeSimulationBindings({DynamicLibrary? library})
    : _library = library ?? DynamicLibrary.open(defaultLibraryPath());

  final DynamicLibrary _library;

  /// Runs [runs] Monte Carlo iterations with the given driving parameters.
  ///
  /// Returns a [NativeSimulationResponse] with mean scores and variance.
  NativeSimulationResponse runBatch({
    required int runs,
    required int seed,
    required double speed,
    required double gripFactor,
    required int surfaceCode,
    required double visibilityMeters,
  }) {
    final function = _library.lookupFunction<_RunBatchNative, _RunBatchDart>(
      'simulation_run_batch',
    );
    return function(runs, seed, speed, gripFactor, surfaceCode, visibilityMeters);
  }

  /// Returns the platform-appropriate path to the compiled C library.
  static String defaultLibraryPath() {
    if (Platform.isLinux) {
      return '${Directory.current.path}/native/build/libsimulation_engine.so';
    }

    if (Platform.isMacOS) {
      return '${Directory.current.path}/native/build/libsimulation_engine.dylib';
    }

    if (Platform.isWindows) {
      return '${Directory.current.path}\\native\\build\\simulation_engine.dll';
    }

    throw UnsupportedError('Native simulation spike is unsupported here.');
  }
}