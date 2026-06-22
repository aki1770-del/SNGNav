/// Offline position-integrity monitoring — the missing "when to stop believing
/// GPS" decision for Dart/Flutter navigation apps.
///
/// A confident-but-wrong fix (GPS multipath in a snow-loaded urban canyon, a
/// reflected signal that teleports the dot 200 m onto the next street) arrives
/// with a perfectly normal accuracy number. The platform reports accuracy; it
/// never decides trust. This package wraps your fused location stream and emits
/// a first-class [IntegrityVerdict] — trusted / suspect / failed, plus a
/// source-handoff recommendation (gps / deadReckoning / hold) — so an app can
/// stop issuing wrong-street turns and fall back to dead reckoning at the right
/// moment, when standard navigation has quietly started lying.
///
/// This release ships the calibration-free FLOOR: four physical-plausibility
/// gates that need only the fixes themselves (no motion model, no road graph,
/// no network, no calibration). Pure Dart, deterministic, low-end-ARM cheap.
///
/// HONESTY BOUND: a `trusted` verdict means "no fault detected by these tests",
/// not "position verified". The floor catches ABRUPT faults (teleports,
/// impossible motion); it does not catch a slow, smooth spoof. See
/// `KNOWN_LIMITATIONS.md`.
library;

export 'src/integrity_verdict.dart';
export 'src/position_fix.dart';
export 'src/position_integrity_monitor.dart';
