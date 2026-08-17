/// Pure-Dart localization fallback: one honest position estimate that degrades
/// truthfully from trusted GPS to dead reckoning to `lost`, and never emits a
/// confidently-wrong fix.
///
/// See [LocalizationController] for the state machine and its honesty contract.
library;

export 'src/dead_reckoning_estimate.dart';
export 'src/estimate_basis.dart';
export 'src/localization_config.dart';
export 'src/localization_controller.dart';
export 'src/localization_estimate.dart';
export 'src/localization_mode.dart';
export 'src/raw_fix.dart';
export 'src/trust_signal.dart';
