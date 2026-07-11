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

import 'daylight.dart';
import 'snow_aware_pretrip_advisor.dart' show HourHazard;

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

  /// Black-ice risk around [at] with ambient ABOVE freezing: high-humidity /
  /// radiative-cooling conditions can take the road surface below 0 °C while
  /// the air reads warmer (freezing fog, hoar frost — no precipitation
  /// needed).
  String blackIceRadiativeRisk(String at);

  /// Generic winter conditions around [at].
  String winterConditionsPossible(String at);

  // --- Daylight-clock chip --------------------------------------------------

  /// A light/time note for a trip that falls in low-light hours. It states only
  /// light and time — never a road hazard inferred from the clock — branching
  /// on [d] for pre-dawn vs after-sunset vs polar-night wording. The reference
  /// time in [TripDaylight.eventHHMM] passes through verbatim.
  String daylightChip(TripDaylight d);

  // --- Destination-AREA condition chips -------------------------------------
  // The subject of every area-* string is the WEATHER AT A PLACE — never a
  // person, an arrival, a presence, or a road. The claim ceiling is "conditions
  // / official advisory for the AREA": never a road-passability or route claim.

  /// The publisher's official warning (or advisory) for the area, verbatim
  /// (e.g. 大雪警報). The verbatim event name carries the precise class; the
  /// frame says "warning or advisory" so it never upgrades an advisory.
  String areaOfficialWarning(String eventVerbatim);

  /// No active snow warning or advisory for the area. Scoped to "snow" because
  /// the wired check is snow-class only — it never claims a wider all-winter
  /// negative it did not actually verify.
  String areaNoOfficialWarning();

  /// The official-warning check failed — a warning may be in effect, unshown.
  String areaWarningCheckUnavailable();

  /// The forecast hazard band for the area (uses [areaHazardBand]).
  String areaHazardChip(HourHazard band);

  /// The human band word for [band] over {clear, caution, elevated, severe}.
  String areaHazardBand(HourHazard band);

  /// No forecast available for the area in the hours ahead.
  String areaForecastNotCovered();

  /// Nearest MEASURED visibility for the area (numbers pass through verbatim).
  ///
  /// [station] and [km] are NULLABLE, and null means NOT KNOWN — never zero and
  /// never "at your location". The whole point of carrying the station name and
  /// its distance is that she can discount a reading taken 40 km away;
  /// substituting `0` for an unknown distance made the LEAST trustworthy reading
  /// look like the MOST trustworthy one.
  String areaMeasuredVisibility(int meters, String? station, int? km);

  /// No measured visibility available for the area.
  String areaNoMeasuredVisibility();
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
  String blackIceRadiativeRisk(String at) =>
      'Black ice possible around $at — radiative cooling can freeze the '
      'road surface even when the air is above 0 °C.';

  @override
  String winterConditionsPossible(String at) =>
      'Winter conditions possible around $at.';

  @override
  String daylightChip(TripDaylight d) {
    switch (d.phase) {
      // Darkness wording, NOT the forecast's measured-hazard noun
      // "visibility" — the daylight clock speaks only of light and time, never
      // a road/atmospheric condition inferred from the clock. The reference
      // time and the minutes-to-event pass through verbatim.
      case DaylightPhase.preDawn:
        return 'Your departure is about ${d.minutesToEvent} min before sunrise '
            '(around ${d.eventHHMM}) — it will still be dark.';
      case DaylightPhase.postDusk:
        return 'Your trip runs to about ${d.minutesToEvent} min past sunset '
            '(around ${d.eventHHMM}) — driving in the dark.';
      case DaylightPhase.polarNight:
        return d.deepDark
            ? 'The sun does not rise here today — '
                'the whole trip is in darkness.'
            : 'The sun does not rise here today — '
                'only brief twilight around midday.';
      case DaylightPhase.daylight:
      case DaylightPhase.polarDay:
        return 'Daylight for your whole trip.';
    }
  }

  @override
  String areaOfficialWarning(String eventVerbatim) =>
      'Official winter warning or advisory in effect for this area: '
      '$eventVerbatim.';

  @override
  String areaNoOfficialWarning() =>
      'No active snow warning or advisory for this area.';

  @override
  String areaWarningCheckUnavailable() =>
      'Official-warning check unavailable — a warning may be in effect that '
      'is not shown here.';

  @override
  String areaHazardChip(HourHazard band) =>
      'Forecast hazard for this area: ${areaHazardBand(band)}.';

  @override
  String areaHazardBand(HourHazard band) {
    switch (band) {
      case HourHazard.clear:
        return 'no winter hazard signal';
      case HourHazard.caution:
        return 'caution';
      case HourHazard.elevated:
        return 'elevated';
      case HourHazard.severe:
        return 'severe';
      case HourHazard.unknown:
        // Never a band. The forecast did not cover this window.
        return 'not assessed';
    }
  }

  @override
  String areaForecastNotCovered() =>
      'No forecast available for this area in the hours ahead.';

  @override
  String areaMeasuredVisibility(int meters, String? station, int? km) {
    if (station != null && km != null) {
      return 'Nearest measured visibility ~$meters m ($station, ~$km km away).';
    }
    if (station != null) {
      return 'Nearest measured visibility ~$meters m ($station; distance from '
          'you not known).';
    }
    if (km != null) {
      return 'Nearest measured visibility ~$meters m (~$km km away; station '
          'not named).';
    }
    return 'Nearest measured visibility ~$meters m (reporting station and its '
        'distance from you are not known).';
  }

  @override
  String areaNoMeasuredVisibility() =>
      'No measured visibility available for this area.';
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
  String blackIceRadiativeRisk(String at) =>
      '$at頃、路面凍結の可能性 — 気温が0°Cより高くても、'
      '放射冷却で路面だけが凍ることがあります(ブラックアイス)。';

  @override
  String winterConditionsPossible(String at) =>
      '$at頃、冬季の気象条件となる可能性があります。';

  @override
  String daylightChip(TripDaylight d) {
    switch (d.phase) {
      // 視界(視程)は予報の計測ハザード用の語。日照クロックは「光と時刻」だけを述べ、
      // 時刻から路面・気象状況を推測しない — だから「暗い」だけを用い、視界には触れない。
      // 時刻と日の出までの分数はそのまま通す。
      case DaylightPhase.preDawn:
        return '出発は日の出(${d.eventHHMM}頃)の約${d.minutesToEvent}分前です。'
            '暗い中での運転になります。';
      case DaylightPhase.postDusk:
        return '移動は日の入り(${d.eventHHMM}頃)の約${d.minutesToEvent}分後に及びます。'
            '暗い中での運転になります。';
      case DaylightPhase.polarNight:
        return d.deepDark
            ? '本日この地点では日が昇りません。移動は終日暗い中となります。'
            : '本日この地点では日が昇りません(正午前後にわずかな薄明のみ)。';
      case DaylightPhase.daylight:
      case DaylightPhase.polarDay:
        return '移動中は終日明るい時間帯です。';
    }
  }

  @override
  String areaOfficialWarning(String eventVerbatim) =>
      'この地域で発表中の警報・注意報: $eventVerbatim。';

  @override
  String areaNoOfficialWarning() =>
      'この地域に発表中の雪の警報・注意報はありません。';

  @override
  String areaWarningCheckUnavailable() =>
      '警報・注意報の確認ができませんでした — 実際には発表されている可能性があります。';

  @override
  String areaHazardChip(HourHazard band) =>
      'この地域の予報ハザード: ${areaHazardBand(band)}。';

  @override
  String areaHazardBand(HourHazard band) {
    switch (band) {
      case HourHazard.clear:
        return '危険の兆候なし';
      case HourHazard.caution:
        return '注意';
      case HourHazard.elevated:
        return '警戒';
      case HourHazard.severe:
        return '重度';
      case HourHazard.unknown:
        // 帯を主張しない。予報が窓を覆っていない。
        return '判定できません';
    }
  }

  @override
  String areaForecastNotCovered() =>
      'この先の時間帯について、この地域の予報データはありません。';

  @override
  String areaMeasuredVisibility(int meters, String? station, int? km) {
    if (station != null && km != null) {
      return '最寄りの計測視程: 約${meters}m($station、約${km}km先)。';
    }
    if (station != null) {
      return '最寄りの計測視程: 約${meters}m($station、現在地からの距離は不明)。';
    }
    if (km != null) {
      return '最寄りの計測視程: 約${meters}m(約${km}km先、観測地点名は不明)。';
    }
    return '最寄りの計測視程: 約${meters}m(観測地点および現在地からの距離は不明)。';
  }

  @override
  String areaNoMeasuredVisibility() =>
      'この地域の計測視程データはありません。';
}
