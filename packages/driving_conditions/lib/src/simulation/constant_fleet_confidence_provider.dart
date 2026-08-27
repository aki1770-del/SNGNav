/// Constant fleet confidence provider — named replacement for the 0.8 literal.
library;

import 'fleet_confidence_provider.dart';

/// A [FleetConfidenceProvider] that returns a fixed confidence value.
///
/// This is the explicit, named form of the `0.8` placeholder that was
/// hardcoded before Sprint 91. Use it to ASSERT a fleet confidence you
/// actually mean — a test fixture, a scenario, a simulator input.
///
/// **Do NOT use it for "no fleet data".** That is
/// [ConstantFleetConfidenceProvider.unavailable], whose [confidence] is
/// `null`. Asserting a scenario is honest; laundering an ABSENCE into an
/// assertion is the defect 0.6.0 removed from the score — and then shipped
/// anyway through three default constructor arguments, until 0.6.1.
///
/// ```dart
/// // An ASSERTED confidence — you mean this number:
/// const asserted = ConstantFleetConfidenceProvider(0.8);
/// asserted.confidence; // 0.8
///
/// // NO fleet data — the honest form, and the engines' default:
/// const absent = ConstantFleetConfidenceProvider.unavailable();
/// absent.confidence; // null
/// ```
class ConstantFleetConfidenceProvider implements FleetConfidenceProvider {
  /// Creates a constant provider with the given [value].
  ///
  /// Defaults to `0.8` — the pre-Sprint 91 baseline. This is an ASSERTED
  /// value, not a measurement, and that is legitimate here: the caller is
  /// deliberately declaring a fleet confidence (a test fixture, a scenario, a
  /// simulator). It is the exact counterpart of
  /// `WeatherCondition.simulatedClear()` in `driving_weather` — asserting a
  /// scenario is honest; laundering an ABSENCE into an assertion is not.
  ///
  /// For "no fleet data", use [ConstantFleetConfidenceProvider.unavailable]
  /// rather than passing a number.
  const ConstantFleetConfidenceProvider([double value = 0.8])
    : assert(value >= 0.0 && value <= 1.0, 'value must be in [0.0, 1.0]'),
      _value = value;

  /// A provider that has NO fleet data. [confidence] is `null`.
  const ConstantFleetConfidenceProvider.unavailable() : _value = null;

  final double? _value;

  @override
  double? get confidence => _value;
}
