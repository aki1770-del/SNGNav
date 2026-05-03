/// NwsAdvisoryProvider — `AdvisoryProvider` adapter for the NOAA / NWS
/// active-winter-alerts feed.
///
/// Wraps `noaa_nws_adapter`'s `NoaaNwsClient.fetchActiveWinterAlerts` and
/// maps each `WinterAlert` to the source-neutral `Advisory` typed event
/// at the boundary. Severity / certainty / urgency / area / effective /
/// expires are CAP-class native at NWS — the mapping is direct.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';

/// Adapter implementing [AdvisoryProvider] against
/// `noaa_nws_adapter`'s [NoaaNwsClient].
class NwsAdvisoryProvider implements AdvisoryProvider {
  final NoaaNwsClient _client;
  final bool _ownsClient;

  /// Constructs an adapter that owns its own [NoaaNwsClient].
  ///
  /// [userAgent] is the NWS-mandated User-Agent header (publisher
  /// rate-limit-accounting + security-contact identifier; see
  /// `noaa_nws_adapter` README).
  NwsAdvisoryProvider({required String userAgent})
      : _client = NoaaNwsClient(userAgent: userAgent),
        _ownsClient = true;

  /// Constructs an adapter against a caller-supplied [NoaaNwsClient]
  /// (test injection).
  NwsAdvisoryProvider.withClient(NoaaNwsClient client)
      : _client = client,
        _ownsClient = false;

  /// Names the publisher this adapter speaks for.
  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;

  /// One-shot init. NWS adapter requires no init beyond construction
  /// (no schema-version negotiation, no auth handshake); init is a
  /// no-op for this adapter and never throws.
  @override
  Future<void> init() async {
    // Intentional no-op. NWS publishes open public-domain data; no
    // schema negotiation, no auth handshake; configuration is fully
    // constructor-injected.
  }

  /// Fetches active winter alerts from NWS at the given point and maps
  /// each to a source-neutral [Advisory] record.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    final alerts = await _client.fetchActiveWinterAlerts(
      latitude: latitude,
      longitude: longitude,
    );
    return alerts.map(mapWinterAlertToAdvisory).toList(growable: false);
  }

  /// Releases the underlying [NoaaNwsClient] HTTP resources if this
  /// adapter constructed it; no-op if a caller-supplied client was
  /// injected via [NwsAdvisoryProvider.withClient].
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Maps one NWS [WinterAlert] to a source-neutral [Advisory].
///
/// Field-level mapping:
/// - `source` ← `AdvisorySource.nwsUnitedStates` (constant)
/// - `eventClass` ← `WinterAlert.event` (verbatim publisher event-class)
/// - `severity` ← `WinterAlert.severity` (CAP-class, direct enum mapping)
/// - `certainty` ← `WinterAlert.certainty` (CAP-class, direct mapping)
/// - `urgency` ← `WinterAlert.urgency` (CAP-class, direct mapping)
/// - `areaDescription` ← `WinterAlert.areaDesc` (verbatim)
/// - `effective` ← `WinterAlert.effective` (nullable, direct)
/// - `expires` ← `WinterAlert.expires` (nullable, direct)
/// - `headline` ← `WinterAlert.headline` (verbatim)
/// - `description` ← `WinterAlert.description` (verbatim)
///
/// Visible at top level for direct-call testing.
Advisory mapWinterAlertToAdvisory(WinterAlert a) {
  return Advisory(
    source: AdvisorySource.nwsUnitedStates,
    eventClass: a.event,
    severity: _mapSeverity(a.severity),
    certainty: _mapCertainty(a.certainty),
    urgency: _mapUrgency(a.urgency),
    areaDescription: a.areaDesc,
    effective: a.effective,
    expires: a.expires,
    headline: a.headline,
    description: a.description,
  );
}

AdvisorySeverity _mapSeverity(AlertSeverity s) {
  switch (s) {
    case AlertSeverity.minor:
      return AdvisorySeverity.minor;
    case AlertSeverity.moderate:
      return AdvisorySeverity.moderate;
    case AlertSeverity.severe:
      return AdvisorySeverity.severe;
    case AlertSeverity.extreme:
      return AdvisorySeverity.extreme;
    case AlertSeverity.unknown:
      return AdvisorySeverity.unknown;
  }
}

AdvisoryCertainty _mapCertainty(AlertCertainty c) {
  switch (c) {
    case AlertCertainty.unlikely:
      return AdvisoryCertainty.unlikely;
    case AlertCertainty.possible:
      return AdvisoryCertainty.possible;
    case AlertCertainty.likely:
      return AdvisoryCertainty.likely;
    case AlertCertainty.observed:
      return AdvisoryCertainty.observed;
    case AlertCertainty.unknown:
      return AdvisoryCertainty.unknown;
  }
}

AdvisoryUrgency _mapUrgency(AlertUrgency u) {
  switch (u) {
    case AlertUrgency.past:
      return AdvisoryUrgency.past;
    case AlertUrgency.future:
      return AdvisoryUrgency.future;
    case AlertUrgency.expected:
      return AdvisoryUrgency.expected;
    case AlertUrgency.immediate:
      return AdvisoryUrgency.immediate;
    case AlertUrgency.unknown:
      return AdvisoryUrgency.unknown;
  }
}
