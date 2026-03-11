/// WeatherStatusBar — compact top bar showing current weather conditions.
///
/// Widget-mediated coupling:
///   `BlocConsumer<WeatherBloc, WeatherState>`
///     - builder: renders weather icon, temperature, visibility, hazard badge
///     - listener: when isHazardous transitions true → dispatches
///       SafetyAlertReceived to NavigationBloc (weather→safety bridge)
///
/// Staleness indicator: when weather data is older than `staleThreshold`,
/// shows elapsed time in amber. When older than `criticalThreshold`,
/// shows "STALE" badge in red. The driver always knows how fresh the
/// data is.
///
/// Periodic rebuild: a 30-second timer calls setState() to recompute
/// staleness from DateTime.now(). Without this, the staleness display
/// freezes between weather provider polls (e.g., 5 minutes for
/// Open-Meteo). The driver sees continuously accurate data age.
///
/// This widget is the critical coupling point between WeatherBloc and
/// NavigationBloc. No direct BLoC-to-BLoC wiring — the widget reads one
/// BLoC and dispatches events to another.
library;

import 'dart:async';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';

import '../bloc/weather_bloc.dart';
import '../bloc/weather_state.dart';

class WeatherStatusBar extends StatefulWidget {
  const WeatherStatusBar({super.key});

  /// Data older than 10 minutes shows amber "Xm ago" indicator.
  static const staleThreshold = Duration(minutes: 10);

  /// Data older than 30 minutes shows red "STALE" badge.
  static const criticalThreshold = Duration(minutes: 30);

  /// Interval for periodic staleness rebuild.
  ///
  /// Every 30 seconds, `setState` forces a rebuild so the staleness
  /// display recomputes from `DateTime.now()`. Without this, the display
  /// only updates when the weather provider emits a new condition.
  static const stalenessRebuildInterval = Duration(seconds: 30);

  @override
  State<WeatherStatusBar> createState() => WeatherStatusBarState();
}

@visibleForTesting
class WeatherStatusBarState extends State<WeatherStatusBar> {
  Timer? _stalenessTimer;

