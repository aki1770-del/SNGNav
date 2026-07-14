/// AdvisoryAggregator — multi-source advisory aggregation primitive.
///
/// Fans a single point query out across registered [AdvisoryProvider]s,
/// returning the merged list of active advisories **plus the truth about which
/// sources could not be read**.
///
/// ## Read this before you trust an empty list
///
/// A per-provider failure is recorded in
/// [AdvisoryAggregateResult.providerErrors] and the aggregator continues with
/// the surviving providers. Getting advisories from N−1 providers when the Nth
/// is down beats getting none. **But that is only half of honest.**
///
/// The other half is this: when every provider fails, `advisories` is an
/// **empty list** — the exact same value it holds when the sky is genuinely
/// clear and no advisory is in force. Those are different facts. One of them is
/// a weather-service outage during a blizzard.
///
/// Up to 0.0.7, the only way to tell them apart was to remember to read
/// `providerErrors` — and a field you *can* ignore *will* be ignored. That is
/// precisely how this shipped.
///
/// **So: an empty `advisories` list means "no advisory is in force" ONLY when
/// [AdvisoryAggregateResult.canAssertNoAdvisory] is `true`.** Otherwise it means
/// "we did not manage to look." Never render the second as the first.
///
/// [AdvisoryAggregateResult.fold] handles all three cases in six lines and will
/// not let you forget one. [AdvisoryAggregateResult.requireCompleteLookup] is
/// the loud stop if you would rather fail than show an all-clear you did not
/// earn.
///
/// In 0.1.0 the return type is a sealed `AdvisoryLookup` and the **compiler**
/// refuses a caller who never handled "could not look".
library;

import 'dart:async' show TimeoutException;

import 'advisory.dart';
import 'advisory_absence.dart';
import 'advisory_provider.dart';

/// Result of one aggregator query — the merged advisory list, the per-provider
/// failures, and the one question that keeps you honest:
/// [canAssertNoAdvisory].
///
/// ## The asymmetry (caution-add-only)
///
/// A hazard **seen** is a hazard **real**, even when some source was
/// unreachable — act on [advisories] regardless. But *"no advisory is in
/// force"* is a claim about **completeness**, and you may only make it when the
/// lookup was complete.
///
/// Positive evidence fires on partial knowledge. A negative conclusion requires
/// whole knowledge. That asymmetry is what lets a system be honest without
/// crying wolf.
class AdvisoryAggregateResult {
  /// All advisories from providers that responded successfully.
  ///
  /// **Safe to act on.** Not the whole picture unless [canAssertNoAdvisory].
  ///
  /// An **empty** list here is NOT an all-clear on its own — it is also what you
  /// get when every source was unreachable. Gate any "nothing is in force"
  /// message on [canAssertNoAdvisory].
  final List<Advisory> advisories;

  /// One entry per provider that errored.
  ///
  /// Reading this is optional and therefore easy to skip — which is why
  /// [canAssertNoAdvisory] exists. Prefer it.
  final List<AdvisoryProviderError> providerErrors;

  /// How many sources were asked, when known.
  ///
  /// The aggregator always sets this. It is optional only so that this
  /// constructor stays source-compatible with 0.0.7 callers (test fakes, etc.).
  ///
  /// **If you construct this object yourself, pass it.** When it is `null` we do
  /// not know whether every source answered, so [canAssertNoAdvisory] is `false`
  /// — we will not claim completeness on your behalf.
  final int? sourcesQueried;

  const AdvisoryAggregateResult({
    required this.advisories,
    required this.providerErrors,
    this.sourcesQueried,
  });

  /// `true` only when **every source answered** — the one condition under which
  /// you may honestly tell a driver *"no advisory is in force."*
  ///
  /// It is `false` whenever any source could not be reached, and `false` when no
  /// source was asked at all. Silence from a source you could not reach is not
  /// an all-clear; it is a gap.
  ///
  /// ```dart
  /// final r = await agg.fetchActiveAdvisoriesAtPoint(lat: …, lon: …);
  /// for (final a in r.advisories) show(a);          // always safe
  /// if (r.advisories.isEmpty) {
  ///   if (r.canAssertNoAdvisory) {
  ///     showNoAdvisory();                            // the silence is real
  ///   } else {
  ///     showFeedDown(r.providerErrors);              // we could not look
  ///   }
  /// }
  /// ```
  ///
  /// If this is `false`, tell her *what you do not know*. Do not tell her
  /// nothing, and never tell her it is clear.
  bool get canAssertNoAdvisory {
    if (providerErrors.isNotEmpty) return false;
    final n = sourcesQueried;
    if (n == null) return false; // unknown provenance — we will not claim it
    return n > 0; // zero sources asked is not an all-clear either
  }

