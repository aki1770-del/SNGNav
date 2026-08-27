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

import '../providers/winter_knowledge.dart';
import '../services/snow_aware_pretrip_advisor.dart';
import 'briefing_strings.dart';

/// The JAF-grounded preparation checklist (DRIVER_VOICES.md, JAF voices):
/// equipment → road information → contingency, in JAF's own hierarchy — now
/// lives in [BriefingStrings.checklist] so it localizes with the rest of the
/// surface.
class PretripBriefingCard extends StatelessWidget {
  const PretripBriefingCard({
    super.key,
    required this.briefing,
    required this.commute,
    required this.forecastIssuedAt,
    required this.tripRequired,
    required this.onTripRequiredChanged,
    required this.sourceCaption,
    this.assessmentIncomplete = false,
    this.winterCard,
    this.strings = BriefingStrings.en,
  });

  /// The localized text the card renders. Defaults to English so existing
  /// callers and tests are unchanged; the running app resolves it from the
  /// ambient locale (see `main.dart`), so HER mother in Akita reads the same
  /// safety verdict in Japanese.
  final BriefingStrings strings;

  /// Optional grounded winter-driving guidance for the surface state expected
  /// on this trip (from [WinterKnowledge.cardFor]). When `null` — no card was
  /// baked for the state, or the surface is benign — the section is omitted
  /// entirely (honest degradation; the typed checklist still stands). The
  /// text was λ-RLM-synthesised offline from an open winter-driving corpus and
  /// is read here by a pure offline lookup.
  final WinterCard? winterCard;

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

