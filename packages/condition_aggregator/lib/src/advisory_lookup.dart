import 'advisory.dart';

/// The result of asking "what advisories are in force at this point?"
///
/// ## Why this is a sealed class and not a `List<Advisory>`
///
/// A list cannot say **"I could not look."**
///
/// Up to `condition_aggregator` 0.0.7 this was `List<Advisory>`, and the
/// aggregator returned an **empty list** when every provider had failed. An
/// integrator reading that list saw `[]` — exactly what it sees when the sky is
/// clear and no advisory is in force. Those are different facts. One of them is
/// a JMA outage during a blizzard in Akita, and it rendered on the driver's
/// screen as silence.
///
/// The adapter was not at fault. `condition_aggregator_jma` threw honestly —
/// *"Incomplete border read for prefectures …"*. The lamp was lit. The aggregator
/// caught it, flattened it to a string, filed it in a `providerErrors` list that
/// **nothing in the tree ever read**, and returned the empty list anyway. The
/// lamp was lit and put in a drawer.
///
/// A field you can ignore will be ignored. This package already knew that and
/// wrote it down in `driving_weather`'s `WeatherReading`:
///
/// > *"A `bool isStale` field would have been ignorable — and being ignorable is
/// > exactly how that defect shipped. A sealed class cannot be ignored: Dart's
/// > exhaustive `switch` refuses a consumer who has not written the branches."*
///
/// So this is sealed. You cannot reach the advisories without first saying what
/// you will do when we could not look. The compiler stops you, at your desk,
/// before your users are on the road.
///
/// ## The asymmetry (caution-add-only)
///
/// A hazard **seen** is a hazard **real**, even on partial data — act on it.
/// But "no advisory is in force" is a **claim about completeness**, and you may
/// only make it when the lookup was complete. Use [canAssertNoAdvisory]; do not
/// infer it from an empty list.
///
/// Positive evidence fires on partial knowledge. Negative conclusions require
/// whole knowledge. That asymmetry is what lets a system be honest without
/// crying wolf.
sealed class AdvisoryLookup {
  const AdvisoryLookup();

  /// Advisories we actually saw. **Safe to act on** — a hazard seen is a hazard
  /// real, even when the lookup was incomplete (caution-add-only).
  ///
  /// This is NOT the whole picture unless [canAssertNoAdvisory] is true.
  List<Advisory> get seen => switch (this) {
        AdvisoryLookupComplete(:final advisories) => advisories,
        AdvisoryLookupPartial(:final advisories) => advisories,
        AdvisoryLookupUnavailable() => const [],
      };

  /// `true` only when you may honestly tell a driver **"no advisory is in force."**
  ///
  /// It is `false` whenever any source could not be reached — because silence
  /// from a source you could not reach is not an all-clear. It is a gap.
  ///
  /// If this is `false`, tell her *what you do not know*. Do not tell her nothing,
  /// and never tell her it is clear.
  bool get canAssertNoAdvisory => this is AdvisoryLookupComplete;

  /// Every source we could not reach, and why — typed, never prose, so the
  /// reason survives into whatever language the driver reads.
  List<AdvisorySourceFailure> get failures => switch (this) {
        AdvisoryLookupComplete() => const [],
        AdvisoryLookupPartial(:final unreachable) => unreachable,
        AdvisoryLookupUnavailable(:final unreachable) => unreachable,
      };
}

/// Every source answered. [advisories] is the complete picture for this point.
///
/// An **empty** list here genuinely means *no advisory is in force*. This is the
/// only shape in which that sentence is true.
final class AdvisoryLookupComplete extends AdvisoryLookup {
  final List<Advisory> advisories;

  const AdvisoryLookupComplete(this.advisories);
}

/// Some sources answered; at least one could not be reached.
///
/// [advisories] is what we DID see — act on it. It is **not** the whole picture:
/// you may not conclude "nothing is in force" from an empty list here, because
/// the warning you are missing may be in the source that did not answer.
final class AdvisoryLookupPartial extends AdvisoryLookup {
  final List<Advisory> advisories;
  final List<AdvisorySourceFailure> unreachable;

  const AdvisoryLookupPartial({
    required this.advisories,
    required this.unreachable,
  });
}

/// No source could be reached. **We did not look. We know nothing.**
///
/// This is not "clear". Show the driver that the feed is down. She can decide
/// what to do with a gap; she cannot decide anything about a silence she was
/// never told about.
final class AdvisoryLookupUnavailable extends AdvisoryLookup {
  final List<AdvisorySourceFailure> unreachable;

  const AdvisoryLookupUnavailable(this.unreachable);
}

/// Why one source could not be read.
///
/// The reason is an **enum, not a string**, so an integrator can render it in
/// the language his driver actually reads. A stack trace is for us. She needs a
/// sentence.
class AdvisorySourceFailure {
  /// Which source could not be read.
  final AdvisorySource source;

  /// Why it could not be read. Typed, so it can be translated.
  final AdvisoryUnavailableReason reason;

  /// The underlying error, for logs. Never show this to a driver.
  final Object? cause;

  const AdvisorySourceFailure({
    required this.source,
    required this.reason,
    this.cause,
  });

  @override
  String toString() => 'AdvisorySourceFailure($source, $reason)';
}

/// Why a source could not be read — the vocabulary of absence.
///
/// Typed so the integrator can say it in her language. "The weather service did
/// not answer" is a sentence a driver in Akita can act on. `SocketException` is
/// not.
enum AdvisoryUnavailableReason {
  /// No network path to the source (offline, DNS, routing).
  networkUnreachable,

  /// The source was reachable but did not answer in time.
  timedOut,

  /// The source answered, but refused us (auth, rate limit, bad request).
  refused,

  /// The source answered with something we could not parse.
  unparseable,

  /// The source answered for some of the area but not all of it — a warning may
  /// exist in the part we could not read.
  incompleteAreaCoverage,

  /// The adapter was never brought into service.
  notInitialised,

  /// The adapter failed in a way it did not classify. Prefer any reason above.
  unclassified,
}
