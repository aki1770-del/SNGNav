// In-drive compound-failure advisory, offline + deterministic.
//
// An integrator assembles a DriveSituation from the bands the catalog already
// publishes — localization_fallback's LocalizationEstimate, a pretrip_source_*
// VisibilityObservation, and the condition_aggregator advisory it selected.
// Here we build them inline so the example is reproducible with no network.
//
// HONESTY (binding): there is no "safe" value anywhere; the strongest positive
// is `continueDriving` = "no heightened concern given what is KNOWN". The
// ceiling is `considerStopping` — an owned, reversible option, never "turn
// back". Advisory-only: it labels the moment; she drives it.
import 'package:compound_failure_advisor/compound_failure_advisor.dart';

void main() {
  // She is already driving toward her mother in Akita. Watch one moment degrade.

  // 1. Start: trusted GPS, a clear km ahead, no advisory, steady speed.
  final calm = DriveSituation(
    positionTrust: PositionTrust.trusted,
    confidenceRadiusMeters: 12,
    secondsSinceTrustedFix: 0,
    hasPosition: true,
    visibilityMeters: 1500,
    visibilityAgeSeconds: 20,
    advisorySeverity: null,
    speedMetersPerSecond: 14,
  );

  // 2. Compound failure: the fix has gone to dead-reckoning (the dot is now a
  //    ~220 m circle) AND a squall drops visibility to 120 m — both at once.
  final whiteout = DriveSituation(
    positionTrust: PositionTrust.degraded,
    confidenceRadiusMeters: 220,
    secondsSinceTrustedFix: 75,
    hasPosition: true,
    visibilityMeters: 120,
    visibilityAgeSeconds: 30,
    advisorySeverity: AdvisoryLevel.severe,
    speedMetersPerSecond: 14,
  );

  for (final entry in {'BEFORE': calm, 'DEGRADED': whiteout}.entries) {
    final advice = adviseInDrive(entry.value);
    print('--- ${entry.key} ---');
    print('  action          : ${advice.action.name}');
    print('  compounding     : ${advice.compounding}');
    print('  positionUncertain: ${advice.positionUncertain}');
    print('  visibilityKnown : ${advice.visibilityKnown}');
    print('  visibilityLow   : ${advice.visibilityLow}');
    print('  reasons         : ${advice.reasons.map((r) => r.name).toList()}');
    print('  unknowns        : ${advice.unknowns.map((u) => u.name).toList()}');
    print('  sightStopHintMps: ${advice.sightStoppingSpeedHintMps}');
  }
}