  /// True when the advisor REFUSED the affirmative all-clear because the
  /// forecast covering this window never measured what decides it — the
  /// `PretripAssessmentIncompleteException` case of
  /// `SnowAwarePretripAdvisor.brief`.
  ///
  /// This is a DIFFERENT absence from "no forecast at all", and the card
  /// cannot tell them apart on its own: both arrive as
  /// [PretripVerdict.noData], and `allClearEarned` returns `false` for both.
  /// Only the caller's typed catch knows. Rendering
  /// [BriefingStrings.headlineNoData] here would tell a driver
  /// 「出発時間帯の予報がありません」 — *there is no forecast* — on a morning a
  /// forecast DID arrive: a new false sentence produced by absence, in the
  /// headline, where it is read first and announced first.
  ///
  /// Defaults to `false`, so every existing caller renders exactly as before.
  final bool assessmentIncomplete;

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
            Text(strings.beforeYouDrive, style: theme.textTheme.titleMedium),
            Text(
              strings.plannedDeparture(
                _hhmm(commute.plannedDeparture),
                commute.plannedDuration.inMinutes,
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // Verdict banner — the one-glance answer. Severity is encoded
            // visually by colour; for assistive tech (a driver may use a
            // screen reader, or may not perceive colour) we announce the
            // severity word followed by the headline as one live-region
            // utterance, so the safety signal is never colour-only — the
            // briefing must reach a driver who cannot see the screen just as
            // fully as one who can.
            Semantics(
              container: true,
              liveRegion: true,
              label: strings
                  .semanticsLabel(v.severity, v.semanticsHeadline)
                  .trim(),
              child: ExcludeSemantics(
                child: Container(
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
              title: Text(strings.tripRequiredTitle),
              subtitle: Text(strings.tripRequiredSubtitle),
              value: tripRequired,
              onChanged: onTripRequiredChanged,
            ),
            const Divider(),

            Text(strings.beforeYouLeave, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in strings.checklist)
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

            if (winterCard != null) ...[
              const Divider(),
              ..._buildWinterCard(theme, winterCard!),
            ],

            const SizedBox(height: 8),
            Text(
              strings.sourceLine(sourceCaption, _hhmm(forecastIssuedAt)),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  /// Render the grounded winter-driving guidance as a glanceable block:
  /// an "If the road is `<state>`" header, then the action bullets. The card
  /// text is light markdown (`#`, `**`, `•`); we strip the markup rather
  /// than pull in a renderer, keeping the surface offline and dependency-light.
  List<Widget> _buildWinterCard(ThemeData theme, WinterCard card) {
    final actions = _actionLines(card.guidance);
    return [
      Text(strings.winterHeader(card.state),
          style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      for (final line in actions)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.snowing, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      const SizedBox(height: 2),
      Text(
        strings.winterFooter,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    ];
  }

  /// Extract the action bullets from the markdown guidance, stripping markup.
  /// Falls back to the non-empty prose lines if the card has no bullets, so a
  /// differently-shaped card still renders something legible.
  static List<String> _actionLines(String guidance) {
    final lines = guidance
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final bullets = <String>[];
    for (final l in lines) {
      if (l.startsWith('•') || l.startsWith('- ') || l.startsWith('* ')) {
        bullets.add(_stripMarkup(l.substring(1).trim()));
      }
    }
    if (bullets.isNotEmpty) return bullets;
    // No bullets — show the prose lines that aren't headings.
    return lines
        .where((l) => !l.startsWith('#'))
        .map(_stripMarkup)
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static String _stripMarkup(String s) =>
      s.replaceAll('**', '').replaceAll('#', '').trim();

  _VerdictStyle _verdictStyle(ThemeData theme) {
    final rec = briefing.recommendation;
    switch (briefing.verdict) {
      case PretripVerdict.noData:
        // TWO absences arrive here and only one of them may say "there is no
        // forecast". Where a forecast DID arrive and simply measured nothing,
        // the banner carries the severity word itself — a state, not a claim
        // — and the package's own `assessmentIncomplete()` chip says WHAT was
        // not measured. NO new driver-facing sentence is authored for this:
        // both strings already shipped, reviewed, in both languages.
        return _VerdictStyle(
          headline: assessmentIncomplete
              ? strings.severityInformationNeeded
              : strings.headlineNoData,
          // The banner already shows the severity word in that case, so it is
          // announced once, not twice.
          semanticsHeadline: assessmentIncomplete ? '' : null,
          icon: Icons.help_outline,
          background: theme.colorScheme.surfaceContainerHighest,
          foreground: theme.colorScheme.onSurface,
          severity: strings.severityInformationNeeded,
        );
      case PretripVerdict.clear:
        return _VerdictStyle(
          headline: strings.headlineClear,
          icon: Icons.check_circle_outline,
          background: const Color(0xFFE3F2E6),
          foreground: const Color(0xFF1B5E20),
          severity: strings.severityClear,
        );
      case PretripVerdict.caution:
        return _VerdictStyle(
          headline: strings.headlineCaution,
          icon: Icons.info_outline,
          background: const Color(0xFFFFF8E1),
          foreground: const Color(0xFF7A5800),
          severity: strings.severityCaution,
        );
      case PretripVerdict.waitAdvised:
        final strong =
            rec?.strength == RecommendationStrength.advisoryStrong;
        final delay = rec?.suggestedDelay ?? Duration.zero;
        return _VerdictStyle(
          headline:
              strings.headlineWaitAdvised(strings.delayText(delay), strong),
          icon: Icons.schedule,
          background:
              strong ? const Color(0xFFFFE0D6) : const Color(0xFFFFF3E0),
          foreground:
              strong ? const Color(0xFF8B2500) : const Color(0xFF8A4B00),
          severity: strong ? strings.severityHazard : strings.severityCaution,
        );
      case PretripVerdict.hazardPersists:
        return _VerdictStyle(
          headline: strings.headlineHazardPersists,
          icon: Icons.warning_amber_outlined,
          background: const Color(0xFFFFE0D6),
          foreground: const Color(0xFF8B2500),
          severity: strings.severityHazard,
        );
      case PretripVerdict.requiredTripHazard:
        return _VerdictStyle(
          headline: strings.headlineRequiredTripHazard,
          icon: Icons.front_hand_outlined,
          background: const Color(0xFFE3EAF6),
          foreground: const Color(0xFF1A3E72),
          severity: strings.severityHazardYourDecision,
        );
    }
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
    required this.severity,
    String? semanticsHeadline,
  }) : semanticsHeadline = semanticsHeadline ?? headline;

  final String headline;
  final IconData icon;
  final Color background;
  final Color foreground;

  /// A short severity word announced first to assistive tech, so the
  /// colour-encoded severity is never the only carrier of the safety signal.
  ///
  /// It is NOT drawn anywhere on the card — measured 2026-08-28, the banner
  /// paints [headline] alone and this word reaches a driver only through the
  /// semantics label below.
  final String severity;

  /// What follows the severity word in the spoken announcement. Normally the
  /// headline itself; empty where the banner is ALREADY showing the severity
  /// word, so a screen reader does not hear it twice.
  final String semanticsHeadline;
}
