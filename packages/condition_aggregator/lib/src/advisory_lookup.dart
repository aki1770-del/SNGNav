/// The result of asking "what advisories are in force at this point?" — as a
/// shape that can say **"I could not look."**
///
/// ## Why this exists, and why it arrived in a patch
///
/// Up to and including 0.0.7, the aggregator returned a bare `List<Advisory>`
/// and returned an **empty list** when every provider had failed. An integrator
/// reading that list saw `[]` — exactly what it sees when the sky is clear and
/// no advisory is in force. Those are different facts. One of them is a weather
/// service outage during a blizzard, and it rendered on the driver's screen as
/// silence.
///
/// The adapter was never at fault. `condition_aggregator_jma` refuses to lie: on
/// an unreachable prefecture it throws *"Incomplete border read for prefectures
/// …"*. **The lamp was lit.** The aggregator caught it, flattened it to a
/// `String`, filed it in a `providerErrors` list that **nothing in the tree ever
/// read**, and returned the empty list anyway. The lamp was lit and put in a
/// drawer.
///
/// 0.0.8 answered that with opt-in surfaces — `canAssertNoAdvisory`, `fold`,
/// `requireCompleteLookup`. They work, and they must be **remembered**.
///
/// This type is the version the compiler enforces. It is `sealed`, so a
/// `switch` over it is exhaustive: you cannot reach the advisories without
/// first saying what you will do when we could not look. **A field you can
/// ignore will be ignored.** That is the whole argument.
///
/// ## The asymmetry it encodes
///
/// A hazard **seen** is a hazard **real**, even on partial data — act on it.
/// But "no advisory is in force" is a **claim about completeness**, and you may
/// only make it when the lookup was complete. Positive evidence fires on
/// partial knowledge; negative conclusions require whole knowledge.
///
/// ## Forward compatibility (read this before you adopt it)
///
/// These names and shapes are **identical to the ones in the unpublished
/// 0.1.0**, where `fetchActiveAdvisoriesAtPoint` returns `AdvisoryLookup`
/// directly. Code you write against [AdvisoryAggregator.lookupAtPoint] today
/// compiles unchanged there. This type was shipped in a **patch** precisely so
/// that consumers pinned to a `^0.0.x` caret receive it at all — a `0.1.0`
/// reaches none of them.
library;

import 'advisory.dart';
import 'advisory_absence.dart';

/// What we found when we asked about a point — including the honest case where
/// we could not ask.
///
/// Exhaustive by construction:
///
/// ```dart
/// // oracle:placeholders lookup, show, showNoAdvisory, showFeedDown
/// switch (lookup) {
///   case AdvisoryLookupComplete(:final advisories):
///     advisories.isEmpty ? showNoAdvisory() : advisories.forEach(show);
///   case AdvisoryLookupPartial(:final advisories):
///     advisories.forEach(show);   // act on what was seen; conclude nothing
///   case AdvisoryLookupUnavailable(:final unreachable):
///     showFeedDown(unreachable);  // NOT "clear"
/// }
/// ```
sealed class AdvisoryLookup {
  /// Const base constructor.
  const AdvisoryLookup();

  /// Advisories we actually saw. **Safe to act on** — a hazard seen is a hazard
  /// real, even when the lookup was incomplete.
  ///
  /// This is NOT the whole picture unless [canAssertNoAdvisory] is `true`.
  List<Advisory> get seen => switch (this) {
    AdvisoryLookupComplete(:final advisories) => advisories,
    AdvisoryLookupPartial(:final advisories) => advisories,
    AdvisoryLookupUnavailable() => const [],
  };

  /// `true` only when you may honestly tell a driver **"no advisory is in
  /// force."**
  ///
  /// `false` whenever any source could not be reached — silence from a source
  /// you could not reach is not an all-clear, it is a gap. If this is `false`,
  /// tell her *what you do not know*. Do not tell her nothing, and never tell
  /// her it is clear.
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
  /// The complete set of advisories in force at the queried point.
  final List<Advisory> advisories;

  /// Every source answered with [advisories].
  const AdvisoryLookupComplete(this.advisories);
}

/// Some sources answered; at least one could not be reached.
///
/// [advisories] is what we DID see — act on it. It is **not** the whole
/// picture: you may not conclude "nothing is in force" from an empty list here,
/// because the warning you are missing may be in the source that did not
/// answer.
final class AdvisoryLookupPartial extends AdvisoryLookup {
  /// What the reachable sources reported.
  final List<Advisory> advisories;

  /// The sources that could not be read, and why.
  final List<AdvisorySourceFailure> unreachable;

  /// Some sources answered; [unreachable] did not.
  const AdvisoryLookupPartial({
    required this.advisories,
    required this.unreachable,
  });
}

/// No source could be reached. **We did not look. We know nothing.**
///
/// This is not "clear". Show the driver that the feed is down. She can decide
/// what to do with a gap; she can decide nothing about a silence she was never
/// told about.
final class AdvisoryLookupUnavailable extends AdvisoryLookup {
  /// Every source we tried, and why each failed.
  final List<AdvisorySourceFailure> unreachable;

  /// Nothing could be read; [unreachable] carries why.
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

  /// A typed failure for one [source].
  const AdvisorySourceFailure({
    required this.source,
    required this.reason,
    this.cause,
  });

  @override
  String toString() => 'AdvisorySourceFailure($source, $reason)';
}
