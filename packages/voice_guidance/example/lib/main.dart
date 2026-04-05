import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:voice_guidance/voice_guidance.dart';

final _exampleRoute = RouteResult(
  shape: const [LatLng(35.1709, 136.9066), LatLng(34.9551, 137.1771)],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Depart Sakae Station',
      type: 'depart',
      lengthKm: 40,
      timeSeconds: 2400,
      position: LatLng(35.1709, 136.9066),
    ),
    RouteManeuver(
      index: 1,
      instruction: 'In 500 metres, turn right onto Route 1',
      type: 'turn',
      lengthKm: 20,
      timeSeconds: 1200,
      position: LatLng(35.0800, 137.0500),
    ),
    RouteManeuver(
      index: 2,
      instruction: 'Arrive at Higashiokazaki Station',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: LatLng(34.9551, 137.1771),
    ),
  ],
  totalDistanceKm: 40.0,
  totalTimeSeconds: 2400,
  summary: '40 km, 40 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

void main() {
  runApp(const VoiceGuidanceExampleApp());
}

class VoiceGuidanceExampleApp extends StatelessWidget {
  const VoiceGuidanceExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'voice_guidance example',
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => NavigationBloc()
              ..add(NavigationStarted(route: _exampleRoute)),
          ),
        ],
        child: const _ExampleScreen(),
      ),
    );
  }
}

class _ExampleScreen extends StatefulWidget {
  const _ExampleScreen();

  @override
  State<_ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<_ExampleScreen> {
  late final VoiceGuidanceBloc _voiceBloc;

  @override
  void initState() {
    super.initState();
    // NoOpTtsEngine is silent — safe for all environments (CI, Linux, test).
    // Replace with DefaultTtsEngine() on a real device.
    _voiceBloc = VoiceGuidanceBloc(
      ttsEngine: NoOpTtsEngine(),
      navigationStateStream:
          context.read<NavigationBloc>().stream,
    );
  }

  @override
  void dispose() {
    _voiceBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _voiceBloc,
      child: Scaffold(
        appBar: AppBar(title: const Text('voice_guidance example')),
        body: BlocBuilder<VoiceGuidanceBloc, VoiceGuidanceState>(
          bloc: _voiceBloc,
          builder: (context, voiceState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusCard(voiceState: voiceState),
                  const SizedBox(height: 24),
                  _ControlRow(voiceBloc: _voiceBloc, voiceState: voiceState),
                  const SizedBox(height: 24),
                  const _ManeuverAnnounceSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final VoiceGuidanceState voiceState;

  const _StatusCard({required this.voiceState});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${voiceState.status.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (voiceState.lastSpokenText != null) ...[
              const SizedBox(height: 8),
              Text('Last spoken: "${voiceState.lastSpokenText}"'),
            ],
            if (voiceState.lastManeuverIndex != null) ...[
              const SizedBox(height: 4),
              Text('Last maneuver index: ${voiceState.lastManeuverIndex}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final VoiceGuidanceBloc voiceBloc;
  final VoiceGuidanceState voiceState;

  const _ControlRow({required this.voiceBloc, required this.voiceState});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      children: [
        FilledButton.icon(
          onPressed: voiceState.isMuted
              ? () => voiceBloc.add(const VoiceEnabled())
              : null,
          icon: const Icon(Icons.volume_up),
          label: const Text('Enable'),
        ),
        OutlinedButton.icon(
          onPressed: !voiceState.isMuted
              ? () => voiceBloc.add(const VoiceDisabled())
              : null,
          icon: const Icon(Icons.volume_off),
          label: const Text('Mute'),
        ),
      ],
    );
  }
}

class _ManeuverAnnounceSection extends StatelessWidget {
  const _ManeuverAnnounceSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manual announcements',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => context.read<VoiceGuidanceBloc>().add(
                    const ManeuverAnnounced(
                      text: 'In 300 metres, turn right',
                    ),
                  ),
              child: const Text('Announce maneuver'),
            ),
            FilledButton(
              onPressed: () => context.read<VoiceGuidanceBloc>().add(
                    const HazardAnnounced(
                      message: 'Icy road conditions ahead',
                      severity: AlertSeverity.warning,
                    ),
                  ),
              child: const Text('Announce hazard'),
            ),
          ],
        ),
      ],
    );
  }
}
