library;

import 'dart:ffi';
import 'dart:io';

final class NativeSimulationResponse extends Struct {
  @Float()
  external double overallMean;

  @Float()
  external double gripMean;

  @Float()
  external double visibilityMean;

  @Float()
  external double fleetMean;

  @Float()
  external double overallVariance;

  @Uint32()
  external int incidentCount;

  @Float()
  external double executionMs;
}

typedef _RunBatchNative = NativeSimulationResponse Function(
  Uint32 runs,
  Uint32 seed,
  Float speed,
  Float gripFactor,
  Uint32 surfaceCode,
  Float visibilityMeters,
);
typedef _RunBatchDart = NativeSimulationResponse Function(
  int runs,
  int seed,
  double speed,
  double gripFactor,
  int surfaceCode,
  double visibilityMeters,
);

class NativeSimulationBindings {
  NativeSimulationBindings({DynamicLibrary? library})
    : _library = library ?? DynamicLibrary.open(defaultLibraryPath());

  final DynamicLibrary _library;

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