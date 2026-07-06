// How an integrator wires the in-drive worst-case chain: take the localization
// estimate and the selected area advisory the SNGNav catalog already produces,
// fuse them into the advisor's input, and ask for advice. Advisory-only — she
// drives it.
import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:drive_situation_fusion/drive_situation_fusion.dart';
import 'package:localization_fallback/localization_fallback.dart';

void main() {
  // GPS has dropped in a snow tunnel — the dot is carried by dead reckoning and
  // the confidence radius is growing. She can barely see. A severe area warning
  // is in force.
  final estimate = LocalizationEstimate(
    latitude: 39.72,
    longitude: 140.10,
    confidenceRadiusMeters: 280,
    mode: LocalizationMode.deadReckoning,
    secondsSinceTrustedFix: 75,
    basis: EstimateBasis.deadReckoning,
  );

  final advisory = Advisory(
    source: AdvisorySource.other,
    eventClass: 'Heavy Snow Warning',
    severity: AdvisorySeverity.severe,
    certainty: AdvisoryCertainty.observed,
    urgency: AdvisoryUrgency.immediate,
    areaDescription: 'Akita',
    effective: null,
    expires: null,
    headline: 'Heavy snow warning in force',
    description: 'Visibility falling; road icing likely.',
  );

  // The caller owns the clock, so it computes the reading's age and passes it.
  final situation = fuseDriveSituation(
    estimate: estimate,
    advisory: advisory,
    visibilityMeters: 60,
    visibilityAgeSeconds: 4,
    speedMetersPerSecond: 11,
  );

  final advice = adviseInDrive(situation);

  print('action:          ${advice.action}');
  print('positionUncertain: ${advice.positionUncertain}');
  print('visibilityLow:   ${advice.visibilityLow}');
  print('compounding:     ${advice.compounding}'); // true — danger compounds
}
