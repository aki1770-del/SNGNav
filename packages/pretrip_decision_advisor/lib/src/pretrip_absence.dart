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
