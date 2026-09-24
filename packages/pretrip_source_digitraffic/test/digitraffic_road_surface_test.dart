/// Tests for the Digitraffic measured ROAD-SURFACE reading.
///
/// The station payload this package already fetches for visibility carries
/// ~97 sensors, of which the road-surface family is the only measured
/// road-surface source in this catalog (measured 2026-09-24, station 14034).
/// Through 0.2.3 every one of them was walked past and discarded.
///
/// These tests fix the honesty rules BEFORE the reader exists:
/// an untabled channel is never given a meaning, a declared sensor fault is
/// never a surface class, and an aggregate never averages away a cold point.
library;

import 'dart:convert';

import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';
import 'package:test/test.dart';

const _lat = 60.2;
const _lon = 24.6;

String _metadata() => jsonEncode({
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'id': 1001,
      'geometry': {
        'type': 'Point',
        'coordinates': [24.596399, 60.228227, 0.0],
      },
      'properties': {
        'id': 1001,
        'name': 'vt1_Espoo_Nupuri',
        'collectionStatus': 'GATHERING',
      },
    },
  ],
});

/// A sensorValues entry shaped exactly like the live payload
/// (`/api/weather/v1/stations/14034/data`, read 2026-09-24T06:03:37Z).
Map<String, dynamic> _sensor(
  String name,
  double value, {
  required String measuredTime,
  String unit = '***',
  String? inlineEn,
}) => <String, dynamic>{
  'id': 0,
  'stationId': 14034,
  'name': name,
  'shortName': name,
  'measuredTime': measuredTime,
  'unit': unit,
  'value': value,
  if (inlineEn != null) 'sensorValueDescriptionEn': inlineEn,
};

String _stationData(List<Map<String, dynamic>> sensors, String updated) =>
    jsonEncode({
      'id': 14034,
      'dataUpdatedTime': updated,
      'sensorValues': sensors,
    });

