/// Feed freshness — "the source answered, and its answer has stopped moving."
///
/// ## The gap this closes
///
/// This package already had a vocabulary for **"we could not reach a source"**
/// (`AdvisoryProviderError`, `AdvisoryUnavailableReason`,
/// `AdvisoryLookupUnavailable`). It had none for **"a source answered, and the
/// document it answered with is months old."**
///
/// Those are different failures with the same symptom. An unreachable source
/// throws, and the aggregator records it. A **frozen** source serves HTTP 200,
/// valid JSON, and an empty warning list, indefinitely. Nothing fails, so
/// `providerErrors` stays empty, so `canAssertNoAdvisory` returns `true`, so an
/// integrator renders a measured calm over a dead document.
///
/// `Advisory.effective` / `Advisory.stalenessAt` already carry freshness — but
/// **per advisory**. A frozen feed listing zero warnings produces no `Advisory`
/// at all, so every per-advisory freshness surface is structurally unreachable
/// in exactly the case that matters. Freshness has to be reportable about the
/// **source**, independently of whether the source had anything to say.
///
/// ## Measured, not hypothetical
///
/// 2026-08-16, JMA `bosai/warning/data/warning/` documents, read live:
/// Niigata `150000` last written **2026-05-26T15:45+09:00** (81.8 days, zero
/// warnings), Akita `050000` **2026-05-28T06:11+09:00**, Yamagata `060000`
/// **2026-05-28T09:48+09:00**. Origin `last-modified` confirmed the age at
/// origin — not a cache artifact. The Niigata point rendered as a clear road.
///
/// ## The asymmetry this preserves (no cry-wolf)
///
/// Reporting is **opt-in and positive-only**. A source is treated as stale only
/// when an adapter *measured* it stale and said so. Silence from an adapter
/// that does not report freshness is **not** treated as staleness — it leaves
/// behaviour exactly as it was. This is the same asymmetry the package already
/// encodes for advisories: positive evidence fires on partial knowledge, and a
/// negative conclusion requires whole knowledge. We refuse to manufacture
/// doubt, for the same reason we refuse to manufacture calm.
///
/// **The residual is therefore real and is stated rather than hidden**: an
/// adapter that does not implement [AdvisoryFeedFreshnessReporting] can still
/// serve a frozen document and still satisfy `canAssertNoAdvisory`. See
/// `SEOOC_ASSUMPTIONS.md` (AoU-CA-004).
library;

import 'advisory.dart';

/// One source's measured report that **its own upstream document has stopped
/// being updated**.
///
/// Produced by an adapter that implements [AdvisoryFeedFreshnessReporting].
/// Its presence is a positive measurement, never an inference: an adapter
/// constructs this only when it has read a publisher timestamp and compared it
/// against a threshold it owns.
///
/// The threshold belongs to the adapter, not to this package. A JMA warning
/// document and an NWS CAP feed have different natural cadences, and a single
/// interface-wide constant would be wrong for both.
class AdvisoryFeedStaleness {
  /// Which publisher's document has stopped moving.
  final AdvisorySource source;

  /// The publisher's own timestamp on the document, when it carries one.
  ///
  /// `null` when the source's document has no timestamp field at all but the
  /// adapter established staleness some other way (a monotonic
  /// content-hash/ETag that has not changed across a span it owns, an origin
  /// `last-modified` header, etc.). Absence here is not permission to treat
  /// the report as weaker — the report itself is the measurement.
  final DateTime? documentTime;

  /// How old the document was **at the moment of the read**.
  ///
  /// Carried rather than computed from [documentTime] on demand, because the
  /// aggregate result has no clock and must not acquire one: a getter that
  /// reads `DateTime.now()` would make this type's answers depend on when they
  /// are asked rather than when they were measured.
  final Duration? age;

  /// A short, renderable, source-specific note — e.g. the prefecture code, the
  /// feed path, or the threshold that was exceeded.
  ///
  /// Intended for the integrator's diagnostics and for the sentence the driver
  /// reads. Keep it factual: the driver is owed *what we do not know*, not an
  /// apology.
  final String? detail;

  /// A measured report that [source]'s document has stopped being updated.
  const AdvisoryFeedStaleness({
    required this.source,
    this.documentTime,
    this.age,
    this.detail,
  });

  /// Renderable one-liner: the source, the age, and the detail if present.
  @override
  String toString() {
    final parts = <String>[source.name];
    final a = age;
    if (a != null) {
      parts.add(
        a.inDays >= 1
            ? 'document ${a.inDays} d old'
            : 'document ${a.inHours} h old',
      );
    }
    final t = documentTime;
    if (t != null) parts.add('last written ${t.toIso8601String()}');
    final d = detail;
    if (d != null && d.isNotEmpty) parts.add(d);
    return 'AdvisoryFeedStaleness(${parts.join('; ')})';
  }
}

/// Opt-in capability: an adapter that can say **how current its own source
/// document is**.
///
/// Implemented *in addition to* `AdvisoryProvider`. It is deliberately a
/// separate interface rather than a new method on `AdvisoryProvider`, because
/// adding a required member to that contract would break every adapter package
/// already implementing it — `condition_aggregator_jma`,
/// `condition_aggregator_nws`, `condition_aggregator_met_norway`,
/// `condition_aggregator_digitraffic`, `condition_aggregator_owm_road_risk`.
/// Those adapters compile unchanged and behave exactly as before; an adapter
/// gains the guard on the day it chooses to.
///
/// ```dart
/// // oracle:placeholders MyProvider, Advisory, AdvisorySource, _fetch
/// class MyProvider implements AdvisoryProvider,
///     AdvisoryFeedFreshnessReporting {
///   AdvisoryFeedStaleness? _staleness;
///
///   @override
///   AdvisoryFeedStaleness? get feedStaleness => _staleness;
///
///   @override
///   Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
///     required double latitude,
///     required double longitude,
///   }) async {
///     final doc = await _fetch(latitude, longitude);
///     final age = DateTime.now().difference(doc.publishedAt);
///     _staleness = age > const Duration(hours: 6)
///         ? AdvisoryFeedStaleness(
///             source: source,
///             documentTime: doc.publishedAt,
///             age: age,
///             detail: 'exceeds 6 h publisher cadence',
///           )
///         : null;
///     return doc.advisories;
///   }
/// }
/// ```
abstract interface class AdvisoryFeedFreshnessReporting {
  /// The staleness measured during the **most recent** point query, or `null`
  /// when the most recent document was current.
  ///
  /// Snapshot semantics, matching the rest of this interface: the aggregator
  /// reads this immediately after awaiting the corresponding fetch on the same
  /// adapter instance. An adapter shared across concurrent queries must key
  /// this per query or return `null` rather than return another query's answer
  /// — reporting the wrong source's freshness is worse than reporting none.
  ///
  /// `null` means **"not stale, or not measured"**, and the aggregator treats
  /// it as "no positive evidence of staleness". It never treats it as proof of
  /// freshness.
  AdvisoryFeedStaleness? get feedStaleness;
}