  @override
  void initState() {
    super.initState();
    _stalenessTimer = Timer.periodic(
      WeatherStatusBar.stalenessRebuildInterval,
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _stalenessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WeatherBloc, WeatherState>(
      // Widget-mediated coupling: weather → safety bridge
      listenWhen: (prev, curr) =>
          !prev.isHazardous && curr.isHazardous,
      listener: (context, state) {
        final condition = state.condition!;
        final message = _hazardMessage(condition);
        final severity = condition.iceRisk
            ? AlertSeverity.critical
            : AlertSeverity.warning;

        context.read<NavigationBloc>().add(SafetyAlertReceived(
              message: message,
              severity: severity,
            ));
      },
      builder: (context, state) {
        if (!state.hasCondition) {
          return const SizedBox.shrink();
        }

        final condition = state.condition!;
        final isHazardous = state.isHazardous;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isHazardous
                ? Colors.red.shade50.withAlpha(230)
                : Colors.white.withAlpha(220),
            border: Border(
              bottom: BorderSide(
                color: isHazardous ? Colors.red.shade300 : Colors.grey.shade300,
                width: isHazardous ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Weather icon
              Icon(
                _weatherIcon(condition),
                size: 20,
                color: isHazardous ? Colors.red.shade700 : Colors.grey.shade700,
              ),
              const SizedBox(width: 8),

              // Precipitation label
              Text(
                _precipLabel(condition),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isHazardous ? FontWeight.bold : FontWeight.normal,
                  color: isHazardous
                      ? Colors.red.shade800
                      : Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 12),

              // Temperature
              Text(
                '${condition.temperatureCelsius.toStringAsFixed(0)}°C',
                style: TextStyle(
                  fontSize: 12,
                  color: condition.isFreezing
                      ? Colors.blue.shade700
                      : Colors.grey.shade700,
                  fontWeight:
                      condition.isFreezing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 12),

              // Visibility
              Text(
                'Vis: ${_visibilityLabel(condition.visibilityMeters)}',
                style: TextStyle(
                  fontSize: 11,
                  color: condition.hasReducedVisibility
                      ? Colors.orange.shade700
                      : Colors.grey.shade600,
                ),
              ),

              // Staleness indicator
              ..._stalenessWidgets(condition.timestamp),

              const Spacer(),

              // Hazard badge
              if (isHazardous)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: condition.iceRisk
                        ? Colors.red.shade700
                        : Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    condition.iceRisk ? 'ICE' : 'HAZARD',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // Ice risk indicator (even when not generally hazardous)
              if (!isHazardous && condition.iceRisk)
                Icon(Icons.ac_unit, size: 16, color: Colors.blue.shade600),
            ],
          ),
        );
      },
    );
  }

  static String _hazardMessage(WeatherCondition condition) {
    if (condition.iceRisk) {
      return 'Black ice risk — reduce speed, increase following distance';
    }
    if (condition.visibilityMeters < 200) {
      return 'Visibility critically low (${condition.visibilityMeters.toStringAsFixed(0)}m) — consider stopping';
    }
    if (condition.intensity == PrecipitationIntensity.heavy) {
      return 'Heavy ${condition.precipType.name} — reduced traction and visibility';
    }
    return 'Hazardous weather conditions detected';
  }

  static IconData _weatherIcon(WeatherCondition condition) {
    if (condition.iceRisk) return Icons.ac_unit;

    return switch (condition.precipType) {
      PrecipitationType.snow => Icons.cloudy_snowing,
      PrecipitationType.rain => Icons.water_drop,
      PrecipitationType.sleet => Icons.grain,
      PrecipitationType.hail => Icons.storm,
      PrecipitationType.none => condition.isFreezing
          ? Icons.thermostat
          : Icons.wb_sunny,
    };
  }

  static String _precipLabel(WeatherCondition condition) {
    if (condition.precipType == PrecipitationType.none) {
      return condition.isFreezing ? 'Clear / Cold' : 'Clear';
    }
    final intensity = switch (condition.intensity) {
      PrecipitationIntensity.light => 'Light',
      PrecipitationIntensity.moderate => 'Moderate',
      PrecipitationIntensity.heavy => 'Heavy',
      PrecipitationIntensity.none => '',
    };
    final type = switch (condition.precipType) {
      PrecipitationType.snow => 'Snow',
      PrecipitationType.rain => 'Rain',
      PrecipitationType.sleet => 'Sleet',
      PrecipitationType.hail => 'Hail',
      PrecipitationType.none => '',
    };
    return '$intensity $type'.trim();
  }

  static String _visibilityLabel(double meters) {
    if (meters >= 10000) return '10+ km';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  // ---------------------------------------------------------------------------
  // Staleness indicator
  // ---------------------------------------------------------------------------

  /// Returns staleness widgets based on data age.
  ///
  /// - Fresh (< 10min): empty list
  /// - Stale (10-30min): amber "Xm ago" text
  /// - Critical (> 30min): red "STALE" badge
  static List<Widget> _stalenessWidgets(DateTime timestamp) {
    final age = DateTime.now().difference(timestamp);
    if (age < WeatherStatusBar.staleThreshold) return const [];

    final isCritical = age >= WeatherStatusBar.criticalThreshold;
    return [
      const SizedBox(width: 8),
      if (isCritical)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'STALE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        )
      else
        Text(
          _stalenessLabel(age),
          style: TextStyle(
            fontSize: 10,
            color: Colors.amber.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
    ];
  }

  static String _stalenessLabel(Duration age) {
    final minutes = age.inMinutes;
    if (minutes < 60) return '${minutes}m ago';
    final hours = age.inHours;
    return '${hours}h ago';
  }
}
