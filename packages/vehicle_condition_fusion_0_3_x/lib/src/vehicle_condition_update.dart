import 'package:driving_conditions/driving_conditions.dart';

import 'vehicle_condition_signals.dart';

/// One emission from [VehicleConditionFusion].
///
/// Either a live condition ([isAvailable] == true, [assessment] non-null), or
/// an honest no-verdict marker — never a fabricated scene. SDK-neutral: nothing
/// here references any databroker transport.
///
/// There are two shapes of no-verdict, and [signals] tells them apart:
///
///  * **no live signals** — [VehicleConditionUpdate.unavailable]. The source
///    errored or ended. [signals] is `null`.
///  * **signals, but no verdict** (since 0.3.4). The vehicle IS publishing, and
///    what it publishes cannot support a classification: no hazard is asserted
///    and the ambient temperature every remaining branch of the classifier
///    reads was never measured. [signals] is retained so the caller can still
///    show what the vehicle did publish, and [unavailableReason] says what is
///    missing.
///
/// In both cases [live] is `false` and [assessment] is `null`, so a caller that
/// already branches on [isAvailable] — as the package example does — needs no
/// change. An abstention is not an alarm: it never asserts a hazard.
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
