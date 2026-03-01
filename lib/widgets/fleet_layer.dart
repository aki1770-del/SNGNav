/// FleetLayer — fleet vehicle markers and hazard circles on flutter_map.
///
/// Renders fleet reports as map markers:
///   - Vehicle markers: colored dot per vehicle, condition-colored border
///   - Hazard circles: red ring around snowy/icy reports (isHazard)
///
/// Widget-mediated coupling: FleetBloc emits unconditionally.
/// Consent gating and layer visibility are enforced at the MapLayer level
/// — this widget only renders the markers when called.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/fleet_report.dart';

/// Builds a [MarkerLayer] from a list of [FleetReport]s.
///
/// Usage in MapLayer children list:
/// ```dart
/// if (mapState.isLayerVisible(MapLayerType.fleet) && fleetState.isListening)
///   FleetLayer(reports: fleetState.reports),
/// ```
class FleetLayer extends StatelessWidget {
  const FleetLayer({super.key, required this.reports});

  /// Active fleet reports to render as markers.
  final List<FleetReport> reports;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) return const MarkerLayer(markers: []);

    return MarkerLayer(
      markers: reports.map(_buildMarker).toList(),
    );
  }

  static Marker _buildMarker(FleetReport report) {
    final isHazard = report.isHazard;
    final color = _conditionColor(report.condition);

    return Marker(
      point: report.position,
      width: isHazard ? 36 : 28,
      height: isHazard ? 36 : 28,
      child: _VehicleMarker(
        vehicleId: report.vehicleId,
        color: color,
        isHazard: isHazard,
        condition: report.condition,
      ),
    );
  }

  static Color _conditionColor(RoadCondition condition) {
    return switch (condition) {
      RoadCondition.dry => Colors.green,
      RoadCondition.wet => Colors.blue,
      RoadCondition.snowy => Colors.orange,
      RoadCondition.icy => Colors.red,
      RoadCondition.unknown => Colors.grey,
    };
  }
}

/// Vehicle marker widget — dot with condition-colored ring.
///
/// Hazard markers get a larger pulsing ring effect (double border)
/// and a warning icon overlay.
class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker({
    required this.vehicleId,
    required this.color,
    required this.isHazard,
    required this.condition,
  });

  final String vehicleId;
  final Color color;
  final bool isHazard;
  final RoadCondition condition;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$vehicleId: ${condition.name}',
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hazard ring — outer glow for snowy/icy
          if (isHazard)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withAlpha(100), width: 3),
              ),
            ),

          // Vehicle dot
          Container(
            width: isHazard ? 20 : 18,
            height: isHazard ? 20 : 18,
            decoration: BoxDecoration(
              color: color.withAlpha(180),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(80),
                  blurRadius: isHazard ? 6 : 3,
                ),
              ],
            ),
            child: isHazard
                ? Icon(
                    condition == RoadCondition.icy
                        ? Icons.ac_unit
                        : Icons.cloudy_snowing,
                    size: 10,
                    color: Colors.white,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
