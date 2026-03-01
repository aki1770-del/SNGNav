/// MapLayer — dual-renderer switch.
///
/// Selects between:
///   - `FluoriteView` (3D terrain) when `fluoriteAvailable` is true
///   - `FlutterMap` (2D tiles) as the production fallback
///
/// The 2D renderer is extracted from `SnowSceneScaffold._buildMap()` —
/// same 6-BlocBuilder structure, same 6 conditional layers.
///
/// Weather-adaptive route color, intensity-scaled snow zone, multiple
/// hazard markers along the mountain pass. FleetLayer integration
/// (consent-gated fleet markers). HazardZoneLayer (fleet hazard
/// aggregation + safety bridge).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bloc/consent_bloc.dart';
import '../bloc/consent_state.dart';
import '../bloc/fleet_bloc.dart';
import '../bloc/fleet_state.dart';
import '../bloc/location_bloc.dart';
import '../bloc/location_state.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../bloc/routing_bloc.dart';
import '../bloc/routing_state.dart';
import '../bloc/weather_bloc.dart';
import '../bloc/weather_state.dart';
import '../fluorite/fluorite.dart';
import '../models/weather_condition.dart';
import '../services/hazard_aggregator.dart';
import 'fleet_layer.dart';
import 'hazard_zone_layer.dart';

/// Dual-renderer map widget.
///
/// When [fluoriteAvailable] is true, renders the Fluorite 3D scene.
/// Otherwise, renders the 2D flutter_map with all overlay layers.
class MapLayer extends StatelessWidget {
  const MapLayer({
    super.key,
    required this.mapController,
    this.fluoriteAvailable = false,
    this.fluoriteHostApi,
    this.onFluoriteStatusChanged,
    this.tileProvider,
  });

  /// The flutter_map controller (owned by parent scaffold).
  final MapController mapController;

  /// Whether the Fluorite 3D renderer is available.
  ///
  /// In Phase A, this is always false. In Phase B, capability detection
  /// sets this based on platform support and GPU availability.
  final bool fluoriteAvailable;

  /// Optional custom host API for FluoriteView (testing / Phase B).
  final FluoriteHostApi? fluoriteHostApi;

  /// Callback when FluoriteView status changes.
  final ValueChanged<FluoriteViewStatus>? onFluoriteStatusChanged;

