/// Localized text for the pre-trip briefing's reason chips.
///
/// Why this exists: the chips are the load-bearing safety REASONS the advisor
/// emits — "Visibility may drop to ~80 m around 07:00 — whiteout conditions."
/// They are the *why* behind the verdict, and a reason a driver cannot read
/// does not reach her, exactly as a colour-only verdict does not reach a driver
/// who cannot see colour. The reference advisor historically built these as
/// English literals inside [SnowAwarePretripAdvisor]; this table lifts every
/// chip string out so the same deterministic logic can speak the driver's
/// language — Japanese for a mother in Akita who reads Japanese, not English.
///
/// It is a hand-rolled locale table, not a generated `gen-l10n` toolchain, on
/// purpose: this is pure Dart with no Flutter, no network, and no codegen, so
/// the worst-case offline path stays dependency-light on a low-end ARM head
/// unit. English stays the default ([PretripMessages.en]) so every existing
/// caller and test is byte-for-byte unchanged.
///
/// The numbers in every method (visibility metres, temperature, minutes,
/// hours) are passed through verbatim — a localization may reorder words but
/// never restate a measured value, so a faithful translation cannot drift a
/// safety number. Times arrive pre-formatted as a locale-neutral 24-hour
/// `HH:MM` clock.
library;

/// The localized chip strings the advisor emits. Resolve one for the active
/// language; [PretripMessages.en] is the default and the fallback for any
/// language this package does not (yet) carry.
abstract class PretripMessages {
  const PretripMessages();

  /// English — the default and the fallback.
  static const PretripMessages en = _EnPretripMessages();

  /// Japanese — for a driver who reads Japanese.
  static const PretripMessages ja = _JaPretripMessages();

  /// Locale subtag separator, compiled once (this is hot on the low-end-ARM
  /// rebuild path, where [forLanguage] is called every frame).
  static final RegExp _localeSep = RegExp('[_-]');

  /// Pick the table for [languageCode] (e.g. `'ja'`, `'ja_JP'`, `'JA'`),
  /// falling back to English for any language not carried. Never throws — an
  /// unsupported language degrades to the English reason, never to no reason.
  static PretripMessages forLanguage(String languageCode) {
    final base = languageCode.toLowerCase().split(_localeSep).first;
    return base == 'ja' ? ja : en;
  }

  // --- Verdict-level chips --------------------------------------------------

  /// The forecast is [hours] old at departure — re-check before leaving.
  String stalenessChip(int hours);

  /// No winter hazard signal across the whole trip window.
  String noWinterHazard();

  /// Caution band: allow extra time and keep distance, no delay suggested.
  String allowExtraTime();

  /// A required trip whose conditions improve later: surface it without urging.
  String conditionsLookBetterIfAllows(String hhmm);

  /// A required (or unknown-flexibility) trip: name the hazard, urge no delay.
  String requiredNoDelayUrged();

  /// A discretionary trip: conditions improve by about [hhmm].
  String conditionsImproveBy(String hhmm);

  /// Extra reaction-time margin added to a suggested delay.
  String reactionMargin(int minutes);

  /// Hazard persists and nothing materially better is within [horizonHours].
  String noBetterWindow(int horizonHours);

  // --- Per-slot describe() chips --------------------------------------------

  /// Whiteout-class visibility (< 100 m) around [at].
  String visibilityWhiteout(int meters, String at);

  /// Forecast ice on the road around [at].
  String icyRoads(String at);

  /// Packed snow around [at].
  String packedSnow(String at);

  /// Precipitation at near-freezing temperature around [at].
  String precipNearFreezing(String at);

  /// Near-whiteout visibility (100–200 m) around [at].
  String visibilityReducedNearWhiteout(int meters, String at);

  /// Slush on the road around [at].
  String slushPossible(String at);

  /// Cold rain (subzero-ish) around [at].
  String coldRain(String at);

  /// Reduced visibility (< 500 m) around [at].
  String reducedVisibility(int meters, String at);

  /// Subzero air ([tempCelsius] °C) around [at] — frost / black-ice risk.
  String freezingAir(int tempCelsius, String at);

  /// Generic winter conditions around [at].
  String winterConditionsPossible(String at);
}

class _EnPretripMessages extends PretripMessages {
  const _EnPretripMessages();

  @override
  String stalenessChip(int hours) =>
      'Forecast is $hours h old at departure — '
      'check conditions again before leaving.';

  @override
  String noWinterHazard() => 'No winter hazard signals in your trip window.';

