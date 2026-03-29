/// Constant fleet confidence provider — named replacement for the 0.8 literal.
library;

import 'fleet_confidence_provider.dart';

/// A [FleetConfidenceProvider] that returns a fixed confidence value.
///
/// This is the explicit, named form of the `0.8` placeholder that was
/// hardcoded before Sprint 91. Use it when no fleet data is available,
/// or in tests that need a deterministic input.
///
/// ```dart
/// // Before Sprint 91 — implicit:
/// const fleetConfidenceScore = 0.8;
///
/// // After Sprint 91 — explicit:
/// const provider = ConstantFleetConfidenceProvider(); // default 0.8
/// final score = provider.confidence;
/// ```
class ConstantFleetConfidenceProvider implements FleetConfidenceProvider {
  /// Creates a constant provider with the given [value].
  ///
  /// Defaults to `0.8` — the pre-Sprint 91 baseline.
  const ConstantFleetConfidenceProvider([this._value = 0.8])
    : assert(_value >= 0.0 && _value <= 1.0, 'value must be in [0.0, 1.0]');

  final double _value;

  @override
  double get confidence => _value;
}
