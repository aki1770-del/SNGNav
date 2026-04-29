import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

/// Stub advisor used to exercise the interface shape.
///
/// Honesty rule: if the commute is required, this stub must return
/// either null or honestyMode. For discretionary commutes, it returns
/// a delay only when at least one upcoming hour reports ice.
class _StubAdvisor implements PretripAdvisor {
  const _StubAdvisor();

  @override
  PretripRecommendation? advise({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) {
    if (commute.flexibility == CommuteFlexibility.required) {
      return PretripRecommendation(
        suggestedDelay: Duration.zero,
        confidenceWindow: Duration.zero,
        strength: RecommendationStrength.honestyMode,
        rationale: const [
          'Commute is required; deferring to the driver.',
        ],
      );
    }

    final hasIce = forecast.hourly.any(
      (h) => h.estimatedRoadCondition == RoadConditionEstimate.ice,
    );
    if (commute.flexibility == CommuteFlexibility.discretionary && hasIce) {
      return PretripRecommendation(
        suggestedDelay: const Duration(hours: 1),
        confidenceWindow: const Duration(minutes: 30),
        strength: RecommendationStrength.advisoryStrong,
        rationale: const ['Ice expected on the road in the next hour.'],
      );
    }

    if (commute.flexibility == CommuteFlexibility.discretionary) {
      return PretripRecommendation(
        suggestedDelay: Duration.zero,
        confidenceWindow: Duration.zero,
        strength: RecommendationStrength.advisoryWeak,
        rationale: const ['Conditions look acceptable for departure.'],
      );
    }

    return null;
  }
}

WeatherForecast _clearForecast(DateTime base) => WeatherForecast(
      issuedAt: base,
      hourly: [
        HourlyForecast(
          hour: base.add(const Duration(hours: 1)),
          tempCelsius: 4.0,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        ),
        HourlyForecast(
          hour: base.add(const Duration(hours: 2)),
          tempCelsius: 5.0,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        ),
      ],
    );

WeatherForecast _iceForecast(DateTime base) => WeatherForecast(
      issuedAt: base,
      hourly: [
        HourlyForecast(
          hour: base.add(const Duration(hours: 1)),
          tempCelsius: -2.0,
          estimatedRoadCondition: RoadConditionEstimate.ice,
        ),
      ],
    );

CommuteShape _commute(CommuteFlexibility flex, DateTime base) => CommuteShape(
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['route-a'],
      flexibility: flex,
      plannedDeparture: base,
    );

const _profile = DriverProfileSpec(
  profileTag: 'ageingRural',
  reactionTimeSeconds: 1.5,
);

void main() {
  final base = DateTime.utc(2026, 1, 15, 7, 0);

  group('honesty rule (V14)', () {
    test('required commute never returns advisoryStrong', () {
      const advisor = _StubAdvisor();
      final r = advisor.advise(
        forecast: _iceForecast(base),
        commute: _commute(CommuteFlexibility.required, base),
        profile: _profile,
      );
      expect(r, isNotNull);
      expect(r!.strength, isNot(RecommendationStrength.advisoryStrong));
      expect(r.strength, isNot(RecommendationStrength.advisoryWeak));
      expect(r.strength, RecommendationStrength.honestyMode);
    });

    test('required commute may also return null', () {
      // Construct a stub that returns null for required commutes.
      final advisor = _NullForRequiredAdvisor();
      final r = advisor.advise(
        forecast: _iceForecast(base),
        commute: _commute(CommuteFlexibility.required, base),
        profile: _profile,
      );
      expect(r, isNull);
    });
  });

  group('discretionary commute', () {
    test('clear forecast yields zero-delay weak recommendation', () {
      const advisor = _StubAdvisor();
      final r = advisor.advise(
        forecast: _clearForecast(base),
        commute: _commute(CommuteFlexibility.discretionary, base),
        profile: _profile,
      );
      expect(r, isNotNull);
      expect(r!.suggestedDelay, Duration.zero);
      expect(r.strength, RecommendationStrength.advisoryWeak);
    });

    test('ice forecast yields a non-zero delay', () {
      const advisor = _StubAdvisor();
      final r = advisor.advise(
        forecast: _iceForecast(base),
        commute: _commute(CommuteFlexibility.discretionary, base),
        profile: _profile,
      );
      expect(r, isNotNull);
      expect(r!.suggestedDelay, greaterThan(Duration.zero));
      expect(r.strength, RecommendationStrength.advisoryStrong);
    });
  });

  group('DTO equality + hashCode round-trip', () {
    test('PretripRecommendation equality holds for equal field sets', () {
      final a = PretripRecommendation(
        suggestedDelay: const Duration(hours: 1),
        confidenceWindow: const Duration(minutes: 30),
        strength: RecommendationStrength.advisoryStrong,
        rationale: const ['ice'],
      );
      final b = PretripRecommendation(
        suggestedDelay: const Duration(hours: 1),
        confidenceWindow: const Duration(minutes: 30),
        strength: RecommendationStrength.advisoryStrong,
        rationale: const ['ice'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('CommuteShape equality holds for equal field sets', () {
      final a = _commute(CommuteFlexibility.discretionary, base);
      final b = _commute(CommuteFlexibility.discretionary, base);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('enum exhaustivity', () {
    test('RecommendationStrength has the three documented cases', () {
      expect(
        RecommendationStrength.values.toSet(),
        {
          RecommendationStrength.advisoryWeak,
          RecommendationStrength.advisoryStrong,
          RecommendationStrength.honestyMode,
        },
      );
    });

    test('CommuteFlexibility has the three documented cases', () {
      expect(
        CommuteFlexibility.values.toSet(),
        {
          CommuteFlexibility.required,
          CommuteFlexibility.discretionary,
          CommuteFlexibility.unknown,
        },
      );
    });
  });
}

/// Variant stub that returns null for required commutes, validating
/// the "null is acceptable" branch of the honesty rule.
class _NullForRequiredAdvisor implements PretripAdvisor {
  @override
  PretripRecommendation? advise({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) {
    if (commute.flexibility == CommuteFlexibility.required) {
      return null;
    }
    return PretripRecommendation(
      suggestedDelay: Duration.zero,
      confidenceWindow: Duration.zero,
      strength: RecommendationStrength.advisoryWeak,
      rationale: const ['ok'],
    );
  }
}
