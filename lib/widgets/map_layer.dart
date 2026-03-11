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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

import '../bloc/consent_bloc.dart';
import '../bloc/consent_state.dart';
import '../bloc/fleet_bloc.dart';
import '../bloc/fleet_state.dart';
import '../bloc/location_bloc.dart';
import '../bloc/location_state.dart';
import '../bloc/weather_bloc.dart';
import '../bloc/weather_state.dart';
import '../fluorite/fluorite.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'fleet_layer.dart';
import 'hazard_zone_layer.dart';

/// Dual-renderer map widget.
///
/// When [fluoriteAvailable] is true, renders the Fluorite 3D scene.
/// Otherwise, renders the 2D flutter_map with all overlay layers.
class MapLayer extends StatelessWidget {
  static const _offlineMaxZoom = 12.0;

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
    return BlocConsumer<MapBloc, MapState>(
      listenWhen: (prev, curr) =>
          prev.center != curr.center ||
          prev.zoom != curr.zoom ||
          prev.hasFitBounds != curr.hasFitBounds,
      listener: (context, mapState) {
        if (mapState.hasFitBounds) {
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds(mapState.fitBoundsSw!, mapState.fitBoundsNe!),
              padding: const EdgeInsets.all(56),
            ),
          );
        } else if (mapState.cameraMode == CameraMode.follow) {
          mapController.move(mapState.center, mapController.camera.zoom);
        }
      },
      builder: (context, mapState) {
        return BlocBuilder<RoutingBloc, RoutingState>(
          builder: (context, routingState) {
            return BlocBuilder<NavigationBloc, NavigationState>(
              builder: (context, navState) {
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
                                        context.read<MapBloc>().add(const UserPanDetected());
                                      }
                                    },
                                  ),
                                  children: [
                                    if (tileProvider != null)
                                      TileLayer(
                                        tileProvider: tileProvider!,
                                        maxZoom: _offlineMaxZoom,
                                        userAgentPackageName: 'com.sngnav.snow_scene',
                                      )
                                    else
                                      TileLayer(
                                        urlTemplate:
                                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        tileProvider: NetworkTileProvider(),
                                        userAgentPackageName: 'com.sngnav.snow_scene',
                                      ),
                                    if (tileProvider != null)
                                      TileLayer(
                                        minZoom: _offlineMaxZoom + 1,
                                        urlTemplate:
                                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        tileProvider: NetworkTileProvider(),
                                        userAgentPackageName: 'com.sngnav.snow_scene',
                                      ),
                                    if (mapState.isLayerVisible(MapLayerType.route) &&
                                        routingState.hasRoute)
                                      PolylineLayer(
                                        polylines: [
                                          Polyline(
                                            points: routingState.route!.shape,
                                            strokeWidth: 9,
                                            color: Colors.white.withValues(alpha: 0.9),
                                          ),
                                          Polyline(
                                            points: routingState.route!.shape,
                                            strokeWidth: 6,
                                            color: weatherState.isHazardous
                                                ? Colors.orange
                                                : Colors.blue,
                                          ),
                                        ],
                                      ),
                                    if (mapState.isLayerVisible(MapLayerType.route) &&
                                        routingState.hasRoute)
                                      MarkerLayer(
                                        markers: routingState.route!.maneuvers
                                            .map((maneuver) {
                                          final isCurrent =
                                              navState.currentManeuverIndex == maneuver.index &&
                                                  navState.status ==
                                                      NavigationStatus.navigating;
                                          return Marker(
                                            point: maneuver.position,
                                            width: isCurrent ? 34 : 24,
                                            height: isCurrent ? 34 : 24,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: isCurrent
                                                    ? Colors.amber
                                                    : Colors.black87,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: isCurrent ? 3 : 2,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Colors.black26,
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${maneuver.index + 1}',
                                                  style: TextStyle(
                                                    color: isCurrent
                                                        ? Colors.black
                                                        : Colors.white,
                                                    fontSize: isCurrent ? 13 : 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    if (mapState.isLayerVisible(MapLayerType.hazard) &&
                                        consentState.isFleetGranted &&
                                        fleetState.isListening &&
                                        fleetState.hasHazards)
                                      HazardZoneLayer(
                                        zones: HazardAggregator.aggregate(
                                          fleetState.reports,
                                        ),
                                      ),
                                    if (mapState.isLayerVisible(MapLayerType.fleet) &&
                                        consentState.isFleetGranted &&
                                        fleetState.isListening)
                                      FleetLayer(reports: fleetState.reports),
                                    if (mapState.isLayerVisible(MapLayerType.weather) &&
                                        weatherState.isSnowing &&
                                        routingState.hasRoute)
                                      PolygonLayer(
                                        polygons: [
                                          Polygon(
                                            points: _snowZonePolygon(
                                              routingState.route!,
                                            ),
                                            color: _snowZoneColor(weatherState),
                                            borderColor: _snowZoneBorder(weatherState),
                                            borderStrokeWidth: 2,
                                            label: _snowZoneLabel(weatherState),
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
                                    if (mapState.isLayerVisible(MapLayerType.hazard) &&
                                        weatherState.isHazardous)
                                      MarkerLayer(markers: _hazardMarkers),
                                    if (locState.hasPosition)
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: LatLng(
                                              locState.position!.latitude,
                                              locState.position!.longitude,
                                            ),
                                            width: 36,
                                            height: 36,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _qualityColor(locState.quality)
                                                    .withValues(alpha: 0.22),
                                                border: Border.all(
                                                  color: _qualityColor(locState.quality),
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    color: _qualityColor(locState.quality),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 3,
                                                    ),
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: Colors.black26,
                                                        blurRadius: 6,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
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

  static String _snowZoneLabel(WeatherState state) {
    if (!state.hasCondition) return 'Snow Zone';
    final condition = state.condition!;
    final intensity = switch (condition.intensity) {
      PrecipitationIntensity.heavy => 'Heavy',
      PrecipitationIntensity.moderate => 'Moderate',
      PrecipitationIntensity.light => 'Light',
      PrecipitationIntensity.none => '',
    };
    final prefix = intensity.isEmpty ? '' : '$intensity ';
    return '${prefix}Snow Zone';
  }

  static List<LatLng> _snowZonePolygon(RouteResult route) {
    final segment = _snowZoneSegment(route);
    final bounds = LatLngBounds.fromPoints(segment);
    final latSpan = bounds.north - bounds.south;
    final lonSpan = bounds.east - bounds.west;
    final averageLat = (bounds.north + bounds.south) / 2;
    final latPadding = math.max(latSpan * 0.35, 0.012);
    final lonPadding = math.max(
      lonSpan * 0.35,
      0.012 / math.max(0.35, math.cos(averageLat * math.pi / 180).abs()),
    );

    return [
      LatLng(bounds.north + latPadding, bounds.west - lonPadding),
      LatLng(bounds.north + latPadding, bounds.east + lonPadding),
      LatLng(bounds.south - latPadding, bounds.east + lonPadding),
      LatLng(bounds.south - latPadding, bounds.west - lonPadding),
    ];
  }

  static List<LatLng> _snowZoneSegment(RouteResult route) {
    if (route.shape.length < 2) {
      return route.shape;
    }

    if (route.maneuvers.length >= 6) {
      final startIndex = _nearestShapeIndex(route.shape, route.maneuvers[3].position);
      final endIndex = _nearestShapeIndex(route.shape, route.maneuvers[5].position);
      final lower = math.min(startIndex, endIndex);
      final upper = math.max(startIndex, endIndex);
      return route.shape.sublist(lower, upper + 1);
    }

    return route.shape;
  }

  static int _nearestShapeIndex(List<LatLng> shape, LatLng point) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < shape.length; index++) {
      final candidate = shape[index];
      final distance = math.pow(candidate.latitude - point.latitude, 2) +
          math.pow(candidate.longitude - point.longitude, 2);
      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        bestIndex = index;
      }
    }
    return bestIndex;
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
