import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

/// Parse an `HH:MM` clock string to minutes-from-midnight.
int _min(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

void _closeTo(String? actual, String expected, int toleranceMin, String why) {
  expect(actual, isNotNull, reason: '$why: expected ~$expected, got null');
  final diff = (_min(actual!) - _min(expected)).abs();
  expect(
    diff <= toleranceMin,
    isTrue,
    reason: '$why: $actual not within $toleranceMin min of $expected',
  );
}

// Word fragments that would mean the daylight chip fabricated a road hazard
// from the clock alone — the cardinal sin this feature must not commit. Covers
// the genuinely-fabricatable ROAD-hazard vocabulary the advisor's own chips use
// (snow / packed / whiteout / precipitation / fog as well as ice family).
// Deliberately EXCLUDES 'visibility' / '視界': the daylight chip is darkness-only
// and never borrows the forecast's measured-visibility noun, so those would be
// the right thing to assert ABSENT — and the chip already omits them.
const _hazardFragments = <String>[
  'ice',
  'freez',
  'frost',
  'black ice',
  'refro',
  'slick',
  'slush',
  'snow',
  'packed',
  'whiteout',
  'precip',
  'fog',
  '凍',
  '氷',
  '霜',
  '滑',
  '雪',
  '圧雪',
  '降水',
  'ホワイトアウト',
];

void _assertNoFabricatedHazard(String chip) {
  for (final f in _hazardFragments) {
    expect(
      chip.toLowerCase().contains(f.toLowerCase()),
      isFalse,
      reason: 'daylight chip must not assert a hazard; found "$f" in: $chip',
    );
  }
}

// Geographies (lat N+, lon E+, civil offset).
const _akita = TripGeo(
  latitude: 39.72,
  longitude: 140.10,
  utcOffset: Duration(hours: 9),
);
const _tokyo = TripGeo(
  latitude: 35.69,
  longitude: 139.69,
  utcOffset: Duration(hours: 9),
);
const _london = TripGeo(
  latitude: 51.51,
  longitude: -0.13,
  utcOffset: Duration(),
);
const _anchorage = TripGeo(
  latitude: 61.22,
  longitude: -149.90,
  utcOffset: Duration(hours: -9),
);
const _tromso = TripGeo(
  latitude: 69.65,
  longitude: 18.96,
  utcOffset: Duration(hours: 1),
);
// High Arctic (e.g. Svalbard latitude): at midwinter the sun never reaches even
// civil twilight, so polar night is DEEP DARK all day.
const _highArctic = TripGeo(
  latitude: 80.0,
  longitude: 15.0,
  utcOffset: Duration(hours: 1),
);

/// A forecast with all-clear slots spanning [fromHour, toHour] on the given day.
WeatherForecast _clearForecast(DateTime day, int fromHour, int toHour) {
  final slots = <HourlyForecast>[
    for (var h = fromHour; h <= toHour; h++)
      HourlyForecast(
        hour: DateTime(day.year, day.month, day.day, h),
        tempCelsius: 5.0, // above frost; no precip; good visibility => clear
        precipitationMmPerHour: 0.0,
        visibilityMeters: 10000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      ),
  ];
  return WeatherForecast(hourly: slots, issuedAt: day);
}

const _fastDriver = DriverProfileSpec(
  profileTag: 'test',
  reactionTimeSeconds: 1.0,
);

void main() {
  group('NOAA solar anchors (offline astronomy)', () {
    test(
      'Akita 2026-01-15 — real external anchor (sunrise 06:59 / sunset 16:38, ±2)',
      () {
        // Morning instant resolves the same day's sunrise/sunset.
        final d = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
        _closeTo(d.sunriseHHMM, '06:59', 2, 'Akita sunrise');
        _closeTo(d.sunsetHHMM, '16:38', 2, 'Akita sunset');
      },
    );

    test(
      'Tokyo 2026-01-15 — sunrise ~06:50 / sunset ~16:51 (real external anchor, ±2)',
      () {
        final d = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _tokyo);
        // Both halves pinned tight to the authoritative NOAA/USNO values at
        // 35.69N/139.69E with the standard 90.833° refraction allowance: sunrise
        // ~06:50, sunset ~16:51 JST. (16:51 — not the often-mis-cited ~16:47 — is
        // the correct astronomical value; the algorithm here is the full
        // NOAA/Meeus method with a refinement pass, so this is a genuine external
        // anchor, not a self-referential bracket.)
        _closeTo(d.sunriseHHMM, '06:50', 2, 'Tokyo sunrise');
        _closeTo(d.sunsetHHMM, '16:51', 2, 'Tokyo sunset');
      },
    );

    test('London 2026-01-15 — sunrise ~07:58 / sunset ~16:21', () {
      final d = evaluateDaylight(DateTime(2026, 1, 15, 7, 0), _london);
      expect(
        _min(d.sunriseHHMM!),
        inInclusiveRange(_min('07:56'), _min('08:01')),
        reason: 'London sunrise: ${d.sunriseHHMM}',
      );
      expect(
        _min(d.sunsetHHMM!),
        inInclusiveRange(_min('16:18'), _min('16:24')),
        reason: 'London sunset: ${d.sunsetHHMM}',
      );
    });

    test(
      'Tromso 2025-12-21 — POLAR NIGHT: sunrise & sunset are NULL (never fabricated)',
      () {
        final d = evaluateDaylight(DateTime(2025, 12, 21, 11, 0), _tromso);
        expect(d.phase, DaylightPhase.polarNight);
        expect(d.sunriseHHMM, isNull);
        expect(d.sunsetHHMM, isNull);
        expect(d.eventHHMM, isNull);
        expect(d.isLowLight, isTrue);
        // The chip states the sun does not rise; it invents no time.
        _assertNoFabricatedHazard(PretripMessages.en.daylightChip(d));
        _assertNoFabricatedHazard(PretripMessages.ja.daylightChip(d));
        expect(PretripMessages.en.daylightChip(d), contains('does not rise'));
        expect(PretripMessages.ja.daylightChip(d), contains('日が昇りません'));
      },
    );
  });

  group('midnight-wrap (event minutes > 1440 roll across the UTC day)', () {
    // The NEGATIVE-wrap side (event UTC on the PRIOR day, minutesUTC < 0) is
    // already exercised by the Akita anchor test above — Akita sunrise 06:59 JST
    // is 21:59 UTC the previous day, so that ±2 pin fails first if the wrap
    // breaks; a byte-identical duplicate here added no extra signal and was
    // removed. The Anchorage case below is the genuinely-distinct >1440 path.
    test(
      'Anchorage sunset — event UTC is the NEXT day (minutes > 1440), local ~16:xx',
      () {
        // Anchorage (UTC-9) sunset ~16:1x AKST == ~01:1x UTC next day: minutesUTC
        // > 1440 relative to the local date's 0Z. Local clock must still read 16:xx.
        final d = evaluateDaylight(DateTime(2026, 1, 15, 18, 0), _anchorage);
        expect(d.sunriseHHMM, isNotNull);
        expect(
          _min(d.sunsetHHMM!),
          inInclusiveRange(_min('16:05'), _min('16:30')),
          reason: 'Anchorage >1440-wrap sunset: ${d.sunsetHHMM}',
        );
        expect(d.phase, DaylightPhase.postDusk); // 18:00 is after sunset
      },
    );
  });

  group('wall-clock semantics (correction c: isUtc-independent)', () {
    test(
      'same wall-clock fields => same result whether DateTime is local or utc',
      () {
        final local = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
        final asUtc = evaluateDaylight(
          DateTime.utc(2026, 1, 15, 6, 30),
          _akita,
        );
        expect(asUtc.sunriseHHMM, local.sunriseHHMM);
        expect(asUtc.sunsetHHMM, local.sunsetHHMM);
        expect(asUtc.phase, local.phase);
        expect(asUtc.eventHHMM, local.eventHHMM);
        expect(asUtc.minutesToEvent, local.minutesToEvent);
      },
    );

    test(
      'minutesToEvent has the right magnitude and sign (never negative)',
      () {
        // 06:30 with sunrise ~06:59 => ~29 min to the coming sunrise.
        final pre = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
        expect(
          pre.minutesToEvent,
          inInclusiveRange(27, 31),
          reason: 'pre-dawn minutes-to-sunrise: ${pre.minutesToEvent}',
        );
        // 18:00 with sunset ~16:38 => ~82 min since the passed sunset.
        final post = evaluateDaylight(DateTime(2026, 1, 15, 18, 0), _akita);
        expect(
          post.minutesToEvent,
          inInclusiveRange(80, 84),
          reason: 'post-dusk minutes-since-sunset: ${post.minutesToEvent}',
        );
      },
    );
  });

  group('reference-instant selection (correction b)', () {
    test(
      'pre-dawn instant names the COMING sunrise (same day, not prior day)',
      () {
        final d = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
        expect(d.phase, DaylightPhase.preDawn);
        _closeTo(
          d.eventHHMM,
          '06:59',
          2,
          'pre-dawn reference = coming sunrise',
        );
        expect(d.eventHHMM, d.sunriseHHMM);
      },
    );

    test('post-dusk instant names the sunset just PASSED (same day)', () {
      final d = evaluateDaylight(DateTime(2026, 1, 15, 18, 0), _akita);
      expect(d.phase, DaylightPhase.postDusk);
      _closeTo(d.eventHHMM, '16:38', 2, 'post-dusk reference = passed sunset');
      expect(d.eventHHMM, d.sunsetHHMM);
    });

    test('midday instant is plain daylight (no chip-worthy reference)', () {
      final d = evaluateDaylight(DateTime(2026, 1, 15, 12, 0), _akita);
      expect(d.phase, DaylightPhase.daylight);
      expect(d.eventHHMM, isNull);
      expect(d.isLowLight, isFalse);
      expect(d.severity, 0);
    });
  });

  group(
    'en/ja chip parity (same numbers, same structure, only language differs)',
    () {
      test(
        'pre-dawn chip carries the identical sunrise time in both languages',
        () {
          final d = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
          final en = PretripMessages.en.daylightChip(d);
          final ja = PretripMessages.ja.daylightChip(d);
          final t = d.eventHHMM!;
          expect(en, contains(t));
          expect(ja, contains(t)); // number passes through verbatim
          expect(en, isNot(equals(ja))); // language differs
          // ja register check: plain-declarative darkness wording, NEVER the
          // warning register おそれ and never an imperative about the trip itself.
          // (The darkness wording is declarative — it does not even hedge with
          // 可能性 — so the drift guard is the negative set below.)
          expect(ja, contains('日の出')); // names the reference event
          expect(ja, isNot(contains('おそれ')));
          expect(ja, isNot(contains('してください')));
          expect(ja, isNot(contains('べき')));
        },
      );

      test(
        'post-dusk chip carries the identical sunset time in both languages',
        () {
          final d = evaluateDaylight(DateTime(2026, 1, 15, 18, 0), _akita);
          final en = PretripMessages.en.daylightChip(d);
          final ja = PretripMessages.ja.daylightChip(d);
          expect(en, contains(d.eventHHMM!));
          expect(ja, contains(d.eventHHMM!));
          expect(en, isNot(equals(ja)));
          // Same register guard as pre-dawn: declarative, never the warning
          // register, never an imperative about the trip.
          expect(ja, contains('日の入り'));
          expect(ja, isNot(contains('おそれ')));
          expect(ja, isNot(contains('してください')));
          expect(ja, isNot(contains('べき')));
        },
      );

      test('forLanguage resolves ja/en and falls back for unknown', () {
        final d = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
        expect(
          PretripMessages.forLanguage('ja_JP').daylightChip(d),
          PretripMessages.ja.daylightChip(d),
        );
        expect(
          PretripMessages.forLanguage('fr').daylightChip(d),
          PretripMessages.en.daylightChip(d),
        );
      });
    },
  );

  group('no fabricated hazard (correction a)', () {
    test(
      'daylight chip asserts no ice/refreeze for any phase, either language',
      () {
        final instants = <DateTime>[
          DateTime(2026, 1, 15, 6, 30), // pre-dawn
          DateTime(2026, 1, 15, 18, 0), // post-dusk
        ];
        for (final t in instants) {
          final d = evaluateDaylight(t, _akita);
          _assertNoFabricatedHazard(PretripMessages.en.daylightChip(d));
          _assertNoFabricatedHazard(PretripMessages.ja.daylightChip(d));
        }
        final polar = evaluateDaylight(DateTime(2025, 12, 21, 11, 0), _tromso);
        _assertNoFabricatedHazard(PretripMessages.en.daylightChip(polar));
        _assertNoFabricatedHazard(PretripMessages.ja.daylightChip(polar));
      },
    );
  });

  group('polar phases', () {
    test('Tromso 2026-06-21 — POLAR DAY: full daylight, no low-light note', () {
      final d = evaluateDaylight(DateTime(2026, 6, 21, 12, 0), _tromso);
      expect(d.phase, DaylightPhase.polarDay);
      expect(d.isLowLight, isFalse);
      expect(d.severity, 0);
      expect(d.eventHHMM, isNull);
      // The chip reads the daylight wording, NOT the "does not rise" wording —
      // a swapped polarDay/polarNight branch would tell a midnight-sun driver
      // the trip is in darkness; this catches it.
      final en = PretripMessages.en.daylightChip(d);
      final ja = PretripMessages.ja.daylightChip(d);
      expect(en, isNot(contains('does not rise')));
      expect(en, contains('Daylight'));
      expect(ja, isNot(contains('日が昇りません')));
      expect(ja, contains('終日明るい'));
      // And the advisor emits NO daylight chip for a polar-day trip.
      final forecast = _clearForecast(DateTime(2026, 6, 21), 10, 14);
      final commute = CommuteShape(
        plannedDuration: const Duration(hours: 1),
        routeIdentifiers: const ['r'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: DateTime(2026, 6, 21, 11, 0),
        geo: _tromso,
      );
      final b = const SnowAwarePretripAdvisor().brief(
        forecast: forecast,
        commute: commute,
        profile: _fastDriver,
      );
      expect(
        b.chips.any(
          (c) =>
              c.contains('does not rise') ||
              c.contains('dark') ||
              c.contains('暗い'),
        ),
        isFalse,
        reason: 'a polar-day trip needs no low-light note',
      );
    });

    test(
      'Tromso 2025-12-21 — polar night WITH midday civil twilight (NOT deep dark)',
      () {
        // 69.65N: the sun never rises but climbs into civil twilight at noon, so
        // it is honestly "brief twilight", not "the whole trip is in darkness".
        final d = evaluateDaylight(DateTime(2025, 12, 21, 11, 0), _tromso);
        expect(d.phase, DaylightPhase.polarNight);
        expect(
          d.deepDark,
          isFalse,
          reason: 'sun reaches civil twilight at midday at 69.65N midwinter',
        );
        final en = PretripMessages.en.daylightChip(d);
        final ja = PretripMessages.ja.daylightChip(d);
        expect(en, contains('does not rise'));
        expect(en, contains('twilight'));
        expect(en, isNot(contains('whole trip is in darkness')));
        expect(ja, contains('日が昇りません'));
        expect(ja, contains('薄明'));
        // Register guard: declarative, never the warning register / imperative.
        expect(ja, isNot(contains('おそれ')));
        expect(ja, isNot(contains('してください')));
        expect(ja, isNot(contains('べき')));
        _assertNoFabricatedHazard(en);
        _assertNoFabricatedHazard(ja);
      },
    );

    test(
      '80N 2025-12-21 — DEEP polar night (no civil twilight): all-day darkness',
      () {
        final d = evaluateDaylight(DateTime(2025, 12, 21, 12, 0), _highArctic);
        expect(d.phase, DaylightPhase.polarNight);
        expect(
          d.deepDark,
          isTrue,
          reason: 'sun never reaches civil twilight at 80N midwinter',
        );
        final en = PretripMessages.en.daylightChip(d);
        final ja = PretripMessages.ja.daylightChip(d);
        expect(en, contains('whole trip is in darkness'));
        expect(ja, contains('終日暗い中'));
        expect(ja, isNot(contains('おそれ')));
        expect(ja, isNot(contains('してください')));
        expect(ja, isNot(contains('べき')));
        _assertNoFabricatedHazard(en);
        _assertNoFabricatedHazard(ja);
      },
    );
  });

  group('deep-dark vs twilight severity (correction: pick the DARKEST instant)', () {
    test(
      'a deep pre-dawn instant is severity 2/deepDark; near sunrise is 1',
      () {
        // 06:00 is before civil dawn (~06:29) => deep dark; 06:55 is after civil
        // dawn but before sunrise (06:59) => usable twilight.
        final deep = evaluateDaylight(DateTime(2026, 1, 15, 6, 0), _akita);
        expect(deep.phase, DaylightPhase.preDawn);
        expect(deep.deepDark, isTrue);
        expect(deep.severity, 2);
        final twilight = evaluateDaylight(DateTime(2026, 1, 15, 6, 55), _akita);
        expect(twilight.phase, DaylightPhase.preDawn);
        expect(twilight.deepDark, isFalse);
        expect(twilight.severity, 1);
      },
    );

    test('a trip with a twilight pre-dawn departure AND a deep-dark post-dusk '
        'arrival surfaces the DARKER (post-dusk) note', () {
      // Departure 06:55 = twilight pre-dawn (severity 1); arrival 17:55 = after
      // civil dusk (~17:08) = deep-dark post-dusk (severity 2). The advisor must
      // pick the darker one, so the chip names the SUNSET, not the sunrise. A
      // regression flipping the max-severity pick to min would name the sunrise.
      final day = DateTime(2026, 1, 15);
      final forecast = _clearForecast(day, 6, 19);
      final commute = CommuteShape(
        plannedDuration: const Duration(hours: 11), // 06:55 -> 17:55
        routeIdentifiers: const ['r'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: DateTime(2026, 1, 15, 6, 55),
        geo: _akita,
      );
      final b = const SnowAwarePretripAdvisor().brief(
        forecast: forecast,
        commute: commute,
        profile: _fastDriver,
      );
      final daylight = b.chips
          .where((c) => c.contains('sunset') || c.contains('sunrise'))
          .toList();
      expect(daylight, hasLength(1));
      expect(
        daylight.single,
        contains('past sunset'),
        reason: 'darkest candidate is the deep-dark post-dusk arrival',
      );
      expect(daylight.single, isNot(contains('before sunrise')));
    });
  });

  group('TripDaylight value equality', () {
    test('equal over all fields; differs when any field differs', () {
      final a = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
      final b = evaluateDaylight(DateTime(2026, 1, 15, 6, 30), _akita);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      // Usable as a Set member (dedup) — two equal readings collapse to one.
      expect(<TripDaylight>{a, b}, hasLength(1));
      final post = evaluateDaylight(DateTime(2026, 1, 15, 18, 0), _akita);
      expect(a, isNot(equals(post)));
    });
  });

  group('advisor integration', () {
    final day = DateTime(2026, 1, 15);
    const advisor = SnowAwarePretripAdvisor();

    test('daylight chip threads through the ja advisor (HER own language)', () {
      // The daylight chip is the new code path; a bug where addDaylightChip
      // ignored `this.messages` would emit an English daylight note inside an
      // otherwise-Japanese card. This pins the locale threading for it.
      final forecast = _clearForecast(day, 14, 19);
      final commute = CommuteShape(
        plannedDuration: const Duration(hours: 1),
        routeIdentifiers: const ['r'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: DateTime(2026, 1, 15, 16, 0),
        geo: _akita, // arrival 17:00 after sunset 16:38 => post-dusk
      );
      final ja = SnowAwarePretripAdvisor(
        messages: PretripMessages.ja,
      ).brief(forecast: forecast, commute: commute, profile: _fastDriver);
      final en = advisor.brief(
        forecast: forecast,
        commute: commute,
        profile: _fastDriver,
      );
      final jaLight = ja.chips.where((c) => c.contains('日の入り')).toList();
      expect(jaLight, hasLength(1), reason: 'ja daylight chip present');
      expect(
        RegExp(r'[぀-ヿ一-龯]').hasMatch(jaLight.single),
        isTrue,
        reason: 'ja daylight chip is Japanese: ${jaLight.single}',
      );
      // Carries the SAME event time the EN advisor produced.
      final enLight = en.chips.firstWhere((c) => c.contains('past sunset'));
      expect(jaLight.single, contains('16:3'));
      expect(enLight, contains('16:3'));
    });

    test('elevated trip: daylight note never restates the measured-visibility '
        'noun (no forecast/clock conflation)', () {
      // A whiteout (MEASURED visibility) trip that also ends after dark: the
      // forecast visibility chip and the clock-inferred daylight chip sit in the
      // same list. The daylight chip must not also speak of "visibility"/"視界",
      // or HER cannot tell the measured number from the time-of-day inference.
      final base = DateTime(2026, 1, 15, 16);
      final forecast = WeatherForecast(
        issuedAt: base,
        hourly: [
          for (var h = 16; h <= 18; h++)
            HourlyForecast(
              hour: DateTime(2026, 1, 15, h),
              tempCelsius: -3.0,
              visibilityMeters: 80,
              estimatedRoadCondition: RoadConditionEstimate.ice,
            ),
        ],
      );
      final commute = CommuteShape(
        plannedDuration: const Duration(hours: 1),
        routeIdentifiers: const ['r'],
        flexibility: CommuteFlexibility.required, // hazard + honesty mode
        plannedDeparture: DateTime(2026, 1, 15, 16, 30), // arrival 17:30 dark
        geo: _akita,
      );
      for (final m in <PretripMessages>[
        PretripMessages.en,
        PretripMessages.ja,
      ]) {
        final b = SnowAwarePretripAdvisor(
          messages: m,
        ).brief(forecast: forecast, commute: commute, profile: _fastDriver);
        final daylight = b.chips
            .where((c) => c.contains('sunset') || c.contains('日の入り'))
            .toList();
        expect(
          daylight,
          hasLength(1),
          reason: 'expected the post-dusk daylight chip',
        );
        expect(
          daylight.single.contains('visibility'),
          isFalse,
          reason: 'daylight chip must not borrow the forecast visibility noun',
        );
        expect(daylight.single.contains('視界'), isFalse);
      }
    });

    test(
      'CLEAR trip ending after dark still gets the light note (post-dusk)',
      () {
        final forecast = _clearForecast(day, 14, 19);
        final commute = CommuteShape(
          plannedDuration: const Duration(hours: 1),
          routeIdentifiers: const ['r'],
          flexibility: CommuteFlexibility.discretionary,
          plannedDeparture: DateTime(2026, 1, 15, 16, 0), // daylight depart
          geo: _akita, // arrival 17:00 is after sunset 16:38
        );
        final b = advisor.brief(
          forecast: forecast,
          commute: commute,
          profile: _fastDriver,
        );
        expect(b.verdict, PretripVerdict.clear);
        final light = b.chips.where((c) => c.contains('past sunset')).toList();
        expect(
          light,
          hasLength(1),
          reason: 'expected one post-dusk light note',
        );
        expect(light.single, contains('16:3')); // ~16:38/16:39 sunset time
        _assertNoFabricatedHazard(light.single);
        // The clear verdict's own reason must still be present and hazard-free.
        expect(b.chips.any((c) => c.contains('No winter hazard')), isTrue);
      },
    );

    test('PRE-DAWN departure is covered (names the coming sunrise)', () {
      final forecast = _clearForecast(day, 4, 10);
      final commute = CommuteShape(
        plannedDuration: const Duration(hours: 1),
        routeIdentifiers: const ['r'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: DateTime(2026, 1, 15, 6, 30), // before sunrise 06:59
        geo: _akita,
      );
      final b = advisor.brief(
        forecast: forecast,
        commute: commute,
        profile: _fastDriver,
      );
      final light = b.chips.where((c) => c.contains('before sunrise')).toList();
      expect(light, hasLength(1), reason: 'expected one pre-dawn light note');
      expect(light.single, contains('06:5')); // ~06:59 sunrise time
    });

    test(
      'null geo => NO daylight chip (feature absent, fully backward compatible)',
      () {
        final forecast = _clearForecast(day, 14, 19);
        final commute = CommuteShape(
          plannedDuration: const Duration(hours: 1),
          routeIdentifiers: const ['r'],
          flexibility: CommuteFlexibility.discretionary,
          plannedDeparture: DateTime(
            2026,
            1,
            15,
            18,
            0,
          ), // after dark, but no geo
        );
        final b = advisor.brief(
          forecast: forecast,
          commute: commute,
          profile: _fastDriver,
        );
        expect(
          b.chips.any(
            (c) =>
                c.contains('sunrise') ||
                c.contains('sunset') ||
                c.contains('darkness'),
          ),
          isFalse,
          reason: 'no geo must mean no daylight chip',
        );
      },
    );

    test('full-daylight trip with geo => NO daylight chip', () {
      final forecast = _clearForecast(day, 10, 14);
      final commute = CommuteShape(
        plannedDuration: const Duration(hours: 1),
        routeIdentifiers: const ['r'],
        flexibility: CommuteFlexibility.discretionary,
        plannedDeparture: DateTime(2026, 1, 15, 11, 0), // midday, ends 12:00
        geo: _akita,
      );
      final b = advisor.brief(
        forecast: forecast,
        commute: commute,
        profile: _fastDriver,
      );
      expect(
        b.chips.any((c) => c.contains('sunset') || c.contains('sunrise')),
        isFalse,
        reason: 'a fully-daylit trip needs no light note',
      );
    });
  });

  group('CommuteShape equality with and without geo', () {
    CommuteShape make({TripGeo? geo}) => CommuteShape(
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['a', 'b'],
      flexibility: CommuteFlexibility.required,
      plannedDeparture: DateTime(2026, 1, 15, 8, 0),
      geo: geo,
    );

    test('equal without geo (backward compatible default null)', () {
      final a = make();
      final b = make();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.geo, isNull);
    });

    test('equal with identical geo', () {
      final a = make(geo: _akita);
      final b = make(geo: _akita);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when geo differs', () {
      expect(make(geo: _akita), isNot(equals(make(geo: _tokyo))));
    });

    test('not equal when one has geo and the other does not', () {
      expect(make(geo: _akita), isNot(equals(make())));
    });
  });

  group('TripGeo value equality', () {
    test('equal over all three fields; differs on any one', () {
      const a = TripGeo(
        latitude: 1,
        longitude: 2,
        utcOffset: Duration(hours: 9),
      );
      const b = TripGeo(
        latitude: 1,
        longitude: 2,
        utcOffset: Duration(hours: 9),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(
        a,
        isNot(
          equals(
            const TripGeo(
              latitude: 9,
              longitude: 2,
              utcOffset: Duration(hours: 9),
            ),
          ),
        ),
      );
      expect(
        a,
        isNot(
          equals(
            const TripGeo(
              latitude: 1,
              longitude: 9,
              utcOffset: Duration(hours: 9),
            ),
          ),
        ),
      );
      expect(
        a,
        isNot(
          equals(
            const TripGeo(
              latitude: 1,
              longitude: 2,
              utcOffset: Duration(hours: 1),
            ),
          ),
        ),
      );
    });
  });
}
