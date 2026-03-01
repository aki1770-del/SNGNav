/// Simulated location provider — Sakae → Higashiokazaki driving scenario.
///
/// Emits pre-defined GPS positions along the OSRM-routed path from Sakae
/// Station (栄駅) through suburban Nagoya toward Higashiokazaki Station
/// (東岡崎駅). Includes a tunnel segment where emissions pause (simulating
/// GPS loss for dead reckoning testing).
///
/// Usage:
///   flutter run --dart-define=LOCATION_PROVIDER=simulated
///
/// Simulated GPS source for demo and testing.
/// Waypoints aligned to OSRM route geometry.
/// Part of the configurable location pipeline.
library;

import 'dart:async';

import '../models/geo_position.dart';
import 'location_provider.dart';

/// Simulated GPS source along Route 153, Nagoya → Mikawa Highlands.
///
/// The scenario has four phases:
/// 1. **City driving** (steps 0–4): Nagoya Station → expressway, 40 km/h
/// 2. **国道153号** (steps 5–9): through Toyota City, 90 km/h
/// 3. **Mountain tunnel** (steps 10–14): GPS lost — stream stops emitting
/// 4. **Tunnel exit** (steps 15–19): GPS recovered, descend to highlands
///
/// After step 19, the scenario loops from step 0.
class SimulatedLocationProvider implements LocationProvider {
  /// Interval between position emissions.
  final Duration interval;

  /// Whether to include a tunnel segment (GPS loss).
  /// Set to `false` for tests that don't need tunnel simulation.
  final bool includeTunnel;

  StreamController<GeoPosition>? _controller;
  Timer? _timer;
  int _step = 0;

  SimulatedLocationProvider({
    this.interval = const Duration(seconds: 1),
    this.includeTunnel = true,
  });

  @override
  Stream<GeoPosition> get positions {
    _controller ??= StreamController<GeoPosition>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> start() async {
    _controller ??= StreamController<GeoPosition>.broadcast();
    _step = 0;
    _emit();
    _timer = Timer.periodic(interval, (_) {
      _step = (_step + 1) % _waypoints.length;
      _emit();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _controller?.close();
    _controller = null;
  }

  void _emit() {
    if (_controller == null || _controller!.isClosed) return;

    final wp = _waypoints[_step];

    // Tunnel segment: skip emission (simulates GPS loss).
    if (wp.isTunnel && includeTunnel) return;

    _controller!.add(GeoPosition(
      latitude: wp.latitude,
      longitude: wp.longitude,
      accuracy: wp.accuracy,
      speed: wp.speed,
      heading: wp.heading,
      timestamp: DateTime.now(),
    ));
  }

  /// Current step index (for testing).
  int get currentStep => _step;
}

// ---------------------------------------------------------------------------
// Waypoint data — Route 19 (Nagoya → mountain pass)
// ---------------------------------------------------------------------------

class _Waypoint {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed; // m/s
  final double heading; // degrees
  final bool isTunnel;

  const _Waypoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    this.isTunnel = false,
  });
}

/// Sakae → Higashiokazaki driving scenario — 20 waypoints.
///
/// Coordinates follow the OSRM-routed path: 栄駅 → 国道153号 → 岡崎方面
/// → 東岡崎駅. Speed in m/s, heading in degrees (0 = north, clockwise).
const _waypoints = <_Waypoint>[
  // Phase 1: City driving — Sakae Station to Nagoya outskirts (40 km/h)
  _Waypoint(latitude: 35.1709, longitude: 136.9066, accuracy: 5.0, speed: 11.11, heading: 86.9),
  _Waypoint(latitude: 35.1713, longitude: 136.9146, accuracy: 5.0, speed: 11.11, heading: 154.1),
  _Waypoint(latitude: 35.1608, longitude: 136.9208, accuracy: 5.0, speed: 11.11, heading: 90.3),
  _Waypoint(latitude: 35.1607, longitude: 136.9491, accuracy: 5.0, speed: 11.11, heading: 108.5),
  _Waypoint(latitude: 35.1513, longitude: 136.9837, accuracy: 5.0, speed: 11.11, heading: 135.8),

  // Phase 2: Suburban road — heading toward Okazaki (70 km/h)
  _Waypoint(latitude: 35.1376, longitude: 137.0000, accuracy: 8.0, speed: 19.44, heading: 124.8),
  _Waypoint(latitude: 35.1291, longitude: 137.0150, accuracy: 8.0, speed: 19.44, heading: 135.7),
  _Waypoint(latitude: 35.1121, longitude: 137.0352, accuracy: 8.0, speed: 19.44, heading: 115.5),
  _Waypoint(latitude: 35.1013, longitude: 137.0628, accuracy: 8.0, speed: 19.44, heading: 124.9),
  _Waypoint(latitude: 35.0889, longitude: 137.0846, accuracy: 8.0, speed: 19.44, heading: 108.0),

  // Phase 3: Tunnel segment — GPS lost (60 km/h)
  _Waypoint(latitude: 35.0824, longitude: 137.1088, accuracy: 0, speed: 16.67, heading: 117.9, isTunnel: true),
  _Waypoint(latitude: 35.0743, longitude: 137.1275, accuracy: 0, speed: 16.67, heading: 165.0, isTunnel: true),
  _Waypoint(latitude: 35.0571, longitude: 137.1332, accuracy: 0, speed: 16.67, heading: 150.5, isTunnel: true),
  _Waypoint(latitude: 35.0449, longitude: 137.1416, accuracy: 0, speed: 16.67, heading: 140.1, isTunnel: true),
  _Waypoint(latitude: 35.0340, longitude: 137.1527, accuracy: 0, speed: 16.67, heading: 138.5, isTunnel: true),

  // Phase 4: Tunnel exit — GPS recovered, approach Higashiokazaki (40 km/h)
  _Waypoint(latitude: 35.0182, longitude: 137.1698, accuracy: 20.0, speed: 11.11, heading: 177.0),
  _Waypoint(latitude: 35.0031, longitude: 137.1708, accuracy: 5.0, speed: 11.11, heading: 180.3),
  _Waypoint(latitude: 34.9896, longitude: 137.1707, accuracy: 5.0, speed: 11.11, heading: 157.6),
  _Waypoint(latitude: 34.9715, longitude: 137.1798, accuracy: 5.0, speed: 11.11, heading: 182.1),
  _Waypoint(latitude: 34.9554, longitude: 137.1791, accuracy: 5.0, speed: 11.11, heading: 182.1),
];
