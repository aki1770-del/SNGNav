import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_conditions/src/simulation/native_safety_score_simulation_engine.dart';
import 'package:test/test.dart';

void main() {
  final nativeLibrary = File(
    '${Directory.current.path}/native/build/libsimulation_engine.so',
  );
  final shouldSkip = !Platform.isLinux || !nativeLibrary.existsSync();

  test('native engine matches cpu engine within epsilon', skip: shouldSkip, () {
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

    expect(native.overall, closeTo(cpu.overall, 0.005));
    expect(native.gripScore, closeTo(cpu.gripScore, 0.005));
    expect(native.visibilityScore, closeTo(cpu.visibilityScore, 0.005));
    expect(
      native.fleetConfidenceScore,
      closeTo(cpu.fleetConfidenceScore, 0.0001),
    );
  });
}