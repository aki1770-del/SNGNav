/// Standalone edge-developer demo app.
///
/// An edge developer assembles the driver's mother's Akita pre-trip winter-safety
/// briefing using ONLY the two published-shaped packages and renders it in
/// THEIR OWN widget ([AkitaBriefingView]) — nothing from the SNGNav app.
///
/// The app opens on the deterministic WHITEOUT demonstration (offline,
/// reproducible). "Try live JMA" wires the real [JmaVisibilityProvider]
/// (via [fetchLiveAkitaVisibility]); if a fresh AMeDAS reading is in range it
/// re-briefs on the live value, otherwise it honestly says nothing fresh was
/// found — it never fabricates a number.
library;

import 'package:flutter/material.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

import 'akita_briefing_view.dart';
import 'akita_data.dart';

void main() => runApp(const EdgeDevAkitaApp());

class EdgeDevAkitaApp extends StatelessWidget {
  const EdgeDevAkitaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akita pre-trip briefing (edge-dev demo)',
      theme: ThemeData(
        // 'Roboto' is Flutter's default; the capture test loads a real TTF
        // under this family so the PNG shows legible text.
        fontFamily: 'Roboto',
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1A3E72),
      ),
      home: const _BriefingScreen(),
    );
  }
}

class _BriefingScreen extends StatefulWidget {
  const _BriefingScreen();

  @override
  State<_BriefingScreen> createState() => _BriefingScreenState();
}

class _BriefingScreenState extends State<_BriefingScreen> {
  late VisibilityObservation _observation = akitaWhiteoutObservation();
  late PretripBriefing _briefing = assembleAkitaBriefing(_observation);
  bool _isLive = false;
  bool _fetching = false;
  String? _note;

  Future<void> _tryLive() async {
    setState(() {
      _fetching = true;
      _note = null;
    });
    final live = await fetchLiveAkitaVisibility();
    if (!mounted) return;
    setState(() {
      _fetching = false;
      if (live == null) {
        _note = 'No fresh measured visibility within range — '
            'showing the demonstration value. (Nothing fabricated.)';
      } else {
        _observation = live;
        _briefing = assembleAkitaBriefing(live);
        _isLive = true;
        _note = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akita pre-trip briefing')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              AkitaBriefingView(
                briefing: _briefing,
                observation: _observation,
                departure: akitaCommute().plannedDeparture,
                isLive: _isLive,
              ),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_note!,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _fetching ? null : _tryLive,
                  icon: const Icon(Icons.satellite_alt),
                  label: Text(_fetching
                      ? 'Fetching live AMeDAS…'
                      : 'Try live JMA (Akita)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
