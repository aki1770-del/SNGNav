import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

/// The reason chips are the load-bearing safety REASONS HER mother reads. A
/// reason she cannot read does not reach her — so the advisor must speak her
/// language, AND a localization must never restate a measured value. These
/// tests pin both: the chips come out Japanese, and every safety number the
/// English chips carry survives byte-for-byte into the Japanese chips.

const _whiteoutVis = 80.0;

WeatherForecast _whiteoutForecast(DateTime base) => WeatherForecast(
      issuedAt: base,
      hourly: [
        HourlyForecast(
          hour: base.add(const Duration(hours: 1)),
          tempCelsius: -3.0,
          visibilityMeters: _whiteoutVis,
          estimatedRoadCondition: RoadConditionEstimate.ice,
        ),
      ],
    );

CommuteShape _commute(CommuteFlexibility flex, DateTime base) => CommuteShape(
      plannedDuration: const Duration(minutes: 30),
      plannedDeparture: base.add(const Duration(hours: 1)),
      routeIdentifiers: const ['t'],
      flexibility: flex,
    );

const _profile = DriverProfileSpec(profileTag: 't', reactionTimeSeconds: 1.5);

void main() {
  final base = DateTime(2026, 1, 15, 6);

  test('default advisor still emits English chips (non-breaking)', () {
    const advisor = SnowAwarePretripAdvisor();
    final briefing = advisor.brief(
      forecast: _whiteoutForecast(base),
      commute: _commute(CommuteFlexibility.required, base),
      profile: _profile,
    );
    expect(briefing.chips, isNotEmpty);
    expect(briefing.chips.first, contains('Visibility may drop'));
    expect(briefing.chips.first, contains('whiteout'));
    // No Japanese leaked into the default surface.
    for (final c in briefing.chips) {
      expect(RegExp(r'[぀-ヿ一-龯]').hasMatch(c), isFalse,
          reason: 'English default must carry no CJK: $c');
    }
  });

  test('ja advisor emits Japanese chips for the same logic', () {
    final advisor = SnowAwarePretripAdvisor(messages: PretripMessages.ja);
    final briefing = advisor.brief(
      forecast: _whiteoutForecast(base),
      commute: _commute(CommuteFlexibility.required, base),
      profile: _profile,
    );
    expect(briefing.chips, isNotEmpty);
    // Every chip carries Japanese.
    for (final c in briefing.chips) {
      expect(RegExp(r'[぀-ヿ一-龯]').hasMatch(c), isTrue,
          reason: 'ja chip must be Japanese: $c');
    }
    // The whiteout reason is the Japanese whiteout phrasing.
    expect(briefing.chips.first, contains('ホワイトアウト'));
  });

  test('safety numbers survive translation byte-for-byte', () {
    const en = SnowAwarePretripAdvisor();
    final ja = SnowAwarePretripAdvisor(messages: PretripMessages.ja);
    final c = _commute(CommuteFlexibility.required, base);
    final enB = en.brief(forecast: _whiteoutForecast(base), commute: c, profile: _profile);
    final jaB = ja.brief(forecast: _whiteoutForecast(base), commute: c, profile: _profile);

    // Same verdict + same number of chips: the logic is identical, only words differ.
    expect(jaB.verdict, enB.verdict);
    expect(jaB.chips.length, enB.chips.length);

    // The visibility number (80) appears in BOTH first chips, with its unit.
    expect(enB.chips.first, contains('80 m'));
    expect(jaB.chips.first, contains('80m'));
  });

  test('forLanguage resolves ja variants and falls back to English', () {
    expect(PretripMessages.forLanguage('ja'), same(PretripMessages.ja));
    expect(PretripMessages.forLanguage('ja_JP'), same(PretripMessages.ja));
    expect(PretripMessages.forLanguage('ja-JP'), same(PretripMessages.ja));
    expect(PretripMessages.forLanguage('JA'), same(PretripMessages.ja));
    expect(PretripMessages.forLanguage('en'), same(PretripMessages.en));
    expect(PretripMessages.forLanguage('fr'), same(PretripMessages.en));
    expect(PretripMessages.forLanguage(''), same(PretripMessages.en));
  });

  // The English chips moved out of the advisor into the locale table, so a
  // future edit there could silently change shipped output. Pin the exact
  // strings (the README golden depends on these byte-for-byte).
  test('EN chip strings are pinned against silent drift', () {
    const m = PretripMessages.en;
    expect(m.visibilityWhiteout(80, '07:00'),
        'Visibility may drop to ~80 m around 07:00 — whiteout conditions.');
    expect(m.conditionsImproveBy('08:15'), 'Conditions improve by about 08:15.');
    expect(m.stalenessChip(7),
        'Forecast is 7 h old at departure — check conditions again before leaving.');
    expect(m.reactionMargin(30),
        'Extra 30 min margin added for your reaction-time profile.');
    expect(m.freezingAir(-4, '06:00'),
        'Freezing air (-4 °C) around 06:00 — frost or black ice possible.');
    expect(m.noWinterHazard(), 'No winter hazard signals in your trip window.');
  });

  // Every message method, both locales: the JA must carry Japanese AND preserve
  // every measured number the EN carries. This covers all the _describe and
  // verdict branches that no forecast fixture in the suite reaches.
  test('every chip preserves its numbers across EN and JA', () {
    final cjk = RegExp(r'[぀-ヿ一-龯]');
    // (method, [args], list of number-substrings that MUST survive)
    final cases = <(String Function(PretripMessages), List<String>)>[
      ((m) => m.stalenessChip(9), ['9']),
      ((m) => m.conditionsLookBetterIfAllows('08:30'), ['08:30']),
      ((m) => m.conditionsImproveBy('09:00'), ['09:00']),
      ((m) => m.reactionMargin(30), ['30']),
      ((m) => m.noBetterWindow(6), ['6']),
      ((m) => m.visibilityWhiteout(80, '07:00'), ['80', '07:00']),
      ((m) => m.visibilityReducedNearWhiteout(150, '07:00'), ['150', '07:00']),
      ((m) => m.reducedVisibility(400, '07:00'), ['400', '07:00']),
      ((m) => m.freezingAir(-4, '06:00'), ['-4', '06:00']),
      ((m) => m.icyRoads('07:00'), ['07:00']),
      ((m) => m.packedSnow('07:00'), ['07:00']),
      ((m) => m.precipNearFreezing('07:00'), ['07:00']),
      ((m) => m.slushPossible('07:00'), ['07:00']),
      ((m) => m.coldRain('07:00'), ['07:00']),
      ((m) => m.winterConditionsPossible('07:00'), ['07:00']),
    ];
    for (final (build, numbers) in cases) {
      final en = build(PretripMessages.en);
      final ja = build(PretripMessages.ja);
      expect(en, isNotEmpty);
      expect(cjk.hasMatch(en), isFalse, reason: 'EN carries no CJK: $en');
      expect(cjk.hasMatch(ja), isTrue, reason: 'JA is Japanese: $ja');
      for (final n in numbers) {
        expect(en, contains(n), reason: 'EN keeps $n: $en');
        expect(ja, contains(n), reason: 'JA keeps $n: $ja');
      }
    }
    // No-number chips still localize.
    expect(PretripMessages.ja.noWinterHazard(), isNot(PretripMessages.en.noWinterHazard()));
    expect(cjk.hasMatch(PretripMessages.ja.allowExtraTime()), isTrue);
  });

  test('caution path is localized end-to-end', () {
    final base = DateTime(2026, 1, 15, 6);
    // A frost-only slot (subzero, no precip/road/visibility) → caution verdict.
    final forecast = WeatherForecast(
      issuedAt: base,
      hourly: [
        HourlyForecast(
          hour: base.add(const Duration(hours: 1)),
          tempCelsius: -1.0,
        ),
      ],
    );
    final ja = SnowAwarePretripAdvisor(messages: PretripMessages.ja);
    final briefing = ja.brief(
      forecast: forecast,
      commute: _commute(CommuteFlexibility.discretionary, base),
      profile: _profile,
    );
    expect(briefing.verdict, PretripVerdict.caution);
    final cjk = RegExp(r'[぀-ヿ一-龯]');
    for (final c in briefing.chips) {
      expect(cjk.hasMatch(c), isTrue, reason: 'caution chip ja: $c');
    }
    // The "allow extra time" caution chip is present in Japanese.
    expect(briefing.chips.any((c) => c.contains('車間距離')), isTrue);
  });

  test('rationale on the recommendation is localized too', () {
    final ja = SnowAwarePretripAdvisor(messages: PretripMessages.ja);
    final briefing = ja.brief(
      forecast: _whiteoutForecast(base),
      commute: _commute(CommuteFlexibility.required, base),
      profile: _profile,
    );
    final rationale = briefing.recommendation!.rationale;
    expect(rationale, equals(briefing.chips),
        reason: 'rationale mirrors the localized chips');
  });
}
