/// Fleet telemetry hazard model and clustering.
///
/// Provides road condition reports ([FleetReport]), clustered hazard zones
/// ([HazardZone]), a pure-Dart aggregation algorithm ([HazardAggregator]),
/// and a pluggable telemetry interface ([FleetProvider]).
///
/// ```dart
/// import 'package:fleet_hazard/fleet_hazard.dart';
/// import 'package:latlong2/latlong.dart';
///
/// final reports = [
///   FleetReport(
///     vehicleId: 'V-001',
///     position: const LatLng(35.050, 137.250),
///     timestamp: DateTime.now(),
///     condition: RoadCondition.snowy,
///   ),
/// ];
///
/// final zones = HazardAggregator.aggregate(reports);
/// ```
library;

export 'src/fleet_provider.dart';
export 'src/fleet_report.dart';
export 'src/hazard_aggregator.dart';
export 'src/hazard_zone.dart';