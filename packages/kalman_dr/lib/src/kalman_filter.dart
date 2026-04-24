/// Extended Kalman Filter for dead reckoning — replaces linear extrapolation.
///
/// State vector: `[latitude, longitude, speed, heading]` (4D).
/// Prediction: constant-velocity model (speed and heading held constant).
/// Measurement: GPS fix provides `[lat, lon, speed, heading]` directly.
///
/// When GPS is available, the filter fuses prediction with measurement,
/// producing a smoothed estimate. When GPS is lost (tunnel), the filter
/// predicts only — covariance grows, honestly signalling uncertainty.
///
/// The covariance diagonal maps to GeoPosition.accuracy:
///   accuracy = sqrt(P\[0\]\[0\] + P\[1\]\[1\]) * metres_per_degree
///
/// Safety: ASIL-QM — display only, no vehicle control.
///
/// A new developer should understand the predict/update cycle in 5 minutes.
library;

import 'dart:math' as math;

/// 4×4 matrix type — small enough to inline, no library needed.
typedef Mat4 = List<List<double>>;

/// 4-element vector type.
typedef Vec4 = List<double>;

/// Extended Kalman Filter for vehicle position estimation.
///
/// Usage:
/// ```dart
/// final kf = KalmanFilter();
///
/// // GPS fix arrives:
/// kf.update(lat: 35.17, lon: 136.88, speed: 11.0, heading: 90.0,
///           accuracy: 5.0, timestamp: DateTime.now());
///
/// // GPS lost — predict forward:
/// final predicted = kf.predict(const Duration(seconds: 1));
/// // predicted.accuracy grows over time (honest uncertainty).
/// ```
class KalmanFilter {
  // -----------------------------------------------------------------------
  // State
  // -----------------------------------------------------------------------

  /// State vector: [lat (°), lon (°), speed (m/s), heading (°)].
  Vec4 _x;

  /// Error covariance matrix (4×4).
  Mat4 _p;

  /// Timestamp of the last update or prediction.
  DateTime _lastTime;

  /// Whether the filter has received at least one measurement.
  bool _initialized = false;

  // -----------------------------------------------------------------------
  // Tuning constants
  // -----------------------------------------------------------------------

  /// Process noise — how much we distrust the constant-velocity model.
  ///
  /// Higher values = filter adapts faster but is noisier.
  /// Lower values = smoother but slower to respond to manoeuvres.
  ///
  /// Units: [lat²/s, lon²/s, (m/s)²/s, (°)²/s].
  /// Tuned for road driving at ~1 Hz GPS updates.
  static const _processNoise = [
    1e-10, // lat variance growth per second (~0.01m)
    1e-10, // lon variance growth per second (~0.01m)
    0.5, // speed variance growth per second (driver brakes/accelerates)
    1.0, // heading variance growth per second (driver turns)
  ];

  /// Measurement noise — how much we distrust the GPS.
  ///
  /// Derived from typical GPS accuracy (~5m = ~4.5e-5° lat).
  /// Speed and heading from GPS are noisier at low speeds.
  static const _defaultMeasurementNoise = [
    2e-9, // lat variance (~5m)²
    2e-9, // lon variance (~5m)²
    1.0, // speed variance (1 m/s)²
    25.0, // heading variance (5°)²
  ];

  /// Metres per degree of latitude (WGS84 approximation).
  static const _metresPerDegreeLat = 111320.0;

  /// Maximum covariance before the filter declares "position lost".
  /// Corresponds to ~500m accuracy — matches DeadReckoningState.maxAccuracy.
  static const maxCovarianceThreshold = 2e-5; // ~500m in degrees²

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------

  /// Creates a Kalman filter. Uninitialised until first [update] call.
  KalmanFilter()
      : _x = [0, 0, 0, 0],
        _p = _identity(1e6), // large initial uncertainty
        _lastTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Creates a Kalman filter initialised to a known state (for testing).
  KalmanFilter.withState({
    required double latitude,
    required double longitude,
    required double speed,
    required double heading,
    required DateTime timestamp,
    double initialAccuracy = 5.0,
  })  : _x = [latitude, longitude, speed, heading],
        _p = _diagFromAccuracy(initialAccuracy),
        _lastTime = timestamp,
        _initialized = true;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Whether the filter has been initialised with at least one GPS fix.
  bool get isInitialized => _initialized;

  /// Current state estimate.
  ({double lat, double lon, double speed, double heading}) get state => (
        lat: _x[0],
        lon: _x[1],
        speed: _x[2],
        heading: _x[3],
      );

