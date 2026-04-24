import 'dart:async';
import 'dart:io';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:voice_guidance/voice_guidance.dart';

/// Local adapter mirroring lib/adapters/navigation_route_adapter.dart.
/// The example tree has no access to that internal app path, so the
/// extension is duplicated here verbatim — consumers of any
/// routing_engine route must convert at this boundary before
/// dispatching navigation events.
extension _RouteResultToNavigation on RouteResult {
  NavigationRoute toNavigationRoute() => NavigationRoute(
        shape: shape,
        maneuvers: maneuvers
            .map((m) => NavigationManeuver(
                  index: m.index,
                  instruction: m.instruction,
                  type: m.type,
                  lengthKm: m.lengthKm,
                  timeSeconds: m.timeSeconds,
                  position: m.position,
                ))
            .toList(),
        totalDistanceKm: totalDistanceKm,
        totalTimeSeconds: totalTimeSeconds,
        summary: summary,
      );
}

const _origin = LatLng(35.1709, 136.8815);
const _destination = LatLng(35.0700, 137.4000);
const _toyotaCity = LatLng(35.0831, 137.1559);
const _mbtilesPath = '../data/offline_tiles.mbtiles';
const _voiceGuidanceEnabled =
    bool.fromEnvironment('VOICE_GUIDANCE', defaultValue: true);
const _voiceLanguageTag = String.fromEnvironment(
  'VOICE_LANGUAGE',
  defaultValue: 'en-US',
);
final TtsEngine _ttsEngine =
    _voiceGuidanceEnabled ? createDefaultTtsEngine() : NoOpTtsEngine();

