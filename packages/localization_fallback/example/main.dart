// A whiteout in miniature, offline + deterministic.
//
// We feed the controller one good trusted fix, then GPS goes away. A simple
// dead-reckoning seam (here a constant-velocity stub; you would back it with
// kalman_dr) carries the position while the confidence radius GROWS — until it
// crosses the honesty horizon and the mode becomes `lost`. Watch the radius:
// it never shrinks without a trusted fix, and the dot is never "confident" once
// GPS is gone.
import 'package:localization_fallback/localization_fallback.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);

  // A toy dead-reckoning seam: keep crawling north at ~10 m/s from the last
  // trusted point. Real code wires kalman_dr here; the controller degrades its
  // confidence truthfully regardless of how good the seam claims to be.
  const lastLat = 39.7036; // Akita
  const lastLon = 140.1031;
  DeadReckoningEstimate? seam(DateTime asOf) {
    final dt = asOf.difference(t0).inMicroseconds / 1e6;
    final metresNorth = 10.0 * dt; // 10 m/s
    final dLat = metresNorth / 111320.0;
    return DeadReckoningEstimate(latitude: lastLat + dLat, longitude: lastLon);
  }

  final controller = LocalizationController(
    config: const LocalizationConfig(
      driftRateMetersPerSecond: 8.0, // admit uncertainty quickly in a whiteout
      maxTrustworthyRadiusMeters: 300.0,
      maxDeadReckoningSeconds: 120.0,
    ),
    deadReckoningSeam: seam,
  );

  void show(String label, LocalizationEstimate e) {
    print('${label.padRight(22)} '
        'mode=${e.mode.name.padRight(13)} '
        'radius=${e.confidenceRadiusMeters.toStringAsFixed(0).padLeft(4)}m  '
        'since=${e.secondsSinceTrustedFix.toStringAsFixed(0).padLeft(3)}s  '
        'basis=${e.basis.name}');
  }

  print('--- localization_fallback degradation demo ---');

  // 1. A good, trusted fix.
  show('trusted fix', controller.onFix(
    RawFix(
      latitude: lastLat,
      longitude: lastLon,
      accuracyMeters: 6,
      timestamp: t0,
    ),
    trust: TrustSignal.trusted,
  ));

  // 2. GPS integrity goes suspect — the fix is present but not believed; we do
  //    NOT jump to its coordinates.
  show('suspect (t+5s)', controller.onFix(
    RawFix(
      latitude: 39.9000, // a wild 20+ km jump — must be ignored
      longitude: 140.4000,
      accuracyMeters: 5, // confidently wrong
      timestamp: t0.add(const Duration(seconds: 5)),
    ),
    trust: TrustSignal.suspect,
  ));

  // 3. GPS is gone. We poll on a tick; dead reckoning carries us, radius grows.
  for (final s in [10, 20, 30, 40]) {
    show('dead-reckon (t+${s}s)', controller.poll(t0.add(Duration(seconds: s))));
  }

  // 4. Far enough out that we cross the honesty horizon → lost (still returns a
  //    position, but says plainly it is a guess).
  for (final s in [60, 90, 130]) {
    show('blackout (t+${s}s)', controller.poll(t0.add(Duration(seconds: s))));
  }

  // 5. A trusted fix returns — and ONLY now may the radius shrink: we reconverge.
  show('trusted returns (t+140s)', controller.onFix(
    RawFix(
      latitude: 39.7050,
      longitude: 140.1040,
      accuracyMeters: 8,
      timestamp: t0.add(const Duration(seconds: 140)),
    ),
    trust: TrustSignal.trusted,
  ));
}