  /// The sources we could not read, and why — typed in
  /// [AdvisoryProviderError.reason], so the reason survives into whatever
  /// language the driver reads.
  ///
  /// Same list as [providerErrors]; named as it is in 0.1.0, so the migration is
  /// a rename you can make today.
  List<AdvisoryProviderError> get unreachable => providerErrors;

  /// What we actually saw. Same list as [advisories]; named as it is in 0.1.0.
  List<Advisory> get seen => advisories;

  /// `true` when **no source answered** — we did not look, and we know nothing.
  ///
  /// This is not "clear". Show the driver that the feed is down. She can decide
  /// what to do with a gap; she can decide nothing about a silence she was never
  /// told about.
  bool get isUnavailable {
    final n = sourcesQueried;
    if (n == null) return false; // unknown provenance — cannot say
    return n - providerErrors.length <= 0;
  }

  /// Handle every case, or do not compile.
  ///
  /// The three callbacks are `required`, so — unlike a field you can skip —
  /// `fold` will not let you forget the case where we could not look. It is the
  /// closest 0.0.8 can get to the sealed `AdvisoryLookup` of 0.1.0 without
  /// breaking your build.
  ///
  /// ```dart
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
      List<AdvisoryProviderError> unreachable,
    )
    partial,
    required T Function(List<AdvisoryProviderError> unreachable) unavailable,
  }) {
    if (canAssertNoAdvisory) return complete(advisories);
    if (isUnavailable) return unavailable(providerErrors);
    return partial(advisories, providerErrors);
  }

  /// The loud stop, opt-in: throws [AdvisoryLookupIncompleteException] unless
  /// every source answered.
  ///
  /// Call this before any code path that would tell a driver the road is clear.
  /// Nothing throws it unless you ask — 0.0.7 callers are untouched.
  ///
  /// A stop with no restart is a wall, not a loom, so the exception says what
  /// broke, why we refuse to guess, and the way forward.
  void requireCompleteLookup() {
    if (canAssertNoAdvisory) return;
    final down = providerErrors
        .map((e) => '${e.source.name} (${e.reason.name})')
        .join(', ');
    throw AdvisoryLookupIncompleteException(
      unreachable: providerErrors,
      message: providerErrors.isEmpty
          ? 'No advisory source was asked (sourcesQueried='
                '${sourcesQueried ?? "unknown"}), so the empty advisory list is '
                'not an all-clear — it is an absence of any lookup. We will not '
                'guess. Forward: register at least one AdvisoryProvider, or '
                'handle this and tell the driver the advisory feed is '
                'unavailable rather than clear.'
          : 'Could not read $down, so the advisory list may be missing a '
                'warning that is really in force. We will not report an '
                'all-clear we did not earn. Forward: act on the advisories you '
                'did get (a hazard seen is a hazard real), tell the driver which '
                'sources are down instead of telling her it is clear, or — when '
                'it is available on pub.dev — upgrade to condition_aggregator '
                '0.1.0, where the return type is a sealed AdvisoryLookup and '
                'the compiler asks this question for you.',
    );
  }
}

/// Thrown by [AdvisoryAggregateResult.requireCompleteLookup] when at least one
/// advisory source could not be read — so the advisory list in hand may be
/// missing a warning that is really in force.
///
/// This is the opt-in loud stop, for callers who would rather fail than show a
/// driver an all-clear they did not earn. **Nothing throws it unless you ask**;
/// existing 0.0.7 call sites never see it.
///
/// The way forward is in [message], and in three sentences:
///
/// * act on what you did see — a hazard seen is a hazard real, even on partial
///   data; just do not claim "nothing is in force";
/// * catch this and tell the driver *which* sources are down ([unreachable]
///   names them, with a typed [AdvisoryProviderError.reason] you can translate);
/// * or move to `condition_aggregator` 0.1.0 — when it is available on
///   pub.dev — where the return type is a sealed `AdvisoryLookup` and the
///   compiler refuses a caller who never handled "could not look".
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

