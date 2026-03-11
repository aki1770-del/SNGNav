import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final reports = [
    FleetReport(
      vehicleId: 'V-001',
      position: const LatLng(35.050, 137.250),
      timestamp: DateTime.now(),
      condition: RoadCondition.snowy,
      confidence: 0.9,
    ),
    FleetReport(
      vehicleId: 'V-002',
      position: const LatLng(35.052, 137.252),
      timestamp: DateTime.now(),
      condition: RoadCondition.icy,
      confidence: 0.95,
    ),
    FleetReport(
      vehicleId: 'V-003',
      position: const LatLng(35.090, 137.290),
      timestamp: DateTime.now(),
      condition: RoadCondition.dry,
    ),
  ];

  final zones = HazardAggregator.aggregate(reports);
  print('hazard zones: ${zones.length}');
  for (final zone in zones) {
    print('${zone.severity.name} zone '
        'vehicles=${zone.vehicleCount} '
        'radius=${zone.radiusMeters.toStringAsFixed(0)}m');
  }
}