  /// Optional tile provider (e.g., MBTiles for offline).
  /// When null, uses the default online OSM tile layer.
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    if (fluoriteAvailable) {
      return FluoriteView(
        hostApi: fluoriteHostApi,
        onStatusChanged: onFluoriteStatusChanged,
        placeholder: _buildFlutterMap(context),
      );
    }
    return _buildFlutterMap(context);
  }

  // -------------------------------------------------------------------------
  // 2D fallback — extracted from SnowSceneScaffold._buildMap()
  // -------------------------------------------------------------------------

  Widget _buildFlutterMap(BuildContext context) {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, mapState) {
        return BlocBuilder<RoutingBloc, RoutingState>(
          builder: (context, routingState) {
            return BlocBuilder<LocationBloc, LocationState>(
              builder: (context, locState) {
                return BlocBuilder<WeatherBloc, WeatherState>(
                  builder: (context, weatherState) {
                    return BlocBuilder<FleetBloc, FleetState>(
                      builder: (context, fleetState) {
                        return BlocBuilder<ConsentBloc, ConsentState>(
                          builder: (context, consentState) {
                    return FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: mapState.center,
                        initialZoom: mapState.zoom,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture) {
                            context
                                .read<MapBloc>()
                                .add(const UserPanDetected());
                          }
                        },
                      ),
                      children: [
                        // Base tiles — MBTiles (offline) or OSM (online)
                        TileLayer(
                          urlTemplate: tileProvider == null
                              ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                              : null,
                          tileProvider: tileProvider ?? NetworkTileProvider(),
                          userAgentPackageName: 'com.sngnav.snow_scene',
                        ),

                        // Route polyline — color adapts to weather
                        if (mapState.isLayerVisible(MapLayerType.route) &&
                            routingState.hasRoute)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: routingState.route!.shape,
                                strokeWidth: 5,
                                color: weatherState.isHazardous
                                    ? Colors.orange
                                    : Colors.blue,
                              ),
                            ],
                          ),

                        // Fleet hazard zones — aggregated circles (Z=0.5)
                        if (mapState.isLayerVisible(MapLayerType.fleet) &&
                            consentState.isFleetGranted &&
                            fleetState.isListening &&
                            fleetState.hasHazards)
                          HazardZoneLayer(
                            zones: HazardAggregator.aggregate(
                              fleetState.reports,
                            ),
                          ),

                        // Fleet vehicle markers (Z=1) — consent-gated
                        if (mapState.isLayerVisible(MapLayerType.fleet) &&
                            consentState.isFleetGranted &&
                            fleetState.isListening)
                          FleetLayer(reports: fleetState.reports),

                        // Weather zone overlay — intensity scales opacity
                        if (mapState.isLayerVisible(MapLayerType.weather) &&
                            weatherState.isSnowing)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: const [
                                  LatLng(35.10, 137.15),
                                  LatLng(35.10, 137.45),
                                  LatLng(35.00, 137.45),
                                  LatLng(35.00, 137.15),
                                ],
                                color: _snowZoneColor(weatherState),
                                borderColor: _snowZoneBorder(weatherState),
                                borderStrokeWidth: 2,
                                label: 'Snow Zone',
                                labelStyle: TextStyle(
                                  color: weatherState.isHazardous
                                      ? Colors.red.shade300
                                      : Colors.blue.shade300,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                        // Safety markers — multiple hazard points along pass
                        if (mapState.isLayerVisible(MapLayerType.safety) &&
                            weatherState.isHazardous)
                          MarkerLayer(
                            markers: _hazardMarkers,
                          ),

                        // Current position marker
                        if (locState.hasPosition)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(
                                  locState.position!.latitude,
                                  locState.position!.longitude,
                                ),
                                width: 20,
                                height: 20,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _qualityColor(locState.quality),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 3),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                        // Attribution
                        const SimpleAttributionWidget(
                          source: Text('\u00a9 OpenStreetMap contributors'),
                        ),
                      ],
                    );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  static Color _qualityColor(LocationQuality quality) {
    return switch (quality) {
      LocationQuality.fix => Colors.blue,
      LocationQuality.degraded => Colors.amber,
      LocationQuality.stale => Colors.orange,
      LocationQuality.acquiring => Colors.grey,
      LocationQuality.error => Colors.red,
      LocationQuality.uninitialized => Colors.grey,
    };
  }

  // ---------------------------------------------------------------------------
  // Weather-adaptive visuals
  // ---------------------------------------------------------------------------

  static Color _snowZoneColor(WeatherState state) {
    if (!state.hasCondition) return Colors.blue.withAlpha(30);
    final condition = state.condition!;
    if (condition.iceRisk) return Colors.red.withAlpha(40);
    return switch (condition.intensity) {
      PrecipitationIntensity.heavy => Colors.blue.withAlpha(60),
      PrecipitationIntensity.moderate => Colors.blue.withAlpha(40),
      _ => Colors.blue.withAlpha(25),
    };
  }

  static Color _snowZoneBorder(WeatherState state) {
    if (!state.hasCondition) return Colors.blue.withAlpha(80);
    final condition = state.condition!;
    if (condition.iceRisk) return Colors.red.withAlpha(120);
    return switch (condition.intensity) {
      PrecipitationIntensity.heavy => Colors.blue.withAlpha(140),
      PrecipitationIntensity.moderate => Colors.blue.withAlpha(100),
      _ => Colors.blue.withAlpha(60),
    };
  }

  /// Hazard markers along the Nagoya mountain pass.
  static const _hazardMarkers = [
    Marker(
      point: LatLng(35.0600, 137.2500),
      width: 32,
      height: 32,
      child: Icon(Icons.warning_amber, color: Colors.orange, size: 24),
    ),
    Marker(
      point: LatLng(35.0500, 137.3200),
      width: 36,
      height: 36,
      child: Icon(Icons.warning, color: Colors.red, size: 28),
    ),
    Marker(
      point: LatLng(35.0550, 137.3700),
      width: 32,
      height: 32,
      child: Icon(Icons.warning_amber, color: Colors.orange, size: 24),
    ),
  ];
}