  /// Current estimated accuracy in metres.
  ///
  /// Derived from the position covariance (`P[0][0] + P[1][1]`).
  /// Grows during prediction-only (tunnel), shrinks on GPS update.
  double get accuracyMetres {
    final latVar = _p[0][0];
    final lonVar = _p[1][1];
    // Convert degree² variance to metres using cos(lat) for longitude.
    final latRad = _x[0] * math.pi / 180.0;
    final lonScale = _metresPerDegreeLat * math.cos(latRad);
    // Guard against numerical errors making variance slightly negative.
    return math.sqrt(
      math.max(
        0.0,
        latVar * _metresPerDegreeLat * _metresPerDegreeLat +
            lonVar * lonScale * lonScale,
      ),
    );
  }

  /// Whether position uncertainty has exceeded the safety cap (~500m).
  bool get isAccuracyExceeded =>
      _p[0][0] + _p[1][1] > maxCovarianceThreshold;

  /// Predict the state forward by [dt] without a GPS measurement.
  ///
  /// Call this every second during GPS loss (tunnel dead reckoning).
  /// The covariance grows, honestly reporting increasing uncertainty.
  ///
  /// Returns the predicted state with current accuracy.
  ({double lat, double lon, double speed, double heading, double accuracy})
      predict(Duration dt) {
    if (!_initialized) {
      return (lat: 0, lon: 0, speed: 0, heading: 0, accuracy: double.infinity);
    }

    final dtSec = dt.inMilliseconds / 1000.0;
    if (dtSec <= 0) {
      return (
        lat: _x[0],
        lon: _x[1],
        speed: _x[2],
        heading: _x[3],
        accuracy: accuracyMetres,
      );
    }

    // --- Predict state: x' = f(x, dt) ---
    _x = _stateTransition(_x, dtSec);

    // --- Predict covariance: P' = F·P·Fᵀ + Q ---
    final f = _jacobian(_x, dtSec);
    final q = _processNoiseMatrix(dtSec);
    _p = _addMat(_mulMat(_mulMat(f, _p), _transpose(f)), q);

    _lastTime = _lastTime.add(dt);

    return (
      lat: _x[0],
      lon: _x[1],
      speed: _x[2],
      heading: _x[3],
      accuracy: accuracyMetres,
    );
  }

  /// Update the filter with a GPS measurement.
  ///
  /// Fuses the prediction with the GPS fix. If this is the first call,
  /// initialises the filter state directly from the measurement.
  ///
  /// The [accuracy] parameter (metres) scales the measurement noise:
  /// higher accuracy = more trust in GPS, lower = more trust in prediction.
  void update({
    required double lat,
    required double lon,
    required double speed,
    required double heading,
    required double accuracy,
    required DateTime timestamp,
  }) {
    if (!_initialized) {
      // First fix — initialise directly.
      _x = [lat, lon, speed, heading];
      _p = _diagFromAccuracy(accuracy);
      _lastTime = timestamp;
      _initialized = true;
      return;
    }

    // --- Predict to measurement time ---
    final dt = timestamp.difference(_lastTime);
    if (dt.inMilliseconds > 0) {
      predict(dt);
    }

    // --- Measurement vector ---
    final z = [lat, lon, speed, heading];

    // --- Measurement noise R (scaled by GPS accuracy) ---
    final accuracyDeg = accuracy / _metresPerDegreeLat;
    final r = _diag([
      accuracyDeg * accuracyDeg, // lat
      accuracyDeg * accuracyDeg, // lon
      _defaultMeasurementNoise[2], // speed
      _defaultMeasurementNoise[3], // heading
    ]);

    // --- Innovation: y = z - H·x (H = identity for direct observation) ---
    final y = _subVec(z, _x);

    // Handle heading wraparound (350° - 10° = -340° → should be +20°).
    y[3] = _wrapAngle(y[3]);

    // --- Innovation covariance: S = H·P·Hᵀ + R = P + R ---
    final s = _addMat(_p, r);

    // --- Kalman gain: K = P·Hᵀ·S⁻¹ = P·S⁻¹ ---
    final sInv = _invertMat(s);
    if (sInv == null) return; // singular — skip update
    final k = _mulMat(_p, sInv);

    // --- State update: x = x + K·y ---
    final ky = _mulMatVec(k, y);
    _x = _addVec(_x, ky);

    // Normalise heading to [0, 360).
    _x[3] = _normaliseHeading(_x[3]);

    // Clamp speed to non-negative.
    if (_x[2] < 0) _x[2] = 0;

    // --- Covariance update: P = (I - K·H)·P = (I - K)·P ---
    final iMinusK = _subMat(_identity(1), k);
    _p = _mulMat(iMinusK, _p);

    _lastTime = timestamp;
  }

