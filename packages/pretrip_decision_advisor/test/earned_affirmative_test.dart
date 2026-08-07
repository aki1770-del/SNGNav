/// The area warning line is the one place this package makes a NEGATIVE claim:
/// "no snow warning or advisory is in force for this area."
///
/// That sentence is a claim about COMPLETENESS — it is only true if we actually
/// asked a publisher and the publisher actually answered. Up to 0.5.2 we made it
/// for free: `warningCheckAvailable` defaulted to `true`, so a caller who never
/// reached a publisher at all still rendered "No active snow warning or advisory
/// for this area." out of a check that never happened.
///
/// And the branch order made honesty expensive: `!warningCheckAvailable` was
/// tested FIRST, so a caller who held a real 大雪警報 but admitted their check
/// was incomplete had the warning REPLACED by "check unavailable".
///
/// Both halves of the asymmetry are pinned here, and it is `condition_aggregator`'s
/// AdvisoryLookup doctrine verbatim:
///
///   Positive evidence fires on partial knowledge.
///   Negative conclusions require whole knowledge.
///
/// These tests exist because the 0.5.2 suite had 86 green tests and not ONE of
/// them ever asserted what a zero-effort call renders. The lie shipped through
/// the rigor, because nothing looked at the path that lied.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

const _enWarning =
    'Official winter warning or advisory in effect for this area: 大雪警報.';
const _enNone = 'No active snow warning or advisory for this area.';
const _enUnavailable = 'Official-warning check unavailable — a warning may be '
    'in effect that is not shown here.';

const _jaWarning = 'この地域で発表中の警報・注意報: 大雪警報。';
const _jaNone = 'この地域に発表中の雪の警報・注意報はありません。';
const _jaUnavailable = '警報・注意報の確認ができませんでした — 実際には発表されている可能性があります。';

