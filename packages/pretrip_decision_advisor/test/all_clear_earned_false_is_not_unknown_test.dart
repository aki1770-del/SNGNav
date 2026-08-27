/// `allClearEarned() == false` must NEVER be readable as "we do not know".
///
/// It is false in two OPPOSITE situations, and an integrator who branches
/// `if (!allClearEarned) renderUnknown()` replaces a measured frost caution
/// with an "unknown" card on the morning the driver needed it. That is the
/// same absence-rendered-as-a-conclusion defect this release exists to close,
/// reachable through the API this release ADDS.
///
/// This is an opposed pair. If a future change ever makes `false` mean only
/// "unassessable", U1 keeps passing while M1 fails. If it ever makes an
/// unmeasured window earn the all-clear, U1 fails. Either direction is caught.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

void main() {
  final base = DateTime.utc(2026, 1, 15, 7, 0);
  const advisor = SnowAwarePretripAdvisor();
  const profile = DriverProfileSpec(
    profileTag: 'her',
    reactionTimeSeconds: 1.5,
  );
  final commute = CommuteShape(
    plannedDuration: const Duration(minutes: 30),
    routeIdentifiers: const ['akita'],
    flexibility: CommuteFlexibility.discretionary,
    plannedDeparture: base,
  );

  WeatherForecast tempOnly(double c) => WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(hour: base, tempCelsius: c),
      HourlyForecast(hour: base.add(const Duration(hours: 1)), tempCelsius: c),
    ],
  );

  group('allClearEarned() == false is not a claim of ignorance', () {
    test(
      'U1 UNASSESSABLE — a 5C temperature-only window: false, and brief() THROWS',
      () {
        final f = tempOnly(5.0);
        expect(advisor.allClearEarned(forecast: f, commute: commute), isFalse);
        expect(
          () => advisor.brief(forecast: f, commute: commute, profile: profile),
          throwsA(isA<PretripAssessmentIncompleteException>()),
          reason: 'an unmeasured window must not earn the affirmative',
        );
      },
    );

    test('M1 MEASURED HAZARD — a -6C temperature-only window: ALSO false, but '
        'brief() RETURNS a measured caution', () {
      final f = tempOnly(-6.0);
      expect(
        advisor.allClearEarned(forecast: f, commute: commute),
        isFalse,
        reason: 'a measured hazard is not "earned all-clear" territory',
      );
      final b = advisor.brief(forecast: f, commute: commute, profile: profile);
      expect(
        b.peakHazard,
        isNot(HourHazard.unknown),
        reason:
            'THE POINT: allClearEarned was false, yet this window WAS '
            'assessed. Rendering "unknown" here suppresses a measurement.',
      );
      expect(b.chips, isNotEmpty);
    });

    test('U1/M1 agree on false while disagreeing on what is known', () {
      expect(
        advisor.allClearEarned(forecast: tempOnly(5.0), commute: commute),
        advisor.allClearEarned(forecast: tempOnly(-6.0), commute: commute),
        reason:
            'both false — which is exactly why false cannot carry the '
            'unknown/measured distinction, and why the throw must',
      );
    });
  });
}