void main() {
  final now = DateTime.utc(2026, 9, 24, 6, 10);
  const fresh = '2026-09-24T06:03:17Z'; // ~7 min old at [now]
  const stale = '2026-09-24T03:00:00Z'; // ~3 h old at [now]

  /// The live 2026-09-24 station-14034 road-surface family, verbatim.
  List<Map<String, dynamic>> liveFamily({String measuredTime = fresh}) => [
    _sensor('TIE_1', 7.3, measuredTime: measuredTime, unit: '°C'),
    _sensor('TIE_2', 7.6, measuredTime: measuredTime, unit: '°C'),
    _sensor('TIE_3', 6.9, measuredTime: measuredTime, unit: '°C'),
    _sensor('TIE_4', 7.0, measuredTime: measuredTime, unit: '°C'),
    _sensor('TIE_1_DERIVAATTA', 0.2, measuredTime: measuredTime, unit: '°C/h'),
    _sensor('TIE_2_DERIVAATTA', -0.3, measuredTime: measuredTime, unit: '°C/h'),
    _sensor('JÄÄTYMISPISTE_1', 0.0, measuredTime: measuredTime, unit: '°C'),
    _sensor('JÄÄTYMISPISTE_3', -0.4, measuredTime: measuredTime, unit: '°C'),
    _sensor('KELI_1', 2.0, measuredTime: measuredTime, inlineEn: 'Moist'),
    _sensor('KELI_2', 2.0, measuredTime: measuredTime, inlineEn: 'Moist'),
    // KELI_3 / KELI_4 carry NO publisher code table (sensor ids 105 / 115,
    // `sensorValueDescriptions: []`, measured 2026-09-24) — and no inline
    // description either, though KELI_1 with the same value has one.
    _sensor('KELI_3', 3.0, measuredTime: measuredTime),
    _sensor('KELI_4', 2.0, measuredTime: measuredTime),
    // TIENPINNAN_TILA_1..4: `sensorValueDescriptions: []` AND
    // `description: null`. The publisher ships the integer and no meaning.
    _sensor('TIENPINNAN_TILA_1', 1.0, measuredTime: measuredTime),
    _sensor('TIENPINNAN_TILA_3', 3.0, measuredTime: measuredTime),
    _sensor('NÄKYVYYS_M', 4514.0, measuredTime: measuredTime, unit: 'm'),
  ];

  group('parseDigitrafficRoadSurface — the publisher speaks, we do not', () {
    test('reads the tabled KELI channels in the publisher own words', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(_stationData(liveFamily(), fresh)) as Map<String, dynamic>,
        now: now,
        stationId: 14034,
        stationName: 'vt4_Rovaniemi_Revontuli',
        distanceKm: 2.1,
      );
      expect(obs, isNotNull);
      expect(obs!.surfaceStates.map((s) => s.sensorName), ['KELI_1', 'KELI_2']);
      expect(obs.surfaceStates.first.code, 2);
      expect(obs.surfaceStates.first.publisherLabel, 'Moist');
    });

    test('NEVER interprets a channel the publisher does not table', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(_stationData(liveFamily(), fresh)) as Map<String, dynamic>,
        now: now,
        stationId: 14034,
        stationName: 'x',
        distanceKm: 1,
      )!;
      expect(
        obs.surfaceStates.map((s) => s.sensorName),
        isNot(anyOf(contains('KELI_3'), contains('TIENPINNAN_TILA_1'))),
      );
      expect(
        obs.uninterpretedSensors,
        containsAll(<String>[
          'KELI_3',
          'KELI_4',
          'TIENPINNAN_TILA_1',
          'TIENPINNAN_TILA_3',
        ]),
      );
    });

    test('a class with no VSS equivalent is null, never DRY', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(_stationData(liveFamily(), fresh)) as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      )!;
      // Fintraffic code 2 is "Moist". VSS has no MOIST; DRY would be a lie
      // toward benign and WET a lie toward hazard.
      expect(obs.surfaceStates.first.vssRoadSurfaceCondition, isNull);
    });

    test('maps only the codes that map cleanly onto VSS', () {
      for (final (code, label, vss) in <(double, String, String?)>[
        (1, 'Dry', 'DRY'),
        (3, 'Wet', 'WET'),
        (6, 'Snow', 'SNOW'),
        (7, 'Ice', 'ICE'),
        (9, 'Slushy', 'SLUSH'),
      ]) {
        final obs = parseDigitrafficRoadSurface(
          jsonDecode(
                _stationData([
                  _sensor('KELI_1', code, measuredTime: fresh),
                ], fresh),
              )
              as Map<String, dynamic>,
          now: now,
          stationId: 1,
          stationName: 'x',
          distanceKm: 1,
        )!;
        expect(obs.surfaceStates.single.publisherLabel, label);
        expect(obs.surfaceStates.single.vssRoadSurfaceCondition, vss);
      }
    });

    test('a declared sensor fault is never a surface class', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(
              _stationData([
                _sensor('KELI_1', 0.0, measuredTime: fresh),
              ], fresh),
            )
            as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      );
      expect(obs?.sensorFaultDeclared, isTrue);
      expect(obs?.surfaceStates, isEmpty);
    });

    test('the COLDEST surface point wins — a mean would hide it', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(
              _stationData([
                _sensor('TIE_1', 7.3, measuredTime: fresh, unit: '°C'),
                _sensor('TIE_2', -1.5, measuredTime: fresh, unit: '°C'),
                _sensor('TIE_3', 6.9, measuredTime: fresh, unit: '°C'),
              ], fresh),
            )
            as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      )!;
      expect(obs.coldestSurfaceCelsius, -1.5);
      expect(obs.coldestSurfaceSensor, 'TIE_2');
    });

    test('the HIGHEST freezing point wins, and names its sensor', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(_stationData(liveFamily(), fresh)) as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      )!;
      expect(obs.highestFreezingPointCelsius, 0.0);
      expect(obs.highestFreezingPointSensor, 'JÄÄTYMISPISTE_1');
    });

    test('the FASTEST cooling trend wins (most negative)', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(_stationData(liveFamily(), fresh)) as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      )!;
      expect(obs.fastestSurfaceCoolingCelsiusPerHour, -0.3);
      expect(obs.fastestSurfaceCoolingSensor, 'TIE_2_DERIVAATTA');
    });

    test('a stale reading is dropped, never served as current', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(_stationData(liveFamily(measuredTime: stale), stale))
            as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      );
      expect(obs, isNull);
    });

    test('a payload with no road-surface family at all returns null', () {
      final obs = parseDigitrafficRoadSurface(
        jsonDecode(
              _stationData([
                _sensor('NÄKYVYYS_M', 4514.0, measuredTime: fresh, unit: 'm'),
                _sensor('ILMA', 6.8, measuredTime: fresh, unit: '°C'),
              ], fresh),
            )
            as Map<String, dynamic>,
        now: now,
        stationId: 1,
        stationName: 'x',
        distanceKm: 1,
      );
      expect(obs, isNull);
    });

    test('every emitted VSS string is an allowed VSS value', () {
      const allowed = {
        'UNKNOWN',
        'DRY',
        'WET',
        'SNOW',
        'ICE',
        'SLUSH',
        'WET_ICE',
        'LOOSE_GRAVEL',
      };
      for (var code = 0; code <= 9; code++) {
        final obs = parseDigitrafficRoadSurface(
          jsonDecode(
                _stationData([
                  _sensor('KELI_1', code.toDouble(), measuredTime: fresh),
                ], fresh),
              )
              as Map<String, dynamic>,
          now: now,
          stationId: 1,
          stationName: 'x',
          distanceKm: 1,
        );
        final vss = obs?.surfaceStates.singleOrNull?.vssRoadSurfaceCondition;
        if (vss != null) expect(allowed, contains(vss));
      }
    });
  });

  group('fetchNearestRoadSurface', () {
    test('returns the nearest station road surface over the wire', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/stations')) {
          return _ok(_metadata());
        }
        return _ok(_stationData(liveFamily(), fresh));
      });
      final provider = DigitrafficVisibilityProvider.withClient(client);
      final obs = await provider.fetchNearestRoadSurface(
        latitude: _lat,
        longitude: _lon,
        now: now,
      );
      expect(obs, isNotNull);
      expect(obs!.stationName, 'vt1_Espoo_Nupuri');
      expect(obs.surfaceStates.first.publisherLabel, 'Moist');
      expect(obs.uninterpretedSensors, contains('TIENPINNAN_TILA_1'));
    });
  });
}

/// A 200 that declares utf-8 — without the charset, `http.Response` encodes
/// the body as latin1 and the provider's `utf8.decode` rejects `Ä`.
Response _ok(String body) => Response(
  body,
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
