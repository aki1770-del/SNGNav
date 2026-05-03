/// AdvisoryProvider — adapter contract for one publisher source.
///
/// Per-source adapter packages (e.g. `condition_aggregator_nws`,
/// `condition_aggregator_jma`) implement this interface. The interface
/// is intentionally minimal: one geographic-point query returning a
/// snapshot list of currently-active advisories.
///
/// Construction discipline (per condition_aggregator spec §3.3):
/// - adapter constructed at aggregator construction time;
/// - configuration is constructor-injected, not mutated post-construction;
/// - `init()` invoked exactly once before any `fetchActive…` call;
///   raises on init failure;
/// - configuration change → new adapter instance (no in-place mutation).
library;

import 'advisory.dart';

/// Contract every per-source advisory adapter implements.
abstract class AdvisoryProvider {
  /// Names the publisher this adapter speaks for.
  AdvisorySource get source;

  /// One-shot init. Idempotent if reasonable; calling more than once
  /// must not corrupt state. Adapters MAY no-op if no init is needed.
  Future<void> init();

  /// Fetches all active advisories at the given point.
  ///
  /// `latitude` and `longitude` in WGS84 decimal degrees.
  ///
  /// Returns an empty list when no advisories are active for the point;
  /// throws an adapter-specific exception (subtype of [Exception]) on
  /// transport / parse failure. Concrete exception classes are declared
  /// by the adapter package for caller-side discrimination.
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  });
}

/// Thrown when [AdvisoryProvider.init] is asked to bring an adapter into
/// service but the adapter cannot do so (configuration invalid, required
/// dependency unavailable, schema version mismatch, etc.).
///
/// Adapters MAY throw this directly OR throw an adapter-specific subclass
/// for caller-side discrimination. Either way, init failure surfaces the
/// drift before any caller becomes dependent.
class AdvisoryProviderInitException implements Exception {
  /// Human-readable description of the init failure.
  final String message;

  /// Which provider failed to initialize.
  final AdvisorySource source;

  const AdvisoryProviderInitException({
    required this.source,
    required this.message,
  });

  @override
  String toString() =>
      'AdvisoryProviderInitException(source: ${source.name}): $message';
}
