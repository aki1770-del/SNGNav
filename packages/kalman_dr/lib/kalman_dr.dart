/// Kalman filter dead reckoning for location services.
///
/// Provides a 4D Extended Kalman Filter and linear extrapolation for
/// estimating position during GPS loss (tunnels, urban canyons).
///
/// Two modes:
/// - **Kalman**: EKF with covariance-driven accuracy. Fuses GPS measurements
///   with predictions. Accuracy degrades honestly during GPS loss.
/// - **Linear**: Constant-velocity extrapolation. Simple baseline mode.
///
/// Safety: ASIL-QM — display only, no vehicle control.
///
/// ```dart
/// import 'package:kalman_dr/kalman_dr.dart';
///
/// final provider = DeadReckoningProvider(
///   inner: myGpsProvider,
///   mode: DeadReckoningMode.kalman,
/// );
/// await provider.start();
/// provider.positions.listen((pos) {
///   print('${pos.latitude}, ${pos.longitude} ±${pos.accuracy}m');
/// });
/// ```
library;

export 'src/dead_reckoning_provider.dart';
export 'src/dead_reckoning_state.dart';
export 'src/geo_position.dart';
export 'src/kalman_filter.dart';
export 'src/location_provider.dart';
