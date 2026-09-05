/// SimulatedFleetCaption — the map screen's honesty label for demo fleet data.
///
/// The live-drive map draws vehicle markers ([FleetLayer]) and red hazard
/// rings ([HazardZoneLayer]) from whatever [FleetProvider] the app was built
/// with. In the snow-scene reference app that provider is
/// `SimulatedFleetProvider`, whose reports come from a fixed-seed `Random(42)`
/// walking five invented vehicles along Route 153. Nothing on the map said so.
///
/// A red ring is the strongest thing this screen draws. Unlabelled, it reads
/// as a real road report from real vehicles, and a developer evaluating the
/// quickstart can carry that belief forward into a product she drives behind.
/// This caption states what the data is, at the moment the data is drawn.
///
/// It is the map-screen sibling of `BriefingStrings.simulatedForecastCaption`,
/// which the pre-trip screen has rendered since its first commit. The two
/// screens were authored separately and the disclosure was written per-screen;
/// this closes the half that was never written.
///
/// Render condition mirrors the fleet layers exactly — consent granted AND the
/// fleet bloc listening. When no fleet data is drawn there is nothing to label
/// and the caption takes no space.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/consent_bloc.dart';
import '../bloc/consent_state.dart';
import '../bloc/fleet_bloc.dart';
import '../bloc/fleet_state.dart';
import 'briefing_strings.dart';

/// A small, non-interactive caption disclosing that the fleet markers and
/// hazard rings currently on the map are simulated.
class SimulatedFleetCaption extends StatelessWidget {
  const SimulatedFleetCaption({super.key, this.isSimulated = true});

  /// Whether the fleet data feeding the map is simulated.
  ///
  /// Defaults to `true` — the same UNKNOWN-is-the-conservative-state
  /// rule the consent gate documents. A caller that wires a real fleet
  /// telemetry feed must say so explicitly; a caller that forgets
  /// over-discloses (claims demo data while live), which under-claims reality
  /// rather than over-claiming it. Silence must never read as "this is live".
  final bool isSimulated;

  @override
  Widget build(BuildContext context) {
    if (!isSimulated) return const SizedBox.shrink();

    return BlocBuilder<ConsentBloc, ConsentState>(
      builder: (context, consentState) {
        if (!consentState.isFleetGranted) return const SizedBox.shrink();

        return BlocBuilder<FleetBloc, FleetState>(
          builder: (context, fleetState) {
            if (!fleetState.isListening) return const SizedBox.shrink();

            final strings = BriefingStrings.of(Localizations.localeOf(context));

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.science_outlined,
                    size: 12,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      strings.simulatedFleetCaption,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
