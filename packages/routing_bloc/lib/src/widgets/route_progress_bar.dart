/// RouteProgressBar — glanceable maneuver progress during navigation.
library;

import 'package:flutter/material.dart';
import 'package:routing_engine/routing_engine.dart';

import '../models/route_progress_status.dart';
import 'maneuver_icons.dart';

class RouteProgressBar extends StatelessWidget {
  final RouteProgressStatus status;
  final RouteResult? route;
  final int currentManeuverIndex;
  final String? destinationLabel;
  final EdgeInsetsGeometry margin;

  const RouteProgressBar({
    super.key,
    required this.status,
    this.route,
    this.currentManeuverIndex = 0,
    this.destinationLabel,
    this.margin = const EdgeInsets.all(8),
  });

  RouteManeuver? get _currentManeuver {
    if (route == null) return null;
    if (currentManeuverIndex < 0 || currentManeuverIndex >= route!.maneuvers.length) {
      return null;
    }
    return route!.maneuvers[currentManeuverIndex];
  }

  double get _progress {
    if (route == null || route!.maneuvers.isEmpty) return 0.0;
    if (status == RouteProgressStatus.arrived) return 1.0;
    return (currentManeuverIndex / route!.maneuvers.length).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      RouteProgressStatus.idle => const SizedBox.shrink(),
      RouteProgressStatus.active => _buildActive(context),
      RouteProgressStatus.deviated => _buildDeviated(context),
      RouteProgressStatus.arrived => _buildArrived(context),
    };
  }

  Widget _buildActive(BuildContext context) {
    if (route == null) {
      return const SizedBox.shrink();
    }

    final maneuver = _currentManeuver;

    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (maneuver != null)
                  Icon(
                    ManeuverIcons.forType(maneuver.type),
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                if (maneuver != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        maneuver?.instruction ?? 'Navigating...',
                        style: Theme.of(context).textTheme.bodyLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (maneuver != null)
                        Text(
                          '${maneuver.lengthKm.toStringAsFixed(1)} km',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${route!.eta.inMinutes} min',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${route!.totalDistanceKm.toStringAsFixed(1)} km',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviated(BuildContext context) {
    return Card(
      margin: margin,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.amber.shade700, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.wrong_location,
              size: 32,
              color: Colors.amber.shade700,
            ),
            const SizedBox(width: 12),
            Text(
              'Rerouting...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrived(BuildContext context) {
    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.sports_score,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                destinationLabel != null
                    ? 'Arrived at $destinationLabel'
                    : 'Arrived',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}