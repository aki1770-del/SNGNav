/// The vocabulary of absence — "we could not look" as a first-class fact.
///
/// Up to and including 0.0.7 this package could tell you that a source had
/// failed (`AdvisoryAggregateResult.providerErrors`), but nothing forced you to
/// ask. A field you *can* ignore *will* be ignored, and an ignored
/// `providerErrors` list turns a total feed outage into an **empty advisory
/// list** — the exact same value you get when the sky is genuinely clear.
///
/// Those are different facts. One of them is a weather-service outage during a
/// blizzard, rendered on a driver's screen as silence.
///
/// 0.0.8 could not change the return type without breaking every caller, so it
/// did the next honest thing: it put the **question** in the caller's hands and
/// made answering it cheap — `AdvisoryAggregateResult.canAssertNoAdvisory`,
/// `AdvisoryAggregateResult.fold`, and
/// `AdvisoryAggregateResult.requireCompleteLookup`.
///
/// 0.1.0 is the version where the **compiler** asks the question for you: the
/// aggregator now returns the sealed `AdvisoryLookup`, and an exhaustive
/// `switch` refuses a caller who never handled "could not look". Everything
/// 0.0.8 shipped remains here — same names, same semantics — so a 0.0.8 caller
/// migrates by renames, not redesign.
library;

import 'advisory.dart';

/// Why one source could not be read.
///
/// Typed, not prose, so an integrator can render it in the language his driver
/// actually reads. *"The weather service did not answer"* is a sentence a driver
/// in Akita can act on. `SocketException` is not.
///
/// Classification is best-effort. When the aggregator cannot tell, it says
/// [unclassified] rather than guessing — the original error is preserved in
/// `AdvisorySourceFailure.cause` (and, on the 0.0.8-compatibility surface, in
/// `AdvisoryProviderError.cause` / `AdvisoryProviderError.message`).
enum AdvisoryUnavailableReason {
  /// No network path to the source (offline, DNS, routing, TLS).
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

  /// The adapter failed in a way it did not classify, and we will not guess.
  /// Read the preserved original on `cause` (and `message` where present).
  unclassified,
}

/// One per-provider error captured during a fan-out.
///
/// This is the 0.0.8 failure record, retained verbatim so 0.0.8 callers keep
/// compiling. Since 0.1.0 the aggregator reports failures as
/// `AdvisorySourceFailure` inside the sealed `AdvisoryLookup`; this type
/// remains the element of `AdvisoryAggregateResult.providerErrors` and of
/// [AdvisoryLookupIncompleteException.unreachable].
class AdvisoryProviderError {
  /// Which provider errored.
  final AdvisorySource source;

  /// Human-readable description of the failure (typically `e.toString()`).
  ///
  /// For **us**, in logs. A driver cannot act on a `SocketException`; she can
  /// act on [reason].
  final String message;

  /// Why the source could not be read — typed, so an integrator can say it in
  /// the language his driver actually reads.
  ///
  /// Best-effort: [AdvisoryUnavailableReason.unclassified] when the aggregator
  /// cannot tell, rather than a guess.
  final AdvisoryUnavailableReason reason;

  /// The underlying error object, for logs. Never show this to a driver.
  final Object? cause;

  const AdvisoryProviderError({
    required this.source,
    required this.message,
    this.reason = AdvisoryUnavailableReason.unclassified,
    this.cause,
  });

  @override
  String toString() =>
      'AdvisoryProviderError(source: ${source.name}, '
      'reason: ${reason.name}): $message';
}

/// Thrown by `requireCompleteLookup` (on `AdvisoryLookup` and on the
/// 0.0.8-compatibility `AdvisoryAggregateResult`) when at least one advisory
/// source could not be read — so the advisory list in hand may be missing a
/// warning that is really in force.
///
/// This is the opt-in loud stop, for callers who would rather fail than show a
/// driver an all-clear they did not earn. **Nothing throws it unless you ask.**
///
/// The way forward is in [message], and in three sentences:
///
/// * act on what you did see — a hazard seen is a hazard real, even on partial
///   data; just do not claim "nothing is in force";
/// * catch this and tell the driver *which* sources are down ([unreachable]
///   names them, with a typed [AdvisoryProviderError.reason] you can translate);
/// * or switch on the sealed `AdvisoryLookup` the aggregator returns — the
///   compiler then refuses a caller who never handled "could not look".
class AdvisoryLookupIncompleteException implements Exception {
  /// The sources that could not be read, and why.
  final List<AdvisoryProviderError> unreachable;

  /// What happened, why we refuse to guess, and the way forward — in plain
  /// words, safe to log.
  final String message;

  const AdvisoryLookupIncompleteException({
    required this.unreachable,
    required this.message,
  });

  @override
  String toString() => 'AdvisoryLookupIncompleteException: $message';
}
