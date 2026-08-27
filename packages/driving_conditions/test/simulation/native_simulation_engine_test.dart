import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';

void main() {
  final nativeLibrary = File(
    '${Directory.current.path}/native/build/libsimulation_engine.so',
  );
  final shouldSkip = !Platform.isLinux || !nativeLibrary.existsSync();

  test('native engine matches cpu engine within epsilon', skip: shouldSkip, () {
    // 0.6.1: both engines take an EXPLICITLY asserted fleet confidence. The
    // default is now unavailable(), and with an absent fleet term the native
    // engine deliberately delegates to the CPU path (its kernel cannot express
    // absence) — which would make this a CPU-vs-CPU comparison and stop
    // exercising the FFI kernel this test exists to check.
    const cpuEngine = CpuSafetyScoreSimulationEngine(
      provider: ConstantFleetConfidenceProvider(0.8),
    );
    final nativeEngine = NativeSafetyScoreSimulationEngine(
      provider: const ConstantFleetConfidenceProvider(0.8),
    );
    const options = SimulationOptions(runs: 5000, seed: 42);

    final cpu = cpuEngine.simulate(
      speed: 55,
      gripFactor: 0.65,
      surface: RoadSurfaceState.wet,
      visibilityMeters: 650,
      options: options,
    );
    final native = nativeEngine.simulate(
      speed: 55,
      gripFactor: 0.65,
      surface: RoadSurfaceState.wet,
      visibilityMeters: 650,
      options: options,
    );

    expect(native.score.overall, closeTo(cpu.score.overall, 0.005));
    expect(native.score.gripScore, closeTo(cpu.score.gripScore, 0.005));
    expect(
      native.score.visibilityScore,
      closeTo(cpu.score.visibilityScore, 0.005),
    );
    expect(
      native.score.fleetConfidenceScore!,
      closeTo(cpu.score.fleetConfidenceScore!, 0.0001),
    );
    expect(native.variance, isNonNegative);
    expect(native.executionMs, isNotNull);
  });
}