/// condition_aggregator_nws — NOAA / NWS adapter for the
/// condition_aggregator interface.
///
/// Wraps `noaa_nws_adapter`'s `NoaaNwsClient.fetchActiveWinterAlerts`
/// and maps each `WinterAlert` to the source-neutral `Advisory` typed
/// event at the adapter boundary. Implements `AdvisoryProvider` for use
/// inside an `AdvisoryAggregator`.
///
/// Phase: explore (`publish_to: none` in pubspec.yaml).
///
/// Driver-facing loom: when NWS has issued a winter alert for the
/// driver's current point inside the U.S., the integrator HMI surfaces
/// a typed `Advisory` event with severity / certainty / urgency / area /
/// effective / expires normalized — as the driver's decision substrate,
/// not as raw GeoJSON. The driver always drives.
library;

export 'src/nws_advisory_provider.dart'
    show NwsAdvisoryProvider, mapWinterAlertToAdvisory;
