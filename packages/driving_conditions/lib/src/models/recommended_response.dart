// Re-exported from snow_rendering.
//
// This re-export was MISSING up to 0.5.4: `DrivingConditionAssessment` was
// re-exported, but the type of its `recommendedResponse` field was not — so a
// consumer importing only `package:driving_conditions` could hold the value but
// could not NAME the type, and therefore could not switch on it.
//
// That gap became load-bearing in 0.6.0: `RecommendedResponse.conditionsUnknown`
// is the tier a consumer MUST handle to avoid treating an unassessed road as a
// clear one. A contract the consumer cannot name is a contract that does not
// reach them.
export 'package:snow_rendering/snow_rendering.dart' show RecommendedResponse;
