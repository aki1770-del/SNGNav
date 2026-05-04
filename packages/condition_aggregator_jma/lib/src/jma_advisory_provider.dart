/// JmaAdvisoryProvider — `AdvisoryProvider` adapter for the JMA
/// disaster-info XML feed.
///
/// **Explore-phase scaffold.** The provider compiles, satisfies the
/// `AdvisoryProvider` interface, and is composable into an
/// `AdvisoryAggregator` alongside `condition_aggregator_nws` today —
/// but [fetchActiveAdvisoriesAtPoint] returns an empty list at every
/// point until the upstream parser integration lands. The shape is
/// locked so consuming packages can wire against the interface today;
/// the mapping graduates once the upstream parser substrate is
/// elected and integrated.
///
/// Construction discipline (per condition_aggregator interface
/// contract):
/// - configuration is constructor-injected;
/// - `init()` is invoked exactly once before any
///   `fetchActiveAdvisoriesAtPoint` call;
/// - configuration change → new adapter instance (no in-place
///   mutation).
library;

import 'package:condition_aggregator/condition_aggregator.dart';

/// Adapter implementing [AdvisoryProvider] against the JMA
/// disaster-info XML feed.
///
/// **TODO (explore-phase → deploy graduation)**: integration with the
/// upstream parser substrate is gated by a separate engagement-shape
/// election. Two paths are on the table per UPA T3 substrate prep:
/// (a) WASM bridge to the existing Rust crate, and
/// (b) Dart-native re-implementation of the codegen pipeline.
/// Until that election lands, this provider is a stub.
class JmaAdvisoryProvider implements AdvisoryProvider {
  /// Endpoint base URL for the JMA disaster-info XML feed.
  ///
  /// Default points at the public JMA XML feed root. Construction-time
  /// injectable to allow integrators to point at a regional cache or a
  /// test fixture server.
  final String endpointBaseUrl;

  /// Whether [init] has been called. Used to enforce the
  /// "init exactly once before fetch" interface contract.
  bool _initialized = false;

  /// Constructs the provider with a configuration captured at
  /// construction time.
  ///
  /// Once the upstream parser integrates, additional construction-time
  /// configuration will land here (e.g. report-family allowlist,
  /// regional code filter). The public surface stays additive.
  JmaAdvisoryProvider({
    this.endpointBaseUrl = 'https://www.data.jma.go.jp/developer/xml/',
  });

  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

  /// One-shot init. JMA's public XML feed is open public-domain (no
  /// auth handshake); init is currently a no-op marker that records
  /// the contract has been honored. Once parser integration lands,
  /// init MAY perform schema-version probe; the contract that init
  /// raises on init-failure stays.
  @override
  Future<void> init() async {
    _initialized = true;
  }

  /// Fetches active JMA advisories at the given point.
  ///
  /// **Explore-phase stub**: returns an empty list at every point
  /// regardless of latitude / longitude. The contract that
  /// [init] is called exactly once before any fetch is enforced; an
  /// uninitialized fetch surfaces an [AdvisoryProviderInitException].
  ///
  /// Once the upstream parser integration lands, this method will:
  ///   1. fetch the JMA disaster-info XML for the point's region;
  ///   2. parse the XML to typed report records via the upstream
  ///      parser binding (engagement-shape election pending);
  ///   3. filter to snow / blizzard / heavy-snow report families
  ///      (VPWW54 / VPCJ51 / VPAW51 / VPFD60 / VPBS50 / etc.);
  ///   4. map each record to a source-neutral [Advisory] via
  ///      [mapJmaForecastToAdvisory].
  ///
  /// Latitude / longitude are accepted in the WGS84 decimal-degree form
  /// per the interface contract; the JMA region resolution lands at
  /// graduation time.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.jmaJapan,
        message:
            'JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint called before '
            'init(); the AdvisoryProvider contract requires init exactly '
            'once before any fetch.',
      );
    }
    // Explore-phase stub: deploy-graduation lands the parser binding
    // + region resolution + report-family filter + advisory mapping.
    return const <Advisory>[];
  }
}
