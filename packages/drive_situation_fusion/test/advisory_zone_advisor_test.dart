import 'package:drive_situation_fusion/src/advisory_zone_advisor.dart';
import 'package:test/test.dart';

/// Representative advisory type (mirrors snow_rendering's RecommendedResponse),
/// used here to keep the generic element under test dependency-free.
enum Advice { proceed, conditionsUnknown, reduceSpeed, considerTurningBack }

/// A circular zone helper: contains a fix within [radius] degrees of (lat, lon).
AdvisoryZone<Advice> circle(
  Object id,
  Advice advisory,
  double lat,
  double lon,
  double radius,
) {
  return AdvisoryZone<Advice>(
    id: id,
    advisory: advisory,
    contains: (f) =>
        (f.lat - lat).abs() <= radius && (f.lon - lon).abs() <= radius,
  );
}

void main() {
  ZoneAdvisor<Advice> build() => ZoneAdvisor<Advice>(
        baseline: Advice.proceed,
        uncertain: Advice.conditionsUnknown,
        zones: [
          // Most-cautious first: overlap resolves to the strongest hazard.
          circle('bridge', Advice.considerTurningBack, 10, 10, 0.5),
          circle('ice', Advice.reduceSpeed, 10, 10, 2.0),
        ],
      );

  test('trusted fix outside every zone -> baseline (proceed)', () {
    final a = build();
    expect(a.update(const HazardFix(0, 0)), Advice.proceed);
    expect(a.currentZoneId, isNull);
  });

  test('entering a hazard zone yields that zone advisory', () {
    final a = build();
    expect(a.update(const HazardFix(10, 12)), Advice.reduceSpeed); // ice ring only
    expect(a.currentZoneId, 'ice');
  });

  test('overlap resolves to the most-cautious zone (bridge over ice)', () {
    final a = build();
    expect(a.update(const HazardFix(10, 10)), Advice.considerTurningBack);
    expect(a.currentZoneId, 'bridge');
  });

  test('leaving the zone with a trusted fix reverts cleanly to baseline', () {
    final a = build();
    a.update(const HazardFix(10, 10)); // considerTurningBack
    expect(a.update(const HazardFix(0, 0)), Advice.proceed); // no stale warning
    expect(a.currentZoneId, isNull);
  });

  test('untrusted fix HOLDS the last caution (a bad pixel never un-warns her)', () {
    final a = build();
    a.update(const HazardFix(10, 10)); // considerTurningBack
    // GPS goes bad: hold the caution, do not drop to proceed.
    expect(a.update(const HazardFix(0, 0, trusted: false)),
        Advice.considerTurningBack);
    expect(a.update(null), Advice.considerTurningBack);
  });

  test('untrusted fix at baseline escalates to uncertain (honest degradation)', () {
    final a = build();
    a.update(const HazardFix(0, 0)); // proceed
    expect(a.update(const HazardFix(0, 0, trusted: false)),
        Advice.conditionsUnknown);
  });

  test('recovers: after a trusted fix returns, it re-evaluates zones', () {
    final a = build();
    a.update(const HazardFix(10, 10)); // considerTurningBack
    a.update(null); // hold
    expect(a.update(const HazardFix(0, 0)), Advice.proceed); // trusted again -> out
  });
}
