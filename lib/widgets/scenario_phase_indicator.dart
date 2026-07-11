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
    // Ice FIRST: a feed ice flag must never be masked by the no-precip
    // branch — previously a no-precip condition with iceRisk showed
    // "Clear — City Departure" beside the black-ice overlay, two surfaces
    // contradicting each other in the same view. Description is
    // ja-primary, matching the alert surface's precise vocabulary.
    if (condition.iceRisk == true) {
      return (
        'Ice Risk — Pass Descent',
        'ブラックアイスバーンに注意 — 減速 / black ice, reduce speed'
      );
    }
    // An unreported precipitation type is NOT "clear". Saying "Clear — City
    // Departure" about a road nobody measured is the fabrication this release
    // exists to remove, spelled out in a phase label.
    if (condition.precipType == null) {
      return (
        '未計測 / Not measured',
        '路面状況を取得できていません。見える範囲で運転してください。'
      );
    }
    if (condition.precipType == PrecipitationType.none) {
      return ('Clear — City Departure', 'Route 153 east from Nagoya Station');
    }
    return switch (condition.intensity) {
      PrecipitationIntensity.light => (
          'Light Snow — Mountain Approach',
          'Entering elevated terrain toward Toyota'
        ),
      PrecipitationIntensity.moderate =>
        (condition.visibilityMeters ?? double.infinity) < 1000
            ? (
                'Moderate Snow — Pass Approach',
                'Visibility reduced, snow accumulating'
              )
            : (
                // An UNMEASURED visibility is not "improving". Do not claim
                // improvement we did not observe.
                condition.visibilityMeters == null
                    ? 'Moderate Snow — visibility not measured'
                    : 'Moderate Snow — Clearing',
                condition.visibilityMeters == null
                    ? '視程の実測データはありません'
                    : 'Conditions improving, descending to valley'
              ),
      PrecipitationIntensity.heavy => (
          'Heavy Snow — Pass Summit',
          'Visibility critically low, hazardous conditions'
        ),
      PrecipitationIntensity.none => ('Clear', 'No precipitation'),
      null => ('未計測 / Not measured', '降水強度の実測データはありません'),
    };
  }

  static IconData _phaseIcon(WeatherCondition condition) {
    // Ice first — same ordering fix as _phaseInfo: never a sun icon over
    // an ice-flagged road.
    if (condition.iceRisk == true) return Icons.ac_unit;
    // No sun icon over a road we did not measure.
    if (condition.precipType == null) return Icons.help_outline;
    if (condition.precipType == PrecipitationType.none) {
      return Icons.wb_sunny;
    }
    return switch (condition.intensity) {
      PrecipitationIntensity.light => Icons.cloud,
      PrecipitationIntensity.moderate => Icons.cloudy_snowing,
      PrecipitationIntensity.heavy => Icons.storm,
      PrecipitationIntensity.none => Icons.wb_sunny,
      null => Icons.help_outline,
    };
  }
}
