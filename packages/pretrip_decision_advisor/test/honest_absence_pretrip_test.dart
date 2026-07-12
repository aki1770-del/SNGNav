// Regression pins for the 0.5.2 honest-absence fix.
//
// Up to and including 0.5.1, a trip with NO forecast coverage was handed back
// as a briefing whose `peakHazard` was `HourHazard.clear` — a morning nobody
// forecast, painted green for a card that colours from the band. This suite
// pins the honest stop: `brief()` throws a typed, catchable exception (with a
// way forward) instead of fabricating a clear morning, `briefOrNull()` returns
// null, and `advise()` keeps its unchanged null contract. The same hole in
// `AreaConditionRead.areaHazard` is pinned too.
//
// EVERY expectation here FAILS against 0.5.1 (which returned clear), except the
// two that assert the deliberately-unchanged `advise()`/covered-path contracts.

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

const _advisor = SnowAwarePretripAdvisor();

const _profile = DriverProfileSpec(
  profileTag: 'ageingRural',
  reactionTimeSeconds: 1.5,
);

CommuteShape _commute(DateTime departure) => CommuteShape(
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['route-a'],
      flexibility: CommuteFlexibility.discretionary,
      plannedDeparture: departure,
    );

/// A forecast whose only slots are BEFORE the departure window — real forecast
/// data, but none of it covers the trip. This is the empty-window case.
WeatherForecast _forecastNotCovering(DateTime departure) => WeatherForecast(
      issuedAt: departure.subtract(const Duration(hours: 3)),
      hourly: [
        HourlyForecast(
            hour: departure.subtract(const Duration(hours: 2)),
            tempCelsius: -5),
        HourlyForecast(
            hour: departure.subtract(const Duration(hours: 1)),
            tempCelsius: -5),
      ],
    );

WeatherForecast _emptyForecast(DateTime departure) => WeatherForecast(
      issuedAt: departure,
      hourly: const [],
    );

void main() {
  final departure = DateTime.utc(2026, 1, 15, 7, 0);

  group('brief(): no forecast coverage STOPS, never fabricates clear', () {
    test('empty forecast throws PretripForecastCoverageException', () {
      expect(
        () => _advisor.brief(
          forecast: _emptyForecast(departure),
          commute: _commute(departure),
          profile: _profile,
        ),
        throwsA(isA<PretripForecastCoverageException>()),
      );
    });

    test('non-covering forecast throws (slots exist but miss the window)', () {
      expect(
        () => _advisor.brief(
          forecast: _forecastNotCovering(departure),
          commute: _commute(departure),
          profile: _profile,
        ),
        throwsA(isA<PretripForecastCoverageException>()),
      );
    });

    test('the exception is a PretripDataAbsentException (one catch for all)',
        () {
      expect(
        () => _advisor.brief(
          forecast: _emptyForecast(departure),
          commute: _commute(departure),
          profile: _profile,
        ),
        throwsA(isA<PretripDataAbsentException>()),
      );
    });

    test('the message is a lamp: what happened, why, and the way forward', () {
      PretripForecastCoverageException? caught;
      try {
        _advisor.brief(
          forecast: _emptyForecast(departure),
          commute: _commute(departure),
          profile: _profile,
        );
      } on PretripForecastCoverageException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      final msg = caught!.message;
      // Says what happened.
      expect(msg, contains('No forecast covers'));
      // Says why we refuse to guess (no "unknown" value to return).
      expect(msg.toLowerCase(), contains('unknown'));
      // Tells him the way forward.
      expect(msg, contains('briefOrNull'));
      // Carries the structured facts a handler can use.
      expect(caught.forecastSlotCount, 0);
      expect(caught.plannedDeparture, departure);
      expect(caught.plannedDuration, const Duration(minutes: 30));
    });
  });

  group('briefOrNull(): the branch-do-not-catch way forward', () {
    test('returns null (not a clear briefing) on no coverage', () {
      final b = _advisor.briefOrNull(
        forecast: _emptyForecast(departure),
        commute: _commute(departure),
        profile: _profile,
      );
      expect(b, isNull);
    });

    test('returns a real briefing when the window IS covered', () {
      final covered = WeatherForecast(
        issuedAt: departure,
        hourly: [
          HourlyForecast(hour: departure, tempCelsius: 4.0),
        ],
      );
      final b = _advisor.briefOrNull(
        forecast: covered,
        commute: _commute(departure),
        profile: _profile,
      );
      expect(b, isNotNull);
      // The band is derived from a real slot — safe to colour from.
      expect(b!.peakHazard, HourHazard.clear);
    });
  });

  group('advise(): unchanged null contract (must NOT throw)', () {
    test('still returns null on no coverage, exactly as before', () {
      final r = _advisor.advise(
        forecast: _emptyForecast(departure),
        commute: _commute(departure),
        profile: _profile,
      );
      expect(r, isNull);
    });
  });

  group('AreaConditionRead: uncovered window STOPS, never fabricates clear',
      () {
    // A summary whose forecast does not cover the look-ahead window.
    AreaConditionRead uncovered() => summarizeAreaConditions(
          forecast: _forecastNotCovering(departure),
          now: departure,
          areaLabel: 'Akita',
        );

    test('forecastCovered is false for this fixture', () {
      expect(uncovered().forecastCovered, isFalse);
    });

    test('reading areaHazard throws AreaForecastNotCoveredException', () {
      expect(
        () => uncovered().areaHazard,
        throwsA(isA<AreaForecastNotCoveredException>()),
      );
    });

    test('areaHazardOrNull() returns null (not clear) when uncovered', () {
      expect(uncovered().areaHazardOrNull(), isNull);
    });

    test('the message names the place and the way forward', () {
      AreaForecastNotCoveredException? caught;
      try {
        uncovered().areaHazard;
      } on AreaForecastNotCoveredException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.message, contains('Akita'));
      expect(caught.message, contains('areaHazardOrNull'));
      expect(caught.areaLabel, 'Akita');
    });

    test('a COVERED area still returns its band (unchanged path)', () {
      final r = summarizeAreaConditions(
        forecast: WeatherForecast(
          issuedAt: departure,
          hourly: [HourlyForecast(hour: departure, tempCelsius: 4.0)],
        ),
        now: departure,
        areaLabel: 'Akita',
      );
      expect(r.forecastCovered, isTrue);
      expect(r.areaHazard, HourHazard.clear);
      expect(r.areaHazardOrNull(), HourHazard.clear);
    });
  });
}
