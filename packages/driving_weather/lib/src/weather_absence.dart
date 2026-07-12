/// What a weather provider does when it has nothing to report.
///
/// `WeatherCondition`'s measured fields (temperature, visibility, wind, ice
/// risk) are non-nullable in the 0.4.x line, so the type has no way to say
/// "not measured". Rather than fill those fields with invented numbers, a
/// provider that has no data now STOPS and says why: it throws (or, on a
/// stream, emits) a [WeatherDataUnavailableException].
///
/// A crash you can catch is safer than a `+5 °C, no ice` you cannot see.
library;

/// Why a provider refused to produce a `WeatherCondition`.
enum WeatherAbsenceReason {
  /// The advisory feed answered, and published no advisory for this point.
  ///
  /// "No advisory" means no authority announced anything here. It does not mean
  /// the road is clear, warm, or free of ice — black ice is routine with zero
  /// advisories published.
  noAdvisoryPublished,

  /// The upstream feed could not be reached, or answered with an error.
  ///
  /// The last condition we saw is not a measurement of *now*, so it is not
  /// re-emitted as if it were.
  feedUnreachable,

  /// The feed answered, but the answer did not contain the fields required to
  /// state a condition (e.g. an empty or truncated `hourly` block, or a null
  /// visibility for the current hour).
  ///
  /// The missing values are not defaulted: a missing visibility is not 10 km.
  incompleteResponse,
}

/// Thrown (or emitted as a stream error) when a provider has no data and the
/// 0.4.x `WeatherCondition` type cannot express "unknown".
///
/// Catch it and tell the driver the road could not be assessed. Do not render
/// "conditions normal", and do not substitute a value:
///
/// ```dart
/// provider.conditions.listen(
///   (condition) => showWeather(condition),
///   onError: (Object error) {
///     if (error is WeatherDataUnavailableException) {
///       showUnknownRoadState(error.message); // never "clear"
///     }
///   },
/// );
/// ```
///
/// To handle absence as a *value* rather than an error, move to the 0.5.x line,
/// where every measured field is nullable and the safety verdicts are
/// tri-state.
class WeatherDataUnavailableException implements Exception {
  /// Why no condition could be produced.
  final WeatherAbsenceReason reason;

  /// Latitude the data was requested for, when the provider knows it.
  final double? latitude;

  /// Longitude the data was requested for, when the provider knows it.
  final double? longitude;

  /// Timestamp of the last condition this provider actually observed, if any.
  ///
  /// Present on [WeatherAbsenceReason.feedUnreachable]: it tells you how old
  /// the last real observation is, so you can decide for yourself whether to
  /// keep showing it — clearly marked as old — or to show nothing.
  final DateTime? lastObservedAt;

  /// The underlying error (HTTP failure, parse failure), when there was one.
  final Object? cause;

  const WeatherDataUnavailableException({
    required this.reason,
    this.latitude,
    this.longitude,
    this.lastObservedAt,
    this.cause,
  });

  /// A plain-words explanation: what happened, why we will not guess, and the
  /// way forward.
  String get message {
    final at = (latitude != null && longitude != null)
        ? ' at ($latitude, $longitude)'
        : '';
    switch (reason) {
      case WeatherAbsenceReason.noAdvisoryPublished:
        return 'No road advisory was published$at. That is not a measurement '
            'of the road: it means no authority announced anything here. '
            'Black ice is routine with zero advisories published, so this '
            'provider will not report "clear, +5 °C, no ice" — it has not '
            'observed the temperature, the visibility, the wind or the ice '
            'risk, and WeatherCondition (0.4.x) has no way to say "unknown". '
            'Handle it: catch WeatherDataUnavailableException (or listen with '
            'onError) and tell the driver the road could not be assessed. '
            'To treat absence as a value instead of an error, move to the '
            '0.5.x line, where every measured field is nullable and the safety '
            'verdicts are tri-state.';
      case WeatherAbsenceReason.feedUnreachable:
        final age = lastObservedAt == null
            ? 'There is no previous observation.'
            : 'The last real observation was at '
                  '${lastObservedAt!.toIso8601String()}; it is not a '
                  'measurement of now.';
        return 'The weather feed could not be reached$at'
            '${cause != null ? ' ($cause)' : ''}. $age Earlier releases '
            're-emitted that old condition with no staleness marker, so old '
            'data was indistinguishable from fresh data — that has stopped. '
            'Handle it: catch WeatherDataUnavailableException (or listen with '
            'onError). If you choose to keep showing the last condition, mark '
            'it as old on screen; lastObservedAt tells you its age. '
            'To receive staleness as a typed value instead of an error, move '
            'to the 0.5.x line.';
      case WeatherAbsenceReason.incompleteResponse:
        return 'The weather feed answered$at, but the answer did not contain '
            'the fields needed to state a condition'
            '${cause != null ? ' ($cause)' : ''}. The missing values are not '
            'defaulted: a visibility we were not given is not 10 km, and this '
            'provider will not present one. WeatherCondition (0.4.x) has no '
            'way to say "unknown". Handle it: catch '
            'WeatherDataUnavailableException (or listen with onError) and tell '
            'the driver the road could not be assessed. To treat absence as a '
            'value instead of an error, move to the 0.5.x line, where every '
            'measured field is nullable.';
    }
  }

  @override
  String toString() => 'WeatherDataUnavailableException(${reason.name}): '
      '$message';
}
