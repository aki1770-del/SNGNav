/// The silent-coverage-gap countermeasure — a provider may declare where it
/// can actually answer.
///
/// ## The gap the sealed type does NOT close
///
/// `AdvisoryLookup` exists so a provider that **fails** cannot be mistaken for a
/// clear sky. It does exactly that, and no more. There is a second way to be
/// silent, and the sealed type is blind to it:
///
/// > A provider that returns an **empty list without failing** — because the
/// > point is outside the area it ships — is counted as *asked and answered*.
/// > It never sent a request. The lookup is `AdvisoryLookupComplete`, and
/// > `canAssertNoAdvisory` is `true`, on a question nobody asked.
///
/// This is not hypothetical. `condition_aggregator_jma` ships a six-prefecture
/// snow-zone catalog and, for a point outside it, returns `const <Advisory>[]`
/// without throwing (`jma_advisory_provider.dart:169-175`) — no request is sent.
/// Its stated fallback is that *"the aggregator's other providers cover points
/// outside the catalog"*, which is false whenever no sibling actually covers the
/// point: for a Tokyo or Osaka point, a JMA+NWS aggregator asks nobody and
/// reports **complete**.
///
/// The integrator app that first hit this wrote the finding down before the
/// package did:
///
/// > *"`canAssertNoAdvisory` cannot catch that: the provider lied by silence —
/// > it counted as asked-and-answered while never asking."*
///
/// ## What this interface does about it
///
/// It is **opt-in and additive**. [AdvisoryProvider] is unchanged; no existing
/// adapter implements this; every existing behaviour is byte-for-byte what it
/// was. An adapter that knows its own coverage MAY also implement
/// [AdvisoryCoverage], and [AdvisoryAggregator] then honours it:
///
/// * a provider that declares **out of coverage** for the point is **not asked**
///   and is **not a failure** — it legitimately has nothing to say there, so it
///   is removed from the completeness denominator rather than counted as an
///   answer;
/// * when **no** provider covers the point, the lookup is
///   `AdvisoryLookupUnavailable` carrying
///   [AdvisoryUnavailableReason.outOfCoverage] — *"no source here covers this
///   point"*, which is a gap and is **not** an all-clear.
///
/// An adapter adopting this needs no new knowledge: `condition_aggregator_jma`
/// already exports `prefectureCodesForPoint`, the very catalog its fetch path
/// consults, so its implementation is the same predicate the adapter already
/// runs internally. That is the point — coverage must be answered by the
/// adapter's own catalog, never by a box the caller draws.
///
/// ## The half this does NOT close, stated plainly
///
/// A provider that neither fails nor declares coverage is still indistinguishable
/// from one that genuinely looked. That is **every adapter published today**.
/// Refusing completeness for undeclared coverage by default would make
/// `AdvisoryLookupComplete` unreachable for every existing consumer — a reversal
/// of the release's central type, not a defensive addition. So it is offered as
/// an opt-in switch instead: `AdvisoryAggregator(..., requireDeclaredCoverage:
/// true)` refuses to call a lookup complete while any consulted provider's
/// coverage is unknown ([AdvisoryUnavailableReason.coverageUndeclared]).
/// Advisories seen are still returned and still safe to act on — caution-add-only.
///
/// Closing it *by default* requires coverage to become part of the
/// [AdvisoryProvider] contract itself, so the aggregator can distinguish
/// *asked-and-empty* from *never-asked* without asking permission. That is a
/// breaking contract change and belongs to a future major line; it is named in
/// the CHANGELOG as a 0.2.0 contract item.
library;

import 'advisory_provider.dart';

/// Optional companion to [AdvisoryProvider]: *"here is where I can answer."*
///
/// Implement this **in addition to** [AdvisoryProvider] when the adapter ships a
/// bounded catalog (a prefecture list, a country, a set of bounding boxes) and
/// would otherwise answer an out-of-area point with an empty list rather than an
/// error.
///
/// ```dart
/// // oracle:placeholders myAdapterCatalogCovers
/// class MyProvider implements AdvisoryProvider, AdvisoryCoverage {
///   @override
///   AdvisorySource get source => AdvisorySource.other;
///
///   // Answered by the adapter's OWN catalog — the same predicate its fetch
///   // path consults — never by a box drawn at the call site.
///   @override
///   bool coversPoint({required double latitude, required double longitude}) =>
///       myAdapterCatalogCovers(latitude, longitude);
///
///   @override
///   Future<void> init() async {}
///
///   @override
///   Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
///     required double latitude,
///     required double longitude,
///   }) async => const [];
/// }
/// ```
///
/// **Answer from the adapter's own catalog**, not from a hand-drawn box. A box
/// wider than the catalog re-creates the exact defect this exists to end: it
/// declares coverage the adapter does not have, and the empty answer becomes a
/// fabricated all-clear again.
///
/// The predicate must be cheap and synchronous — it is consulted before every
/// fetch and must not perform I/O.
abstract interface class AdvisoryCoverage {
  /// `true` when this adapter's own catalog covers the point, so an empty
  /// answer from it would genuinely mean *"nothing in force here"*.
  ///
  /// `false` when the point lies outside what the adapter ships — the
  /// aggregator will not ask, and will not count the silence as an answer.
  bool coversPoint({required double latitude, required double longitude});
}
