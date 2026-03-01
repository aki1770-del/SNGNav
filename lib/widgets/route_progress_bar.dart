/// RouteProgressBar — live maneuver progress during navigation.
///
/// Reads [NavigationBloc] state to show current maneuver instruction,
/// a linear progress indicator, ETA, and total distance.
/// Invisible when not navigating (returns [SizedBox.shrink]).
///
/// Z-layer: 1 (NavigationOverlay).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/navigation_bloc.dart';
import '../bloc/navigation_state.dart';
import 'maneuver_icons.dart';

class RouteProgressBar extends StatelessWidget {
  const RouteProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, state) {
        return switch (state.status) {
          NavigationStatus.idle => const SizedBox.shrink(),
          NavigationStatus.navigating => _buildNavigating(context, state),
          NavigationStatus.deviated => _buildDeviated(context, state),
          NavigationStatus.arrived => _buildArrived(context, state),
        };
      },
    );
  }

  Widget _buildNavigating(BuildContext context, NavigationState state) {
    final maneuver = state.currentManeuver;
    final route = state.route!;

    return Card(
      margin: const EdgeInsets.all(8),
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
                      '${route.eta.inMinutes} min',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${route.totalDistanceKm.toStringAsFixed(1)} km',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: state.progress),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviated(BuildContext context, NavigationState state) {
    return Card(
      margin: const EdgeInsets.all(8),
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

  Widget _buildArrived(BuildContext context, NavigationState state) {
    return Card(
      margin: const EdgeInsets.all(8),
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
                state.destinationLabel != null
                    ? 'Arrived at ${state.destinationLabel}'
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
