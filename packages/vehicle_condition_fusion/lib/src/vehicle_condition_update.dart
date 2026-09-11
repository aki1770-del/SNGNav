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
    this.observedAt,
    this.fieldObservedAt = const {},
  });

  /// An honest "no live vehicle signals" marker — carries no assessment.
  const VehicleConditionUpdate.unavailable({String? reason})
      : assessment = null,
        signals = null,
        live = false,
        unavailableReason = reason ?? 'no live vehicle signals',
        observedAt = null,
        fieldObservedAt = const {};

  /// The fused driving-condition picture, or `null` when unavailable.
  final DrivingConditionAssessment? assessment;

  /// The vehicle signals behind [assessment], or `null` when unavailable.
  final VehicleConditionSignals? signals;

  /// True when this update reflects real, live vehicle signals.
  final bool live;

  /// Why no live signals are available, when [isAvailable] is false.
  final String? unavailableReason;

  /// When the newest contributing frame actually arrived from the vehicle.
  ///
  /// NOT the time this update was fused. On the partial-frame rail those differ
  /// by however long the transport has been quiet, which is exactly the
  /// difference an integrator needs and could not previously see.
  final DateTime? observedAt;

  /// When each individual signal was last actually SENT by the vehicle, keyed
  /// by [VehicleSignalField].
  ///
  /// The carry-forward merge means the fields of [signals] do not share an age:
  /// a friction reading may be minutes older than the speed beside it. Without
  /// this map an integrator cannot bound signal age, because the component
  /// never told it what the ages were.
  final Map<String, DateTime> fieldObservedAt;

  /// Age of [field] at [now], or `null` if the vehicle never sent it.
  Duration? ageOf(String field, DateTime now) {
    final at = fieldObservedAt[field];
    return at == null ? null : now.difference(at);
  }

  /// Whether this update carries a usable assessment.
  bool get isAvailable => assessment != null;
}
