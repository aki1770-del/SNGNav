/// SpeedDisplay — vehicle speed + GPS quality indicator.
///
/// Reads [LocationBloc] state to show current speed in km/h
/// with a colored dot indicating GPS signal quality.
///
/// Typography: headlineLarge (48sp bold) —
/// readable at arm's length in < 2 seconds (JAMA requirement).
///
/// Z-layer: 1 (NavigationOverlay).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/location_bloc.dart';
import '../bloc/location_state.dart';

class SpeedDisplay extends StatelessWidget {
  const SpeedDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocationBloc, LocationState>(
      builder: (context, state) {
        final hasSpeed = state.position != null &&
            !state.position!.speed.isNaN &&
            state.position!.speed >= 0;

        final speedText = hasSpeed
            ? state.position!.speedKmh.round().toString()
            : '--';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              speedText,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 48,
                  ),
            ),
            Text(
              'km/h',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 4),
            _GpsQualityDot(quality: state.quality),
          ],
        );
      },
    );
  }
}

class _GpsQualityDot extends StatelessWidget {
  final LocationQuality quality;

  const _GpsQualityDot({required this.quality});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _colorForQuality(quality),
        shape: BoxShape.circle,
      ),
    );
  }

  static Color _colorForQuality(LocationQuality quality) {
    return switch (quality) {
      LocationQuality.fix => Colors.green,
      LocationQuality.degraded => Colors.amber,
      LocationQuality.stale => Colors.orange,
      LocationQuality.acquiring => Colors.blue,
      LocationQuality.error => Colors.red,
      LocationQuality.uninitialized => Colors.grey,
    };
  }
}
