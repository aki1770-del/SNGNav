/// Constant fleet confidence provider — named replacement for the 0.8 literal.
library;

import 'fleet_confidence_provider.dart';

/// A [FleetConfidenceProvider] that returns a fixed confidence value.
///
/// Use it to ASSERT a fleet confidence you actually mean — a test fixture, a
/// scenario, a simulator input.
///
/// **Do NOT use it for "no fleet data".** That is
/// [ConstantFleetConfidenceProvider.unavailable], whose [confidence] is `null`.
/// Asserting a scenario is honest; laundering an ABSENCE into an assertion is
/// not.
///
/// ⚑ **0.7.0 made [value] required.** It used to default to `0.8`, and every
/// defect in this chain began with an `0.8` that appeared without anyone typing
/// it: 0.6.0's three engine constructors defaulted to `ConstantFleetConfidenceProvider()`
/// and so reported a fleet that had never spoken. A value nobody stated is not
/// an assertion, and this class exists only to carry assertions.
///
/// ```dart
/// // An ASSERTED confidence — you mean this number:
/// const asserted = ConstantFleetConfidenceProvider(0.8);
/// asserted.confidence; // 0.8
///
/// // NO fleet data — the honest form:
/// const absent = ConstantFleetConfidenceProvider.unavailable();
/// absent.confidence; // null
/// ```
///
/// Note that neither form reaches `SimulatedSafetyScore` any more — the score
/// has no fleet term as of 0.7.0. See [FleetConfidenceProvider].
class ConstantFleetConfidenceProvider implements FleetConfidenceProvider {
  /// Creates a constant provider asserting [value].
  ///
  /// [value] is REQUIRED. There is no default, deliberately: see the class doc.
  const ConstantFleetConfidenceProvider(double value)
    : assert(value >= 0.0 && value <= 1.0, 'value must be in [0.0, 1.0]'),
      _value = value;

  /// A provider that has NO fleet data. [confidence] is `null`.
  const ConstantFleetConfidenceProvider.unavailable() : _value = null;

  final double? _value;

  @override
  double? get confidence => _value;
}
