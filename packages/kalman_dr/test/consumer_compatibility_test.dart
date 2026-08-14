// Stands where a stranger stands.
//
// Every other test in this package holds the provider and asks whether the
// provider is right. This one holds only what a consumer holds — a
// `GeoPosition` — and asks whether the promises the CHANGELOG makes to that
// consumer are true. It exists because 0.5.0 changed the equality contract, and
// a contract nobody tests from the outside is a contract that changes silently.
//
// If `GeoPosition.props` changes again, this file should be the first failure.
import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

/// A codec that predates 0.5.0: it round-trips the seven fields it knows about
/// and has never heard of `source`. This is not a strawman — it is every
/// consumer serializer written against 0.4.x.
GeoPosition legacyRoundTrip(GeoPosition p) => GeoPosition(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      altitude: p.altitude,
      speed: p.speed,
      heading: p.heading,
      timestamp: p.timestamp,
    );

/// The migration the CHANGELOG actually recommends: carry `source` through.
GeoPosition provenanceAwareRoundTrip(GeoPosition p) => GeoPosition(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      altitude: p.altitude,
      speed: p.speed,
      heading: p.heading,
      timestamp: p.timestamp,
      source: p.source,
      extrapolatedFor: p.extrapolatedFor,
    );

void main() {
  final t = DateTime.utc(2026, 8, 14, 12, 0, 0);

  GeoPosition at({PositionSource? source, Duration? extrapolatedFor}) =>
      GeoPosition(
        latitude: 39.7186,
        longitude: 140.1023,
        accuracy: 13.0,
        altitude: 25.0,
        speed: 8.3,
        heading: 271.0,
        timestamp: t,
        source: source ?? PositionSource.unknown,
        extrapolatedFor: extrapolatedFor,
      );

  group('what a 0.4.x consumer still gets unchanged', () {
    test('constructing without source yields unknown, never measured', () {
      // A library must not assert a sensor reading it did not take.
      final p = GeoPosition(
        latitude: 39.7186,
        longitude: 140.1023,
        accuracy: 13.0,
        altitude: 25.0,
        speed: 8.3,
        heading: 271.0,
        timestamp: t,
      );
      expect(p.source, PositionSource.unknown);
      expect(p.isMeasured, isFalse);
      expect(p.isDeadReckoned, isFalse);
      expect(p.containsMeasurement, isFalse);
    });

    test('two consumer-built positions still compare equal', () {
      expect(at(), equals(at()));
      expect(at().hashCode, equals(at().hashCode));
      expect({at(), at()}, hasLength(1));
    });

    test('toString is unchanged for positions a consumer builds', () {
      // The CHANGELOG promises byte-identity only for this case. It does NOT
      // promise it for positions we emit — those now print their provenance.
      expect(at().toString(), equals(at().toString()));
      expect(at().toString(), isNot(contains('deadReckoned')));
      expect(
        at(source: PositionSource.deadReckoned).toString(),
        isNot(equals(at().toString())),
        reason: 'emitted positions print provenance; that difference is the '
            'point, and the CHANGELOG must keep saying so',
      );
    });
  });

  group('the break 0.5.0 took the minor slot to announce', () {
    test('a legacy codec round-trip breaks equality', () {
      final emitted = at(
        source: PositionSource.deadReckoned,
        extrapolatedFor: const Duration(seconds: 4),
      );
      final rebuilt = legacyRoundTrip(emitted);

      expect(emitted == rebuilt, isFalse,
          reason: 'this is the documented break; if it ever becomes true, the '
              'CHANGELOG is lying');
      expect(emitted.hashCode == rebuilt.hashCode, isFalse);
    });

    test('a Map keyed on GeoPosition misses — silently, returning null', () {
      final emitted = at(source: PositionSource.deadReckoned);
      final cache = <GeoPosition, String>{emitted: 'last known position'};

      // No exception. No analyzer warning. Just null. This is the whole
      // reason the change could not ride in as a patch.
      expect(cache[legacyRoundTrip(emitted)], isNull);
      expect(cache[emitted], 'last known position');
    });

    test('the break reaches the GPS-present fused path, not just fallback',
        () {
      // If this were fallback-only a consumer could dismiss it as an edge
      // case. It is not: normal Kalman operation emits `fused`.
      final fused = at(source: PositionSource.fused);
      expect(fused == legacyRoundTrip(fused), isFalse);
    });

    test('HER case: a last-known-position cache misses when GPS is gone', () {
      // The compound-failure scenario. A cache keyed by GeoPosition holds fine
      // while fixes are real, then starts missing at exactly the moment the
      // position becomes an estimate — when she needs the last known point.
      final cache = <GeoPosition, String>{};
      final measured = at(source: PositionSource.measured);
      cache[measured] = 'tunnel entrance';
      expect(cache[legacyRoundTrip(measured)], isNull);
    });
  });

  group('the migrations the CHANGELOG recommends actually work', () {
    test('carrying source through the codec restores equality', () {
      final emitted = at(
        source: PositionSource.deadReckoned,
        extrapolatedFor: const Duration(seconds: 4),
      );
      final rebuilt = provenanceAwareRoundTrip(emitted);

      expect(rebuilt, equals(emitted));
      expect(rebuilt.hashCode, equals(emitted.hashCode));
      expect(<GeoPosition, String>{emitted: 'ok'}[rebuilt], 'ok');
    });

    test('keying on (lat, lon, timestamp) is stable across the change', () {
      final emitted = at(source: PositionSource.deadReckoned);
      String key(GeoPosition p) => '${p.latitude},${p.longitude},${p.timestamp}';
      final cache = <String, String>{key(emitted): 'ok'};
      expect(cache[key(legacyRoundTrip(emitted))], 'ok');
    });
  });

  test('props is pinned — changing it must fail HERE first', () {
    // Not decoration. `props` is the equality contract, and the last change to
    // it was a breaking change that nearly shipped described as non-breaking.
    final p = at(
      source: PositionSource.deadReckoned,
      extrapolatedFor: const Duration(seconds: 4),
    );
    expect(
      p.props,
      orderedEquals(<Object?>[
        39.7186,
        140.1023,
        13.0,
        25.0,
        8.3,
        271.0,
        t,
        PositionSource.deadReckoned,
        const Duration(seconds: 4),
      ]),
      reason: 'if you changed props, you changed what == means for every '
          'consumer. That needs a version bump and a CHANGELOG line.',
    );
  });
}
