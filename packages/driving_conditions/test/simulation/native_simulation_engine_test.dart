import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';

void main() {
  final nativeLibrary = File(
    '${Directory.current.path}/native/build/libsimulation_engine.so',
  );
  final shouldSkip = !Platform.isLinux || !nativeLibrary.existsSync();

  test('native engine matches cpu engine within epsilon', skip: shouldSkip, () {
    // 0.7.0: neither engine takes a provider, and the native engine no longer
    // has a CPU fallback — the kernel's 7th argument (fleet_confidence) and the
    // struct's fleet_mean field are gone, so the FFI path is always taken and
    // this test always exercises it. The C weights are 0.5/0.5, matching Dart.
    // ⚑ This test compares a REBUILT libsimulation_engine.so; a 0.6.x binary is
    // an ABI mismatch and would fail here rather than silently mis-read.
    const cpuEngine = CpuSafetyScoreSimulationEngine();
    final nativeEngine = NativeSafetyScoreSimulationEngine();
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
    expect(native.variance, isNonNegative);
    expect(native.executionMs, isNotNull);
  });
}