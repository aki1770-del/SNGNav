/// HazardZoneLayer — renders aggregated fleet hazard zones on flutter_map.
///
/// Each [HazardZone] is rendered as a translucent circle on the map:
///   - Icy zones: red circle with ice icon at center
///   - Snowy zones: orange circle with snow icon at center
///
/// Sits between the route polyline and individual fleet markers in the
/// Z-order, so drivers see the zone first and individual reports on top.
///
/// Fleet hazard aggregation layer.
library;

import 'package:flutter/material.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:flutter_map/flutter_map.dart';

/// Builds a [CircleLayer] + [MarkerLayer] from a list of [HazardZone]s.
class HazardZoneLayer extends StatelessWidget {
  const HazardZoneLayer({super.key, required this.zones});

  final List<HazardZone> zones;

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: [
        // Translucent zone circles.
        CircleLayer(
          circles: zones.map(_buildCircle).toList(),
        ),
        // Center markers with hazard icon and vehicle count.
        MarkerLayer(
          markers: zones.map(_buildCenterMarker).toList(),
        ),
      ],
    );
  }

  static CircleMarker _buildCircle(HazardZone zone) {
    final isIcy = zone.severity == HazardSeverity.icy;
    return CircleMarker(
      point: zone.center,
      radius: zone.radiusMeters,
      useRadiusInMeter: true,
      color: isIcy
          ? Colors.red.withAlpha(40)
          : Colors.orange.withAlpha(35),
      borderColor: isIcy
          ? Colors.red.withAlpha(120)
          : Colors.orange.withAlpha(100),
      borderStrokeWidth: 2,
    );
  }

  static Marker _buildCenterMarker(HazardZone zone) {
    final isIcy = zone.severity == HazardSeverity.icy;
    return Marker(
      point: zone.center,
      width: 44,
      height: 44,
      child: _ZoneCenterIcon(
        severity: zone.severity,
        vehicleCount: zone.vehicleCount,
        isIcy: isIcy,
      ),
    );
  }
}

/// Center icon for a hazard zone — shows severity icon + vehicle count badge.
class _ZoneCenterIcon extends StatelessWidget {
  const _ZoneCenterIcon({
    required this.severity,
    required this.vehicleCount,
    required this.isIcy,
  });

  final HazardSeverity severity;
  final int vehicleCount;
  final bool isIcy;

  @override
  Widget build(BuildContext context) {
    final color = isIcy ? Colors.red : Colors.orange;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Main icon circle.
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withAlpha(200),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: color.withAlpha(100), blurRadius: 8),
            ],
          ),
          child: Icon(
            isIcy ? Icons.ac_unit : Icons.cloudy_snowing,
            size: 16,
            color: Colors.white,
          ),
        ),

        // Vehicle count badge (top-right).
        if (vehicleCount > 1)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Center(
                child: Text(
                  '$vehicleCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
