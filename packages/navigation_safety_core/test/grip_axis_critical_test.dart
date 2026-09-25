/// Black ice under a clear sky: one axis is catastrophic, the other is fine.
///
/// **CORRECTED IN 0.11.12. THE 0.11.11 ARCHIVE SHIPPED THIS PARAGRAPH
/// UNCORRECTED, AND IT STATED THE TWO CLAIMS 0.11.11 EXISTS TO RETRACT.** It
/// read, verbatim, so that a reader who acted on it can recognise it:
///
/// > *The composite `overall` is a MEAN (`0.5 * grip + 0.5 * visibility` in
/// > `driving_conditions`). ... So a grip score of ZERO under clear air scored
/// > `info` on the default config and could NOT reach `critical` at any grip
/// > value.*
///
/// **`overall` is NOT a mean** — it is a third input the caller supplies and
/// this package only clamps — and **`critical` WAS reachable**: on 0.11.9,
/// `SafetyScore(overall: 0.2, gripScore: 1.0, visibilityScore: 1.0,
/// fleetConfidenceScore: 1.0)` returns `critical` at PERFECT grip, because the
/// composite returns `critical` whenever `overall` is below
/// `warningScoreFloor` (default 0.30). This file was the one the 0.11.11
/// changelog named as the remedy, so a reader who followed our own correction
/// to check it met the false premise in its first paragraph.
///
/// The true statement follows.
///
/// WHEN `overall` IS the 50/50 mean of the axes — which is what
/// `driving_conditions` supplies — a mean cannot express "one axis alone is
/// lethal": with visibility at 1.0, `overall >= 0.5`, while every shipped
/// `warningScoreFloor` is 0.30-0.40. So on that slice a grip score of ZERO
/// under clear air scored `info` on the default config and could not reach
/// `critical` at any grip value. Google Maps working, GPS working, sky clear,
/// road lethal — the exact condition this product exists for, and the severity
/// model had no shape in which to say it.
///
/// These tests fail on the composite-only rule and pass on the per-axis rule.
library;

import 'dart:io';

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// 1.5 / 5.5 m/s^2 — glare-ice braking deceleration over dry-pavement, both
/// values published in `navigation_safety_calibration`'s
/// `speed_dependent_visibility.dart`. Written as a literal here so this test
/// compiles against the PRE-fix API and fails on BEHAVIOUR, not on a missing
/// symbol.
const double _glareIceFloor = 1.5 / 5.5;

