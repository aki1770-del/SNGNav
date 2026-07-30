import 'advisory.dart';
import 'advisory_absence.dart';
// Doc-reference only: the coverage-scope clauses below name AdvisoryCoverage and
// AdvisoryProvider, and a doc link that does not resolve is a broken thread for
// the reader who follows it.
import 'advisory_coverage.dart';
import 'advisory_provider.dart';

/// The result of asking "what advisories are in force at this point?"
///
/// ## Why this is a sealed class and not a `List<Advisory>`
///
/// A list cannot say **"I could not look."**
///
/// Up to `condition_aggregator` 0.0.7 the aggregator's result carried a plain
/// advisory list, and when every provider had failed that list was **empty** —
/// exactly what an integrator sees when the sky is clear and no advisory is in
/// force. Those are different facts. One of them is a JMA outage during a
/// blizzard in Akita, and it rendered on the driver's screen as silence.
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
/// So this is sealed. Switch on it — or use [fold] — and the compiler refuses
/// a caller who has not written the "could not look" branches: it stops you,
/// at your desk, before your users are on the road. That guarantee belongs to
/// the switch/fold path. The 0.0.8-named getters ([seen], [unreachable],
/// [isUnavailable]) are the compiler-UN-enforced migration path — [seen]
/// answers `const []` on [AdvisoryLookupUnavailable], the founding silence
/// shape, without making you say anything — so a getter-path caller must keep
/// gating any all-clear on [canAssertNoAdvisory].
///
/// ## The TRUE scope of that guarantee — read this before you rely on it
///
/// The sealed type forces you to handle *"could not look"* when a provider
/// **fails**. That is its whole reach, and it is narrower than it sounds.
///
/// **It does not catch a provider that returns empty without failing.** An
/// adapter shipping a bounded catalog can answer `const <Advisory>[]` for a
/// point outside that catalog, send no request, and throw nothing. The
/// aggregator counts it as asked-and-answered; the result is
/// [AdvisoryLookupComplete]; [canAssertNoAdvisory] is `true` — on a lookup that
/// never looked. This is the **silent-coverage-gap** class, and no exhaustive
/// `switch` can see it, because the type it produces is genuinely `Complete`.
///
/// It is not hypothetical: `condition_aggregator_jma` ships a six-prefecture
/// snow-zone catalog and returns an empty list without throwing for any point
/// outside it (`jma_advisory_provider.dart:169-175`).
///
/// **What closes it today: your own coverage guard.** Before you render an
/// all-clear, ask whether any adapter you registered actually covers the point,
/// using **that adapter's own catalog** — never a box you drew. The working
/// precedent is the integrator app that hit this first: it delegates to
/// `prefectureCodesForPoint`, which `condition_aggregator_jma` exports, so its
/// coverage predicate and the adapter's fetch path consult the same catalog and
/// can never drift apart. A point no registered adapter covers renders as
/// *"no source here covers this point"* — true, and not an all-clear.
///
/// **What closes it in this package today, partially:** an adapter that also
/// implements [AdvisoryCoverage] is handled precisely — declared out-of-coverage
/// means *not asked and not counted*, and a point no provider covers yields
/// [AdvisoryLookupUnavailable]. For adapters that declare nothing, construct the
/// aggregator with `requireDeclaredCoverage: true` to refuse completeness rather
/// than assume it. Both are opt-in; no adapter published today declares coverage.
///
/// **What closes it by default: a later contract change.** Coverage has to
/// become part of the [AdvisoryProvider] contract so the aggregator can tell
/// *asked-and-empty* from *never-asked* without permission. That is breaking,
/// and it is named as a 0.2.0 contract item in the CHANGELOG.
///
/// ## Coming from 0.0.8?
///
/// Everything 0.0.8 gave you keeps its name here: [canAssertNoAdvisory],
/// [seen], [unreachable], [isUnavailable], [fold], and [requireCompleteLookup]
/// all exist on this type with the same semantics. What changed is the
/// guarantee: 0.0.8 let you ask the question; an exhaustive `switch` or [fold]
/// over the sealed type cannot skip it. On the carried getter names the
/// question stays yours to ask — keep the [canAssertNoAdvisory] gate.
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
  /// from a source you could not reach is not an all-clear. It is a gap. And it
  /// is `false` when no source was asked at all: a lookup that consulted
  /// nothing cannot claim completeness.
  ///
  /// If this is `false`, tell her *what you do not know*. Do not tell her nothing,
  /// and never tell her it is clear.
  ///
  /// ## What it does NOT prove
  ///
  /// **`true` means every registered provider RETURNED. It does not mean every
  /// provider LOOKED.** An adapter that answers an empty list without failing —
  /// because the point is outside the catalog it ships — is counted as an
  /// answer, and this getter is `true` on a lookup nobody performed. That is the
  /// silent-coverage-gap class; the sealed type cannot see it, because the
  /// provider never failed. The integrator app that hit this first wrote it
  /// down: *"the provider lied by silence — it counted as asked-and-answered
  /// while never asking."*
  ///
  /// So gate an all-clear on this AND on a coverage check of your own, asked of
  /// **the adapter's own catalog** (`condition_aggregator_jma` exports
  /// `prefectureCodesForPoint` for exactly this) — or register adapters that
  /// implement [AdvisoryCoverage], or construct the aggregator with
  /// `requireDeclaredCoverage: true`. See the class doc on [AdvisoryLookup] for
  /// the full scope, and the CHANGELOG for the 0.2.0 contract item that closes
  /// it by default.
  bool get canAssertNoAdvisory => this is AdvisoryLookupComplete;

  /// Every source we could not reach, and why — typed, never prose, so the
  /// reason survives into whatever language the driver reads.
  List<AdvisorySourceFailure> get failures => switch (this) {
    AdvisoryLookupComplete() => const [],
    AdvisoryLookupPartial(:final unreachable) => unreachable,
    AdvisoryLookupUnavailable(:final unreachable) => unreachable,
  };

  /// The sources we could not read, and why. Same list as [failures], under the
  /// name 0.0.8 shipped (`AdvisoryAggregateResult.unreachable`) — so a 0.0.8
  /// caller migrates without a rename.
  List<AdvisorySourceFailure> get unreachable => failures;

  /// `true` when **no source answered** — we did not look, and we know nothing.
  ///
  /// Same semantics, and the same name, as 0.0.8's
  /// `AdvisoryAggregateResult.isUnavailable`. Prefer switching on the sealed
  /// type; this getter exists so 0.0.8 call sites survive the migration.
  ///
  /// This is not "clear". Show the driver that the feed is down. She can decide
  /// what to do with a gap; she can decide nothing about a silence she was never
  /// told about.
  bool get isUnavailable => this is AdvisoryLookupUnavailable;

  /// Handle every case, or do not compile.
  ///
  /// The three callbacks are `required`, so — like the exhaustive `switch` this
  /// type exists for — `fold` will not let you forget the case where we could
  /// not look. It is 0.0.8's `AdvisoryAggregateResult.fold`, carried forward
  /// with the same shape (the failure lists are now typed
  /// [AdvisorySourceFailure]).
  ///
  /// ```dart
  /// // oracle:placeholders r
  /// final banner = r.fold(
  ///   complete: (a) => a.isEmpty ? '警報なし' : a.first.headline,
  ///   partial: (seen, down) => seen.isEmpty
  ///       ? '一部の気象情報を取得できません'   // NOT "no advisory"
  ///       : seen.first.headline,
  ///   unavailable: (down) => '気象情報を取得できません',  // NOT "clear"
  /// );
  /// ```
  ///
  /// * [complete] — every source answered. An empty list here genuinely means
  ///   *no advisory in force*. This is the only shape in which that is true.
  /// * [partial] — act on what was seen; you may **not** conclude "nothing is in
  ///   force", because the warning you are missing may be in the source that did
  ///   not answer.
  /// * [unavailable] — we did not look. Not clear.
  T fold<T>({
    required T Function(List<Advisory> advisories) complete,
    required T Function(
      List<Advisory> seen,
      List<AdvisorySourceFailure> unreachable,
    )
    partial,
    required T Function(List<AdvisorySourceFailure> unreachable) unavailable,
  }) => switch (this) {
    AdvisoryLookupComplete(:final advisories) => complete(advisories),
    AdvisoryLookupPartial(:final advisories, :final unreachable) => partial(
      advisories,
      unreachable,
    ),
    AdvisoryLookupUnavailable(:final unreachable) => unavailable(unreachable),
  };

  /// The loud stop, opt-in: throws [AdvisoryLookupIncompleteException] unless
  /// every source answered.
  ///
  /// Call this before any code path that would tell a driver the road is clear.
  /// Nothing throws it unless you ask. Same name, same contract as 0.0.8's
  /// `AdvisoryAggregateResult.requireCompleteLookup` — the exception still
  /// carries its unreachable sources as [AdvisoryProviderError] values, so a
  /// 0.0.8 `catch` block keeps working unchanged.
  ///
  /// A stop with no restart is a wall, not a loom, so the exception says what
  /// broke, why we refuse to guess, and the way forward.
  void requireCompleteLookup() {
    switch (this) {
      case AdvisoryLookupComplete():
        return;
      case AdvisoryLookupPartial(:final unreachable):
      case AdvisoryLookupUnavailable(:final unreachable):
        final errors = [
          for (final f in unreachable)
            AdvisoryProviderError(
              source: f.source,
              message: f.cause?.toString() ?? f.reason.name,
              reason: f.reason,
              cause: f.cause,
            ),
        ];
        final down = errors
            .map((e) => '${e.source.name} (${e.reason.name})')
            .join(', ');
        throw AdvisoryLookupIncompleteException(
          unreachable: errors,
          message: errors.isEmpty
              ? 'No advisory source was asked, so the empty advisory list is '
                    'not an all-clear — it is an absence of any lookup. We '
                    'will not guess. Forward: register at least one '
                    'AdvisoryProvider, or handle this and tell the driver the '
                    'advisory feed is unavailable rather than clear.'
              : 'Could not read $down, so the advisory list may be missing a '
                    'warning that is really in force. We will not report an '
                    'all-clear we did not earn. Forward: act on the advisories '
                    'you did get (a hazard seen is a hazard real), tell the '
                    'driver which sources are down instead of telling her it '
                    'is clear, or switch on the sealed AdvisoryLookup so the '
                    'compiler asks this question for you.',
        );
    }
  }
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
  @override
  final List<AdvisorySourceFailure> unreachable;

  const AdvisoryLookupPartial({
    required this.advisories,
    required this.unreachable,
  });
}

/// No source could be reached — or no source was asked at all. **We did not
/// look. We know nothing.**
///
/// This is not "clear". Show the driver that the feed is down. She can decide
/// what to do with a gap; she cannot decide anything about a silence she was
/// never told about.
final class AdvisoryLookupUnavailable extends AdvisoryLookup {
  @override
  final List<AdvisorySourceFailure> unreachable;

  const AdvisoryLookupUnavailable(this.unreachable);
}

/// Why one source could not be read.
///
/// The reason is an **enum, not a string** ([AdvisoryUnavailableReason], the
/// same vocabulary 0.0.8 shipped), so an integrator can render it in the
/// language his driver actually reads. A stack trace is for us. She needs a
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
