/// ConsentGate — fleet data opt-in toggle (Jidoka gate).
///
/// `BlocBuilder<ConsentBloc, ConsentState>`:
///   - Fleet granted: green chip 'Fleet: ON' + tap to revoke
///   - Fleet denied/unknown: grey chip 'Fleet: OFF' + tap to grant
///   - Loading: disabled chip with spinner
///   - Error: red chip 'Fleet: ERR'
///
/// Consent is per-purpose and revocable. This widget controls fleetLocation.
/// The driver taps to toggle — explicit, revocable, per-purpose consent.
///
/// Jidoka (自働化): UNKNOWN = DENIED. The pipeline stops itself.
library;

import 'package:driving_consent/driving_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/consent_bloc.dart';
import '../bloc/consent_event.dart';
import '../bloc/consent_state.dart';

class ConsentGate extends StatelessWidget {
  const ConsentGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConsentBloc, ConsentState>(
      builder: (context, state) {
        return switch (state.status) {
          ConsentBlocStatus.idle ||
          ConsentBlocStatus.loading =>
            _buildChip(
              label: 'Fleet: ...',
              color: Colors.grey.shade400,
              icon: Icons.hourglass_empty,
              onTap: null,
            ),
          ConsentBlocStatus.error => _buildChip(
              label: 'Fleet: ERR',
              color: Colors.red.shade600,
              icon: Icons.error_outline,
              onTap: () => context
                  .read<ConsentBloc>()
                  .add(const ConsentLoadRequested()),
            ),
          ConsentBlocStatus.ready => _buildReadyChip(context, state),
        };
      },
    );
  }

  Widget _buildReadyChip(BuildContext context, ConsentState state) {
    final isGranted = state.isFleetGranted;

    return _buildChip(
      label: isGranted ? 'Fleet: ON' : 'Fleet: OFF',
      color: isGranted ? Colors.green.shade600 : Colors.grey.shade500,
      icon: isGranted ? Icons.share_location : Icons.location_disabled,
      onTap: () {
        if (isGranted) {
          context.read<ConsentBloc>().add(
                const ConsentRevokeRequested(
                  purpose: ConsentPurpose.fleetLocation,
                ),
              );
        } else {
          context.read<ConsentBloc>().add(
                const ConsentGrantRequested(
                  purpose: ConsentPurpose.fleetLocation,
                  jurisdiction: Jurisdiction.appi,
                ),
              );
        }
      },
    );
  }

  Widget _buildChip({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