void main() {
  group('a single catastrophic axis reaches critical', () {
    test('zero grip + perfect visibility is critical, not info', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.5, // 0.5 * 0.0 + 0.5 * 1.0 — the mean says "half good"
        gripScore: 0.0, // she has no grip at all
        visibilityScore: 1.0, // and she can see every metre of it
        fleetConfidenceScore: 1.0,
      );

      // Pre-fix: overall 0.5 is not < 0.50 and not < 0.30, but is < 0.80,
      // so this returned AlertSeverity.info.
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('critical is reachable at perfect visibility on every profile', () {
      for (final profile in DriverProfile.values) {
        final config = NavigationSafetyConfig.forProfile(profile);
        final score = SafetyScore(
          overall: 0.5,
          gripScore: 0.0,
          visibilityScore: 1.0,
          fleetConfidenceScore: 1.0,
        );
        expect(
          score.toAlertSeverity(config),
          AlertSeverity.critical,
          reason:
              'profile $profile: with visibility 1.0 the mean can never fall '
              'below warningScoreFloor ${config.warningScoreFloor}, so critical '
              'was unreachable however bad the grip was',
        );
      }
    });

    test('grip just below the glare-ice floor is critical under clear air', () {
      final config = NavigationSafetyConfig();
      // 1.5 / 5.5 m/s^2 — the package's own glare-ice-over-dry braking ratio.
      // The comparison is STRICT, so the value tested is just below the
      // floor, not at it. The name said "at" while the body tested below;
      // a test whose name and body disagree is a test nobody can read.
      final score = SafetyScore(
        overall: 0.5 * _glareIceFloor + 0.5,
        gripScore: _glareIceFloor - 0.001,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('grip exactly AT the floor is not critical on grip alone', () {
      // The other side of the strict comparison, asserted so the boundary
      // is pinned by a test rather than by a comment.
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.5 * _glareIceFloor + 0.5,
        gripScore: _glareIceFloor,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), isNot(AlertSeverity.critical));
    });
  });

  group('the floor is pinned to its published derivation', () {
    test('the shipped floor is the glare-ice braking ratio', () {
      // A silent retune of this number is a change to when she is told the
      // road is lethal. It must be a decision, not a drift.
      expect(NavigationSafetyConfig().criticalGripScoreFloor, _glareIceFloor);
      expect(_glareIceFloor, closeTo(0.2727, 0.0001));
    });

    test('compacted snow sits well clear of the floor', () {
      // 3.0 / 5.5 — a winter road is not glare ice, and must not be told it is.
      expect(3.0 / 5.5, greaterThan(_glareIceFloor));
      expect(
        SafetyScore(
          overall: 0.5 * (3.0 / 5.5) + 0.5,
          gripScore: 3.0 / 5.5,
          visibilityScore: 1.0,
          fleetConfidenceScore: 1.0,
        ).toAlertSeverity(NavigationSafetyConfig()),
        AlertSeverity.info,
      );
    });

    test('a vehicle override cannot weaken the floor', () {
      // Severity-class, exactly like the score floors: a per-vehicle
      // transform that lowered it would re-open this gap one car at a time.
      final base = NavigationSafetyConfig();
      expect(
        () => NavigationSafetyConfig(criticalGripScoreFloor: double.nan),
        throwsArgumentError,
      );
      expect(
        () => NavigationSafetyConfig(criticalGripScoreFloor: 1.5),
        throwsRangeError,
      );
      expect(base.criticalGripScoreFloor, _glareIceFloor);
    });
  });

  group('the reverse control: ordinary conditions are not promoted', () {
    test('a good road stays silent', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.90,
        gripScore: 0.90,
        visibilityScore: 0.90,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), isNull);
    });

    test('a wet autumn road is not shouted at', () {
      final config = NavigationSafetyConfig();
      // Grip well above the glare-ice floor; visibility mediocre.
      final score = SafetyScore(
        overall: 0.5 * 0.60 + 0.5 * 0.60,
        gripScore: 0.60,
        visibilityScore: 0.60,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.info);
    });

    test('grip just above the floor does not fire critical on its own', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.5 * (_glareIceFloor + 0.01) + 0.5,
        gripScore: _glareIceFloor + 0.01,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.info);
    });

    test(
      'the per-axis rule NEVER lowers severity, over the derived-mean slice',
      () {
        // READ THE BOUND IN THE NAME. This sweep RECOMPUTES `overall` from
        // the two axes. `overall` is not derived by this package — the
        // README calls it "an `overall` score the caller supplies" — so it
        // is a THIRD independent input, and this loop walks a 2-D slice of
        // a 3-D domain. The group below sweeps the surface the constructor
        // actually accepts.
        final config = NavigationSafetyConfig();
        var promoted = 0;
        var allClearDisturbed = 0;
        const n = 101;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final grip = i / (n - 1);
            final visibility = j / (n - 1);
            final overall = 0.5 * grip + 0.5 * visibility;
            final before = _compositeOnly(config, overall);
            final after = SafetyScore(
              overall: overall,
              gripScore: grip,
              visibilityScore: visibility,
              fleetConfidenceScore: 1.0,
            ).toAlertSeverity(config);

            expect(
              _rank[after]! >= _rank[before]!,
              isTrue,
              reason:
                  'grip=$grip visibility=$visibility: severity FELL from '
                  '$before to $after — the axis rule must be monotone',
            );
            if (_rank[after]! > _rank[before]!) promoted++;
            if (before == null && after != null) allClearDisturbed++;
          }
        }
        // It does change something — a rule that promotes nothing is ornament.
        expect(promoted, greaterThan(0));
        // Zero here is ARITHMETIC, NOT EVIDENCE. On this slice, grip below
        // `criticalGripScoreFloor` (0.2727…) caps the 50/50 mean at
        // 0.5 * 0.2727… + 0.5 = 0.635, while the LOWEST `safeScoreFloor`
        // this package ships is 0.80. "silent before AND alerting after" is
        // unsatisfiable here, so this counter cannot be anything but 0
        // whatever the rule does. It is pinned to say so, not to reassure.
        expect(allClearDisturbed, 0);
      },
    );
  });

  group('the free `overall` surface the constructor accepts', () {
    // `SafetyScore` clamps each field to [0,1] and does NOTHING else: it
    // never recomputes `overall` from the axes and never checks the two
    // against each other. Any integrator whose `overall` is not our 50/50
    // mean — a different weighting, more axes, a model of their own — lives
    // OFF the slice above.
    //
    // `driving_conditions` is NOT such an integrator, and this comment said
    // it was until it was measured. BOTH of its engines produce `overall` as
    // exactly 0.5*grip + 0.5*visibility: the pure-Dart one through
    // SimulatedSafetyScore's two fixed weights, the native one per run at
    // native/native_simulation.c:104, so its `overallMean` is
    // 0.5*gripMean + 0.5*visMean by construction (compiled and swept:
    // max departure 2.09e-06, float32 rounding). No test in THIS package can
    // check that — it depends on neither `driving_conditions` nor `dart:ffi`
    // — which is exactly why the claim was writable. See CHANGELOG 0.11.11.
    late int freeCells, freePromoted, freeOutOfNone, freeLowered;
    late int slicedCells, slicedPromoted, slicedOutOfNone, slicedLowered;
    late int slicedWarningToCritical, slicedInfoToCritical;

    setUpAll(() {
      const n = 101;
      final configs = <NavigationSafetyConfig>[
        NavigationSafetyConfig(),
        ...DriverProfile.values.map(NavigationSafetyConfig.forProfile),
      ];

      slicedCells = slicedPromoted = slicedOutOfNone = slicedLowered = 0;
      slicedWarningToCritical = slicedInfoToCritical = 0;
      for (final c in configs) {
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final grip = i / (n - 1), vis = j / (n - 1);
            final overall = 0.5 * grip + 0.5 * vis;
            slicedCells++;
            final b = _compositeOnly(c, overall);
            final a = SafetyScore(
              overall: overall,
              gripScore: grip,
              visibilityScore: vis,
              fleetConfidenceScore: 1.0,
            ).toAlertSeverity(c);
            if (_rank[a]! > _rank[b]!) slicedPromoted++;
            if (_rank[a]! < _rank[b]!) slicedLowered++;
            if (b == null && a != null) slicedOutOfNone++;
            if (b == AlertSeverity.warning && a == AlertSeverity.critical) {
              slicedWarningToCritical++;
            }
            if (b == AlertSeverity.info && a == AlertSeverity.critical) {
              slicedInfoToCritical++;
            }
          }
        }
      }

      freeCells = freePromoted = freeOutOfNone = freeLowered = 0;
      for (final c in configs) {
        for (var k = 0; k < n; k++) {
          final overall = k / (n - 1);
          for (var i = 0; i < n; i++) {
            for (var j = 0; j < n; j++) {
              final grip = i / (n - 1), vis = j / (n - 1);
              freeCells++;
              final b = _compositeOnly(c, overall);
              final a = SafetyScore(
                overall: overall,
                gripScore: grip,
                visibilityScore: vis,
                fleetConfidenceScore: 1.0,
              ).toAlertSeverity(c);
              if (_rank[a]! > _rank[b]!) freePromoted++;
              if (_rank[a]! < _rank[b]!) freeLowered++;
              if (b == null && a != null) freeOutOfNone++;
            }
          }
        }
      }
    });

    test('the numbers the CHANGELOG cites are the numbers measured', () {
      // 0.11.10 printed these four counts and said they were "Asserted in
      // test/grip_axis_critical_test.dart". They were asserted nowhere.
      // They are asserted here, so the citation is true.
      expect(slicedCells, 71407);
      expect(slicedPromoted, 9721);
      expect(slicedWarningToCritical, 7723);
      expect(slicedInfoToCritical, 1998);
      expect(slicedLowered, 0);
      expect(slicedOutOfNone, 0);
    });

    test(
      'the comma-formatted counts in the 0.11.11 and 0.11.10 entries are the '
      'counts measured, in the order the entries print them — read from the '
      'file',
      () {
        // THIS TEST'S NAME ONCE PROMISED A COUPLING IT DID NOT HAVE. The
        // test above asserts integer literals and never opens CHANGELOG.md,
        // so editing the changelog failed nothing and editing that test
        // re-checked no document. The name is now what it does, and nothing
        // more: SIX comma-formatted figures inside TWO entries. The section
        // was measured at 37 distinct numeric tokens; this covers 7 of them.
        // The tolerances, the sweep dimension and two line-number citations
        // are NOT covered. An over-claimed guard is how a reader stops
        // looking.
        //
        // It is not academic. 0.11.11 quoted a tolerance that was true when
        // it published and false 28 minutes later, because the suite moved
        // and nothing re-checked the document. This closes that loop for the
        // figures below — and for those only.
        final changelog = File('${Directory.current.path}/CHANGELOG.md');
        expect(
          changelog.existsSync(),
          isTrue,
          reason:
              'CHANGELOG.md is absent, so the citations this test exists to '
              'check were NOT checked. Do not read that as a pass.',
        );
        final text = changelog.readAsStringSync();

        final from = text.indexOf('## 0.11.11');
        final to = text.indexOf('## 0.11.9');
        expect(from, greaterThanOrEqualTo(0), reason: 'no 0.11.11 entry');
        expect(to, greaterThan(from), reason: 'no 0.11.9 entry after it');
        final section = text.substring(from, to);

        // CORRECTION MARKERS ARE EXCLUDED, AND THE REASON IS MEASURED.
        //
        // An earlier version of this test argued that pinning order costs
        // nothing because these entries are published and frozen. Measured:
        // published, and NOT frozen. The 0.11.10 entry has been corrected in
        // place three times since it published, each time by adding a
        // marker — and correcting a published entry in place is this
        // package's documented practice, precisely because the archive cannot
        // be changed. Markers RE-QUOTE figures, which is why several counts
        // appear twice at all. So an ordinary future marker re-quoting a
        // correct count reddened this test while the document was right.
        //
        // Brittleness-by-design is the argument that justifies the whitelist
        // of permitted C statements in driving_conditions' native-kernel
        // test, and it does NOT transfer here. There it guards a safety
        // identity that should not change without the assertion changing with
        // it. Here it would fire on the most common edit made to these
        // entries, and a guard that cries wolf on routine work is one a
        // reader stops believing.
        //
        // COST OF THE EXCLUSION, stated rather than implied: a figure
        // re-quoted INSIDE a marker is no longer covered. Measured, that is
        // exactly one occurrence today.

        // ORDERED LIST, not a set and not a multiset.
        //
        // v1 used `contains` per figure — satisfied by any occurrence, and
        // each of these is cited TWICE, so corrupting one of the two passed.
        // v2 compared SETS, which fixed corruption to a value OUTSIDE the
        // measured set and did not fix the twice-cited case it was built for:
        // changing one of two `71,407` to `9,721` kept both sets equal.
        // A MULTISET catches that one — measured — but NOT a straight swap of
        // two figures cited the same number of times, which leaves the
        // multiset identical while both sentences become false.
        //
        // The ordered list catches both, because a transposition changes the
        // sequence. These two entries are published and, as measured above,
        // not frozen. With correction markers left out, a correction in the
        // `CORRECTED IN` shape cannot change this order; only an edit to the
        // entries' own text can, so pinning it costs nothing such an edit
        // should not pay.
        const allowedNonMeasurements = <int>{
          200000, // the run-count range the driving_conditions suite asserts
        };
        final measured = <int>{
          slicedCells,
          slicedPromoted,
          slicedWarningToCritical,
          slicedInfoToCritical,
          freeCells,
          freeOutOfNone,
        };

        List<int> citedIn(String s) => RegExp(r'[0-9]{1,3}(?:,[0-9]{3})+')
            .allMatches(s)
            .map((m) => int.parse(m.group(0)!.replaceAll(',', '')))
            .toList();

        final prose = _withoutCorrectionMarkers(section);
        final cited = citedIn(prose);
        final expected = <int>[
          freeCells,
          freeOutOfNone,
          200000,
          slicedCells,
          slicedPromoted,
          slicedWarningToCritical,
          slicedInfoToCritical,
          slicedCells,
          slicedPromoted,
          slicedWarningToCritical,
          slicedInfoToCritical,
        ];
        expect(
          cited,
          expected,
          reason:
              'the comma-formatted figures in the 0.11.11/0.11.10 entries are '
              'no longer the measured ones in the order the entries print '
              'them. Either an entry was edited away from what was measured, '
              'or a measurement moved and the entry did not follow it — which '
              'is exactly how 0.11.11 came to quote a tolerance that was true '
              'when it published and false 28 minutes later.',
        );
        expect(
          cited.toSet().difference(measured).difference(allowedNonMeasurements),
          isEmpty,
          reason: 'a cited figure is not one this test measured',
        );

        // CONTROLS, BOTH SIDES.
        //
        // OUT-OF-SET: a value no measurement produces.
        expect(
          citedIn(_withoutCorrectionMarkers(section.replaceFirst(
            _thousands(freeOutOfNone),
            _thousands(freeOutOfNone + 1),
          ))),
          isNot(expected),
          reason: 'an out-of-set corruption was not detected',
        );
        // IN-SET, ONE OF TWO — the case being cited twice used to rescue, and
        // the side v2's control never touched.
        expect(
          citedIn(_withoutCorrectionMarkers(section.replaceFirst(
            _thousands(slicedCells),
            _thousands(slicedPromoted),
          ))),
          isNot(expected),
          reason:
              'changing ONE of two occurrences of a cited figure to ANOTHER '
              'MEASURED figure was not detected — the exact case that passed '
              'the set comparison',
        );
        // IN-SET, TRANSPOSITION — multiset-invariant, so only order sees it.
        expect(
          citedIn(_withoutCorrectionMarkers(section
              .replaceAll(_thousands(slicedWarningToCritical), '@@')
              .replaceAll(
                  _thousands(slicedInfoToCritical), _thousands(slicedWarningToCritical))
              .replaceAll('@@', _thousands(slicedInfoToCritical)))),
          isNot(expected),
          reason:
              'swapping two figures cited the same number of times was not '
              'detected; a multiset cannot see this and a set cannot either',
        );
        // AND THE OTHER SIDE OF A CONTROL: it must NOT fire on the routine
        // edit. Adding a correction marker that re-quotes a correct figure is
        // what is done to these entries constantly, and it reddened the
        // previous version while the document was right.
        expect(
          citedIn(_withoutCorrectionMarkers(section.replaceFirst(
            '- ${_thousands(slicedPromoted)} cells change',
            '- ${_thousands(slicedPromoted)} cells change\n'
                '  **CORRECTED IN 0.11.13 — the wording above.** The '
                '${_thousands(slicedPromoted)} figure is right.\n',
          ))),
          expected,
          reason:
              'adding an ordinary correction marker that re-quotes a CORRECT '
              'figure made this test red. That is a false red on the most '
              'common edit these entries receive.',
        );
      },
    );

    test('no alert 0.11.9 delivers is silenced, on the WHOLE surface', () {
      // The safety property, and the one that must never break. It holds
      // off the slice as well as on it: 7,212,107 cells, none lowered.
      expect(freeCells, 7212107);
      expect(freeLowered, 0);
      expect(freePromoted, 1357440);
    });

    test('the release DOES speak where 0.11.9 was silent', () {
      // 0.11.10's CHANGELOG said it "cannot make the package speak where
      // 0.11.9 was silent". Off the derived slice it can, and this is the
      // count. A test that could not have produced this number is a test
      // that proved nothing.
      expect(
        freeOutOfNone,
        359156,
        reason:
            'cells that are silent on 0.11.9 and alerting on 0.11.10, over '
            'the free (overall, grip, visibility) surface on all seven '
            'configs — new alert volume an integrator must expect',
      );
    });

    test('the probe that the derived slice could not reach', () {
      // Measured against the PUBLISHED 0.11.9 archive: `null`.
      // A legal construction: every field is in [0,1].
      final score = SafetyScore(
        overall: 0.8, // NOT 0.5 * 0.0 + 0.5 * 1.0 — the caller's own number
        gripScore: 0.0, // the road brakes like glare ice
        visibilityScore: 1.0, // under a clear sky
        fleetConfidenceScore: 1.0,
      );
      expect(
        score.toAlertSeverity(NavigationSafetyConfig()),
        AlertSeverity.critical,
      );
      // And it is unreachable on the derived slice: with grip 0.0 the
      // 50/50 mean is at most 0.5, never 0.8.
      expect(0.5 * 0.0 + 0.5 * 1.0, lessThan(0.8));
    });
  });
}

