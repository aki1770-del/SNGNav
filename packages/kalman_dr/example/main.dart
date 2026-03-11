import 'package:kalman_dr/kalman_dr.dart';

void main() {
  final timestamp = DateTime.now();
  final filter = KalmanFilter.withState(
    latitude: 35.1709,
    longitude: 136.9066,
    speed: 13.5,
    heading: 90.0,
    timestamp: timestamp,
    initialAccuracy: 5.0,
  );

  final predicted = filter.predict(const Duration(seconds: 2));

  filter.update(
    lat: 35.1709,
    lon: 136.9070,
    speed: 12.8,
    heading: 92.0,
    accuracy: 4.5,
    timestamp: timestamp.add(const Duration(seconds: 2)),
  );

  print('predicted lat/lon: '
      '${predicted.lat.toStringAsFixed(6)}, '
      '${predicted.lon.toStringAsFixed(6)}');
  print('predicted accuracy: ${predicted.accuracy.toStringAsFixed(1)}m');
  print('updated accuracy: ${filter.accuracyMetres.toStringAsFixed(1)}m');
  print('safety cap exceeded: ${filter.isAccuracyExceeded}');
}