  @override
  String allowExtraTime() =>
      'Allow extra time and keep distance — no delay suggested.';

  @override
  String conditionsLookBetterIfAllows(String hhmm) =>
      'Conditions look better around $hhmm, if your schedule allows.';

  @override
  String requiredNoDelayUrged() =>
      'This trip is marked required — no delay urged. '
      'Prepare before leaving; your judgment decides.';

  @override
  String conditionsImproveBy(String hhmm) =>
      'Conditions improve by about $hhmm.';

  @override
  String reactionMargin(int minutes) =>
      'Extra $minutes min margin added for your reaction-time profile.';

  @override
  String noBetterWindow(int horizonHours) =>
      'No clearly better departure window within the next $horizonHours h — '
      'consider whether this trip is needed today.';

  @override
  String visibilityWhiteout(int meters, String at) =>
      'Visibility may drop to ~$meters m around $at — whiteout conditions.';

  @override
  String icyRoads(String at) => 'Icy roads expected around $at.';

  @override
  String packedSnow(String at) => 'Packed snow expected around $at.';

  @override
  String precipNearFreezing(String at) =>
      'Precipitation near freezing around $at — icy patches likely.';

  @override
  String visibilityReducedNearWhiteout(int meters, String at) =>
      'Visibility may drop to ~$meters m around $at.';

  @override
  String slushPossible(String at) => 'Slush possible around $at.';

  @override
  String coldRain(String at) =>
      'Cold rain around $at — surfaces may be slick.';

  @override
  String reducedVisibility(int meters, String at) =>
      'Reduced visibility (~$meters m) around $at.';

  @override
  String freezingAir(int tempCelsius, String at) =>
      'Freezing air ($tempCelsius °C) around $at — '
      'frost or black ice possible.';

  @override
  String winterConditionsPossible(String at) =>
      'Winter conditions possible around $at.';
}

class _JaPretripMessages extends PretripMessages {
  const _JaPretripMessages();

  @override
  String stalenessChip(int hours) =>
      '予報は出発時点で$hours時間前のものです — 出発前に最新の状況を再確認してください。';

  @override
  String noWinterHazard() => '出発時間帯に冬季の危険を示す兆候はありません。';

  @override
  String allowExtraTime() =>
      '時間に余裕をもち、車間距離を保ってください — 出発を遅らせる必要はありません。';

  @override
  String conditionsLookBetterIfAllows(String hhmm) =>
      '$hhmm頃には状況が改善する見込みです。予定が許せばご検討ください。';

  @override
  String requiredNoDelayUrged() =>
      'この移動は必須に設定されています — 出発を遅らせることは勧めません。'
      '出発前に準備を整えてください。判断はあなたが行います。';

  @override
  String conditionsImproveBy(String hhmm) => '$hhmm頃までに状況は改善します。';

  @override
  String reactionMargin(int minutes) =>
      '反応にかかる時間に合わせて、$minutes分の余裕を追加しました。';

  @override
  String noBetterWindow(int horizonHours) =>
      '今後$horizonHours時間以内に明らかに良い出発時間帯はありません — '
      '本日この移動が必要かご検討ください。';

  @override
  String visibilityWhiteout(int meters, String at) =>
      '$at頃、視界が約${meters}mまで低下する可能性があります — ホワイトアウト状態です。';

  @override
  String icyRoads(String at) => '$at頃、路面の凍結が予想されます。';

  @override
  String packedSnow(String at) => '$at頃、圧雪が予想されます。';

  @override
  String precipNearFreezing(String at) =>
      '$at頃、氷点付近での降水 — 部分的な路面凍結の可能性が高いです。';

  @override
  String visibilityReducedNearWhiteout(int meters, String at) =>
      '$at頃、視界が約${meters}mまで低下する可能性があります。';

  @override
  String slushPossible(String at) => '$at頃、シャーベット状の雪の可能性があります。';

  @override
  String coldRain(String at) =>
      '$at頃、冷たい雨 — 路面が滑りやすくなる可能性があります。';

  @override
  String reducedVisibility(int meters, String at) =>
      '$at頃、視界不良(約${meters}m)。';

  @override
  String freezingAir(int tempCelsius, String at) =>
      '$at頃、氷点下の気温($tempCelsius°C) — '
      '霜やブラックアイス(見えにくい薄い氷)の可能性があります。';

  @override
  String winterConditionsPossible(String at) =>
      '$at頃、冬季の気象条件となる可能性があります。';
}