const _rank = <AlertSeverity?, int>{
  null: 0,
  AlertSeverity.info: 1,
  AlertSeverity.warning: 2,
  AlertSeverity.critical: 3,
};

/// The 0.11.9 rule, recomputed so the comparison is against behaviour and
/// not a remembered table. Verified against the published 0.11.9 archive:
/// composite-only, against these same three floors.
AlertSeverity? _compositeOnly(NavigationSafetyConfig c, double overall) {
  if (overall < c.warningScoreFloor) return AlertSeverity.critical;
  if (overall < c.infoScoreFloor) return AlertSeverity.warning;
  if (overall < c.safeScoreFloor) return AlertSeverity.info;
  return null;
}

/// Renders [n] with thousands separators, the way the CHANGELOG writes them.
String _thousands(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Drops correction-marker blocks from [section].
///
/// A marker runs from the line carrying `CORRECTED IN` to the next blank line.
/// Markers re-quote figures by design — that is what makes a correction
/// recognisable to a reader who acted on the old wording — so counting their
/// figures makes routine, correct corrections fail.
String _withoutCorrectionMarkers(String section) {
  final out = StringBuffer();
  var inMarker = false;
  for (final line in section.split('\n')) {
    if (line.contains('CORRECTED IN ')) inMarker = true;
    if (inMarker && line.trim().isEmpty) inMarker = false;
    if (!inMarker) out.writeln(line);
  }
  return out.toString();
}
