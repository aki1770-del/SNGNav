/// Typed stops for the case where there is nothing to say.
///
/// The types in this package cannot say "unknown": [HourHazard] has no
/// `unknown` member and both `PretripBriefing.peakHazard` and
/// `AreaConditionRead.areaHazard` are non-nullable. Adding an enum member or
/// making a field nullable would break every consumer's build, so on the 0.5.x
/// line those two values had to be filled with SOMETHING — and what they were
/// filled with was [HourHazard.clear].
///
/// A morning with no forecast at all was therefore handed to the driver as a
/// clear morning. A card that colours itself from the hazard band painted green
/// on a total data blackout.
///
/// We will not fill the gap with a guess. Where the value cannot be honest, we
/// stop and say so, and we say what to do next. Every exception below carries a
/// plain-language [message] with a way forward: it is meant to be read by the
/// developer who catches it, not merely logged.
library;

import 'snow_aware_pretrip_advisor.dart' show HazardEvidenceGap;

/// Base type for "there was nothing to classify, so no value was produced".
///
/// Catch this to handle every absence stop this package can raise:
///
/// ```dart
/// try {
///   final briefing = advisor.brief(...);
///   render(briefing);
/// } on PretripDataAbsentException catch (e) {
///   renderNoDataCard(e.message); // never a green card
/// }
/// ```
abstract class PretripDataAbsentException implements Exception {
  const PretripDataAbsentException(this.message);

  /// Plain language: what happened, why we refuse to guess, what to do next.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown by `SnowAwarePretripAdvisor.brief` when no forecast slot covers the
/// planned departure window, so there is no hazard band to report.
///
/// Before 0.5.2 this case returned a briefing whose `peakHazard` was
/// `HourHazard.clear` — a fabricated all-clear for a morning nobody forecast.
///
/// Two ways forward, both non-breaking for you:
///   * catch this (or [PretripDataAbsentException]) and render your own
///     "no forecast" state; or
///   * call `SnowAwarePretripAdvisor.briefOrNull`, added in 0.5.2, which
///     returns `null` instead of throwing.
///
/// `SnowAwarePretripAdvisor.advise` is unchanged: it still returns `null` here,
/// as it always has.
class PretripForecastCoverageException extends PretripDataAbsentException {
  PretripForecastCoverageException({
    required this.plannedDeparture,
    required this.plannedDuration,
    required this.forecastSlotCount,
  }) : super(
         'No forecast covers the planned trip window '
         '(${plannedDeparture.toIso8601String()} '
         'for ${plannedDuration.inMinutes} minutes). '
         'The forecast handed in has $forecastSlotCount hourly '
         '${forecastSlotCount == 1 ? 'slot' : 'slots'}, none of them '
         'overlapping that window. '
         'There is no hazard band to report, and this advisor will not '
         'invent one: the hazard type has no "unknown" value, so returning '
         'a band here would mean returning "clear" for a morning nobody '
         'forecast. '
         'What to do: catch PretripForecastCoverageException (or its base, '
         'PretripDataAbsentException) and show your own "no forecast" state, '
         'or call briefOrNull() which returns null instead of throwing. '
         'advise() still returns null here, as before. On the 0.6.x line, '
         'HourHazard.unknown makes absence a first-class value.',
       );

  /// The departure the caller asked about.
  final DateTime plannedDeparture;

  /// The trip length the caller asked about.
  final Duration plannedDuration;