  /// Reset the filter to uninitialised state.
  void reset() {
    _x = [0, 0, 0, 0];
    _p = _identity(1e6);
    _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
    _initialized = false;
  }

  // -----------------------------------------------------------------------
  // State transition model (constant velocity)
  // -----------------------------------------------------------------------

  /// f(x, dt): predict next state from current state.
  ///
  /// lat' = lat + speed·cos(heading)·dt / metresPerDegreeLat
  /// lon' = lon + speed·sin(heading)·dt / (metresPerDegreeLat·cos(lat))
  /// speed' = speed  (constant)
  /// heading' = heading  (constant)
  static Vec4 _stateTransition(Vec4 x, double dt) {
    final lat = x[0];
    final lon = x[1];
    final speed = x[2];
    final heading = x[3];

    final headingRad = heading * math.pi / 180.0;
    final latRad = lat * math.pi / 180.0;
    final distance = speed * dt;

    final cosLat = math.cos(latRad);
    final safeCosLat = cosLat.abs() < 0.001 ? 0.001 : cosLat; // pole guard

    final dLat = distance * math.cos(headingRad) / _metresPerDegreeLat;
    final dLon = distance *
        math.sin(headingRad) /
        (_metresPerDegreeLat * safeCosLat);

    return [lat + dLat, lon + dLon, speed, heading];
  }

  /// F = ∂f/∂x: Jacobian of the state transition.
  ///
  /// Needed for covariance propagation (P' = F·P·Fᵀ + Q).
  static Mat4 _jacobian(Vec4 x, double dt) {
    final lat = x[0];
    final speed = x[2];
    final heading = x[3];

    final headingRad = heading * math.pi / 180.0;
    final latRad = lat * math.pi / 180.0;
    final cosH = math.cos(headingRad);
    final sinH = math.sin(headingRad);
    final cosLat = math.cos(latRad);
    final safeCosLat = cosLat.abs() < 0.001 ? 0.001 : cosLat; // pole guard
    final sinLat = math.sin(latRad);

    // ∂lat'/∂speed = cos(heading)·dt / metresPerDegreeLat
    final dLatDSpeed = cosH * dt / _metresPerDegreeLat;

    // ∂lat'/∂heading = -speed·sin(heading)·dt / metresPerDegreeLat · (π/180)
    final dLatDHeading =
        -speed * sinH * dt / _metresPerDegreeLat * math.pi / 180.0;

    // ∂lon'/∂lat = speed·sin(heading)·dt·sin(lat) /
    //              (metresPerDegreeLat·cos²(lat)) · (π/180)
    final dLonDLat = speed *
        sinH *
        dt *
        sinLat /
        (_metresPerDegreeLat * safeCosLat * safeCosLat) *
        math.pi /
        180.0;

    // ∂lon'/∂speed = sin(heading)·dt / (metresPerDegreeLat·cos(lat))
    final dLonDSpeed = sinH * dt / (_metresPerDegreeLat * safeCosLat);

    // ∂lon'/∂heading = speed·cos(heading)·dt /
    //                  (metresPerDegreeLat·cos(lat)) · (π/180)
    final dLonDHeading =
        speed * cosH * dt / (_metresPerDegreeLat * safeCosLat) * math.pi / 180.0;

    return [
      [1, 0, dLatDSpeed, dLatDHeading], // ∂lat'/∂x
      [dLonDLat, 1, dLonDSpeed, dLonDHeading], // ∂lon'/∂x
      [0, 0, 1, 0], // ∂speed'/∂x
      [0, 0, 0, 1], // ∂heading'/∂x
    ];
  }

  // -----------------------------------------------------------------------
  // Noise matrices
  // -----------------------------------------------------------------------

  /// Process noise Q scaled by time step.
  static Mat4 _processNoiseMatrix(double dt) => _diag([
        _processNoise[0] * dt,
        _processNoise[1] * dt,
        _processNoise[2] * dt,
        _processNoise[3] * dt,
      ]);

