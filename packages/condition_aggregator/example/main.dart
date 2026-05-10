// Minimal example for condition_aggregator.
//
// Demonstrates the source-neutral Advisory typed event the umbrella
// interface defines. Per-source adapter packages
// (`condition_aggregator_jma`, `condition_aggregator_nws`,
// `condition_aggregator_owm_road_risk`) implement `AdvisoryProvider`
// and produce these typed events; consumers receive a single typed
// shape across publishers.

import 'package:condition_aggregator/condition_aggregator.dart';

void main() {
  const advisory = Advisory(
    source: AdvisorySource.nwsUnitedStates,
    eventClass: 'Winter Storm Warning',
    severity: AdvisorySeverity.severe,
    certainty: AdvisoryCertainty.likely,
    urgency: AdvisoryUrgency.expected,
    areaDescription: 'Erie County, NY',
    effective: null,
    expires: null,
    headline: 'Heavy snow expected',
    description:
        'Heavy snow expected. Travel could be very difficult to impossible.',
  );

  print('Advisory from ${advisory.source.name}: ${advisory.headline}');
  print('Severity: ${advisory.severity.name}');
  print('Area: ${advisory.areaDescription}');
}
