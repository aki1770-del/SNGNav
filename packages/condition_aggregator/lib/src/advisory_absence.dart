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
/// 0.0.8 cannot change the return type without breaking every caller, so it does
/// the next honest thing: it puts the **question** in your hands, and makes
/// answering it cheap. See `AdvisoryAggregateResult.canAssertNoAdvisory`,
/// `AdvisoryAggregateResult.fold` and
/// `AdvisoryAggregateResult.requireCompleteLookup`.
///
/// 0.1.0 is the version where the **compiler** asks the question for you.
library;

/// Why one source could not be read.
///
/// Typed, not prose, so an integrator can render it in the language his driver
/// actually reads. *"The weather service did not answer"* is a sentence a driver
/// in Akita can act on. `SocketException` is not.
///
/// Classification is best-effort. When the aggregator cannot tell, it says
/// [unclassified] rather than guessing — the original error is preserved in
/// `AdvisoryProviderError.cause` and `AdvisoryProviderError.message`.
enum AdvisoryUnavailableReason {
  /// No network path to the source (offline, DNS, routing, TLS).
  networkUnreachable,

  /// The source was reachable but did not answer in time.
  timedOut,

  /// The source answered with something we could not parse.
  unparseable,

  /// The adapter was never brought into service.
  notInitialised,

  /// The adapter failed in a way it did not classify, and we will not guess.
  /// Read `AdvisoryProviderError.message` / `AdvisoryProviderError.cause`.
  unclassified,
}
