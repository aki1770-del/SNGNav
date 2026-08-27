/// Typed stops for the case where there is nothing to say.
///
/// ## Why these exist on the 0.6.x line, where [HourHazard.unknown] does too
///
/// 0.6.0 added [HourHazard.unknown] and used it in the one place it fits: a
/// window with NO forecast slot at all. That was the right move and it stands.
///
/// It does not cover the case these types are for. `unknown` is a single flat
/// value on a field; it can say "not assessed" but it cannot say WHICH hazard
/// family went unmeasured, in WHICH hour, or what to measure instead. And it
/// cannot be produced by `SnowAwarePretripAdvisor.hazardOf` without entering
/// the `index`-ordered peak reduce, where — being declared last — it outranks
/// [HourHazard.severe] and would swallow a MEASURED whiteout standing beside
/// an unmeasured hour. (Driven and confirmed, 2026-08-28: under that shape a
/// 40 m whiteout with ice reduced to `verdict: noData, chips: []`.)
///
/// So absence is reported here, BESIDE the ladder, and never on it — at the
/// benign end absence invents safety, at the adverse end it invents danger.
/// [HourHazard] is untouched, `hazardOf` is untouched, and the peak reduce
/// keeps the exact semantics 0.6.0 documented for it.
///
/// ## What went wrong without them
///
/// Every hazard test in `hazardOf` is guarded `field != null && ...`. A slot
/// carrying a temperature and nothing else fails every test, falls through all
/// of them, returns [HourHazard.clear], and the briefing prints "No winter
/// hazard signals in your trip window." A morning nobody measured was handed
/// to the driver as a measured-clear morning.
///
/// We will not fill the gap with a guess. Where the value cannot be honest, we
/// stop and say so, and we say what to do next. Every exception below carries a
/// plain-language [message] with a way forward: it is meant to be read by the
/// developer who catches it, not merely logged.
///
/// ## Three ways to avoid catching, if you would rather branch
///
///  * `SnowAwarePretripAdvisor.allClearEarned` answers the question BEFORE you
///    call `brief`;
///  * `SnowAwarePretripAdvisor.briefOrNull` returns `null` instead of throwing;
///  * `SnowAwarePretripAdvisor.briefOrUnassessed` returns a real
///    [PretripBriefing] whose `peakHazard` is [HourHazard.unknown] — the
///    non-throwing 0.6.x shape, for callers written against 0.6.0.
library;

import 'snow_aware_pretrip_advisor.dart' show HazardEvidenceGap, HourHazard;

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

/// **NOT THROWN on the 0.6.x line.** Retained so a `catch` clause written
/// against 0.5.2–0.5.3 still compiles after upgrading.
///
/// On 0.5.2–0.5.3 `SnowAwarePretripAdvisor.brief` threw this when no forecast
/// slot covered the planned departure window, because [HourHazard] had no
/// member for "not assessed" and `PretripBriefing.peakHazard` is non-nullable,
/// so there was no honest value to return. 0.6.0 added [HourHazard.unknown] and
/// returns it here instead — a value the caller can render beats an exception
/// they must catch, for a case this ordinary. That is 0.6.0's improvement and
/// 0.6.1 keeps it unchanged.
///
/// If you catch this today, nothing will reach the clause. Read
/// `PretripBriefing.peakHazard == HourHazard.unknown` instead, or call
/// `SnowAwarePretripAdvisor.briefOrNull`, which still returns `null` for an
/// uncovered window.
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
         'invent one. '
         'What to do: catch PretripForecastCoverageException (or its base, '
         'PretripDataAbsentException) and show your own "no forecast" state, '
         'or call briefOrNull() which returns null, or call briefOrUnassessed() '
         'which returns a briefing carrying HourHazard.unknown. '
         'advise() still returns null here, as before.',
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
/// This is the per-slot half of the fabricated-clear defect. 0.5.2 stopped the
/// advisor reporting a clear morning when NO forecast covered the trip. It
/// still reported one when a forecast covered the trip but carried a
/// temperature and nothing else: every hazard test in the ladder is guarded
/// `field != null && ...`, so absent visibility, absent precipitation and
/// absent road-surface state each fell THROUGH to [HourHazard.clear] and the
/// briefing said "No winter hazard signals in your trip window."
///
/// Not a corner case: `pretrip_source_met_norway` emits `visibilityMeters:
/// null` and `estimatedRoadCondition: null` on EVERY slot, by its own honesty
/// rule — the compact product carries neither field.
///
/// Positive evidence fires on partial knowledge; a negative conclusion requires
/// whole knowledge. A hazard still reports from whatever was measured — this
/// stop fires ONLY where the verdict would have been the affirmative all-clear.
///
/// Four ways forward, all non-breaking for you:
///   * fill the gap — `mergeObservedVisibility` puts a measured
///     `VisibilityObservation` into the departure hour, and
///     `estimatedRoadCondition` accepts your own road-surface estimate; or
///   * ask first — `SnowAwarePretripAdvisor.allClearEarned` returns a bool and
///     throws nothing; or
///   * call `SnowAwarePretripAdvisor.briefOrNull`, which returns `null` here;
///     or
///   * call `SnowAwarePretripAdvisor.briefOrUnassessed`, which returns a
///     briefing carrying [HourHazard.unknown] instead of stopping.
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
         'your own road-surface estimate), or call allClearEarned() to ask '
         'before you call brief(), or call briefOrNull() which returns null, '
         'or call briefOrUnassessed() which returns a briefing carrying '
         'HourHazard.unknown, or catch PretripDataAbsentException and show '
         'your own "could not assess" state. advise() still returns null '
         'here. Use SnowAwarePretripAdvisor.evidenceGaps(slot) to inspect '
         'this per slot and decide your own policy.',
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
