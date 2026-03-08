/// ScenarioPhaseIndicator — shows the current weather scenario phase.
///
/// Reads [WeatherBloc] to display the phase name (e.g., "Heavy Snow —
/// Pass Summit") so a demo viewer understands the simulated scenario.
///
/// Snow Scene scenario display.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/weather_bloc.dart';
import '../bloc/weather_state.dart';

class ScenarioPhaseIndicator extends StatelessWidget {
  const ScenarioPhaseIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (context, state) {
        if (!state.hasCondition) {
          return const SizedBox.shrink();
        }

        final condition = state.condition!;
        final (label, description) = _phaseInfo(condition);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _phaseIcon(condition),
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static (String, String) _phaseInfo(WeatherCondition condition) {
    if (condition.precipType == PrecipitationType.none) {
      return ('Clear — City Departure', 'Route 153 east from Nagoya Station');
    }
    if (condition.iceRisk) {
      return (
        'Ice Risk — Pass Descent',
        'Black ice warning, reduce speed'
      );
    }
    return switch (condition.intensity) {
      PrecipitationIntensity.light => (
          'Light Snow — Mountain Approach',
          'Entering elevated terrain toward Toyota'
        ),
      PrecipitationIntensity.moderate => condition.visibilityMeters < 1000
          ? (
              'Moderate Snow — Pass Approach',
              'Visibility reduced, snow accumulating'
            )
          : (
              'Moderate Snow — Clearing',
              'Conditions improving, descending to valley'
            ),
      PrecipitationIntensity.heavy => (
          'Heavy Snow — Pass Summit',
          'Visibility critically low, hazardous conditions'
        ),
      PrecipitationIntensity.none => ('Clear', 'No precipitation'),
    };
  }

  static IconData _phaseIcon(WeatherCondition condition) {
    if (condition.precipType == PrecipitationType.none) {
      return Icons.wb_sunny;
    }
    if (condition.iceRisk) return Icons.ac_unit;
    return switch (condition.intensity) {
      PrecipitationIntensity.light => Icons.cloud,
      PrecipitationIntensity.moderate => Icons.cloudy_snowing,
      PrecipitationIntensity.heavy => Icons.storm,
      PrecipitationIntensity.none => Icons.wb_sunny,
    };
  }
}
