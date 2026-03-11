/// Simulated fleet provider — generates plausible fleet reports along
/// the Nagoya → Mikawa Highlands route.
///
/// Simulates 5 vehicles reporting road conditions at varying positions
/// along Route 153. Vehicles near mountain passes report snowy/icy
/// conditions; lowland vehicles report dry/wet.
///
/// Simulated fleet data for demo and testing. Production replacement:
/// real fleet telemetry API.
library;

import 'dart:async';
import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'package:fleet_hazard/fleet_hazard.dart';

class SimulatedFleetProvider implements FleetProvider {
  final Duration interval;
  final _controller = StreamController<FleetReport>.broadcast();
  final _random = Random(42); // Fixed seed for reproducibility.
  Timer? _timer;
  int _tick = 0;

  SimulatedFleetProvider({
    this.interval = const Duration(seconds: 6),
  });

  @override
  Stream<FleetReport> get reports => _controller.stream;

  @override
  Future<void> startListening() async {
    _tick = 0;
    _emit();
    _timer = Timer.periodic(interval, (_) => _emit());
  }

  @override
  Future<void> stopListening() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }

  void _emit() {
    final vehicle = _vehicles[_tick % _vehicles.length];
    final jitter = (_random.nextDouble() - 0.5) * 0.01; // ~1km jitter
    final report = FleetReport(
      vehicleId: vehicle.id,
      position: LatLng(
        vehicle.baseLat + jitter,
        vehicle.baseLon + jitter,
      ),
      timestamp: DateTime.now(),
      condition: vehicle.conditions[_tick % vehicle.conditions.length],
      confidence: 0.7 + _random.nextDouble() * 0.3, // 0.7–1.0
    );

    if (!_controller.isClosed) {
      _controller.add(report);
    }
    _tick++;
  }
}

// ---------------------------------------------------------------------------
// Simulated vehicles along Route 153 (Nagoya → Mikawa Highlands)
// ---------------------------------------------------------------------------

class _SimVehicle {
  final String id;
  final double baseLat;
  final double baseLon;
  final List<RoadCondition> conditions;

  const _SimVehicle(this.id, this.baseLat, this.baseLon, this.conditions);
}

const _vehicles = [
  // Nagoya city — mostly dry
  _SimVehicle('V-001', 35.170, 136.882, [
    RoadCondition.dry,
    RoadCondition.dry,
    RoadCondition.wet,
  ]),
  // Toyota city — transition zone
  _SimVehicle('V-002', 35.083, 137.156, [
    RoadCondition.wet,
    RoadCondition.snowy,
    RoadCondition.wet,
  ]),
  // Mountain approach — snowy
  _SimVehicle('V-003', 35.060, 137.250, [
    RoadCondition.snowy,
    RoadCondition.snowy,
    RoadCondition.icy,
  ]),
  // Summit area — icy
  _SimVehicle('V-004', 35.050, 137.320, [
    RoadCondition.icy,
    RoadCondition.snowy,
    RoadCondition.icy,
  ]),
  // Mikawa Highlands — clearing
  _SimVehicle('V-005', 35.070, 137.400, [
    RoadCondition.snowy,
    RoadCondition.wet,
    RoadCondition.dry,
  ]),
];
