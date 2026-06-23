/// The destination-AREA condition section — the FAMILY-THREAD read.
///
/// "What conditions will SHE face in her mother's area if she drives there?" so
/// the driver — a daughter who drives to care for family — decides whether and
/// when to make the trip. It is the companion to the offline daylight clock: a
/// lightweight, DECLARATIVE section, NOT a second full briefing card.
///
/// BINDING BOUNDARIES (each is the point of this surface):
///   * It is a PUBLIC-WEATHER-AT-A-PLACE read. It watches NO person. The
///     subject of every line is the weather at a PLACE — never an arrival, a
///     presence, a person, or a road.
///   * Honest claim ceiling: "conditions / official advisory for the AREA"
///     only — NEVER a road-passability, per-road, or route-segment claim.
///   * NOT a second briefing card: no [SwitchListTile], no verdict banner, no
///     delay / wait / go-no-go. It never deters a needed family-care trip.
///
/// It renders a [AreaConditionRead] already computed upstream (offline,
/// deterministic); it does no fetching and no scoring itself.
library;

import 'package:flutter/material.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

import 'briefing_strings.dart';

class FamilyAreaCard extends StatelessWidget {
  const FamilyAreaCard({
    super.key,
    required this.read,
    required this.messages,
    this.strings = BriefingStrings.en,
  });

  /// The computed area read this section renders.
  final AreaConditionRead read;

  /// The locale table the area chips are written in (resolved from the active
  /// locale upstream, so HER mother in Akita reads Japanese).
  final PretripMessages messages;

  /// The localized structural text (title, place line, honesty note).
  final BriefingStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = areaConditionChips(read, messages);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.destinationAreaTitle,
                style: theme.textTheme.titleMedium),
            Text(
              strings.destinationAreaPlace(read.areaLabel),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // The declarative area lines — same bullet row style as the
            // pre-trip briefing card's reasons.
            for (final chip in chips)
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

            const SizedBox(height: 2),
            Text(
              strings.areaResolutionNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