final _demoRoute = RouteResult(
  shape: const [
    // Nagoya Station area
    LatLng(35.1709, 136.8815),
    LatLng(35.1705, 136.8850),
    LatLng(35.1700, 136.8900),
    LatLng(35.1695, 136.8960),
    LatLng(35.1690, 136.9020),
    LatLng(35.1685, 136.9080),
    // Heading east toward Chikusa
    LatLng(35.1680, 136.9100),
    LatLng(35.1672, 136.9150),
    LatLng(35.1660, 136.9220),
    LatLng(35.1645, 136.9300),
    LatLng(35.1630, 136.9380),
    LatLng(35.1610, 136.9450),
    // Route 153 southeast toward Tenpaku
    LatLng(35.1580, 136.9500),
    LatLng(35.1550, 136.9560),
    LatLng(35.1520, 136.9600),
    LatLng(35.1480, 136.9650),
    LatLng(35.1450, 136.9700),
    LatLng(35.1410, 136.9760),
    // Approaching Miyoshi
    LatLng(35.1370, 136.9830),
    LatLng(35.1330, 136.9900),
    LatLng(35.1280, 136.9970),
    LatLng(35.1230, 137.0040),
    LatLng(35.1200, 137.0100),
    LatLng(35.1160, 137.0180),
    // Route 153 continuing east
    LatLng(35.1120, 137.0260),
    LatLng(35.1080, 137.0350),
    LatLng(35.1040, 137.0450),
    LatLng(35.1000, 137.0550),
    LatLng(35.0960, 137.0650),
    LatLng(35.0930, 137.0750),
    // Approaching Toyota City
    LatLng(35.0900, 137.0850),
    LatLng(35.0880, 137.0960),
    LatLng(35.0860, 137.1080),
    LatLng(35.0845, 137.1200),
    LatLng(35.0835, 137.1350),
    LatLng(35.0831, 137.1559),
    // Past Toyota heading east into mountains
    LatLng(35.0825, 137.1700),
    LatLng(35.0810, 137.1850),
    LatLng(35.0790, 137.2000),
    LatLng(35.0760, 137.2150),
    LatLng(35.0720, 137.2300),
    LatLng(35.0680, 137.2400),
    // Mountain road climbing
    LatLng(35.0640, 137.2500),
    LatLng(35.0610, 137.2600),
    LatLng(35.0590, 137.2720),
    LatLng(35.0570, 137.2850),
    LatLng(35.0550, 137.2980),
    LatLng(35.0530, 137.3100),
    // Descending toward Mikawa Highlands
    LatLng(35.0520, 137.3200),
    LatLng(35.0530, 137.3320),
    LatLng(35.0550, 137.3450),
    LatLng(35.0580, 137.3570),
    LatLng(35.0610, 137.3680),
    LatLng(35.0650, 137.3800),
    LatLng(35.0680, 137.3900),
    LatLng(35.0700, 137.4000),
  ],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Depart Nagoya Station via Route 153 East',
      type: 'depart',
      lengthKm: 2.1,
      timeSeconds: 180,
      position: LatLng(35.1709, 136.8815),
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Continue east on Route 153',
      type: 'straight',
      lengthKm: 4.5,
      timeSeconds: 270,
      position: LatLng(35.1680, 136.9100),
    ),
    RouteManeuver(
      index: 2,
      instruction: 'Bear right toward Toyota',
      type: 'slight_right',
      lengthKm: 5.2,
      timeSeconds: 310,
      position: LatLng(35.1450, 136.9600),
    ),
    RouteManeuver(
      index: 3,
      instruction: 'Continue through Toyota City',
      type: 'straight',
      lengthKm: 6.0,
      timeSeconds: 430,
      position: LatLng(35.1200, 137.0100),
    ),
    RouteManeuver(
      index: 4,
      instruction: 'Turn left toward the mountain road',
      type: 'left',
      lengthKm: 8.0,
      timeSeconds: 690,
      position: LatLng(35.0831, 137.1559),
    ),
    RouteManeuver(
      index: 5,
      instruction: 'Climb toward the summit',
      type: 'straight',
      lengthKm: 5.5,
      timeSeconds: 570,
      position: LatLng(35.0600, 137.2500),
    ),
    RouteManeuver(
      index: 6,
      instruction: 'Descend toward Mikawa Highlands',
      type: 'straight',
      lengthKm: 6.8,
      timeSeconds: 610,
      position: LatLng(35.0500, 137.3200),
    ),
    RouteManeuver(
      index: 7,
      instruction: 'Arrive at Mikawa Highlands',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: LatLng(35.0700, 137.4000),
    ),
  ],
  totalDistanceKm: 38.1,
  totalTimeSeconds: 3060,
  summary: 'Route 153: Nagoya -> Toyota -> Mikawa Highlands',
  engineInfo: EngineInfo(
    name: 'mock',
    version: '0.2.0-example',
    queryLatency: Duration(milliseconds: 24),
  ),
);

void main() {
  runApp(const SngNavExampleApp());
}

class SngNavExampleApp extends StatelessWidget {
  const SngNavExampleApp({super.key, this.homeOverride});

