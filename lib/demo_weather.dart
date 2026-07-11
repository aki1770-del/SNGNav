/// Weather Demo — live SimulatedWeatherProvider → WeatherBloc visualization.
///
/// Run: flutter run -d linux -t lib/demo_weather.dart
///
/// Shows the 6-phase Nagoya mountain pass weather scenario cycling in
/// real time. Each phase updates the display with current conditions,
/// hazard status, and safety alert level.
///
/// Demonstrates real-time weather monitoring with hazard detection.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snow_rendering/snow_rendering.dart';

import 'bloc/weather_bloc.dart';
import 'bloc/weather_event.dart';
import 'bloc/weather_state.dart';

void main() {
  runApp(const WeatherDemoApp());
}

class WeatherDemoApp extends StatelessWidget {
  const WeatherDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Weather Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (_) => WeatherBloc(
          provider: SimulatedWeatherProvider(
            interval: const Duration(seconds: 3),
          ),
        )..add(const WeatherMonitorStarted()),
        child: const WeatherDemoPage(),
      ),
    );
  }
}

class WeatherDemoPage extends StatelessWidget {
  const WeatherDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Weather Demo'),
        centerTitle: true,
      ),
      body: BlocBuilder<WeatherBloc, WeatherState>(
        builder: (context, state) {
          if (!state.hasCondition) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Starting weather monitor...'),
                ],
              ),
            );
          }

          final c = state.condition!;
          return _WeatherDisplay(condition: c, state: state);
        },
      ),
    );
  }
}

class _WeatherDisplay extends StatelessWidget {
  final WeatherCondition condition;
  final WeatherState state;

