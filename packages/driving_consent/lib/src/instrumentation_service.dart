/// Abstract instrumentation service — decouples consumers from storage.
///
/// `InstrumentationService` is the boundary at which per-purpose consent
/// gates instrumentation event recording. The integrator swaps the
/// in-memory test implementation for a persistent, encrypted-at-rest
/// implementation per jurisdiction. The package boundary stays the same.
///
/// Jidoka discipline at the gate boundary:
///   * `recordEvent` throws `StateError` if the corresponding consent
///     status is not explicitly granted. UNKNOWN equals DENIED — the
///     line stops itself.
///   * `readEvents` enforces the same gate on the way out: it queries the
///     consent service per purpose and excludes any purpose whose consent
///     is not effectively granted. Revoking consent stops reads, not just
///     writes — UNKNOWN equals DENIED on both boundaries. The service does
///     not trust the caller's gate-check; it performs its own.
///
/// Driver-always-drives invariant: instrumentation is feedback-class,
/// not control-loop-class. Reading or writing events never alters
/// vehicle behavior.
library;

import 'consent_record.dart';
import 'instrumentation_event.dart';

abstract class InstrumentationService {
  /// Record an instrumentation event for a given purpose.
  ///
  /// Throws `StateError` if consent for [purpose] is not explicitly granted
  /// (UNKNOWN equals DENIED). The exception preserves the Jidoka discipline:
  /// silent integrators cannot accidentally harvest data the driver never
  /// authorized.
  Future<void> recordEvent(ConsentPurpose purpose, InstrumentationEvent event);

  /// Read recorded events, optionally filtered by purpose and time window.
  ///
  /// Consent-gated on read: events for a purpose are returned only while
  /// that purpose's consent is effectively granted. Once consent is
  /// revoked (or was never granted — UNKNOWN equals DENIED) the purpose's
  /// events are excluded, even though they remain stored until erased via
  /// [deleteAllEvents]. Revoking consent stops reads, not just writes.
  ///
  /// Results are returned in chronological order (oldest first). When
  /// [purpose] is null, every stored purpose is gated independently and
  /// only the effectively-granted purposes' events are returned. When
  /// [since] or [until] are provided, only events whose timestamp falls
  /// within `[since, until]` (inclusive bounds) are returned.
  Future<List<InstrumentationEvent>> readEvents({
    ConsentPurpose? purpose,
    DateTime? since,
    DateTime? until,
  });

  /// Get the retention duration for [purpose].
  ///
  /// Default: 30 days. A null retention (set via [setRetention]) means the
  /// purpose is held indefinitely; in that case the returned duration is
  /// the largest representable `Duration`. Callers that need to know
  /// whether retention is finite should use [setRetention] with caution
  /// and rely on integrator-provided UI to surface the policy.
  Future<Duration> getRetention(ConsentPurpose purpose);

  /// Set the retention duration for [purpose].
  ///
  /// A null [newRetention] indicates that events for the purpose are held
  /// indefinitely (the integrator's persistent implementation is
  /// responsible for surfacing this in the disclosure UI per jurisdiction).
  Future<void> setRetention(ConsentPurpose purpose, Duration? newRetention);

  /// Delete all events recorded for [purpose].
  ///
  /// This operation is distinct from revoking consent: it removes the
  /// event record while leaving the consent state untouched. Integrators
  /// surface this as the driver's "delete my data" action and surface
  /// consent revocation as a distinct affordance.
  Future<void> deleteAllEvents(ConsentPurpose purpose);

  /// Prune events whose timestamp is older than the per-purpose retention.
  ///
  /// Returns the number of events pruned. The in-memory implementation
  /// also prunes opportunistically on every `recordEvent`; persistent
  /// implementations should schedule this on their own cadence.
  Future<int> pruneExpired();

  /// Stable per-device-install opaque identifier for the driver.
  ///
  /// The pseudonym must be stable across events for the same install and
  /// must not link across installs. Implementations should generate the
  /// pseudonym lazily and persist it to disk in their own storage.
  String get driverPseudonym;

  /// Release resources.
  Future<void> dispose();
}
