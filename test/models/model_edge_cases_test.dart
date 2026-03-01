/// Model edge case tests — computed properties, boundary conditions,
/// Jidoka semantics, and Equatable behavior for all data models.
///
/// These tests exercise the derived fields and helper methods on
/// RouteResult, FleetReport, HazardZone, GeoPosition, and ConsentRecord
/// that were previously only tested indirectly through BLoC/widget tests.
///
/// Sprint 9 Day 11 — Test hardening.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/models/consent_record.dart';
import 'package:sngnav_snow_scene/models/fleet_report.dart';
import 'package:sngnav_snow_scene/models/geo_position.dart';
import 'package:sngnav_snow_scene/models/hazard_zone.dart';
import 'package:sngnav_snow_scene/models/route_result.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);

RouteResult _route({
  List<LatLng>? shape,
  double distKm = 25.7,
  double timeSec = 1830,
  List<RouteManeuver>? maneuvers,
}) {
  return RouteResult(
    shape: shape ?? [_nagoya, _toyota],
    maneuvers: maneuvers ?? [],
    totalDistanceKm: distKm,
    totalTimeSeconds: timeSec,
    summary: '$distKm km',
    engineInfo: const EngineInfo(name: 'mock'),
  );
}

FleetReport _fleetReport({
  String vehicleId = 'v1',
  RoadCondition condition = RoadCondition.snowy,
  double confidence = 0.8,
  DateTime? timestamp,
}) {
  return FleetReport(
    vehicleId: vehicleId,
    position: _nagoya,
    timestamp: timestamp ?? DateTime.now(),
    condition: condition,
    confidence: confidence,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // RouteResult
  // =========================================================================
  group('RouteResult', () {
    group('eta', () {
      test('converts totalTimeSeconds to Duration', () {
        final r = _route(timeSec: 1830);
        expect(r.eta, const Duration(seconds: 1830));
        expect(r.eta.inMinutes, 30);
      });

      test('rounds fractional seconds', () {
        final r = _route(timeSec: 90.7);
        expect(r.eta, const Duration(seconds: 91));
      });

      test('zero time → Duration.zero', () {
        final r = _route(timeSec: 0);
        expect(r.eta, Duration.zero);
      });
    });

    group('hasGeometry', () {
      test('true when shape has 2+ points', () {
        final r = _route(shape: [_nagoya, _toyota]);
        expect(r.hasGeometry, isTrue);
      });

      test('false when shape has 1 point', () {
        final r = _route(shape: [_nagoya]);
        expect(r.hasGeometry, isFalse);
      });

      test('false when shape is empty', () {
        final r = _route(shape: []);
        expect(r.hasGeometry, isFalse);
      });
    });

    group('toString', () {
      test('includes distance and engine name', () {
        final r = _route(distKm: 25.7);
        final s = r.toString();
        expect(s, contains('25.7km'));
        expect(s, contains('mock'));
      });

      test('includes point count', () {
        final r = _route(shape: [_nagoya, _toyota]);
        expect(r.toString(), contains('2 pts'));
      });
    });

    group('Equatable', () {
      test('equal routes have same props', () {
        final r1 = _route();
        final r2 = _route();
        expect(r1, equals(r2));
      });

      test('different distance → not equal', () {
        final r1 = _route(distKm: 10);
        final r2 = _route(distKm: 20);
        expect(r1, isNot(equals(r2)));
      });
    });
  });

  // =========================================================================
  // RouteManeuver
  // =========================================================================
  group('RouteManeuver', () {
    test('toString includes index, type, instruction', () {
      const m = RouteManeuver(
        index: 0,
        instruction: 'Turn right',
        type: 'right',
        lengthKm: 1.5,
        timeSeconds: 90,
        position: _nagoya,
      );
      final s = m.toString();
      expect(s, contains('0'));
      expect(s, contains('right'));
      expect(s, contains('Turn right'));
    });

    test('Equatable by all fields', () {
      const m1 = RouteManeuver(
        index: 0,
        instruction: 'Go',
        type: 'depart',
        lengthKm: 1.0,
        timeSeconds: 60,
        position: _nagoya,
      );
      const m2 = RouteManeuver(
        index: 0,
        instruction: 'Go',
        type: 'depart',
        lengthKm: 1.0,
        timeSeconds: 60,
        position: _nagoya,
      );
      expect(m1, equals(m2));
    });
  });

  // =========================================================================
  // EngineInfo
  // =========================================================================
  group('EngineInfo', () {
    test('default version is unknown', () {
      const info = EngineInfo(name: 'osrm');
      expect(info.version, 'unknown');
    });

    test('default queryLatency is zero', () {
      const info = EngineInfo(name: 'osrm');
      expect(info.queryLatency, Duration.zero);
    });

    test('toString includes name and version', () {
      const info = EngineInfo(
        name: 'valhalla',
        version: '3.4.0',
        queryLatency: Duration(milliseconds: 42),
      );
      expect(info.toString(), contains('valhalla'));
      expect(info.toString(), contains('3.4.0'));
      expect(info.toString(), contains('42ms'));
    });
  });

  // =========================================================================
  // RouteRequest
  // =========================================================================
  group('RouteRequest', () {
    test('default costing is auto', () {
      const req = RouteRequest(origin: _nagoya, destination: _toyota);
      expect(req.costing, 'auto');
    });

    test('default language is ja-JP', () {
      const req = RouteRequest(origin: _nagoya, destination: _toyota);
      expect(req.language, 'ja-JP');
    });

    test('Equatable by origin, destination, costing, language', () {
      const r1 = RouteRequest(origin: _nagoya, destination: _toyota);
      const r2 = RouteRequest(origin: _nagoya, destination: _toyota);
      expect(r1, equals(r2));
    });

    test('different costing → not equal', () {
      const r1 = RouteRequest(
          origin: _nagoya, destination: _toyota, costing: 'auto');
      const r2 = RouteRequest(
          origin: _nagoya, destination: _toyota, costing: 'bicycle');
      expect(r1, isNot(equals(r2)));
    });
  });

  // =========================================================================
  // FleetReport
  // =========================================================================
  group('FleetReport', () {
    group('isHazard', () {
      test('snowy → true', () {
        expect(_fleetReport(condition: RoadCondition.snowy).isHazard, isTrue);
      });

      test('icy → true', () {
        expect(_fleetReport(condition: RoadCondition.icy).isHazard, isTrue);
      });

      test('dry → false', () {
        expect(_fleetReport(condition: RoadCondition.dry).isHazard, isFalse);
      });

      test('wet → false', () {
        expect(_fleetReport(condition: RoadCondition.wet).isHazard, isFalse);
      });

      test('unknown → false', () {
        expect(
            _fleetReport(condition: RoadCondition.unknown).isHazard, isFalse);
      });
    });

    group('isRecent', () {
      test('report from 5 minutes ago is recent (default 15m)', () {
        final report = _fleetReport(
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        expect(report.isRecent(), isTrue);
      });

      test('report from 20 minutes ago is not recent (default 15m)', () {
        final report = _fleetReport(
          timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
        );
        expect(report.isRecent(), isFalse);
      });

      test('custom maxAge respected', () {
        final report = _fleetReport(
          timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
        );
        expect(
          report.isRecent(maxAge: const Duration(minutes: 2)),
          isFalse,
        );
        expect(
          report.isRecent(maxAge: const Duration(minutes: 5)),
          isTrue,
        );
      });

      test('report from the future is recent', () {
        final report = _fleetReport(
          timestamp: DateTime.now().add(const Duration(minutes: 5)),
        );
        expect(report.isRecent(), isTrue);
      });
    });

    group('confidence', () {
      test('default confidence is 0.8', () {
        expect(_fleetReport().confidence, 0.8);
      });

      test('custom confidence accepted', () {
        expect(_fleetReport(confidence: 0.95).confidence, 0.95);
      });
    });

    group('toString', () {
      test('includes vehicleId and condition', () {
        final s = _fleetReport(vehicleId: 'abc', condition: RoadCondition.icy)
            .toString();
        expect(s, contains('abc'));
        expect(s, contains('icy'));
      });
    });
  });

  // =========================================================================
  // HazardZone
  // =========================================================================
  group('HazardZone', () {
    group('vehicleCount', () {
      test('counts unique vehicles', () {
        final zone = HazardZone(
          center: _nagoya,
          radiusMeters: 500,
          severity: HazardSeverity.snowy,
          reports: [
            _fleetReport(vehicleId: 'v1'),
            _fleetReport(vehicleId: 'v2'),
            _fleetReport(vehicleId: 'v1'), // duplicate
          ],
        );
        expect(zone.vehicleCount, 2);
      });

      test('single report → 1 vehicle', () {
        final zone = HazardZone(
          center: _nagoya,
          radiusMeters: 500,
          severity: HazardSeverity.snowy,
          reports: [_fleetReport(vehicleId: 'v1')],
        );
        expect(zone.vehicleCount, 1);
      });

      test('empty reports → 0 vehicles', () {
        const zone = HazardZone(
          center: _nagoya,
          radiusMeters: 500,
          severity: HazardSeverity.snowy,
          reports: [],
        );
        expect(zone.vehicleCount, 0);
      });
    });

    group('averageConfidence', () {
      test('average of multiple reports', () {
        final zone = HazardZone(
          center: _nagoya,
          radiusMeters: 500,
          severity: HazardSeverity.snowy,
          reports: [
            _fleetReport(confidence: 0.6),
            _fleetReport(confidence: 0.8),
            _fleetReport(confidence: 1.0),
          ],
        );
        expect(zone.averageConfidence, closeTo(0.8, 0.001));
      });

      test('empty reports → 0', () {
        const zone = HazardZone(
          center: _nagoya,
          radiusMeters: 500,
          severity: HazardSeverity.snowy,
          reports: [],
        );
        expect(zone.averageConfidence, 0);
      });

      test('single report → its confidence', () {
        final zone = HazardZone(
          center: _nagoya,
          radiusMeters: 500,
          severity: HazardSeverity.snowy,
          reports: [_fleetReport(confidence: 0.95)],
        );
        expect(zone.averageConfidence, 0.95);
      });
    });

    group('toString', () {
      test('includes severity, report count, vehicle count', () {
        final zone = HazardZone(
          center: _nagoya,
          radiusMeters: 1500,
          severity: HazardSeverity.icy,
          reports: [
            _fleetReport(vehicleId: 'v1'),
            _fleetReport(vehicleId: 'v2'),
          ],
        );
        final s = zone.toString();
        expect(s, contains('icy'));
        expect(s, contains('2 reports'));
        expect(s, contains('2 vehicles'));
        expect(s, contains('1500m'));
      });
    });
  });

  // =========================================================================
  // GeoPosition
  // =========================================================================
  group('GeoPosition', () {
    group('speedKmh', () {
      test('converts m/s to km/h', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          speed: 11.11,
          timestamp: DateTime.now(),
        );
        expect(pos.speedKmh, closeTo(40.0, 0.1));
      });

      test('NaN speed → NaN km/h', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          timestamp: DateTime.now(),
        );
        expect(pos.speedKmh.isNaN, isTrue);
      });

      test('zero speed → 0 km/h', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          speed: 0,
          timestamp: DateTime.now(),
        );
        expect(pos.speedKmh, 0);
      });
    });

    group('isNavigationGrade', () {
      test('accuracy 5m → true', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          timestamp: DateTime.now(),
        );
        expect(pos.isNavigationGrade, isTrue);
      });

      test('accuracy 50m → true (boundary)', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 50,
          timestamp: DateTime.now(),
        );
        expect(pos.isNavigationGrade, isTrue);
      });

      test('accuracy 51m → false', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 51,
          timestamp: DateTime.now(),
        );
        expect(pos.isNavigationGrade, isFalse);
      });
    });

    group('isHighAccuracy', () {
      test('accuracy 5m → true', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          timestamp: DateTime.now(),
        );
        expect(pos.isHighAccuracy, isTrue);
      });

      test('accuracy 10m → true (boundary)', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 10,
          timestamp: DateTime.now(),
        );
        expect(pos.isHighAccuracy, isTrue);
      });

      test('accuracy 11m → false', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 11,
          timestamp: DateTime.now(),
        );
        expect(pos.isHighAccuracy, isFalse);
      });
    });

    group('defaults', () {
      test('altitude defaults to NaN', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          timestamp: DateTime.now(),
        );
        expect(pos.altitude.isNaN, isTrue);
      });

      test('heading defaults to NaN', () {
        final pos = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 5,
          timestamp: DateTime.now(),
        );
        expect(pos.heading.isNaN, isTrue);
      });
    });

    group('toString', () {
      test('includes lat, lon, accuracy', () {
        final pos = GeoPosition(
          latitude: 35.1709,
          longitude: 136.8815,
          accuracy: 5,
          timestamp: DateTime.now(),
        );
        expect(pos.toString(), contains('35.1709'));
        expect(pos.toString(), contains('136.8815'));
        expect(pos.toString(), contains('5.0m'));
      });
    });
  });

  // =========================================================================
  // ConsentRecord — Jidoka semantics
  // =========================================================================
  group('ConsentRecord', () {
    group('Jidoka: unknown = denied', () {
      test('isEffectivelyGranted: only true when granted', () {
        final granted = ConsentRecord(
          purpose: ConsentPurpose.fleetLocation,
          status: ConsentStatus.granted,
          jurisdiction: Jurisdiction.gdpr,
          updatedAt: DateTime.now(),
        );
        expect(granted.isEffectivelyGranted, isTrue);
      });

      test('isEffectivelyGranted: false when denied', () {
        final denied = ConsentRecord(
          purpose: ConsentPurpose.fleetLocation,
          status: ConsentStatus.denied,
          jurisdiction: Jurisdiction.gdpr,
          updatedAt: DateTime.now(),
        );
        expect(denied.isEffectivelyGranted, isFalse);
      });

      test('isEffectivelyGranted: false when unknown (Jidoka)', () {
        final unknown = ConsentRecord.unknown(
          purpose: ConsentPurpose.fleetLocation,
        );
        expect(unknown.isEffectivelyGranted, isFalse);
      });

      test('isExplicitlyDenied: only true when denied', () {
        final denied = ConsentRecord(
          purpose: ConsentPurpose.fleetLocation,
          status: ConsentStatus.denied,
          jurisdiction: Jurisdiction.gdpr,
          updatedAt: DateTime.now(),
        );
        expect(denied.isExplicitlyDenied, isTrue);
      });

      test('isExplicitlyDenied: false when unknown', () {
        final unknown = ConsentRecord.unknown(
          purpose: ConsentPurpose.fleetLocation,
        );
        expect(unknown.isExplicitlyDenied, isFalse);
      });

      test('isUnknown: true for unknown status', () {
        final unknown = ConsentRecord.unknown(
          purpose: ConsentPurpose.diagnostics,
        );
        expect(unknown.isUnknown, isTrue);
      });

      test('isUnknown: false for granted', () {
        final granted = ConsentRecord(
          purpose: ConsentPurpose.diagnostics,
          status: ConsentStatus.granted,
          jurisdiction: Jurisdiction.appi,
          updatedAt: DateTime.now(),
        );
        expect(granted.isUnknown, isFalse);
      });
    });

    group('ConsentRecord.unknown factory', () {
      test('status is unknown', () {
        final r = ConsentRecord.unknown(
          purpose: ConsentPurpose.weatherTelemetry,
        );
        expect(r.status, ConsentStatus.unknown);
      });

      test('default jurisdiction is GDPR', () {
        final r = ConsentRecord.unknown(
          purpose: ConsentPurpose.weatherTelemetry,
        );
        expect(r.jurisdiction, Jurisdiction.gdpr);
      });

      test('updatedAt is epoch (never set)', () {
        final r = ConsentRecord.unknown(
          purpose: ConsentPurpose.weatherTelemetry,
        );
        expect(r.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      });

      test('custom jurisdiction accepted', () {
        final r = ConsentRecord.unknown(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.ccpa,
        );
        expect(r.jurisdiction, Jurisdiction.ccpa);
      });
    });

    group('all three purposes', () {
      test('fleetLocation purpose', () {
        final r = ConsentRecord.unknown(
            purpose: ConsentPurpose.fleetLocation);
        expect(r.purpose, ConsentPurpose.fleetLocation);
      });

      test('weatherTelemetry purpose', () {
        final r = ConsentRecord.unknown(
            purpose: ConsentPurpose.weatherTelemetry);
        expect(r.purpose, ConsentPurpose.weatherTelemetry);
      });

      test('diagnostics purpose', () {
        final r = ConsentRecord.unknown(
            purpose: ConsentPurpose.diagnostics);
        expect(r.purpose, ConsentPurpose.diagnostics);
      });
    });

    group('toString', () {
      test('includes purpose, status, jurisdiction', () {
        final r = ConsentRecord(
          purpose: ConsentPurpose.fleetLocation,
          status: ConsentStatus.granted,
          jurisdiction: Jurisdiction.gdpr,
          updatedAt: DateTime(2026, 2, 28),
        );
        final s = r.toString();
        expect(s, contains('fleetLocation'));
        expect(s, contains('granted'));
        expect(s, contains('gdpr'));
      });
    });
  });
}