void main() {
  final now = DateTime(2026, 2, 8, 5);

  // A benign, fully-populated slot: the forecast is NOT what these tests are
  // about, so it must never be the reason a chip moves.
  WeatherForecast benign() => WeatherForecast(
        hourly: [
          HourlyForecast(
            hour: now,
            tempCelsius: 4,
            precipitationMmPerHour: 0,
            visibilityMeters: 20000,
            estimatedRoadCondition: RoadConditionEstimate.dry,
          ),
        ],
        issuedAt: now,
      );

  /// The area read for a given publisher state. `warning` is what the publisher
  /// currently has in force (null = nothing in force); `checkComplete` is
  /// whether we actually reached it.
  AreaConditionRead read({String? warning, required bool checkComplete}) =>
      summarizeAreaConditions(
        forecast: benign(),
        now: now,
        areaLabel: '秋田県内陸南部',
        warningEventVerbatim: warning,
        warningCheckAvailable: checkComplete,
      );

  String warningChip(AreaConditionRead r, PretripMessages m) =>
      areaConditionChips(r, m).first;

  group('the negative claim must be EARNED (0.5.3 default flip)', () {
    test(
        'the zero-effort call no longer fabricates an all-clear: no publisher '
        'reached => "check unavailable", NOT "none in force"', () {
      // Neither a warning nor the flag: the caller has told us nothing about
      // whether they ever asked anyone. Up to 0.5.2 this rendered the
      // affirmative. It is a check that never happened.
      final r = summarizeAreaConditions(
        forecast: benign(),
        now: now,
        areaLabel: '秋田県内陸南部',
      );

      expect(r.warningCheckAvailable, isFalse,
          reason: 'the default must fail safe: we did not ask anyone');
      expect(warningChip(r, PretripMessages.en), _enUnavailable);
      expect(warningChip(r, PretripMessages.ja), _jaUnavailable);

      // The load-bearing guarantee: you MAY NOT tell her nothing is in force.
      expect(areaConditionChips(r, PretripMessages.en), isNot(contains(_enNone)));
      expect(areaConditionChips(r, PretripMessages.ja), isNot(contains(_jaNone)));
    });

    test(
        'the affirmative SURVIVES and is still reachable — an asserted-complete '
        'check with nothing in force still says so', () {
      // This is the whole point of the flip: we are gating the sentence, not
      // deleting it. A caller who reached the publisher and got nothing back
      // has EARNED the negative claim, and renders exactly as in 0.5.2.
      final r = read(warning: null, checkComplete: true);

      expect(warningChip(r, PretripMessages.en), _enNone);
      expect(warningChip(r, PretripMessages.ja), _jaNone);
    });
  });

  group('a hazard seen is a hazard real, even on partial data (0.5.3 reorder)',
      () {
    test(
        'REGRESSION: a warning in hand renders even when the check was '
        'INCOMPLETE — admitting a gap must not cost her the warning', () {
      // The 0.5.2 defect, exactly: one publisher answered with 大雪警報, a second
      // publisher failed, so the caller honestly reports the check incomplete.
      // Up to 0.5.2 the !warningCheckAvailable branch ran first and the
      // heavy-snow warning was replaced by a shrug.
      final r = read(warning: '大雪警報', checkComplete: false);

      expect(warningChip(r, PretripMessages.en), _enWarning);
      expect(warningChip(r, PretripMessages.ja), _jaWarning);

      // The shrug must NOT have swallowed it.
      expect(areaConditionChips(r, PretripMessages.ja),
          isNot(contains(_jaUnavailable)));
    });

    test('a warning in hand with a complete check renders identically', () {
      // Positive evidence does not care about completeness: same sentence.
      final partial = read(warning: '大雪警報', checkComplete: false);
      final complete = read(warning: '大雪警報', checkComplete: true);

      expect(warningChip(partial, PretripMessages.ja), _jaWarning);
      expect(warningChip(complete, PretripMessages.ja), _jaWarning);
      expect(warningChip(partial, PretripMessages.ja),
          warningChip(complete, PretripMessages.ja));
    });
  });

  group('THE RUNG COMES DOWN — and its release is the authority\'s, not ours',
      () {
    test(
        'authority withdraws the warning => the chip FALLS from 大雪警報 to the '
        'earned affirmative, with nothing else changed', () {
      // Thursday: the publisher has 大雪警報 in force. We reached it.
      final thursday = read(warning: '大雪警報', checkComplete: true);
      expect(warningChip(thursday, PretripMessages.ja), _jaWarning);

      // Sunday: the SAME complete check, the SAME benign forecast, the SAME
      // code — the publisher has simply withdrawn the warning. That is the only
      // thing in the world that changed.
      final sunday = read(warning: null, checkComplete: true);
      expect(warningChip(sunday, PretripMessages.ja), _jaNone);
      expect(warningChip(sunday, PretripMessages.en), _enNone);

      // The rung fell. Nothing we shipped released it; the weather did.
      expect(warningChip(thursday, PretripMessages.ja),
          isNot(warningChip(sunday, PretripMessages.ja)));
    });

    test(
        'the fall is NOT on our release schedule: no parser update, no new '
        'version, no integrator call releases it — only the publisher', () {
      // Every input except the publisher's own declaration is held fixed.
      // The single bit that moves the chip is the authority's verbatim.
      for (final warning in <String?>['大雪警報', null]) {
        final r = read(warning: warning, checkComplete: true);
        expect(
          warningChip(r, PretripMessages.ja),
          warning == null ? _jaNone : _jaWarning,
          reason: 'the chip tracks the publisher and nothing else',
        );
      }
    });
  });

  group('IT DOES NOT FLAP — there is no latch in either direction', () {
    test('pure: identical inputs render identically across repeated calls', () {
      // A ratchet is a latch. A latch is hidden state. If repeated identical
      // calls can disagree, there is state here that could stick.
      final first = areaConditionChips(
          read(warning: null, checkComplete: true), PretripMessages.ja);
      for (var i = 0; i < 50; i++) {
        expect(
          areaConditionChips(
              read(warning: null, checkComplete: true), PretripMessages.ja),
          first,
        );
      }
    });

    test(
        'no stickiness up OR down: warning -> withdrawn -> warning -> withdrawn '
        'tracks the publisher exactly, with no memory of the prior state', () {
      // The failure this catches: a rung that, having once been raised, stays
      // raised (the ratchet) — or, having once fallen, refuses to rise again
      // (the mirror defect, which would be far worse).
      final sequence = <String?>[
        '大雪警報',
        null,
        '大雪警報',
        null,
        null,
        '大雪警報',
        '大雪警報',
        null,
      ];

      final rendered = [
        for (final w in sequence)
          warningChip(read(warning: w, checkComplete: true), PretripMessages.ja),
      ];

      expect(rendered, [
        _jaWarning,
        _jaNone,
        _jaWarning,
        _jaNone,
        _jaNone,
        _jaWarning,
        _jaWarning,
        _jaNone,
      ]);
    });

    test(
        'order-independence: the chip for a given publisher state is the same '
        'whether it was reached from a warning or from an all-clear', () {
      // Feed the states in both directions; each read must depend only on its
      // own input, never on what was rendered before it.
      final downThenUp = [
        warningChip(read(warning: '大雪警報', checkComplete: true),
            PretripMessages.ja),
        warningChip(read(warning: null, checkComplete: true), PretripMessages.ja),
      ];
      final upThenDown = [
        warningChip(read(warning: null, checkComplete: true), PretripMessages.ja),
        warningChip(read(warning: '大雪警報', checkComplete: true),
            PretripMessages.ja),
      ];

      expect(downThenUp, [_jaWarning, _jaNone]);
      expect(upThenDown, [_jaNone, _jaWarning]);
    });
  });

  group('the claim ceiling is not crossed by any of this', () {
    test('no chip claims a road, a route, or passability', () {
      for (final w in <String?>['大雪警報', null]) {
        for (final complete in [true, false]) {
          for (final m in [PretripMessages.en, PretripMessages.ja]) {
            final chips =
                areaConditionChips(read(warning: w, checkComplete: complete), m);
            for (final chip in chips) {
              for (final banned in const [
                'passable',
                'safe to drive',
                'clear to go',
                'go ahead',
                '通行可能',
                '安全',
                '走行可能',
                '大丈夫',
              ]) {
                expect(chip.toLowerCase(), isNot(contains(banned.toLowerCase())),
                    reason: 'the subject is the AREA and the publisher\'s '
                        'declaration — never her road');
              }
            }
          }
        }
      }
    });
  });
}