  /// How many hourly slots the forecast held (none of which covered the trip).
  final int forecastSlotCount;
}

/// Thrown by `SnowAwarePretripAdvisor.brief` when a forecast DOES cover the
/// trip window but the fields that decide the winter-hazard ladder were never
/// measured — so the affirmative all-clear was not earned.
///
/// This is the per-slot half of the fabricated-clear defect 0.5.2 fixed at the
/// per-window level. 0.5.2 stopped the advisor reporting a clear morning when
/// NO forecast covered the trip. Up to and including 0.5.2 it still reported
/// one when a forecast covered the trip but carried a temperature and nothing
/// else: every hazard test in the ladder is guarded `field != null && ...`, so
/// absent visibility, absent precipitation and absent road-surface state each
/// fell THROUGH to `HourHazard.clear` and the briefing said
/// "No winter hazard signals in your trip window."
///
/// Positive evidence fires on partial knowledge; a negative conclusion requires
/// whole knowledge. A hazard still reports from whatever was measured — this
/// stop fires ONLY where the verdict would have been the affirmative all-clear.
///
/// Three ways forward, all non-breaking for you:
///   * fill the gap — `mergeObservedVisibility` puts a measured
///     [VisibilityObservation] into the departure hour, and
///     `estimatedRoadCondition` accepts your own road-surface estimate; or
///   * call `SnowAwarePretripAdvisor.briefOrNull`, which returns `null` here;
///     or
///   * catch this (or its base [PretripDataAbsentException], which is the same
///     `catch` clause 0.5.2 already asked you to write) and render your own
///     "could not assess" state.
///
/// `advise` is unchanged: it still returns `null` rather than throwing.
///
/// [gapsByHour] names, per forecast hour, exactly which hazard families were
/// left undecided, so the message can say what to measure rather than only
/// that something was missing.
class PretripAssessmentIncompleteException extends PretripDataAbsentException {
  PretripAssessmentIncompleteException({
    required this.plannedDeparture,
    required this.plannedDuration,
    required this.gapsByHour,
    required this.windowFullyCovered,
  }) : super(
         'The forecast covers the planned trip window '
         '(${plannedDeparture.toIso8601String()} '
         'for ${plannedDuration.inMinutes} minutes), but the fields that '
         'decide the winter-hazard ladder were not all measured, so the '
         'affirmative "no winter hazard" claim was not earned. '
         '${windowFullyCovered ? '' : 'Part of the trip window has no '
                   'forecast slot at all. '}'
         '${_describeGaps(gapsByHour)}'
         'This advisor will not report an all-clear it did not measure: a '
         'negative conclusion ("no hazard in your window") requires whole '
         'knowledge, while a hazard still reports from whatever WAS measured. '
         'What to do: fill the gap (mergeObservedVisibility puts a measured '
         'visibility into the departure hour; estimatedRoadCondition takes '
         'your own road-surface estimate), or call briefOrNull() which '
         'returns null instead of throwing, or catch '
         'PretripDataAbsentException and show your own "could not assess" '
         'state. advise() still returns null here. '
         'Use SnowAwarePretripAdvisor.evidenceGaps(slot) to inspect this '
         'per slot and decide your own policy.',
       );

  /// The departure the caller asked about.
  final DateTime plannedDeparture;

  /// The trip length the caller asked about.
  final Duration plannedDuration;

  /// Per forecast hour, the hazard families the ladder could not decide.
  /// Hours whose evidence was complete do not appear.
  final Map<DateTime, Set<HazardEvidenceGap>> gapsByHour;

  /// False when at least one stretch of the trip window had no forecast slot.
  final bool windowFullyCovered;

  static String _describeGaps(Map<DateTime, Set<HazardEvidenceGap>> g) {
    if (g.isEmpty) return '';
    final parts = <String>[];
    for (final e in g.entries) {
      final hh = e.key.hour.toString().padLeft(2, '0');
      final mm = e.key.minute.toString().padLeft(2, '0');
      final names = e.value.map((v) => v.name).toList()..sort();
      parts.add('$hh:$mm (${names.join(', ')})');
    }
    return 'Not measured: ${parts.join('; ')}. ';
  }
}

/// Thrown when `AreaConditionRead.areaHazard` is read while
/// `AreaConditionRead.forecastCovered` is false — i.e. no forecast slot covered
/// the look-ahead window, so the band was never computed.
///
/// Before 0.5.2 that field held `HourHazard.clear` as a "non-asserted
/// placeholder". A placeholder is invisible to a caller who colours a card from
/// the band, so the destination area rendered green when nothing was known
/// about it.
///
/// Two ways forward, both non-breaking for you:
///   * check `forecastCovered` before reading `areaHazard` (this is what
///     `areaConditionChips` has always done, and it is why the chips were
///     honest while a hazard-coloured card was not); or
///   * call `AreaConditionRead.areaHazardOrNull`, added in 0.5.2.
class AreaForecastNotCoveredException extends PretripDataAbsentException {
  AreaForecastNotCoveredException({required this.areaLabel})
    : super(
        'No forecast covers the look-ahead window for "$areaLabel", so no '
        'hazard band was computed and areaHazard has no honest value to '
        'return. It is not clear there; it is unknown there. '
        'What to do: check forecastCovered before reading areaHazard, or '
        'call areaHazardOrNull() which returns null when the window is not '
        'covered. Everything else on this read (the official warning, the '
        'measured visibility, the area label) is still valid and still '
        'available. On the 0.6.x line, HourHazard.unknown makes absence a '
        'first-class value.',
      );

  /// The place the read was about.
  final String areaLabel;
}
