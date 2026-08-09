// Before 0.2.3 the mapper dropped
// timeseries slices silently, so a slice WE dropped was indistinguishable
// from one the publisher never issued, and both from an hour that is fine.
//
// These tests exist to prove the hole is visible. They do not test that we
// guess — we still refuse to guess.
import 'package:pretrip_source_met_norway/pretrip_source_met_norway.dart';
import 'package:test/test.dart';

Map<String, dynamic> _resp(List<Map<String, dynamic>> slices) => {
  'properties': {
    'meta': {'updated_at': '2026-01-15T06:00:00Z'},
    'timeseries': slices,
  },
};

Map<String, dynamic> _goodSlice(String t) => {
  'time': t,
  'data': {
    'instant': {
      'details': {'air_temperature': -4.0, 'relative_humidity': 88.0},
    },
    'next_1_hours': {
      'details': {'precipitation_amount': 0.4},
    },
  },
};

void main() {
  group('the dropped slice is visible', () {
    test('a complete response reports complete coverage and no drops', () {
      final r = mapLocationForecastWithCoverage(
        _resp([
          _goodSlice('2026-01-15T07:00:00Z'),
          _goodSlice('2026-01-15T08:00:00Z'),
        ]),
      );
      expect(r.forecast, isNotNull);
      expect(r.coverage.slicesSeen, 2);
      expect(r.coverage.hoursEmitted, 2);
      expect(r.coverage.dropped, 0);
      expect(r.coverage.isComplete, isTrue);
      expect(r.coverage.dropsByCause, isEmpty);
    });

    test(
      'the 6-hourly tail is counted as an EXPECTED drop, not a gap in what we were given',
      () {
        final tail = {
          'time': '2026-01-16T12:00:00Z',
          'data': {
            'instant': {
              'details': {'air_temperature': -2.0},
            },
            // no next_1_hours — the publisher's documented shape
          },
        };
        final r = mapLocationForecastWithCoverage(
          _resp([_goodSlice('2026-01-15T07:00:00Z'), tail]),
        );
        expect(r.coverage.hoursEmitted, 1);
        expect(r.coverage.dropped, 1);
        expect(r.coverage.dropsByCause[MetNorwaySliceDrop.noHourlyBlock], 1);
        expect(r.coverage.expectedDrops, 1);
        expect(
          r.coverage.unexpectedDrops,
          0,
          reason:
              'the 6-hourly tail is the publisher shape, not an unexpected hole',
        );
      },
    );

    test(
      'a missing air_temperature is an UNEXPECTED drop — and is still not guessed',
      () {
        final noTemp = {
          'time': '2026-01-15T09:00:00Z',
          'data': {
            'instant': {
              'details': {'relative_humidity': 90.0}, // no air_temperature
            },
            'next_1_hours': {
              'details': {'precipitation_amount': 0.1},
            },
          },
        };
        final r = mapLocationForecastWithCoverage(
          _resp([_goodSlice('2026-01-15T07:00:00Z'), noTemp]),
        );
        expect(
          r.coverage.hoursEmitted,
          1,
          reason: 'we skip, we do not invent a temperature',
        );
        expect(
          r.coverage.dropsByCause[MetNorwaySliceDrop.missingAirTemperature],
          1,
        );
        expect(r.coverage.unexpectedDrops, 1);
        expect(r.coverage.isComplete, isFalse);
      },
    );

    test('each drop cause is attributed separately', () {
      final r = mapLocationForecastWithCoverage(
        _resp([
          _goodSlice('2026-01-15T07:00:00Z'),
          {'time': 'not-a-time', 'data': <String, dynamic>{}},
          {'time': '2026-01-15T10:00:00Z', 'data': 'not-a-map'},
        ]),
      );
      expect(r.coverage.slicesSeen, 3);
      expect(r.coverage.hoursEmitted, 1);
      expect(r.coverage.dropsByCause[MetNorwaySliceDrop.unparseableTime], 1);
      expect(r.coverage.dropsByCause[MetNorwaySliceDrop.missingData], 1);
    });

    test(
      'THE POINT: two responses yielding the same forecast are distinguishable by coverage',
      () {
        final clean = mapLocationForecastWithCoverage(
          _resp([_goodSlice('2026-01-15T07:00:00Z')]),
        );
        final holed = mapLocationForecastWithCoverage(
          _resp([
            _goodSlice('2026-01-15T07:00:00Z'),
            {
              'time': '2026-01-15T08:00:00Z',
              'data': {
                'instant': {'details': <String, dynamic>{}},
                'next_1_hours': {'details': <String, dynamic>{}},
              },
            },
          ]),
        );
        expect(
          clean.forecast!.hourly.length,
          holed.forecast!.hourly.length,
          reason: 'identical forecasts…',
        );
        expect(clean.coverage.isComplete, isTrue);
        expect(
          holed.coverage.isComplete,
          isFalse,
          reason: '…but the hole is now visible, which it was not before',
        );
      },
    );

    test('the existing entrypoint is unchanged for every consumer', () {
      final resp = _resp([_goodSlice('2026-01-15T07:00:00Z')]);
      final old = mapLocationForecastToWeatherForecast(resp);
      final wrapped = mapLocationForecastWithCoverage(resp).forecast;
      expect(old, isNotNull);
      expect(old!.hourly.length, wrapped!.hourly.length);
      expect(old.issuedAt, wrapped.issuedAt);
    });
  });

  group('the PRE-LOOP paths, where the record used to lie', () {
    // An earlier draft of this type reported
    // slicesSeen: 0, dropped: 0, isComplete: TRUE for a response that carried
    // usable slices and failed only on meta.updated_at — indistinguishable
    // from a genuinely empty timeseries. The type built to make a hole
    // visible had a hole, on exactly the paths no test covered.

    test(
      'unparseable issuedAt still reports the slices the publisher SENT',
      () {
        final r = mapLocationForecastWithCoverage({
          'properties': {
            'meta': {'updated_at': 'not-a-timestamp'},
            'timeseries': [
              _goodSlice('2026-01-15T07:00:00Z'),
              _goodSlice('2026-01-15T08:00:00Z'),
              _goodSlice('2026-01-15T09:00:00Z'),
            ],
          },
        });
        expect(r.forecast, isNull);
        expect(
          r.coverage.slicesSeen,
          3,
          reason: 'three slices were sent; reporting 0 was the defect',
        );
        expect(r.coverage.hoursEmitted, 0);
        expect(r.coverage.dropped, 3);
        expect(r.coverage.responseUnusable, isTrue);
        expect(
          r.coverage.isComplete,
          isFalse,
          reason: 'a response we could not read must never report complete',
        );
      },
    );

    test('missing properties is unusable and not complete', () {
      final r = mapLocationForecastWithCoverage(<String, dynamic>{});
      expect(r.forecast, isNull);
      expect(r.coverage.slicesSeen, 0);
      expect(r.coverage.responseUnusable, isTrue);
      expect(r.coverage.isComplete, isFalse);
    });

    test('empty timeseries is unusable and not complete', () {
      final r = mapLocationForecastWithCoverage({
        'properties': {
          'meta': {'updated_at': '2026-01-15T06:00:00Z'},
          'timeseries': <Map<String, dynamic>>[],
        },
      });
      expect(r.forecast, isNull);
      expect(r.coverage.responseUnusable, isTrue);
      expect(r.coverage.isComplete, isFalse);
    });

    test('every slice dropped in-loop is also not complete', () {
      final r = mapLocationForecastWithCoverage(
        _resp([
          {'time': 'bad'},
        ]),
      );
      expect(r.forecast, isNull);
      expect(r.coverage.isComplete, isFalse);
    });
  });
}
