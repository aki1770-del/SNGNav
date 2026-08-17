/// AdvisoryAggregator — multi-source advisory aggregation primitive.
///
/// Fans a single point query out across registered [AdvisoryProvider]s,
/// returning the merged list of active advisories.
///
/// Per-provider failure handling: a per-provider failure is logged into
/// the result's `providerErrors` list and the aggregator continues with
/// surviving providers. The driver receiving advisory information from
/// N-1 providers on transient failure of the Nth is preferable to the
/// driver receiving zero providers because of one fault. The aggregator
/// collects per-provider errors so the integrator can surface staleness
/// honestly (warn-and-continue, not abort).
library;

import 'advisory.dart';
import 'advisory_provider.dart';

/// Result of one aggregator query — the merged advisory list plus any
/// per-provider failures that occurred during the fan-out.
class AdvisoryAggregateResult {
  /// All advisories from providers that responded successfully.
  final List<Advisory> advisories;

  /// One entry per provider that errored; consumed by the integrator
  /// for staleness / honesty surfacing.
  final List<AdvisoryProviderError> providerErrors;

  const AdvisoryAggregateResult({
    required this.advisories,
    required this.providerErrors,
  });
}

/// One per-provider error captured during a fan-out.
class AdvisoryProviderError {
  /// Which provider errored.
  final AdvisorySource source;

  /// Human-readable description of the failure (typically `e.toString()`).
  final String message;

  const AdvisoryProviderError({required this.source, required this.message});

  @override
  String toString() =>
      'AdvisoryProviderError(source: ${source.name}): $message';
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
        errors.add(
          AdvisoryProviderError(source: p.source, message: e.toString()),
        );
      }
    }
    return AdvisoryAggregateResult(
      advisories: advisories,
      providerErrors: errors,
    );
  }
}
