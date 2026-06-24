import 'package:driving_conditions/driving_conditions.dart';

import 'vehicle_condition_signals.dart';

/// One emission from [VehicleConditionFusion].
///
/// Either a live condition ([isAvailable] == true, [assessment] non-null), or
/// an honest unavailability marker ([VehicleConditionUpdate.unavailable])
/// telling the caller there are no live vehicle signals — never a fabricated
/// scene. SDK-neutral: nothing here references any databroker transport.
class VehicleConditionUpdate {
  const VehicleConditionUpdate({
    required this.assessment,
    required this.signals,
    required this.live,
    this.unavailableReason,
  });

  /// An honest "no live vehicle signals" marker — carries no assessment.
  const VehicleConditionUpdate.unavailable({String? reason})
      : assessment = null,
        signals = null,
        live = false,
        unavailableReason = reason ?? 'no live vehicle signals';

  /// The fused driving-condition picture, or `null` when unavailable.
  final DrivingConditionAssessment? assessment;

  /// The vehicle signals behind [assessment], or `null` when unavailable.
  final VehicleConditionSignals? signals;

  /// True when this update reflects real, live vehicle signals.
  final bool live;

  /// Why no live signals are available, when [isAvailable] is false.
  final String? unavailableReason;

  /// Whether this update carries a usable assessment.
  bool get isAvailable => assessment != null;
}