  final Widget? homeOverride;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E6D61)),
        useMaterial3: true,
      ),
      home: homeOverride ??
          MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) => MapBloc()
                  ..add(const MapInitialized(center: _origin, zoom: 9.8)),
              ),
              BlocProvider(
                create: (_) => RoutingBloc(engine: _HybridRoutingEngine())
                  ..add(const RoutingEngineCheckRequested()),
              ),
              BlocProvider(create: (_) => NavigationBloc()),
              BlocProvider(
                create: (context) => VoiceGuidanceBloc(
                  ttsEngine: _ttsEngine,
                  navigationStateStream: context.read<NavigationBloc>().stream,
                  config: VoiceGuidanceConfig(
                    enabled: _voiceGuidanceEnabled,
                    languageTag: _voiceLanguageTag,
                  ),
                ),
              ),
            ],
            child: const ExampleHomePage(),
          ),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  final MapController _mapController = MapController();
  final SimulatedWeatherProvider _weatherProvider =
      SimulatedWeatherProvider(interval: const Duration(seconds: 6));
  static const _autoAdvanceInterval = Duration(seconds: 3);
  StreamSubscription<WeatherCondition>? _weatherSubscription;
  Timer? _autoAdvanceTimer;

  offline_tiles.OfflineTileManager? _offlineTileManager;
  WeatherCondition? _latestWeather;
  String _tileStatus = 'Checking tile source...';
  bool? _voiceBackendAvailable;
  bool _autoAdvanceEnabled = false;
  String _autoAdvanceStatus = 'Manual control';
  bool _isTestingVoice = false;
  String? _voiceTestStatus;
  bool _isOffline = false;
  bool _navigationStarted = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _initTileProvider();
    _loadVoiceDiagnostics();
    _startWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoutingBloc>().add(const RouteRequested(
            origin: _origin,
            destination: _destination,
            destinationLabel: 'Mikawa Highlands',
          ));
    });
  }

  Future<void> _loadVoiceDiagnostics() async {
    final available = await _ttsEngine.isAvailable();
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceBackendAvailable = available;
    });
  }

  Future<void> _runVoiceTest() async {
    if (_isTestingVoice) {
      return;
    }

    if (!_voiceGuidanceEnabled) {
      setState(() {
        _voiceTestStatus = 'Voice guidance disabled by VOICE_GUIDANCE.';
      });
      return;
    }

    setState(() {
      _isTestingVoice = true;
      _voiceTestStatus = 'Sending test phrase...';
    });

    try {
      final available = await _ttsEngine.isAvailable();
      if (!available) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceBackendAvailable = false;
          _voiceTestStatus = 'Voice is unavailable.';
        });
        return;
      }

      await _ttsEngine.setLanguage(_voiceLanguageTag);
      await _ttsEngine.setVolume(1.0);
      await _ttsEngine.stop();
      await _ttsEngine.speak(_voiceTestPhrase(_voiceLanguageTag));

      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBackendAvailable = true;
        _voiceTestStatus = 'Test phrase sent.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceBackendAvailable = false;
        _voiceTestStatus = 'Voice test failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTestingVoice = false;
        });
      }
    }
  }

  Future<void> _initTileProvider() async {
    final file = File(_mbtilesPath);
    if (await file.exists()) {
      final manager = offline_tiles.OfflineTileManager(
        tileSource: offline_tiles.TileSourceType.mbtiles,
        mbtilesPath: _mbtilesPath,
      );
      if (!mounted) {
        manager.dispose();
        return;
      }
      setState(() {
        _offlineTileManager = manager;
        _isOffline = true;
        _tileStatus = 'Offline MBTiles loaded from $_mbtilesPath';
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _tileStatus = 'No MBTiles found, using OpenStreetMap fallback';
    });
  }

  Future<void> _startWeather() async {
    _weatherSubscription = _weatherProvider.conditions.listen((condition) {
      if (!mounted) {
        return;
      }
      setState(() {
        _latestWeather = condition;
      });
      if (condition.isHazardous) {
        context.read<NavigationBloc>().add(
              SafetyAlertReceived(
                message:
                    'Weather: ${condition.precipType.name} ${condition.intensity.name}, visibility ${condition.visibilityMeters.toStringAsFixed(0)} m',
                severity: condition.iceRisk || condition.visibilityMeters < 200
                    ? AlertSeverity.critical
                    : AlertSeverity.warning,
              ),
            );
      }
    });
    await _weatherProvider.startMonitoring();
  }

  void _startNavigation(RouteResult route) {
    if (_navigationStarted) {
      return;
    }
    _navigationStarted = true;
    context.read<NavigationBloc>().add(
          NavigationStarted(
            route: route.toNavigationRoute(),
            destinationLabel: 'Mikawa Highlands',
          ),
        );
    context.read<MapBloc>().add(
          FitToBounds(
            southWest: _southWest(route.shape),
            northEast: _northEast(route.shape),
          ),
        );
  }

  void _advanceNavigation() {
    context.read<NavigationBloc>().add(const ManeuverAdvanced());
    // Force map to follow the new maneuver position
    context.read<MapBloc>().add(
          const CameraModeChanged(CameraMode.follow),
        );
  }

  void _toggleAutoAdvance() {
    if (_autoAdvanceEnabled) {
      _stopAutoAdvance(status: 'Manual control');
      return;
    }

    final navState = context.read<NavigationBloc>().state;
    if (!navState.hasRoute) {
      setState(() {
        _autoAdvanceStatus = 'Waiting for route';
      });
      return;
    }

    setState(() {
      _autoAdvanceEnabled = true;
      _autoAdvanceStatus = 'Auto-advancing every 3 seconds';
    });

    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer.periodic(_autoAdvanceInterval, (_) {
      if (!mounted) {
        _stopAutoAdvance();
        return;
      }

      final currentState = context.read<NavigationBloc>().state;
      switch (currentState.status) {
        case NavigationStatus.idle:
          _stopAutoAdvance(status: 'Waiting for route');
        case NavigationStatus.arrived:
          _stopAutoAdvance(status: 'Demo complete');
        case NavigationStatus.deviated:
          if (_autoAdvanceStatus != 'Paused for reroute') {
            setState(() {
              _autoAdvanceStatus = 'Paused for reroute';
            });
          }
        case NavigationStatus.navigating:
          if (_autoAdvanceStatus != 'Auto-advancing every 3 seconds') {
            setState(() {
              _autoAdvanceStatus = 'Auto-advancing every 3 seconds';
            });
          }
          _advanceNavigation();
      }
    });
  }

  void _stopAutoAdvance({String status = 'Manual control'}) {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _autoAdvanceEnabled = false;
      _autoAdvanceStatus = status;
    });
  }

  void _simulateDeviation() {
    final navBloc = context.read<NavigationBloc>();
    navBloc.add(const RouteDeviationDetected(reason: 'Snow drift on shoulder'));
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      navBloc.add(RerouteCompleted(newRoute: _demoRoute.toNavigationRoute()));
    });
  }

  void _applyMapState(MapState state) {
    if (!_mapReady) return;
    if (state.hasFitBounds) {
      final bounds = LatLngBounds(state.fitBoundsSw!, state.fitBoundsNe!);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
      );
      return;
    }
    _mapController.move(state.center, state.zoom);
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _weatherSubscription?.cancel();
    _weatherProvider.dispose();
    _offlineTileManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<MapBloc, MapState>(
          listener: (_, state) {
            if (state.isReady) {
              _applyMapState(state);
            }
          },
        ),
        BlocListener<RoutingBloc, RoutingState>(
          listener: (_, state) {
            if (state.hasRoute && state.route != null) {
              _startNavigation(state.route!);
            }
          },
        ),
        BlocListener<NavigationBloc, NavigationState>(
          listener: (_, state) {
            final maneuver = state.currentManeuver;
            if (maneuver != null) {
              context.read<MapBloc>().add(CenterChanged(maneuver.position));
              context.read<MapBloc>().add(const ZoomChanged(12.0));
            }
            if (_autoAdvanceEnabled && state.status == NavigationStatus.arrived) {
              _stopAutoAdvance(status: 'Demo complete');
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SNGNav Example'),
          actions: [
            BlocBuilder<VoiceGuidanceBloc, VoiceGuidanceState>(
              builder: (context, voiceState) {
                final isMuted =
                    !_voiceGuidanceEnabled || voiceState.status == VoiceGuidanceStatus.muted;
                return IconButton(
                  tooltip: isMuted ? 'Enable voice guidance' : 'Mute voice guidance',
                  onPressed: () {
                    context.read<VoiceGuidanceBloc>().add(
                          isMuted ? const VoiceEnabled() : const VoiceDisabled(),
                        );
                  },
                  icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  _isOffline ? 'OFFLINE TILES' : 'ONLINE TILES',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final content = [
              Expanded(flex: wide ? 7 : 6, child: _buildMapStack()),
              Expanded(flex: wide ? 4 : 5, child: _buildSidePanel()),
            ];
            return wide
                ? Row(children: content)
                : Column(children: content);
          },
        ),
      ),
    );
  }

  Widget _buildMapStack() {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, mapState) {
        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapState.center,
                initialZoom: mapState.zoom,
                minZoom: 6,
                maxZoom: 16,
                onMapReady: () {
                  _mapReady = true;
                  if (mapState.isReady) _applyMapState(mapState);
                },
                onPositionChanged: (position, hasGesture) {
                  if (!hasGesture) {
                    return;
                  }
                  context.read<MapBloc>().add(const UserPanDetected());
                  context.read<MapBloc>().add(CenterChanged(position.center));
                  context.read<MapBloc>().add(ZoomChanged(position.zoom));
                },
              ),
              children: [
                TileLayer(
                  tileProvider:
                      _offlineTileManager?.tileProvider ?? NetworkTileProvider(),
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.sngnav.example',
                ),
                BlocBuilder<RoutingBloc, RoutingState>(
                  builder: (context, routingState) {
                    if (!mapState.isLayerVisible(MapLayerType.route) ||
                        !routingState.hasRoute ||
                        routingState.route == null) {
                      return const SizedBox.shrink();
                    }
                    return PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routingState.route!.shape,
                          strokeWidth: 5,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    );
                  },
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _origin,
                      width: 80,
                      height: 40,
                      child: _MarkerBubble(
                        color: Colors.green.shade700,
                        icon: Icons.trip_origin,
                        label: 'Start',
                      ),
                    ),
                    Marker(
                      point: _destination,
                      width: 80,
                      height: 40,
                      child: _MarkerBubble(
                        color: Colors.red.shade700,
                        icon: Icons.place,
                        label: 'Goal',
                      ),
                    ),
                    if (mapState.isLayerVisible(MapLayerType.weather))
                      Marker(
                        point: _toyotaCity,
                        width: 52,
                        height: 52,
                        child: _WeatherMarker(condition: _latestWeather),
                      ),
                  ],
                ),
                const SimpleAttributionWidget(
                  source: Text('© OpenStreetMap contributors'),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: BlocBuilder<NavigationBloc, NavigationState>(
                builder: (context, navState) {
                  return RouteProgressBar(
                    status: switch (navState.status) {
                      NavigationStatus.idle => RouteProgressStatus.idle,
                      NavigationStatus.navigating => RouteProgressStatus.active,
                      NavigationStatus.deviated => RouteProgressStatus.deviated,
                      NavigationStatus.arrived => RouteProgressStatus.arrived,
                    },
                    route: navState.route,
                    currentManeuverIndex: navState.currentManeuverIndex,
                    destinationLabel: navState.destinationLabel,
                    margin: EdgeInsets.zero,
                  );
                },
              ),
            ),
            const SafetyOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildSidePanel() {
    return ColoredBox(
      color: const Color(0xFFF5F7F4),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _PanelCard(
            title: 'What This Shows',
            child: const Text(
              'A single example app composes offline tiles, viewport state, routing, navigation safety, and weather updates into one runnable flow.',
            ),
          ),
          _PanelCard(
            title: 'Voice Diagnostics',
            child: BlocBuilder<VoiceGuidanceBloc, VoiceGuidanceState>(
              builder: (context, voiceState) {
                final availabilityLabel = switch (_voiceBackendAvailable) {
                  true => 'available',
                  false => 'unavailable',
                  null => 'checking...',
                };
                final effectiveStatus = !_voiceGuidanceEnabled
                    ? 'disabled by VOICE_GUIDANCE'
                    : voiceState.status.name;
                final lastPhrase = voiceState.lastHazardMessage ??
                    voiceState.lastSpokenText ??
                    'No announcements yet';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DiagnosticsRow(
                      label: 'Availability',
                      value: availabilityLabel,
                    ),
                    _DiagnosticsRow(
                      label: 'Status',
                      value: effectiveStatus,
                    ),
                    _DiagnosticsRow(
                      label: 'Language',
                      value: _voiceLanguageTag,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Latest message',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastPhrase,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isTestingVoice ? null : _runVoiceTest,
                          icon: _isTestingVoice
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.record_voice_over),
                          label: Text(
                            _isTestingVoice ? 'Testing...' : 'Test Voice',
                          ),
                        ),
                        if (_voiceTestStatus != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              _voiceTestStatus!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          _PanelCard(
            title: 'Map Controls',
            child: BlocBuilder<MapBloc, MapState>(
              builder: (context, mapState) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => context.read<MapBloc>().add(
                            const CameraModeChanged(CameraMode.follow),
                          ),
                      child: Text(
                        mapState.cameraMode == CameraMode.follow
                            ? 'Following'
                            : 'Follow',
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => context.read<MapBloc>().add(
                            FitToBounds(
                              southWest: _southWest(_demoRoute.shape),
                              northEast: _northEast(_demoRoute.shape),
                            ),
                          ),
                      child: const Text('Overview'),
                    ),
                    for (final layer in MapLayerType.values.where(
                      (layer) => layer.isUserToggleable,
                    ))
                      FilterChip(
                        selected: mapState.isLayerVisible(layer),
                        label: Text(layer.name),
                        onSelected: (selected) => context.read<MapBloc>().add(
                              LayerToggled(layer: layer, visible: selected),
                            ),
                      ),
                  ],
                );
              },
            ),
          ),
          _PanelCard(
            title: 'Navigation Demo',
            child: BlocBuilder<NavigationBloc, NavigationState>(
              builder: (context, navState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${navState.status.name}'),
                    if (navState.hasRoute) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Step ${navState.currentManeuverIndex + 1} / ${navState.route!.maneuvers.length}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      navState.currentManeuver?.instruction ?? 'Waiting for route',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (navState.nextManeuver != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Next: ${navState.nextManeuver!.instruction}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: navState.hasRoute ? _advanceNavigation : null,
                          child: const Text('Advance Maneuver'),
                        ),
                        FilledButton.tonal(
                          onPressed: navState.hasRoute || _autoAdvanceEnabled
                              ? _toggleAutoAdvance
                              : null,
                          child: Text(
                            _autoAdvanceEnabled ? 'Stop Auto Demo' : 'Start Auto Demo',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: navState.hasRoute ? _simulateDeviation : null,
                          child: const Text('Simulate Deviation'),
                        ),
                        OutlinedButton(
                          onPressed: navState.hasSafetyAlert
                              ? () => context.read<NavigationBloc>().add(
                                    const SafetyAlertDismissed(),
                                  )
                              : null,
                          child: const Text('Dismiss Alert'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _autoAdvanceStatus,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
          _PanelCard(
            title: 'Voice Guidance',
            child: BlocBuilder<VoiceGuidanceBloc, VoiceGuidanceState>(
              builder: (context, voiceState) {
                final isMuted =
                    !_voiceGuidanceEnabled || voiceState.status == VoiceGuidanceStatus.muted;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enabled by config: $_voiceGuidanceEnabled'),
                    Text('Language: $_voiceLanguageTag'),
                    Text('Status: ${voiceState.status.name}'),
                    const SizedBox(height: 6),
                    Text(
                      voiceState.lastSpokenText ?? 'No announcement yet',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        context.read<VoiceGuidanceBloc>().add(
                              isMuted
                                  ? const VoiceEnabled()
                                  : const VoiceDisabled(),
                            );
                      },
                      icon: Icon(isMuted ? Icons.volume_up : Icons.volume_off),
                      label: Text(isMuted ? 'Enable Voice' : 'Mute Voice'),
                    ),
                  ],
                );
              },
            ),
          ),
          _PanelCard(
            title: 'Weather Feed',
            child: _WeatherSummary(
              condition: _latestWeather,
              tileStatus: _tileStatus,
            ),
          ),
          _PanelCard(
            title: 'Routing State',
            child: BlocBuilder<RoutingBloc, RoutingState>(
              builder: (context, routingState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Engine available: ${routingState.engineAvailable}'),
                    const SizedBox(height: 6),
                    Text('Status: ${routingState.status.name}'),
                    if (routingState.route != null) ...[
                      const SizedBox(height: 6),
                      Text(routingState.route!.summary),
                      Text('Engine: ${routingState.route!.engineInfo.name}'),
                      Text(
                        '${routingState.route!.totalDistanceKm.toStringAsFixed(1)} km • ${routingState.route!.eta.inMinutes} min',
                      ),
                    ],
                    if (routingState.errorMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(routingState.errorMessage!),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _voiceTestPhrase(String languageTag) {
  final normalized = languageTag.toLowerCase();
  if (normalized.startsWith('ja')) {
    return '音声ガイダンスのテストです。次の交差点を右折します。';
  }
  return 'Voice guidance test. Turn right at the next intersection.';
}

class _DiagnosticsRow extends StatelessWidget {
  const _DiagnosticsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _HybridRoutingEngine implements RoutingEngine {
  _HybridRoutingEngine()
      : _primary = ValhallaRoutingEngine.local(),
        _secondary = OsrmRoutingEngine(baseUrl: 'https://router.project-osrm.org'),
        _fallback = _MockRoutingEngine();

  final RoutingEngine _primary;
  final RoutingEngine _secondary;
  final RoutingEngine _fallback;

  @override
  EngineInfo get info => _primary.info;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    try {
      final route = await _primary.calculateRoute(request);
      if (route.hasGeometry) {
        return route;
      }
    } catch (_) {
      // Try secondary engine.
    }

    try {
      final route = await _secondary.calculateRoute(request);
      if (route.hasGeometry) {
        return route;
      }
    } catch (_) {
      // Fall back to deterministic demo route when online engines are unavailable.
    }

    return _fallback.calculateRoute(request);
  }

  @override
  Future<bool> isAvailable() async {
    final primaryAvailable = await _primary.isAvailable();
    if (primaryAvailable) {
      return true;
    }

    final secondaryAvailable = await _secondary.isAvailable();
    if (secondaryAvailable) {
      return true;
    }

    return _fallback.isAvailable();
  }

  @override
  Future<void> dispose() async {
    await _primary.dispose();
    await _secondary.dispose();
    await _fallback.dispose();
  }
}

class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => _demoRoute.engineInfo;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _demoRoute;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> dispose() async {}
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MarkerBubble extends StatelessWidget {
  const _MarkerBubble({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMarker extends StatelessWidget {
  const _WeatherMarker({required this.condition});

  final WeatherCondition? condition;

  @override
  Widget build(BuildContext context) {
    final hazardous = condition?.isHazardous ?? false;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hazardous ? Colors.red.shade700 : Colors.blue.shade700,
        shape: BoxShape.circle,
      ),
      child: Icon(
        hazardous ? Icons.ac_unit : Icons.cloud,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _WeatherSummary extends StatelessWidget {
  const _WeatherSummary({required this.condition, required this.tileStatus});

  final WeatherCondition? condition;
  final String tileStatus;

  @override
  Widget build(BuildContext context) {
    if (condition == null) {
      return Text(tileStatus);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${condition!.precipType.name} ${condition!.intensity.name}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '${condition!.temperatureCelsius.toStringAsFixed(1)} C • visibility ${condition!.visibilityMeters.toStringAsFixed(0)} m • wind ${condition!.windSpeedKmh.toStringAsFixed(0)} km/h',
        ),
        const SizedBox(height: 6),
        Text(condition!.iceRisk ? 'Ice risk detected' : 'No ice risk'),
        const SizedBox(height: 10),
        Text(tileStatus),
      ],
    );
  }
}

LatLng _southWest(List<LatLng> points) {
  final lat = points.map((point) => point.latitude).reduce((a, b) => a < b ? a : b);
  final lon = points.map((point) => point.longitude).reduce((a, b) => a < b ? a : b);
  return LatLng(lat, lon);
}

LatLng _northEast(List<LatLng> points) {
  final lat = points.map((point) => point.latitude).reduce((a, b) => a > b ? a : b);
  final lon = points.map((point) => point.longitude).reduce((a, b) => a > b ? a : b);
  return LatLng(lat, lon);
}
