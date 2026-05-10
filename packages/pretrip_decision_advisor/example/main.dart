// Minimal example for pretrip_decision_advisor.
//
// 0.1.0 ships interface-only — abstract PretripAdvisor + DTOs + enums.
// This example demonstrates the typed surface; reference
// implementations compose with the contract.

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

void main() {
  print(
    'CommuteFlexibility values: '
    '${CommuteFlexibility.values.map((v) => v.name).toList()}',
  );
  print(
    'RoadConditionEstimate values: '
    '${RoadConditionEstimate.values.map((v) => v.name).toList()}',
  );
  print(
    'RecommendationStrength values: '
    '${RecommendationStrength.values.map((v) => v.name).toList()}',
  );
}
