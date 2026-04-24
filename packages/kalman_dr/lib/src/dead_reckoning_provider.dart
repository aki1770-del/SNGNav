/// Dead reckoning location provider — tunnel fallback.
///
/// Wraps an inner [LocationProvider] (e.g., GeoClue2) using the decorator
/// pattern. When GPS signal is lost for `gpsTimeout` seconds, begins
/// predicting position using either:
///   - **linear**: constant-velocity extrapolation (baseline mode)
///   - **kalman**: Extended Kalman Filter with covariance tracking
///
/// The consumer sees only a stream of [GeoPosition] — no changes needed.
/// Dead reckoning positions have degrading accuracy so the consumer
/// correctly transitions from `fix` → `degraded` as uncertainty grows.
///
/// Safety: ASIL-QM — display only, no vehicle control.
///
/// Offline behavior: when GPS is lost, dead reckoning
/// provides estimated positions. When accuracy exceeds 500m safety cap,
/// stream stops emitting — driver sees "position unavailable".
library;

import 'dart:async';

import 'dead_reckoning_state.dart';
import 'geo_position.dart';
import 'kalman_filter.dart';
import 'location_provider.dart';

/// Dead reckoning mode selection.
enum DeadReckoningMode {
  /// Linear extrapolation (constant velocity, constant heading).
  /// Baseline mode. Simple, predictable, no filtering.
  linear,

  /// Extended Kalman Filter. Fuses GPS measurements with predictions.
  /// Provides covariance-based accuracy (honest uncertainty).
  /// Advanced mode with covariance-based accuracy.
  kalman,
}

/// Dead reckoning wrapper for any [LocationProvider].
///
/// Usage:
/// ```dart
/// final gps = MyGpsProvider();
/// // Linear mode (baseline):
/// final linear = DeadReckoningProvider(inner: gps);
/// // Kalman mode (advanced):
/// final kalman = DeadReckoningProvider(
///   inner: gps,
///   mode: DeadReckoningMode.kalman,
/// );
/// ```
class DeadReckoningProvider implements LocationProvider {
  final LocationProvider _inner;

  /// Dead reckoning algorithm: linear extrapolation or Kalman filter.
  final DeadReckoningMode mode;

  /// How long to wait after the last GPS position before starting DR.
  /// Default: 3 seconds.
  final Duration gpsTimeout;

  /// How often to emit extrapolated positions during DR.
  /// Default: 1 second — matches typical GPS update rate.
  final Duration extrapolationInterval;

  // Internal state — linear mode.
  DeadReckoningState? _lastState;

  // Internal state — Kalman mode.
  KalmanFilter? _kalman;

  // Shared state.
  Timer? _drTimer;
  Timer? _gpsWatchdog;
  StreamController<GeoPosition>? _controller;
  StreamSubscription<GeoPosition>? _innerSub;
  bool _isDrActive = false;

  DeadReckoningProvider({
    required LocationProvider inner,
    this.mode = DeadReckoningMode.linear,
    this.gpsTimeout = const Duration(seconds: 3),
    this.extrapolationInterval = const Duration(seconds: 1),
  }) : _inner = inner;

