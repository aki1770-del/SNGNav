/// Abstract consent service — decouples ConsentBloc from storage.
///
/// The edge developer swaps InMemoryConsentService for SQLiteConsentService
/// without touching the BLoC. Same pattern as LocationProvider, RoutingEngine,
/// WeatherProvider.
///
/// Production: SqliteConsentService (persistent, with audit trail).
/// Fallback: InMemoryConsentService (testing, no persistence).
library;

import '../models/consent_record.dart';

abstract class ConsentService {
  /// Get current consent for a specific purpose.
  ///
  /// Returns [ConsentRecord.unknown] if no consent has been recorded.
  /// Jidoka: unknown = denied. The caller checks [isEffectivelyGranted].
  Future<ConsentRecord> getConsent(ConsentPurpose purpose);

  /// Get all consent records (one per purpose that has been set).
  Future<List<ConsentRecord>> getAllConsents();

  /// Grant consent for a purpose under a jurisdiction.
  ///
  /// Returns the new [ConsentRecord] with [ConsentStatus.granted]
  /// and a fresh [updatedAt] timestamp (audit trail).
  Future<ConsentRecord> grant(
    ConsentPurpose purpose,
    Jurisdiction jurisdiction,
  );

  /// Revoke consent for a purpose.
  ///
  /// Returns the new [ConsentRecord] with [ConsentStatus.denied]
  /// and a fresh [updatedAt] timestamp.
  Future<ConsentRecord> revoke(ConsentPurpose purpose);

  /// Release resources.
  Future<void> dispose();
}