  const _WeatherDisplay({required this.condition, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = _backgroundForCondition(condition);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scenario header
            _ScenarioHeader(condition: condition),
            const SizedBox(height: 32),

            // Main weather icon + temperature
            _MainDisplay(condition: condition),
            const SizedBox(height: 32),

            // Condition details
            _ConditionGrid(condition: condition),
            const SizedBox(height: 24),

            // Safety assessment
            _SafetyBanner(state: state),
            const Spacer(),

            // Footer
            Text(
              'Nagoya Mountain Pass — Route 153 → Toyota → Mikawa Highlands',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Cycling every 3 seconds. ${condition.timestamp.toString().substring(0, 19)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white38,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _backgroundForCondition(WeatherCondition c) {
    if (c.hazard == SafetyVerdict.hazardous) return const Color(0xFF1A0A0A);
    if (c.snowing == SafetyVerdict.hazardous) return const Color(0xFF0A1A2A);
    // Slate, not the green "all clear" — a road we did not measure must not
    // paint the calm background.
    if (c.hazard == SafetyVerdict.unknown) return const Color(0xFF11171A);
    return const Color(0xFF0A1A0A);
  }
}

class _ScenarioHeader extends StatelessWidget {
  final WeatherCondition condition;

  const _ScenarioHeader({required this.condition});

  @override
  Widget build(BuildContext context) {
    final phase = _phaseLabel(condition);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        phase,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _phaseLabel(WeatherCondition c) {
    if (c.precipType == null) return 'NOT MEASURED';
    if (c.precipType == PrecipitationType.none) {
      return 'PHASE 0 — CITY DEPARTURE (CLEAR)';
    }
    if (c.iceRisk == true) return 'PHASE 4 — DESCENT (ICE RISK)';
    return switch (c.intensity) {
      PrecipitationIntensity.light
          when (c.visibilityMeters ?? -1) >= 2000 =>
        'PHASE 5 — VALLEY (CLEARING)',
      PrecipitationIntensity.light => 'PHASE 1 — ENTERING MOUNTAINS',
      PrecipitationIntensity.moderate => 'PHASE 2 — PASS APPROACH',
      PrecipitationIntensity.heavy => 'PHASE 3 — PASS SUMMIT (HAZARDOUS)',
      PrecipitationIntensity.none => 'CLEAR',
      null => 'NOT MEASURED',
    };
  }
}

class _MainDisplay extends StatelessWidget {
  final WeatherCondition condition;

  const _MainDisplay({required this.condition});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _iconForCondition(condition),
          size: 80,
          color: _iconColor(condition),
        ),
        const SizedBox(width: 32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              condition.temperatureCelsius == null
                  ? '—°C'
                  : '${condition.temperatureCelsius!.toStringAsFixed(0)}°C',
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${condition.precipType?.name.toUpperCase() ?? 'NOT MEASURED'} — ${condition.intensity?.name.toUpperCase() ?? 'NOT MEASURED'}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white70,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _iconForCondition(WeatherCondition c) {
    if (c.iceRisk == true) return Icons.ac_unit;
    return switch (c.precipType) {
      PrecipitationType.none => Icons.wb_sunny,
      PrecipitationType.snow => switch (c.intensity) {
          PrecipitationIntensity.heavy => Icons.severe_cold,
          _ => Icons.cloudy_snowing,
        },
      PrecipitationType.rain => Icons.water_drop,
      PrecipitationType.sleet => Icons.grain,
      PrecipitationType.hail => Icons.storm,
      // A sun over an unmeasured sky is a claim.
      null => Icons.help_outline,
    };
  }

  Color _iconColor(WeatherCondition c) {
    if (c.hazard == SafetyVerdict.hazardous) return Colors.red.shade300;
    if (c.snowing == SafetyVerdict.hazardous) return Colors.blue.shade200;
    if (c.hazard == SafetyVerdict.unknown) return Colors.blueGrey.shade300;
    return Colors.amber.shade300;
  }
}

class _ConditionGrid extends StatelessWidget {
  final WeatherCondition condition;

  const _ConditionGrid({required this.condition});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Every tile renders "—" for a field the feed did not carry. A metric
        // tile that prints a NUMBER for an unmeasured field is the whole defect,
        // rendered at 64pt on the driver's screen.
        Expanded(
          child: _MetricTile(
            label: 'VISIBILITY',
            value: _visibility(condition.visibilityMeters),
            icon: Icons.visibility,
            alert: condition.reducedVisibility == SafetyVerdict.hazardous,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _MetricTile(
            label: 'WIND',
            value: condition.windSpeedKmh == null
                ? '—'
                : '${condition.windSpeedKmh!.toStringAsFixed(0)} km/h',
            icon: Icons.air,
            alert: (condition.windSpeedKmh ?? 0) > 40,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _MetricTile(
            label: 'ICE RISK',
            // `null` is NOT "NO". 0.4.4 printed "NO" for an ice risk nobody had
            // measured — on a road that may have been freezing.
            value: switch (condition.iceRisk) {
              true => 'YES',
              false => 'NO',
              null => '—',
            },
            icon: condition.iceRisk == true
                ? Icons.warning
                : condition.iceRisk == null
                    ? Icons.help_outline
                    : Icons.check_circle,
            alert: condition.iceRisk == true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _MetricTile(
            label: 'FREEZING',
            value: switch (condition.freezing) {
              SafetyVerdict.hazardous => 'YES',
              SafetyVerdict.notHazardous => 'NO',
              SafetyVerdict.unknown => '—',
            },
            icon: Icons.thermostat,
            alert: condition.freezing == SafetyVerdict.hazardous,
          ),
        ),
      ],
    );
  }

  /// `null` metres = NOT MEASURED. It is not 10 km of clear air.
  static String _visibility(double? m) {
    if (m == null) return '—';
    return m >= 1000
        ? '${(m / 1000).toStringAsFixed(1)} km'
        : '${m.toStringAsFixed(0)} m';
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool alert;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alert ? Colors.red.withAlpha(30) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: alert
            ? Border.all(color: Colors.red.withAlpha(80))
            : Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(icon, color: alert ? Colors.red.shade300 : Colors.white54),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: alert ? Colors.red.shade200 : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white38,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  final WeatherState state;

  const _SafetyBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final isHazardous = state.isHazardous;
    final condition = state.condition;

    // THE THIRD STATE. Up to now this banner had exactly two: red HAZARD and
    // green ALL CLEAR — so a road nobody had measured was painted green and
    // labelled "Conditions clear — no safety alerts". "ALL CLEAR" is a POSITIVE
    // claim, and it may only be made about a road we actually assessed.
    final isUnknown = !isHazardous &&
        !state.isSnowing &&
        (condition == null || state.isConditionUnknown);

    final message = isHazardous
        ? _hazardMessage(condition!)
        : state.isSnowing
            ? 'Snow detected — drive with caution'
            : isUnknown
                ? '路面状況を取得できていません。見える範囲で運転してください。\n'
                    'Road conditions unavailable — drive to what you can see.'
                : 'Conditions clear — no safety alerts';

    final color = isHazardous
        ? Colors.red
        : state.isSnowing
            ? Colors.amber
            : isUnknown
                ? Colors.blueGrey
                : Colors.green;

    final icon = isHazardous
        ? Icons.report_problem
        : state.isSnowing
            ? Icons.info
            : isUnknown
                ? Icons.help_outline
                : Icons.check_circle;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHazardous
                      ? 'SAFETY ALERT — HAZARDOUS CONDITIONS'
                      : state.isSnowing
                          ? 'WEATHER ADVISORY'
                          : isUnknown
                              ? '未計測 / CONDITIONS NOT MEASURED'
                              : 'ALL CLEAR',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(color: color.withAlpha(200)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _hazardMessage(WeatherCondition c) {
    if (c.iceRisk == true) {
      // Precise term from the catalog's JAF-grounded announcement seam —
      // ja first (HER reads Japanese), EN kept for legibility.
      final a = RoadSurfaceState.blackIce.announcement!;
      return '${a.jaSpokenText}\n${a.enSpokenText}';
    }
    final vis = c.visibilityMeters;
    if (vis != null && vis < 200) {
      return 'Near-zero visibility — pull over if safe';
    }
    if (c.intensity == PrecipitationIntensity.heavy) {
      return vis == null
          ? 'Heavy snow — visibility not measured'
          : 'Heavy snow — visibility ${vis.toStringAsFixed(0)}m';
    }
    return 'Hazardous conditions detected';
  }
}