  @override
  Stream<GeoPosition> get positions {
    _controller ??= StreamController<GeoPosition>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start() async {
    // Stop any in-progress DR and cancel watchdog before re-initializing.
    // Prevents double-start from leaking a second DR timer or corrupting
    // Kalman state while the old timer keeps calling predict().
    _stopDr();
    _cancelGpsWatchdog();

    _controller ??= StreamController<GeoPosition>.broadcast();
    _isDrActive = false;
    _lastState = null;
    if (mode == DeadReckoningMode.kalman) {
      _kalman = KalmanFilter();
    }

    // Cancel any existing subscription before creating a new one — prevents
    // duplicate position events when start() is called twice without stop().
    await _innerSub?.cancel();
    _innerSub = null;

    await _inner.start();

    _innerSub = _inner.positions.listen(
      _onGpsPosition,
      onError: _onGpsError,
    );
  }

  @override
  Future<void> stop() async {
    _stopDr();
    _cancelGpsWatchdog();
    await _innerSub?.cancel();
    _innerSub = null;

    try {
      await _inner.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _stopDr();
    _cancelGpsWatchdog();
    await _innerSub?.cancel();
    _innerSub = null;

    await _controller?.close();
    _controller = null;

    await _inner.dispose();
  }

  /// Whether dead reckoning is currently active (GPS lost, extrapolating).
  bool get isDrActive => _isDrActive;

  /// The current dead reckoning state (linear mode only).
  DeadReckoningState? get currentState => _lastState;

  /// The Kalman filter instance (kalman mode only). Null in linear mode.
  KalmanFilter? get kalmanFilter => _kalman;

  // -------------------------------------------------------------------------
  // GPS position handling
  // -------------------------------------------------------------------------

  void _onGpsPosition(GeoPosition pos) {
    if (_controller == null || _controller!.isClosed) return;

    // GPS is back — stop DR if it was active.
    if (_isDrActive) {
      _stopDr();
    }

    if (mode == DeadReckoningMode.kalman) {
      _onGpsPositionKalman(pos);
    } else {
      _onGpsPositionLinear(pos);
    }

    // Reset GPS watchdog — if it fires, we start DR.
    _resetGpsWatchdog();
  }

  void _onGpsPositionLinear(GeoPosition pos) {
    // Forward GPS position to output stream.
    _controller!.add(pos);

    // Update DR state from this GPS fix (may be null if no speed/heading).
    final state = DeadReckoningState.fromGeoPosition(pos);
    if (state != null) {
      _lastState = DeadReckoningState(
        latitude: state.latitude,
        longitude: state.longitude,
        speed: state.speed,
        heading: state.heading,
        baseAccuracy: state.baseAccuracy,
        lastGpsTime: DateTime.now(),
      );
    } else {
      _lastState = null;
    }
  }

  void _onGpsPositionKalman(GeoPosition pos) {
    final kf = _kalman!;

    // Feed GPS fix into Kalman filter.
    if (!pos.speed.isNaN && !pos.heading.isNaN && pos.speed >= 0) {
      kf.update(
        lat: pos.latitude,
        lon: pos.longitude,
        speed: pos.speed,
        heading: pos.heading,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      );

      // Emit filtered position (smoother than raw GPS).
      final s = kf.state;
      _controller!.add(GeoPosition(
        latitude: s.lat,
        longitude: s.lon,
        accuracy: kf.accuracyMetres,
        speed: s.speed,
        heading: s.heading,
        timestamp: pos.timestamp,
      ));
    } else {
      // No speed/heading — forward raw GPS, don't update filter.
      _controller!.add(pos);
    }
  }

  void _onGpsError(Object error) {
    if (!_isDrActive) {
      _controller?.addError(error);
    }
  }

  // -------------------------------------------------------------------------
  // GPS watchdog — detects GPS loss
  // -------------------------------------------------------------------------

  void _resetGpsWatchdog() {
    _cancelGpsWatchdog();
    _gpsWatchdog = Timer(gpsTimeout, _onGpsTimeout);
  }

  void _cancelGpsWatchdog() {
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
  }

  void _onGpsTimeout() {
    // Guard: do not re-enter _startDr() if DR is already running.
    // Without this, a stale watchdog firing mid-DR resets Kalman state.
    if (_isDrActive) return;

    if (mode == DeadReckoningMode.kalman) {
      // Kalman mode: filter must be initialised.
      if (_kalman == null || !_kalman!.isInitialized) return;
    } else {
      // Linear mode: need valid state for extrapolation.
      if (_lastState == null || !_lastState!.canExtrapolate) return;
    }

    _startDr();
  }

  // -------------------------------------------------------------------------
  // Dead reckoning — prediction
  // -------------------------------------------------------------------------

  void _startDr() {
    _isDrActive = true;
    _drTimer?.cancel(); // guard against double-start
    _emitDrPosition();

    _drTimer = Timer.periodic(extrapolationInterval, (_) {
      _emitDrPosition();
    });
  }

  void _emitDrPosition() {
    if (_controller == null || _controller!.isClosed) return;

    if (mode == DeadReckoningMode.kalman) {
      _emitDrPositionKalman();
    } else {
      _emitDrPositionLinear();
    }
  }

  void _emitDrPositionLinear() {
    if (_lastState == null) return;

    _lastState = _lastState!.predict(extrapolationInterval);
    final now = DateTime.now();

    if (_lastState!.accuracyAt(now) > DeadReckoningState.maxAccuracy) {
      _stopDr();
      return;
    }

    _controller!.add(_lastState!.toGeoPosition(now: now));
  }

  void _emitDrPositionKalman() {
    final kf = _kalman!;

    final result = kf.predict(extrapolationInterval);

    if (kf.isAccuracyExceeded) {
      _stopDr();
      return;
    }

    _controller!.add(GeoPosition(
      latitude: result.lat,
      longitude: result.lon,
      accuracy: result.accuracy,
      speed: result.speed,
      heading: result.heading,
      timestamp: DateTime.now(),
    ));
  }

  void _stopDr() {
    _isDrActive = false;
    _drTimer?.cancel();
    _drTimer = null;
  }
}
