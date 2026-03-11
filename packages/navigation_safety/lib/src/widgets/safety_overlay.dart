/// Safety overlay - topmost alert layer for advisory navigation safety.
///
/// Five non-negotiable rules:
///   1. Always rendered - never removed from the widget tree.
///   2. Always on top - Z=5, above all other app content.
///   3. Passthrough when inactive - [IgnorePointer] lets touch reach the map.
///   4. Modal when active - [GestureDetector] barrier swallows background taps.
///   5. Independent state - not affected by unrelated navigation resets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/navigation_bloc.dart';
import '../bloc/navigation_event.dart';
import '../bloc/navigation_state.dart';
import '../models/alert_severity.dart';

class SafetyOverlay extends StatelessWidget {
  const SafetyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, state) {
        final hasAlert = state.hasSafetyAlert;

        if (!hasAlert) {
          return const Positioned.fill(
            child: IgnorePointer(child: SizedBox.shrink()),
          );
        }

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                  child: ColoredBox(
                    color: _backgroundForSeverity(state.alertSeverity),
                  ),
                ),
              ),
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
      AlertSeverity.warning => Colors.amber,
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