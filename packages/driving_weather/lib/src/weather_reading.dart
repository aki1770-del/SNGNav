/// What a [WeatherProvider] hands you on each poll.
///
/// Not a [WeatherCondition] — a *reading*, which may be an observation, a
/// stale last-known value, or nothing at all.
///
/// ## Why this is a type and not a flag
///
/// Up to and including 0.4.4, a provider whose fetch FAILED silently re-emitted
/// its last [WeatherCondition] with no marker at all. Old data was
/// indistinguishable from fresh data. A `bool isStale` field would have been
/// ignorable — and being ignorable is exactly how that defect shipped.
///
/// A sealed class cannot be ignored: Dart's exhaustive `switch` refuses a
/// consumer who has not written the stale and unavailable branches.
///
/// ```dart
/// provider.conditions.listen((reading) {
///   switch (reading) {
///     case WeatherObserved(:final condition):
///       render(condition);
///     case WeatherStale(:final lastKnown, :final age):
///       renderStale(lastKnown, age); // say "last seen 12 min ago"
///     case WeatherUnavailable():
///       renderNoData();              // say "no weather data"
///   }
/// });
/// ```
library;

import 'weather_condition.dart';

/// A single reading from a [WeatherProvider].
sealed class WeatherReading {
  const WeatherReading();
}

/// The provider fetched successfully on this poll. This is fresh.
final class WeatherObserved extends WeatherReading {
  /// The condition fetched on this poll.
  ///
  /// Its individual fields may still be `null` — the fetch succeeded, but the
  /// source may not measure everything. See [WeatherCondition].
  final WeatherCondition condition;

  const WeatherObserved(this.condition);

  @override
  String toString() => 'WeatherObserved($condition)';
}

/// The provider FAILED to refresh, and is handing back the last value it did
/// manage to observe — explicitly labelled, with its real age.
///
/// This is not a fresh reading. Do not present it as one.
final class WeatherStale extends WeatherReading {
  /// The last condition that was actually observed.
  final WeatherCondition lastKnown;

  /// When [lastKnown] was ACTUALLY true — not when it was re-emitted.
  final DateTime observedAt;

  /// How old [lastKnown] is, as of this emission.
  final Duration age;

  /// Why the refresh failed, when the provider knows.
  final Object? cause;

  const WeatherStale({
    required this.lastKnown,
    required this.observedAt,
    required this.age,
    this.cause,
  });

  @override
  String toString() =>
      'WeatherStale(age=${age.inSeconds}s, observedAt=$observedAt, '
      'cause=$cause, lastKnown=$lastKnown)';
}

/// The provider has no data at all — the fetch failed and there is no previous
/// observation to fall back on.
///
/// Up to 0.4.4 this case emitted NOTHING, which the UI could not distinguish
/// from "not fetched yet". It is now stated.
final class WeatherUnavailable extends WeatherReading {
  /// When the provider first found itself without data.
  final DateTime since;

  /// Why, when the provider knows.
  final Object? cause;

  const WeatherUnavailable({required this.since, this.cause});

  @override
  String toString() => 'WeatherUnavailable(since=$since, cause=$cause)';
}
