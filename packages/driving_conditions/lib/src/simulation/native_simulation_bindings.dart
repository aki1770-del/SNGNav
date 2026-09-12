/// FFI bindings to the native C simulation library.
///
/// Loads a platform-specific shared library and exposes
/// [NativeSimulationBindings.runBatch] for Monte Carlo simulation.
library;

import 'dart:ffi';
import 'dart:io';

/// Raw result struct returned by the native `simulation_run_batch` function.
///
/// ⚑ **The layout changed in 0.7.0.** `fleet_mean` was removed from the C
/// struct and `fleet_confidence` from the function signature, because the score
/// has no fleet term (see `SimulatedSafetyScore`). This is an ABI change:
/// `native/build/libsimulation_engine.so` must be rebuilt from the shipped
/// `native/native_simulation.c`. A 0.6.x binary will mis-read every field.
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

/// Native C signature for `simulation_abi_version`.
typedef _AbiVersionNative = Uint32 Function();

/// Dart-side signature for `simulation_abi_version`.
typedef _AbiVersionDart = int Function();

/// Thrown when the loaded shared library does not match the ABI this Dart code
/// was compiled against.
///
/// This is deliberately a hard failure. The alternative — proceeding — is worse
/// than a crash, because a mismatched library returns a plausible NUMBER rather
/// than an error, and that number is a safety score a driver acts on.
class NativeSimulationAbiMismatch implements Exception {
  /// Creates a mismatch error describing [found] against [expected].
  NativeSimulationAbiMismatch({required this.expected, required this.found, required this.path});

  /// ABI version this Dart code requires.
  final int expected;

  /// ABI version the loaded library reported, or `null` when the library is so
  /// old it exports no version symbol at all.
  final int? found;

  /// Path the library was loaded from.
  final String path;

  @override
  String toString() {
    // NOT "0.6.x or older". A CORRECTLY built library from any release before
    // the contract existed also exports no version symbol, so naming a version
    // range here would state something untrue about a sound build. Say what was
    // observed, not what it implies about which release someone has.
    final what = found == null
        ? 'exports no simulation_abi_version symbol, so it was built from a C '
              'source that predates the ABI contract'
        : 'reports ABI version $found';
    return 'NativeSimulationAbiMismatch: the native simulation library at\n'
        '  $path\n'
        '$what, but this code requires version $expected.\n\n'
        'A mismatched library does NOT crash — it returns a saturated, '
        'plausible-looking safety score. Refusing to run rather than return one.\n\n'
        // REBUILDING ALONE CAN LOOP FOREVER. If you vendored this package by
        // path or by copying it, your native/ directory is the OLD one: a
        // rebuild recompiles the old C and produces the same refused library,
        // and you can repeat that indefinitely. The C source must come from the
        // upgraded package FIRST. Stated because we ship this package with
        // "use via path dependency or copy into your project" in its own README.
        'Take native_simulation.c and CMakeLists.txt from the UPGRADED package —\n'
        'a rebuild alone recompiles the old source and is refused again — then:\n'
        '  (cd native && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build)';
  }
}

/// Loads the platform-specific native simulation library and provides
/// a typed [runBatch] method for Monte Carlo safety-score computation.
///
/// The ABI contract is verified at construction. See
/// [NativeSimulationAbiMismatch] for why this fails hard rather than degrading.
class NativeSimulationBindings {
  /// Creates bindings, loading [library] or the platform default.
  ///
  /// Throws [NativeSimulationAbiMismatch] if the loaded library's ABI version
  /// is absent or does not equal [expectedAbiVersion].
  NativeSimulationBindings({DynamicLibrary? library})
    : _library = library ?? DynamicLibrary.open(defaultLibraryPath()),
      _path = library == null ? defaultLibraryPath() : '<injected>' {
    _verifyAbi();
  }

  /// ABI version this Dart code requires. Must track `SIMULATION_ABI_VERSION`
  /// in `native/native_simulation.c`.
  static const int expectedAbiVersion = 2;

  final DynamicLibrary _library;
  final String _path;

  /// Reads the library's ABI version and refuses anything but an exact match.
  ///
  /// A library predating the contract exports no symbol at all; `lookupFunction`
  /// throws [ArgumentError] for that, which is translated rather than leaked,
  /// because "symbol not found" does not tell a reader what to do about it.
  void _verifyAbi() {
    int? found;
    try {
      found = _library
          .lookupFunction<_AbiVersionNative, _AbiVersionDart>(
            'simulation_abi_version',
          )();
    } on ArgumentError {
      found = null;
    }

    if (found != expectedAbiVersion) {
      throw NativeSimulationAbiMismatch(
        expected: expectedAbiVersion,
        found: found,
        path: _path,
      );
    }
  }

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
    return function(
      runs,
      seed,
      speed,
      gripFactor,
      surfaceCode,
      visibilityMeters,
    );
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