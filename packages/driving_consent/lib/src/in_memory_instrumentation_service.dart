// NOT FOR PRODUCTION; integrator implements own with encrypted-at-rest persistence per jurisdiction.

/// In-memory instrumentation service — non-persistent test-class
/// implementation of [InstrumentationService].
///
/// Stores events in a map keyed by [ConsentPurpose]. No persistence
/// across restarts; no encryption; no cross-process visibility. Suitable
/// for tests, demos, and offline flows. **Not** suitable for production —
/// integrators implement their own with encrypted-at-rest persistence
/// per jurisdiction.
///
/// Jidoka gate enforcement: every call to [recordEvent] queries the
/// supplied [ConsentService] for the purpose's consent state and throws
/// `StateError` unless the status is `ConsentStatus.granted`. UNKNOWN
/// equals DENIED. The line stops itself.
library;

import 'dart:math';

import 'consent_record.dart';
import 'consent_service.dart';
import 'instrumentation_event.dart';
import 'instrumentation_service.dart';

class InMemoryInstrumentationService implements InstrumentationService {
  final ConsentService _consentService;
  final Map<ConsentPurpose, List<InstrumentationEvent>> _events = {};
  final Map<ConsentPurpose, Duration?> _retention = {};

  /// Default retention if a purpose has no explicit setting.
  static const Duration defaultRetention = Duration(days: 30);

  /// Sentinel returned by `getRetention` when retention is set to null
  /// (indefinite). Callers compare against this constant to detect the
  /// indefinite case. Persistent implementations may surface a richer
  /// API; the in-memory one keeps the surface narrow.
  static const Duration indefiniteRetention =
      Duration(microseconds: 9223372036854775807);

  String? _driverPseudonym;

  InMemoryInstrumentationService(this._consentService);

  @override
  String get driverPseudonym {
    final existing = _driverPseudonym;
    if (existing != null) return existing;
    // Compose a stable per-instance pseudonym from a strong-ish bit mix:
    // microsecond timestamp + a 64-bit random integer, encoded as hex.
    // No `uuid` package dependency. Stable for the life of this
    // instance (the integrator's persistent implementation persists
    // the pseudonym to disk).
    final rng = Random.secure();
    final highBits = rng.nextInt(0xFFFFFFFF);
    final lowBits = rng.nextInt(0xFFFFFFFF);
    final micros = DateTime.now().microsecondsSinceEpoch;
    final pseudonym =
        '${micros.toRadixString(16)}-${highBits.toRadixString(16).padLeft(8, '0')}'
        '${lowBits.toRadixString(16).padLeft(8, '0')}';
    _driverPseudonym = pseudonym;
    return pseudonym;
  }

  @override
  Future<void> recordEvent(
    ConsentPurpose purpose,
    InstrumentationEvent event,
  ) async {
    // Jidoka gate: query consent service. UNKNOWN equals DENIED.
    final consent = await _consentService.getConsent(purpose);
    if (!consent.isEffectivelyGranted) {
      throw StateError(
        'recordEvent refused: consent for ${purpose.name} is '
        '${consent.status.name} (UNKNOWN = DENIED).',
      );
    }
    final bucket = _events.putIfAbsent(purpose, () => []);
    bucket.add(event);
    // Auto-prune opportunistically on every record.
    await _pruneBucket(purpose);
  }

  @override
  Future<List<InstrumentationEvent>> readEvents({
    ConsentPurpose? purpose,
    DateTime? since,
    DateTime? until,
  }) async {
    final result = <InstrumentationEvent>[];
    final purposes = purpose != null ? [purpose] : _events.keys.toList();
    for (final p in purposes) {
      final bucket = _events[p];
      if (bucket == null) continue;
      for (final ev in bucket) {
        if (since != null && ev.timestamp.isBefore(since)) continue;
        if (until != null && ev.timestamp.isAfter(until)) continue;
        result.add(ev);
      }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  @override
  Future<Duration> getRetention(ConsentPurpose purpose) async {
    if (_retention.containsKey(purpose)) {
      final r = _retention[purpose];
      return r ?? indefiniteRetention;
    }
    return defaultRetention;
  }

  @override
  Future<void> setRetention(
    ConsentPurpose purpose,
    Duration? newRetention,
  ) async {
    _retention[purpose] = newRetention;
  }

  @override
  Future<void> deleteAllEvents(ConsentPurpose purpose) async {
    _events.remove(purpose);
  }

  @override
  Future<int> pruneExpired() async {
    var total = 0;
    for (final purpose in _events.keys.toList()) {
      total += await _pruneBucket(purpose);
    }
    return total;
  }

  Future<int> _pruneBucket(ConsentPurpose purpose) async {
    // Detect indefinite retention by inspecting the raw map: explicit
    // null entry means indefinite (set via setRetention with null).
    if (_retention.containsKey(purpose) && _retention[purpose] == null) {
      return 0;
    }
    final retention = await getRetention(purpose);
    final bucket = _events[purpose];
    if (bucket == null || bucket.isEmpty) return 0;
    final now = DateTime.now();
    final cutoff = now.subtract(retention);
    final originalLength = bucket.length;
    bucket.removeWhere((ev) => ev.timestamp.isBefore(cutoff));
    return originalLength - bucket.length;
  }

  @override
  Future<void> dispose() async {
    _events.clear();
    _retention.clear();
    _driverPseudonym = null;
  }
}
