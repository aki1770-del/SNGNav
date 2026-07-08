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
import 'package:snow_rendering/snow_rendering.dart';

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
      // Widget-mediated coupling: weather → safety bridge.
      // The gate is _isAlertable, NOT raw isHazardous: the invisible-ice
      // window (no precipitation, ambient 0…+3 °C with dew point ≤ 0 °C —
      // the radiative-frost morning) has isHazardous FALSE, and without
      // the widening the screen stays silent on exactly the surface that
      // looks safest. The second clause fires again when an already-
      // alertable condition ESCALATES into raw hazard (e.g. standing
      // radiative frost → heavy snow), so escalation is never swallowed
      // by the widened predicate.
      listenWhen: (prev, curr) =>
          (!_isAlertable(prev) && _isAlertable(curr)) ||
          (_isAlertable(prev) && !prev.isHazardous && curr.isHazardous),
      listener: (context, state) {
        final condition = state.condition!;
        final invisibleIce = _isInvisibleIceWindow(condition);
        final message = _hazardMessage(condition, invisibleIce);
        // Explicit feed ice flag → critical. The invisible-ice window is
        // a dew-point INFERENCE (no surface measurement), so it alerts at
        // warning tier — mirroring the pre-trip surface's milder tier for
        // the same window, and keeping critical trustworthy.
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
        // Ice presence: explicit feed flag, or the invisible-ice window —
        // the same predicates as the alert GATE, so badge presence and
        // alert firing can never disagree. (Message CONTENT may still name
        // a classified ice surface this predicate doesn't cover — e.g.
        // heavy freezing rain names ブラックアイスバーン while the badge
        // reads HAZARD; that path fails safe: it always alerts.)
        final hasIceSurface =
            condition.iceRisk || _isInvisibleIceWindow(condition);
        final isHazardous = state.isHazardous || hasIceSurface;

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
                    color: hasIceSurface
                        ? Colors.red.shade700
                        : Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    hasIceSurface ? 'ICE' : 'HAZARD',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

            ],
          ),
        );
      },
    );
  }

  /// The INVISIBLE-ice alert window: no precipitation, ambient ABOVE
  /// freezing, and the dew-point classifier says the road surface can be
  /// frozen (radiative frost — the Akita pre-dawn morning where the road
  /// looks merely wet or dry).
  ///
  /// Scope, stated honestly (measured by probe, 2026-07-08):
  /// `isRadiativeFrostBlackIce` alone is true for essentially EVERY
  /// ambient ≤ +3 °C whose dew point is ≤ 0 °C — including all sub-zero
  /// readings at any plausible humidity. Gating on it directly would
  /// alert on every freezing reading from a humidity-carrying feed
  /// (Open-Meteo supplies humidity) — mass cry-wolf. The two extra
  /// clauses restrict the ALERT to the band where nothing else warns and
  /// the "looks wet but may be frozen" fact is true:
  ///
  /// - `precipType == none`: visible precipitation means the driver can
  ///   see the hazard class; the feed `iceRisk` flag / `isHazardous`
  ///   already cover those paths.
  /// - `temperature > 0`: at sub-zero ambient the pre-existing product
  ///   contract (negative-safety suite: −5 °C clear NEVER alerts) holds —
  ///   the classifier's cold-dry branch stays render-only.
  ///
  /// Within the remaining 0…+3 °C no-precip band this still fires on
  /// most winter-dry mornings whose dew point is ≤ 0 °C. That exposure
  /// is ACCEPTED deliberately: it is the bond-#3 founding window, the
  /// phrasing is possibility-graded (おそれ), it alerts at WARNING
  /// tier, not critical — mirroring the pre-trip surface's treatment of
  /// the same window — and the transition-gated listener fires ONCE per
  /// entry into the window, not continuously.
  ///
  /// HABITUATION TRIPWIRE (standing, per the bond-#3 restraint
  /// decision): repeated consecutive-morning warnings can train the
  /// driver to dismiss the panel on the morning the road really is
  /// frozen. No wind/time/dew-point-margin dampener is added HERE
  /// because there is no field data to ground one — inventing a safety
  /// threshold without measurement violates measure-first, and an
  /// in-drive-only gate would reopen the pre-trip↔in-drive
  /// contradiction bond #3 closed. The falsifier: once real-feed
  /// exposure is measurable, if this window fires on N consecutive
  /// mornings for the same route, the dampener decision must be
  /// REVISITED with that data (do not silently keep the alert; do not
  /// silently gate it).
  static bool _isInvisibleIceWindow(WeatherCondition condition) {
    return condition.precipType == PrecipitationType.none &&
        condition.temperatureCelsius > 0 &&
        isRadiativeFrostBlackIce(
          ambientCelsius: condition.temperatureCelsius,
          humidityRHPercent: condition.humidityRH,
        );
  }

  /// Whether the state warrants a safety alert: the raw hazard flags OR
  /// the invisible-ice window above.
  static bool _isAlertable(WeatherState state) {
    final condition = state.condition;
    if (condition == null) return false;
    return state.isHazardous || _isInvisibleIceWindow(condition);
  }

  static String _hazardMessage(
    WeatherCondition condition,
    bool invisibleIce,
  ) {
    // The precise term HER knows, from the catalog's JAF-grounded
    // announcement seam — ja first (the driver this app anchors on reads
    // Japanese), EN line kept for foreign-driver legibility. The
    // looks-wet variant is spoken ONLY on the invisible-ice path; the
    // feed-flagged path (typically visible precipitation at ≤ 0 °C) gets
    // the provenance-neutral line — telling a driver in falling snow
    // that the road "looks wet" would be false.
    if (invisibleIce) {
      final a = invisibleBlackIceAnnouncement;
      return '${a.jaSpokenText}\n${a.enSpokenText}';
    }
    if (condition.iceRisk) {
      final a = RoadSurfaceState.blackIce.announcement!;
      return '${a.jaSpokenText}\n${a.enSpokenText}';
    }
    if (condition.visibilityMeters < 200) {
      return 'Visibility critically low (${condition.visibilityMeters.toStringAsFixed(0)}m) — consider stopping';
    }
    if (condition.intensity == PrecipitationIntensity.heavy) {
      // Name the classified surface precisely when the vocabulary exists
      // (圧雪 / シャーベット — the terms the driver knows), falling back
      // to the generic line for surfaces without one.
      final surfaceAnnouncement =
          RoadSurfaceState.fromCondition(condition).announcement;
      if (surfaceAnnouncement != null) {
        return '${surfaceAnnouncement.jaSpokenText}\n'
            '${surfaceAnnouncement.enSpokenText}';
      }
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
