import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

/// Minimal in-test advisor used to exercise the abstract contract.
///
/// This is NOT a reference implementation. It encodes only the
/// interface-level rules the contract requires:
/// - required-commute -> never advisoryStrong delay (honestyMode or null)
/// - any-ice in window + discretionary -> may suggest a delay
/// - empty forecast -> null (degrade gracefully)
class _MockAdvisor extends PretripAdvisor {
  const _MockAdvisor();

  @override
  PretripRecommendation? advise({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) {
    if (forecast.hours.isEmpty) return null;

    final hasIce = forecast.hours
        .any((h) => h.roadCondition == RoadConditionEstimate.ice);

    if (commute.flexibility == CommuteFlexibility.required) {
      if (!hasIce) return null;
      return const PretripRecommendation(
        strength: RecommendationStrength.honestyMode,
        delay: Duration.zero,
        rationaleTag: 'required_commute_ice_in_window',
      );
    }

    if (!hasIce) {
      return const PretripRecommendation(
        strength: RecommendationStrength.advisoryWeak,
        delay: Duration.zero,
      );
    }

    return const PretripRecommendation(
      strength: RecommendationStrength.advisoryStrong,
      delay: Duration(minutes: 45),
      rationaleTag: 'ice_window_suggests_delay',
    );
  }
}

WeatherForecast _forecast(List<RoadConditionEstimate> conditions) {
  final base = DateTime(2026, 1, 15, 7);
  return WeatherForecast(
    hours: [
      for (var i = 0; i < conditions.length; i++)
        HourlyForecast(
          localHourStart: base.add(Duration(hours: i)),
          airTemperatureC: -2.0,
          roadCondition: conditions[i],
        ),
    ],
  );
}

const _profile = DriverProfileSpec(
  profileTag: 'ageingRural',
  reactionTimeSeconds: 1.4,
  unfamiliarRouteFlag: false,
);

void main() {
  const advisor = _MockAdvisor();

  test('required commute never returns advisoryStrong delay', () {
    final rec = advisor.advise(
      forecast: _forecast([
        RoadConditionEstimate.ice,
        RoadConditionEstimate.ice,
        RoadConditionEstimate.packedSnow,
      ]),
      commute: const CommuteShape(
        flexibility: CommuteFlexibility.required,
        estimatedDriveDuration: Duration(minutes: 25),
      ),
      profile: _profile,
    );
    expect(rec, isNotNull);
    expect(rec!.strength, RecommendationStrength.honestyMode);
    expect(rec.delay, Duration.zero);
    expect(rec.strength, isNot(RecommendationStrength.advisoryStrong));
  });

  test('discretionary + clear forecast may return zero-delay weak advisory',
      () {
    final rec = advisor.advise(
      forecast: _forecast([
        RoadConditionEstimate.dry,
        RoadConditionEstimate.dry,
      ]),
      commute: const CommuteShape(
        flexibility: CommuteFlexibility.discretionary,
        estimatedDriveDuration: Duration(minutes: 30),
      ),
      profile: _profile,
    );
    expect(rec, isNotNull);
    expect(rec!.delay, Duration.zero);
    expect(rec.strength, RecommendationStrength.advisoryWeak);
  });

  test('discretionary + ice forecast may suggest waiting', () {
    final rec = advisor.advise(
      forecast: _forecast([
        RoadConditionEstimate.ice,
        RoadConditionEstimate.slush,
        RoadConditionEstimate.wet,
      ]),
      commute: const CommuteShape(
        flexibility: CommuteFlexibility.discretionary,
        estimatedDriveDuration: Duration(minutes: 30),
      ),
      profile: _profile,
    );
    expect(rec, isNotNull);
    expect(rec!.strength, RecommendationStrength.advisoryStrong);
    expect(rec.delay, greaterThan(Duration.zero));
  });

  test('empty forecast degrades to null (no silent strong advisory)', () {
    final rec = advisor.advise(
      forecast: const WeatherForecast(hours: []),
      commute: const CommuteShape(
        flexibility: CommuteFlexibility.discretionary,
        estimatedDriveDuration: Duration(minutes: 20),
      ),
      profile: _profile,
    );
    expect(rec, isNull);
  });

  test('DTO equality + hashCode round-trip', () {
    const a = PretripRecommendation(
      strength: RecommendationStrength.advisoryWeak,
      delay: Duration(minutes: 10),
      rationaleTag: 'tag_x',
    );
    const b = PretripRecommendation(
      strength: RecommendationStrength.advisoryWeak,
      delay: Duration(minutes: 10),
      rationaleTag: 'tag_x',
    );
    const c = PretripRecommendation(
      strength: RecommendationStrength.advisoryStrong,
      delay: Duration(minutes: 10),
      rationaleTag: 'tag_x',
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));

    final f1 = _forecast([RoadConditionEstimate.ice]);
    final f2 = _forecast([RoadConditionEstimate.ice]);
    expect(f1, equals(f2));
    expect(f1.hashCode, equals(f2.hashCode));

    const cs1 = CommuteShape(
      flexibility: CommuteFlexibility.unknown,
      estimatedDriveDuration: Duration(minutes: 15),
    );
    const cs2 = CommuteShape(
      flexibility: CommuteFlexibility.unknown,
      estimatedDriveDuration: Duration(minutes: 15),
    );
    expect(cs1, equals(cs2));
    expect(cs1.hashCode, equals(cs2.hashCode));
  });

  test('RecommendationStrength enum is exhaustively three-valued', () {
    expect(RecommendationStrength.values, hasLength(3));
    expect(
      RecommendationStrength.values.toSet(),
      {
        RecommendationStrength.advisoryWeak,
        RecommendationStrength.advisoryStrong,
        RecommendationStrength.honestyMode,
      },
    );
  });

  test('CommuteFlexibility enum is exhaustively three-valued', () {
    expect(CommuteFlexibility.values, hasLength(3));
    expect(
      CommuteFlexibility.values.toSet(),
      {
        CommuteFlexibility.required,
        CommuteFlexibility.discretionary,
        CommuteFlexibility.unknown,
      },
    );
  });
}
