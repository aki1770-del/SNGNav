/// SnowSceneScaffold — top-level Stack compositing all layers.
///
/// Z-layer structure:
///   `Z=0` MapLayer — dual-renderer (Fluorite 3D or flutter_map 2D)
///   `Z=1` NavigationOverlay — weather bar, speed, route progress, consent
///   `Z=2` SafetyOverlay — always rendered, always on top
///
/// Widget-mediated coupling:
///   - `BlocListener<RoutingBloc>`: routeActive → NavigationStarted
///   - WeatherStatusBar: isHazardous → SafetyAlertReceived
///   - FleetBloc: hasHazards → SafetyAlertReceived (fleet→safety bridge)
///   - Timer: auto-advances maneuvers (simulated drive)
///
/// Top-level Stack compositing all layers.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bloc/fleet_bloc.dart';
import '../bloc/fleet_state.dart';
import '../models/fleet_report.dart';
import '../bloc/location_bloc.dart';
import '../bloc/location_state.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../bloc/navigation_bloc.dart';
import '../bloc/navigation_event.dart';
import '../bloc/navigation_state.dart';
import '../bloc/routing_bloc.dart';
import '../bloc/routing_state.dart';
import 'consent_gate.dart';
import 'map_layer.dart';
import 'route_progress_bar.dart';
import 'safety_overlay.dart';
import 'scenario_phase_indicator.dart';
import 'speed_display.dart';
import 'weather_status_bar.dart';

class SnowSceneScaffold extends StatefulWidget {
  const SnowSceneScaffold({super.key, this.tileProvider});

  /// Optional tile provider (e.g., MBTiles for offline).
  /// When null, MapLayer uses the default online OSM tiles.
  final TileProvider? tileProvider;

  @override
  State<SnowSceneScaffold> createState() => _SnowSceneScaffoldState();
}

class _SnowSceneScaffoldState extends State<SnowSceneScaffold> {
  final MapController _mapController = MapController();
  Timer? _advanceTimer;
  bool _navigationStarted = false;

  @override
  void initState() {
    super.initState();

    // Initialize MapBloc after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapBloc>().add(const MapInitialized(
            center: LatLng(35.1709, 136.8815),
            zoom: 11,
          ));
    });
  }

  void _startAutoAdvance() {
    if (_advanceTimer != null) return;
    _advanceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final navState = context.read<NavigationBloc>().state;
      if (navState.status == NavigationStatus.arrived) {
        _advanceTimer?.cancel();
        _advanceTimer = null;
        return;
      }
      if (navState.status == NavigationStatus.navigating) {
        context.read<NavigationBloc>().add(const ManeuverAdvanced());
      }
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav Snow Scene v0.3'),
        centerTitle: true,
        actions: [
          // Navigation status chip
          BlocBuilder<NavigationBloc, NavigationState>(
            builder: (context, state) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  label: Text(state.status.name.toUpperCase(),
                      style: const TextStyle(fontSize: 10)),
                  backgroundColor: _navStatusColor(state.status),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ],
      ),
      body: MultiBlocListener(
        listeners: [
          // Widget-mediated: RoutingBloc routeActive → NavigationStarted
          BlocListener<RoutingBloc, RoutingState>(
            listenWhen: (prev, curr) =>
                !prev.hasRoute && curr.hasRoute,
            listener: (context, state) {
              if (!_navigationStarted && state.route != null) {
                _navigationStarted = true;
                context.read<NavigationBloc>().add(NavigationStarted(
                      route: state.route!,
                      destinationLabel: state.destinationLabel,
                    ));
                _startAutoAdvance();
              }
            },
          ),
          // Widget-mediated: FleetBloc hasHazards → SafetyAlertReceived
          BlocListener<FleetBloc, FleetState>(
            listenWhen: (prev, curr) =>
                !prev.hasHazards && curr.hasHazards,
            listener: (context, state) {
              final hazards = state.hazardReports;
              final hasIcy = hazards.any(
                  (r) => r.condition == RoadCondition.icy);
              context.read<NavigationBloc>().add(SafetyAlertReceived(
                    message: hasIcy
                        ? 'Fleet reports: icy road conditions detected '
                            '(${hazards.length} vehicles reporting)'
                        : 'Fleet reports: snowy road conditions ahead '
                            '(${hazards.length} vehicles reporting)',
                    severity: hasIcy
                        ? AlertSeverity.critical
                        : AlertSeverity.warning,
                  ));
            },
          ),
          // Follow GPS position on map when location updates
          BlocListener<LocationBloc, LocationState>(
            listenWhen: (prev, curr) => curr.hasPosition,
            listener: (context, state) {
              final pos = state.position!;
              final mapBloc = context.read<MapBloc>();
              if (mapBloc.state.cameraMode == CameraMode.follow) {
                mapBloc.add(CenterChanged(
                    LatLng(pos.latitude, pos.longitude)));
              }
            },
          ),
        ],
        child: Stack(
          children: [
            // [Z=0] MapLayer — dual-renderer
            MapLayer(
              mapController: _mapController,
              tileProvider: widget.tileProvider,
            ),

            // [Z=1] Navigation overlay
            _buildNavigationOverlay(context),

            // [Z=2] Safety overlay — always in tree (rule 1)
            const SafetyOverlay(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Z=1: Navigation overlay
  // -------------------------------------------------------------------------

  Widget _buildNavigationOverlay(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Column(
          children: [
            // Top: weather bar + scenario phase
            const WeatherStatusBar(),
            const ScenarioPhaseIndicator(),

            const Spacer(),

            // Bottom: route progress + speed + consent
            const RouteProgressBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Speed display
                  const SizedBox(width: 80, child: SpeedDisplay()),
                  const Spacer(),
                  // Consent gate
                  const ConsentGate(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _navStatusColor(NavigationStatus status) {
    return switch (status) {
      NavigationStatus.idle => Colors.grey.shade700,
      NavigationStatus.navigating => Colors.green.shade800,
      NavigationStatus.deviated => Colors.amber.shade800,
      NavigationStatus.arrived => Colors.blue.shade800,
    };
  }

}
