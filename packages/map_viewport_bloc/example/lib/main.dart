import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';

const _routeSw = LatLng(35.0400, 136.8700);
const _routeNe = LatLng(35.1800, 137.4200);

void main() {
  runApp(const MapViewportExampleApp());
}

class MapViewportExampleApp extends StatelessWidget {
  const MapViewportExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BlocProvider(
        create: (_) => MapBloc()
          ..add(const MapInitialized(
            center: LatLng(35.1709, 136.8815),
            zoom: 15,
          )),
        child: const _MapViewportExampleScreen(),
      ),
    );
  }
}

class _MapViewportExampleScreen extends StatelessWidget {
  const _MapViewportExampleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('map_viewport_bloc example')),
      body: BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'Camera: ${state.cameraMode.name}\n'
                        'Center: ${state.center.latitude.toStringAsFixed(4)}, '
                        '${state.center.longitude.toStringAsFixed(4)}\n'
                        'Zoom: ${state.zoom.toStringAsFixed(1)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: () => context
                          .read<MapBloc>()
                          .add(const CameraModeChanged(CameraMode.follow)),
                      child: const Text('Follow'),
                    ),
                    FilledButton(
                      onPressed: () => context
                          .read<MapBloc>()
                          .add(const UserPanDetected()),
                      child: const Text('Free Look'),
                    ),
                    FilledButton(
                      onPressed: () => context.read<MapBloc>().add(
                            const FitToBounds(
                              southWest: _routeSw,
                              northEast: _routeNe,
                            ),
                          ),
                      child: const Text('Overview'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final layer in MapLayerType.values.where(
                      (layer) => layer.isUserToggleable,
                    ))
                      FilterChip(
                        label: Text('${layer.name} (Z${layer.zIndex})'),
                        selected: state.isLayerVisible(layer),
                        onSelected: (selected) => context.read<MapBloc>().add(
                              LayerToggled(layer: layer, visible: selected),
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Visible layers: '
                  '${state.visibleLayers.map((layer) => layer.name).join(', ')}',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}