/// One per-provider error captured during a fan-out.
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

/// Multi-source aggregator. Holds N providers; init's them all; queries
/// them all on each `fetch…` call.
class AdvisoryAggregator {
  final List<AdvisoryProvider> _providers;
  bool _initialized = false;

  AdvisoryAggregator({required List<AdvisoryProvider> providers})
    : _providers = List<AdvisoryProvider>.unmodifiable(providers);

  /// Read-only view of registered providers.
  List<AdvisoryProvider> get providers => _providers;

  /// True once [init] has completed for every provider.
  bool get isInitialized => _initialized;

  /// Initializes all registered providers. Failure of any one provider
  /// raises [AdvisoryProviderInitException] (adapter's own subclass
  /// allowed); the aggregator does NOT swallow init failures since init
  /// is the canonical surface for surfacing schema-drift / configuration
  /// errors before any caller depends on the broken provider.
  ///
  /// Idempotent: calling twice is a no-op after the first success.
  Future<void> init() async {
    if (_initialized) return;
    for (final p in _providers) {
      await p.init();
    }
    _initialized = true;
  }

  /// Fans the point query out across all registered providers.
  ///
  /// Per-provider transport / parse failures are caught and surfaced via
  /// [AdvisoryAggregateResult.providerErrors]; surviving providers'
  /// advisories appear in [AdvisoryAggregateResult.advisories]. Init
  /// failures are NOT caught here (they fire from [init], which the
  /// caller invokes explicitly).
  ///
  /// **An empty [AdvisoryAggregateResult.advisories] is not an all-clear
  /// unless [AdvisoryAggregateResult.canAssertNoAdvisory] is `true`.** When
  /// every source is down, this method returns an empty advisory list — the
  /// same value as a clear sky. Gate any "no advisory in force" message on
  /// `canAssertNoAdvisory`, or use [AdvisoryAggregateResult.fold], which will
  /// not let you skip the case.
  ///
  /// Throws [StateError] if called before [init].
  Future<AdvisoryAggregateResult> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw StateError(
        'AdvisoryAggregator.fetchActiveAdvisoriesAtPoint called before init()',
      );
    }
    final advisories = <Advisory>[];
    final errors = <AdvisoryProviderError>[];
    for (final p in _providers) {
      try {
        final found = await p.fetchActiveAdvisoriesAtPoint(
          latitude: latitude,
          longitude: longitude,
        );
        advisories.addAll(found);
      } on Object catch (e) {
        // The adapter lit the lamp. Up to 0.0.7 we flattened it to a String and
        // filed it in a list nothing was obliged to read — so a source outage
        // reached the integrator as `[]`, the same value as a clear night. The
        // failure now also carries a TYPED reason, and `sourcesQueried` below
        // lets the caller ask `canAssertNoAdvisory` instead of remembering to
        // check this list.
        errors.add(
          AdvisoryProviderError(
            source: p.source,
            message: e.toString(),
            reason: _classify(e),
            cause: e,
          ),
        );
      }
    }
    return AdvisoryAggregateResult(
      advisories: advisories,
      providerErrors: errors,
      sourcesQueried: _providers.length,
    );
  }

  /// Best-effort classification of an adapter failure. Returns
  /// [AdvisoryUnavailableReason.unclassified] rather than guessing — the raw
  /// error is preserved on [AdvisoryProviderError.cause] either way.
  static AdvisoryUnavailableReason _classify(Object e) {
    if (e is TimeoutException) return AdvisoryUnavailableReason.timedOut;
    if (e is FormatException) return AdvisoryUnavailableReason.unparseable;
    if (e is AdvisoryProviderInitException) {
      return AdvisoryUnavailableReason.notInitialised;
    }
    // dart:io / package:http types are not importable here (pure Dart, and this
    // package must stay web-safe), so the family is matched by type name.
    final name = e.runtimeType.toString();
    if (name.contains('SocketException') ||
        name.contains('HandshakeException') ||
        name.contains('ClientException') ||
        name.contains('HttpException')) {
      return AdvisoryUnavailableReason.networkUnreachable;
    }
    return AdvisoryUnavailableReason.unclassified;
  }
}
