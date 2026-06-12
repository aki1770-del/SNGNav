/// The "Before you drive" pre-trip briefing surface.
///
/// DRIVER_VOICES.md (JAF pre-trip voice) puts the load-bearing safety weight
/// on pre-trip preparation, not in-trip alerts. This card is that surface for
/// HER and her family at the kitchen table: a one-glance verdict on the
/// planned departure, plain-language reasons, and the JAF-grounded
/// preparation checklist — equipment first, then prediction, then the
/// whiteout plan.
///
/// The card renders a typed [PretripBriefing] (already computed by
/// [SnowAwarePretripAdvisor]); it does no fetching and no scoring itself, so
/// it stays purely offline-renderable.
library;

import 'package:flutter/material.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

import '../services/snow_aware_pretrip_advisor.dart';

/// JAF-grounded preparation checklist (DRIVER_VOICES.md, JAF voices):
/// equipment → road information → contingency, in JAF's own hierarchy.
const List<String> pretripChecklist = [
  'Snow tires or chains fitted — carry chains and a jack even with snow tires',
  'Check road conditions before leaving (JARTIC / local road information)',
  'Booster cables and a charged phone on board',
  'Warm layers and blanket in the car in case of stranding',
  'Whiteout plan: hazard lamps on, stop at a safe place — do not push on',
];

class PretripBriefingCard extends StatelessWidget {
  const PretripBriefingCard({
    super.key,
    required this.briefing,
    required this.commute,
    required this.forecastIssuedAt,
    required this.tripRequired,
    required this.onTripRequiredChanged,
    required this.sourceCaption,
  });

  /// The computed briefing this card renders.
  final PretripBriefing briefing;

  /// The commute the briefing was computed for (departure time shown).
  final CommuteShape commute;

  /// When the forecast feeding the briefing was issued (honesty line).
  final DateTime forecastIssuedAt;

  /// Whether the driver marked this trip as required (e.g. work shift,
  /// school run with no alternative). Flips the advisor into honesty mode.
  final bool tripRequired;
  final ValueChanged<bool> onTripRequiredChanged;

  /// Honest one-line description of where the forecast came from.
  final String sourceCaption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = _verdictStyle(theme);

    return Card(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Before you drive', style: theme.textTheme.titleMedium),
            Text(
              'Planned departure ${_hhmm(commute.plannedDeparture)} · '
              'trip about ${commute.plannedDuration.inMinutes} min',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // Verdict banner — the one-glance answer.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: v.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(v.icon, color: v.foreground, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      v.headline,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: v.foreground),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Plain-language reasons.
            for (final chip in briefing.chips)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.circle, size: 6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(chip, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This trip is required'),
              subtitle: const Text(
                'When on, no delay is urged — you decide, we help you prepare.',
              ),
              value: tripRequired,
              onChanged: onTripRequiredChanged,
            ),
            const Divider(),

            Text('Before you leave', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in pretripChecklist)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_box_outline_blank, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            Text(
              '$sourceCaption · forecast issued ${_hhmm(forecastIssuedAt)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  _VerdictStyle _verdictStyle(ThemeData theme) {
    final rec = briefing.recommendation;
    switch (briefing.verdict) {
      case PretripVerdict.noData:
        return _VerdictStyle(
          headline: 'No forecast for your departure window — '
              'use your own judgment',
          icon: Icons.help_outline,
          background: theme.colorScheme.surfaceContainerHighest,
          foreground: theme.colorScheme.onSurface,
        );
      case PretripVerdict.clear:
        return const _VerdictStyle(
          headline: 'Conditions look clear for your trip window',
          icon: Icons.check_circle_outline,
          background: Color(0xFFE3F2E6),
          foreground: Color(0xFF1B5E20),
        );
      case PretripVerdict.caution:
        return const _VerdictStyle(
          headline: 'Drive with care — no delay suggested',
          icon: Icons.info_outline,
          background: Color(0xFFFFF8E1),
          foreground: Color(0xFF7A5800),
        );
      case PretripVerdict.waitAdvised:
        final strong =
            rec?.strength == RecommendationStrength.advisoryStrong;
        final delay = rec?.suggestedDelay ?? Duration.zero;
        return _VerdictStyle(
          headline: 'Consider waiting about ${_delayText(delay)}'
              '${strong ? ' — conditions are hazardous now' : ''}',
          icon: Icons.schedule,
          background:
              strong ? const Color(0xFFFFE0D6) : const Color(0xFFFFF3E0),
          foreground:
              strong ? const Color(0xFF8B2500) : const Color(0xFF8A4B00),
        );
      case PretripVerdict.hazardPersists:
        return const _VerdictStyle(
          headline: 'Hazardous through the forecast — '
              'consider whether this trip is needed today',
          icon: Icons.warning_amber_outlined,
          background: Color(0xFFFFE0D6),
          foreground: Color(0xFF8B2500),
        );
      case PretripVerdict.requiredTripHazard:
        return const _VerdictStyle(
          headline: 'Your call — trip is marked required. '
              'Hazard ahead; prepare well',
          icon: Icons.front_hand_outlined,
          background: Color(0xFFE3EAF6),
          foreground: Color(0xFF1A3E72),
        );
    }
  }

  static String _delayText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _VerdictStyle {
  const _VerdictStyle({
    required this.headline,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String headline;
  final IconData icon;
  final Color background;
  final Color foreground;
}
