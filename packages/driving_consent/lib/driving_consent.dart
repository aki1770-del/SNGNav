/// Automotive-grade privacy consent with Jidoka semantics.
///
/// Provides a three-state consent gate ([ConsentStatus]) where UNKNOWN is
/// treated as DENIED — the pipeline stops itself until the driver explicitly
/// grants consent.
///
/// Consent is per-purpose ([ConsentPurpose]) and jurisdiction-aware
/// ([Jurisdiction]), supporting GDPR, CCPA, and APPI without
/// jurisdiction-specific code paths.
///
/// ```dart
/// import 'package:driving_consent/driving_consent.dart';
///
/// final service = InMemoryConsentService();
///
/// // Check before sending fleet data — Jidoka gate
/// final consent = await service.getConsent(ConsentPurpose.fleetLocation);
/// if (!consent.isEffectivelyGranted) {
///   // Pipeline stops. No data leaves the device.
///   return;
/// }
///
/// // Driver grants consent explicitly
/// await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
/// ```
library;

export 'src/consent_record.dart';
export 'src/consent_service.dart';
export 'src/in_memory_consent_service.dart';