  /// Create diagonal covariance from GPS accuracy (metres).
  ///
  /// [accuracyMetres] must be positive. Zero or negative accuracy produces a
  /// zero-covariance matrix, causing the filter to reject all future
  /// measurements (infinite Kalman gain trust in a zero-noise GPS).
  static Mat4 _diagFromAccuracy(double accuracyMetres) {
    // Floor to 1m — prevents zero/negative covariance from degenerate input.
    final safeAccuracy = accuracyMetres < 1.0 ? 1.0 : accuracyMetres;
    final accDeg = safeAccuracy / _metresPerDegreeLat;
    return _diag([
      accDeg * accDeg, // lat variance
      accDeg * accDeg, // lon variance
      1.0, // speed variance (1 m/s)²
      25.0, // heading variance (5°)²
    ]);
  }

  // -----------------------------------------------------------------------
  // Heading utilities
  // -----------------------------------------------------------------------

  /// Wrap angle difference to [-180, 180].
  static double _wrapAngle(double degrees) {
    var d = degrees % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Normalise heading to [0, 360).
  static double _normaliseHeading(double degrees) {
    var d = degrees % 360;
    if (d < 0) d += 360;
    return d;
  }

  // -----------------------------------------------------------------------
  // 4×4 matrix operations (inlined — no external dependency)
  // -----------------------------------------------------------------------

  static Mat4 _identity(double scale) => [
        [scale, 0, 0, 0],
        [0, scale, 0, 0],
        [0, 0, scale, 0],
        [0, 0, 0, scale],
      ];

  static Mat4 _diag(List<double> d) => [
        [d[0], 0, 0, 0],
        [0, d[1], 0, 0],
        [0, 0, d[2], 0],
        [0, 0, 0, d[3]],
      ];

  static Mat4 _transpose(Mat4 a) => [
        [a[0][0], a[1][0], a[2][0], a[3][0]],
        [a[0][1], a[1][1], a[2][1], a[3][1]],
        [a[0][2], a[1][2], a[2][2], a[3][2]],
        [a[0][3], a[1][3], a[2][3], a[3][3]],
      ];

  static Mat4 _addMat(Mat4 a, Mat4 b) => List.generate(
      4, (i) => List.generate(4, (j) => a[i][j] + b[i][j]));

  static Mat4 _subMat(Mat4 a, Mat4 b) => List.generate(
      4, (i) => List.generate(4, (j) => a[i][j] - b[i][j]));

  static Mat4 _mulMat(Mat4 a, Mat4 b) => List.generate(
      4,
      (i) => List.generate(4, (j) {
            var sum = 0.0;
            for (var k = 0; k < 4; k++) {
              sum += a[i][k] * b[k][j];
            }
            return sum;
          }));

  static Vec4 _mulMatVec(Mat4 a, Vec4 v) => List.generate(4, (i) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[i][k] * v[k];
        }
        return sum;
      });

  static Vec4 _addVec(Vec4 a, Vec4 b) =>
      List.generate(4, (i) => a[i] + b[i]);

  static Vec4 _subVec(Vec4 a, Vec4 b) =>
      List.generate(4, (i) => a[i] - b[i]);

  /// 4×4 matrix inversion using cofactor expansion.
  /// Returns null if the matrix is singular (determinant ≈ 0).
  static Mat4? _invertMat(Mat4 m) {
    // Compute cofactors for 4×4 — expanded inline for clarity.
    final det = _det4(m);
    if (det.abs() < 1e-30) return null;

    final invDet = 1.0 / det;
    final adj = List.generate(4, (_) => List.filled(4, 0.0));

    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        final minor = _minor3(m, i, j);
        final sign = ((i + j) % 2 == 0) ? 1.0 : -1.0;
        adj[j][i] = sign * minor * invDet; // transposed
      }
    }
    return adj;
  }

  /// Determinant of a 4×4 matrix (Laplace expansion along first row).
  static double _det4(Mat4 m) {
    var det = 0.0;
    for (var j = 0; j < 4; j++) {
      final sign = (j % 2 == 0) ? 1.0 : -1.0;
      det += sign * m[0][j] * _minor3(m, 0, j);
    }
    return det;
  }

  /// 3×3 minor determinant (exclude row i, column j).
  static double _minor3(Mat4 m, int row, int col) {
    final r = <List<double>>[];
    for (var i = 0; i < 4; i++) {
      if (i == row) continue;
      final c = <double>[];
      for (var j = 0; j < 4; j++) {
        if (j == col) continue;
        c.add(m[i][j]);
      }
      r.add(c);
    }
    // 3×3 determinant.
    return r[0][0] * (r[1][1] * r[2][2] - r[1][2] * r[2][1]) -
        r[0][1] * (r[1][0] * r[2][2] - r[1][2] * r[2][0]) +
        r[0][2] * (r[1][0] * r[2][1] - r[1][1] * r[2][0]);
  }
}
