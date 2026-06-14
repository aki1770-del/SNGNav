/// The edge developer's OWN minimal briefing UI.
///
/// This is deliberately hand-rolled — it does NOT import the SNGNav app's
/// `PretripBriefingCard`. It takes a typed [PretripBriefing] (already computed
/// by the published advisor) plus the measured [VisibilityObservation] and
/// renders three things, simply and legibly:
///   1. the verdict headline (coloured by severity),
///   2. the plain-language hazard chips, and
///   3. the departure-hour MEASURED-visibility line (the AMeDAS reading).
///
/// On-card text is English only: the bundled DejaVuSans font carries no CJK
/// glyphs, so 気象庁 would render as tofu boxes — the source line names the
/// agency in English.
library;

import 'package:flutter/material.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

class AkitaBriefingView extends StatelessWidget {
  const AkitaBriefingView({
    super.key,
    required this.briefing,
    required this.observation,
    required this.departure,
    required this.isLive,
  });

  /// The computed briefing to render.
  final PretripBriefing briefing;

  /// The measured visibility observation merged into the departure hour.
  final VisibilityObservation observation;

  /// Planned departure (for the measured-visibility line label).
  final DateTime departure;

  /// True when [observation] came from a live AMeDAS fetch; false for the
  /// deterministic demo value (drives the honesty banner).
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg, headline) = _verdict(theme);

    return Card(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Before you drive — Akita",
                style: theme.textTheme.titleLarge),
            Text(
              'Planned departure ${_hhmm(departure)} · winter morning',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),

            // 1. Verdict headline.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                headline,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Plain-language hazard chips.
            for (final chip in briefing.chips)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                      child: Text(chip, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),

            const Divider(height: 24),

            // 3. The departure-hour MEASURED-visibility line.
            Text(
              'Departure-hour visibility MEASURED: '
              '${observation.meters.round()} m at ${observation.stationName} '
              '(${observation.distanceKm.toStringAsFixed(1)} km away)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Data: Japan Meteorological Agency / AMeDAS (open data).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              isLive
                  ? 'LIVE reading from the AMeDAS network near Akita.'
                  : 'Demonstration value — 80 m is the whiteout case. Live '
                      'Akita visibility in June reads clear; this labelled '
                      'value shows the path that lights the severe band.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Maps the typed verdict to a (background, foreground, headline) triple.
  (Color, Color, String) _verdict(ThemeData theme) {
    final rec = briefing.recommendation;
    switch (briefing.verdict) {
      case PretripVerdict.noData:
        return (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurface,
          'No forecast for your departure window — use your own judgment',
        );
      case PretripVerdict.clear:
        return (
          const Color(0xFFE3F2E6),
          const Color(0xFF1B5E20),
          'Conditions look clear for your trip window',
        );
      case PretripVerdict.caution:
        return (
          const Color(0xFFFFF8E1),
          const Color(0xFF7A5800),
          'Drive with care — no delay suggested',
        );
      case PretripVerdict.waitAdvised:
        final strong = rec?.strength == RecommendationStrength.advisoryStrong;
        final delay = rec?.suggestedDelay ?? Duration.zero;
        return (
          strong ? const Color(0xFFFFE0D6) : const Color(0xFFFFF3E0),
          strong ? const Color(0xFF8B2500) : const Color(0xFF8A4B00),
          'Consider waiting about ${_delay(delay)}'
              '${strong ? ' — conditions are hazardous now' : ''}',
        );
      case PretripVerdict.hazardPersists:
        return (
          const Color(0xFFFFE0D6),
          const Color(0xFF8B2500),
          'Hazardous through the forecast — '
              'consider whether this trip is needed today',
        );
      case PretripVerdict.requiredTripHazard:
        return (
          const Color(0xFFE3EAF6),
          const Color(0xFF1A3E72),
          'Your call — trip is marked required. Hazard ahead; prepare well',
        );
    }
  }

  static String _delay(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
