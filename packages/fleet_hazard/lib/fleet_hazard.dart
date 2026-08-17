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
///
/// ## Absence is not an all-clear
///
/// [HazardAggregator.aggregate] returns an empty list both when nobody has
/// reported a road and when the fleet has driven it and found it clear. Use
/// [HazardAggregator.aggregateWithProvenance] when your surface has to tell a
/// driver which of those is true — and it does, because rendering silence as a
/// clear road is the failure that puts her on the ice.
///
/// ```dart
/// // oracle:placeholders reports
/// final result = HazardAggregator.aggregateWithProvenance(
///   reports,
///   maxAge: const Duration(minutes: 30),
/// );
/// print(result.isSilent); // true when nothing fresh was reported at all
/// ```
library;

export 'src/fleet_aggregate.dart';
export 'src/fleet_provider.dart';
export 'src/fleet_report.dart';
export 'src/hazard_aggregator.dart';
export 'src/hazard_zone.dart';
export 'src/zone_observation.dart';
