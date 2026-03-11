/// Abstract consent service — decouples consumers from storage.
///
/// The edge developer swaps InMemoryConsentService for a persistent
/// implementation without touching the consumer. Same pattern as
/// RoutingEngine, WeatherProvider.
///
/// Production: bring your own persistent service (SQLite, Hive, etc.).
/// Testing/offline: [InMemoryConsentService] (no persistence).
library;

import 'consent_record.dart';

abstract class ConsentService {
  /// Get current consent for a specific purpose.
  ///
  /// Returns [ConsentRecord.unknown] if no consent has been recorded.
  /// Jidoka: unknown = denied. The caller checks [ConsentRecord.isEffectivelyGranted].
  Future<ConsentRecord> getConsent(ConsentPurpose purpose);

  /// Get all consent records (one per purpose that has been set).
  Future<List<ConsentRecord>> getAllConsents();

  /// Grant consent for a purpose under a jurisdiction.
  ///
  /// Returns the new [ConsentRecord] with [ConsentStatus.granted]
  /// and a fresh [ConsentRecord.updatedAt] timestamp (audit trail).
  Future<ConsentRecord> grant(
    ConsentPurpose purpose,
    Jurisdiction jurisdiction,
  );

  /// Revoke consent for a purpose.
  ///
  /// Returns the new [ConsentRecord] with [ConsentStatus.denied]
  /// and a fresh [ConsentRecord.updatedAt] timestamp.
  Future<ConsentRecord> revoke(ConsentPurpose purpose);

  /// Release resources.
  Future<void> dispose();
}
