/// SafetyOverlay — safety-critical alert layer at Z=2.
///
/// Five non-negotiable rules:
///   1. Always rendered — never removed from the widget tree.
///   2. Always on top — Z=2, above NavigationOverlay (Z=1).
///   3. Passthrough when inactive — [IgnorePointer] lets touch reach map.
///   4. Modal when active — [AbsorbPointer] blocks touch during alert.
///   5. Independent state — not affected by navigation state resets.
///
/// Safety overlay: always top z-layer (ASIL-QM).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/navigation_bloc.dart';
import '../bloc/navigation_event.dart';
import '../bloc/navigation_state.dart';

class SafetyOverlay extends StatelessWidget {
  const SafetyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, state) {
        final hasAlert = state.hasSafetyAlert;

        if (!hasAlert) {
          // Rule 1 + 3: always in tree, passthrough when inactive.
          return const Positioned.fill(
            child: IgnorePointer(child: SizedBox.shrink()),
          );
        }

        // Rule 4: modal when active.
        // GestureDetector on background swallows map taps (modal).
        // The alert card sits on top and remains interactive for dismiss.
        return Positioned.fill(
          child: Stack(
            children: [
              // Modal barrier — swallows all taps on the background.
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {}, // swallow
                  behavior: HitTestBehavior.opaque,
                  child: ColoredBox(
                    color: _backgroundForSeverity(state.alertSeverity),
                  ),
                ),
              ),
              // Alert banner — interactive (dismiss button works).
              Center(
                child: _AlertBanner(
                  message: state.alertMessage!,
                  severity: state.alertSeverity!,
                  dismissible: state.alertDismissible,
                  onDismiss: () => context
                      .read<NavigationBloc>()
                      .add(const SafetyAlertDismissed()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _backgroundForSeverity(AlertSeverity? severity) {
    return switch (severity) {
      AlertSeverity.info => Colors.blue.withAlpha(25),
      AlertSeverity.warning => Colors.amber.withAlpha(38),
      AlertSeverity.critical => const Color(0xFFD32F2F).withAlpha(51),
      null => Colors.transparent,
    };
  }
}

class _AlertBanner extends StatelessWidget {
  final String message;
  final AlertSeverity severity;
  final bool dismissible;
  final VoidCallback onDismiss;

  const _AlertBanner({
    required this.message,
    required this.severity,
    required this.dismissible,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      color: _cardColorForSeverity(severity),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForSeverity(severity),
              size: 48,
              color: _iconColorForSeverity(severity),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            if (dismissible) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onDismiss,
                child: const Text('Dismiss'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconForSeverity(AlertSeverity severity) {
    return switch (severity) {
      AlertSeverity.info => Icons.info_outline,
      AlertSeverity.warning => Icons.warning_amber,
      AlertSeverity.critical => Icons.error,
    };
  }

  static Color _iconColorForSeverity(AlertSeverity severity) {
    return switch (severity) {
      AlertSeverity.info => Colors.blue,
      AlertSeverity.warning => Colors.amber.shade700,
      AlertSeverity.critical => const Color(0xFFD32F2F),
    };
  }

  static Color _cardColorForSeverity(AlertSeverity severity) {
    return switch (severity) {
      AlertSeverity.info => Colors.blue.shade50,
      AlertSeverity.warning => Colors.amber.shade50,
      AlertSeverity.critical => Colors.red.shade50,
    };
  }
}
