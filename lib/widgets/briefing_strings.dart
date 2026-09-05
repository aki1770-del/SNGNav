/// Localized text for the pre-trip "Before you drive" safety surface.
///
/// Why this exists: the briefing is the load-bearing safety surface for the driver
/// and her family at the kitchen table — including a mother in Akita who reads
/// Japanese, not English. A safety verdict she cannot read does not reach her,
/// exactly as a colour-only verdict does not reach a driver who cannot see
/// colour (see the `Semantics` block in [PretripBriefingCard]). This table is
/// the reach-fix for language, sibling to the a11y reach-fix already shipped.
///
/// It is a hand-rolled locale table, not a generated `gen-l10n` toolchain, on
/// purpose: the card already strips markdown by hand rather than pull a
/// renderer, to stay offline and dependency-light. The safety surface must
/// render with zero network and zero codegen in the build, on a low-end ARM
/// head unit. English stays the default so existing callers and tests are
/// unchanged.
///
/// HONEST BOUND (verified by rendering the production-faithful card and
/// looking at the real output): this localizes the card's OWN structural + safety
/// strings — verdict headline, severity word, checklist, headers, switch,
/// assistive-tech announcement, winter-card header/footer. The winter-driving
/// action BULLETS are ALSO Japanese now: `assets/winter_knowledge.json` carries
/// a faithful `guidance_ja` for the four winter states, verified offline by an
/// automated adversarial LLM sweep (back-translation + numbers/omission audit,
/// fail-closed) — NOT yet human-native-reviewed (resolved upstream by
/// `WinterKnowledge.cardFor(lang:)`, English fallback if absent — see the asset
/// `_meta.translation_ja`). The plain-language safety REASONS (`briefing.chips`,
/// e.g. "Visibility may drop to ~80 m…") are ALSO Japanese now: the
/// `pretrip_decision_advisor` package carries a `PretripMessages` locale table
/// and `main.dart` resolves it from the active locale, so the same
/// deterministic logic speaks the driver's language (measured numbers pass
/// through verbatim). The `sourceCaption` line is now PARTLY Japanese — the
/// offline/demo caption is localized — but its LIVE arms are still English:
///   - `sourceCaption` (live arms) — composed upstream in `main.dart` from MET
///     Norway / JMA / Digitraffic strings. It is MORE than attribution: on a
///     failed JMA check it carries the safety-material caveat "an official snow
///     warning may exist that is NOT reflected here", the "hazard signal from
///     temperature + precipitation only" limitation, and any MEASURED
///     departure-hour visibility reading (e.g. "visibility 80 m at a station").
///     These clauses are English-only today, so the known-incomplete signal —
///     and the most concrete measured reason — do not yet reach the driver's mother.
///     Localizing them is the next reach-fix and is NOT cosmetic; it needs its
///     own translation-faithfulness verification, so it is a separate commit.
/// The gap is named here rather than hidden: the verdict, checklist, whiteout
/// plan, winter-driving guidance, reason chips, AND the demo source caption
/// reach the driver's mother in Japanese today; the live source-caption caveats do not
/// yet. English remains a complete fallback surface for any unsupported locale.
library;

import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:flutter/widgets.dart';

/// The localized strings the briefing card renders. Resolve one with
/// [BriefingStrings.of] from the ambient [Locale]; [BriefingStrings.en] is the
/// default and the fallback for any unsupported language.
abstract class BriefingStrings {
  const BriefingStrings();

  /// English — the default and the fallback.
  static const BriefingStrings en = _EnBriefingStrings();

  /// Japanese — for the driver's mother in Akita and every Japanese-reading driver.
  static const BriefingStrings ja = _JaBriefingStrings();

  /// Pick the table for [locale], falling back to English for any language we
  /// do not (yet) carry. Never throws — an unsupported locale degrades to the
  /// English safety surface rather than to no surface.
  static BriefingStrings of(Locale locale) =>
      locale.languageCode == 'ja' ? ja : en;

  // --- Header ---------------------------------------------------------------
  String get beforeYouDrive;

  /// The shell's "start the live drive" action label. Localized so the chrome
  /// around the driver's mother's Japanese briefing is also Japanese (no language split).
  String get startDrive;
  String plannedDeparture(String hhmm, int minutes);

  // --- Verdict (visible headline + assistive-tech severity word) ------------
  String get severityInformationNeeded;
  String get headlineNoData;
  String get severityClear;
  String get headlineClear;
  String get severityCaution;
  String get headlineCaution;
  String get severityHazard;

  /// Wait-advised headline. [delay] is already localized via [delayText];
  /// [strong] appends the "hazardous now" clause.
  String headlineWaitAdvised(String delay, bool strong);
  String get headlineHazardPersists;
  String get severityHazardYourDecision;
  String get headlineRequiredTripHazard;

  /// Localized human-readable duration, e.g. "2 h 30 min" / "2時間30分".
  String delayText(Duration d);

  // --- Trip-required switch -------------------------------------------------
  String get tripRequiredTitle;
  String get tripRequiredSubtitle;

  // --- Checklist ------------------------------------------------------------
  String get beforeYouLeave;
  List<String> get checklist;

  // --- Winter-knowledge card ------------------------------------------------
  /// Header for the grounded winter-driving block, e.g.
  /// "If the road is black ice" / "路面がブラックアイス(凍結)のとき".
  String winterHeader(String surfaceState);
  String get winterFooter;

  // --- Assistive tech + source line -----------------------------------------
  /// The single live-region utterance: severity word first, then headline, so
  /// the colour-encoded severity is never the only carrier of the signal.
  String semanticsLabel(String severity, String headline);

  /// The honesty footline: where the forecast came from + when it was issued.
  String sourceLine(String sourceCaption, String hhmm);

  // --- Offline/demo source caption (number-free, fully localizable) ----------
  /// The caption for the simulated/offline demo forecast (no live data). The
  /// LIVE-arm captions stay English for now — see this file's HONEST BOUND.
  String get simulatedForecastCaption;

  /// Appended to [simulatedForecastCaption] when a live fetch was requested but
  /// unavailable, so the card never implies live data it does not have.
  String get liveFetchUnavailableSuffix;

  /// The map screen's companion to [simulatedForecastCaption]: the fleet
  /// vehicle markers and the red hazard rings around them come from a
  /// seeded, deterministic demo generator, not from vehicles on the road.
  ///
  /// The pre-trip screen disclosed its simulated forecast from the first
  /// commit; the live-drive map disclosed nothing, because the disclosure was
  /// authored per-screen and the map screen inherited none of it. A red ring
  /// that reads as a real road report, and is not one, is the failure this
  /// caption exists to stop.
  String get simulatedFleetCaption;

  // --- Destination-AREA section ---------------------------------------------
  // The companion to the daylight clock: a PLACE's public conditions so SHE
  // decides whether/when to drive there. Watches no person; claims no road.
  String get destinationAreaTitle;
  String destinationAreaPlace(String label);
  String get areaResolutionNote;

  /// A localized generic PLACE phrase for the destination area, used when no
  /// explicit label and no resolvable prefecture name is available — so the
  /// Japanese card never falls back to an English literal or a bare code.
  String get genericDestinationArea;

  /// A caution shown when the official-warning check was only PARTIAL: at a
  /// border a containing prefecture could NOT be reached, so a warning (up to a
  /// 大雪特別警報) may be in force there that is not reflected here.
  /// [unreachableArea] names the unreachable prefecture(s) verbatim (e.g. 秋田県).
  /// Conservative / over-warn — it discloses the gap; it NEVER tells the driver
  /// not to go.
  String borderWarningCheckIncomplete(String unreachableArea);

  // --- JMA turmoil warnings card (0.4.0 widening) ---------------------------
  /// Header for the in-force JMA non-snow warnings card (downpour /
  /// typhoon-wind / thunder / fog — e.g. 大雨危険警報 during a summer
  /// downpour). Snow-class warnings do NOT ride this card (they merge into
  /// the road-condition band); this card exists so a fetched in-force
  /// warning is never silently dropped between the adapter and the driver.
  String get jmaWarningsInForceHeader;

  /// One warning row: the publisher's verbatim event name + prefecture-level
  /// area label (Article 17 β verbatim relay — never re-summarized).
  String jmaWarningWithArea(String eventName, String area);

  /// Honesty footer: the wording is JMA's own, relayed verbatim, and the
  /// warnings are prefecture-level (not road- or route-level).
  String get jmaWarningsVerbatimNote;

  // --- Route bridge caution --------------------------------------------------
  /// One-line caution: the fetched route crosses about [approxCount] mapped
  /// bridge sites, and bridge decks freeze before the road surface does.
  /// The count is APPROXIMATE BY CONSTRUCTION (a 30 m corridor match on OSM
  /// data — see `bridge_corridor_read.dart`), so the phrasing MUST carry
  /// 約/"About" and never read as an exact inventory. Rendered ONLY when a
  /// REAL route delivered AND [approxCount] ≥ 1 AND the departure window is
  /// cold enough to matter (window minimum ≤ the advisor's +3.0 °C
  /// radiative-frost ceiling at either endpoint, or an Oct–Apr month —
  /// warm point evidence never suppresses the season band);
  /// NEVER rendered as an all-clear when the count is 0. The claim is SCOPED
  /// to the bundled dataset's region (today: Akita prefecture — the provider
  /// hides the section when the route leaves the data's coverage extent, and
  /// this phrasing covers the residual in-extent border slivers a bbox cannot
  /// exclude). A caution, not an
  /// alarm — it names the physics; it never tells the driver not to go.
  String bridgeCorridorCaution(int approxCount);

  /// Source credit for the bridge dataset behind [bridgeCorridorCaution] —
  /// an ODbL "produced work" notice (§4.3). The pre-trip briefing is
  /// designed to be read at the kitchen table WITHOUT opening the map, so
  /// the tile-layer OSM credit never reaches this surface; the caution card
  /// carries its own, following the per-surface source-credit idiom
  /// ([winterFooter], the visibility caption). The OSM mappers who charted
  /// these bridges are edge developers too.
  String get bridgeDataAttribution;

  // --- In-app place ENTRY (typed-place destination area) --------------------
  // The driver sets the destination AREA herself. All strings frame a PLACE,
  // never a person; English is the complete fallback.
  String get setDestinationAreaButton;
  String get editDestinationAreaButton;
  String get placeEntryTitle;
  String get placeEntryModePrefecture;
  String get placeEntryModeCoordinates;
  String get placeEntryPrefectureHint;
  String get placeEntryLatLabel;
  String get placeEntryLonLabel;
  String get placeEntryLabelLabel;
  String get placeEntryLabelHint;
  String get placeEntrySave;
  String get placeEntryCancel;
  String get placeEntryClear;
  String get placeEntryCoarseNote;
  String get placeEntryInvalidCoords;
  String get placeEntryForecastOffNote;
  String get placeEntryLocalOnlyNote;

  /// A readable PLACE name for a JMA prefecture [code]. English uses the
  /// catalog's English name (or the bare code as last resort); Japanese uses the
  /// 県名 — so the Japanese surface never leaks an English literal.
  String prefectureName(String code);
}

class _EnBriefingStrings extends BriefingStrings {
  const _EnBriefingStrings();

  @override
  String get beforeYouDrive => 'Before you drive';
  @override
  String get startDrive => 'Start drive';
  @override
  String plannedDeparture(String hhmm, int minutes) =>
      'Planned departure $hhmm · trip about $minutes min';

  @override
  String get severityInformationNeeded => 'Information needed';
  @override
  String get headlineNoData =>
      'No forecast for your departure window — use your own judgment';
  @override
  String get severityClear => 'Clear';
  @override
  String get headlineClear => 'Conditions look clear for your trip window';
  @override
  String get severityCaution => 'Caution';
  @override
  String get headlineCaution => 'Drive with care — no delay suggested';
  @override
  String get severityHazard => 'Hazard';
  @override
  String headlineWaitAdvised(String delay, bool strong) =>
      'Consider waiting about $delay'
      '${strong ? ' — conditions are hazardous now' : ''}';
  @override
  String get headlineHazardPersists =>
      'Hazardous through the forecast — '
      'consider whether this trip is needed today';
  @override
  String get severityHazardYourDecision => 'Hazard, your decision';
  @override
  String get headlineRequiredTripHazard =>
      'Your call — trip is marked required. Hazard ahead; prepare well';

  @override
  String delayText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
  }

  @override
  String get tripRequiredTitle => 'This trip is required';
  @override
  String get tripRequiredSubtitle =>
      'When on, no delay is urged — you decide, we help you prepare.';

  @override
  String get beforeYouLeave => 'Before you leave';
  @override
  List<String> get checklist => const [
        'Snow tires or chains fitted — carry chains and a jack even with snow tires',
        'Check road conditions before leaving (JARTIC / local road information)',
        'Booster cables and a charged phone on board',
        'Warm layers and blanket in the car in case of stranding',
        'Whiteout plan: hazard lamps on, stop at a safe place — do not push on',
      ];

  @override
  String winterHeader(String surfaceState) =>
      'If the road is ${_humanStateEn(surfaceState)}';
  @override
  String get winterFooter =>
      'Offline winter-driving guidance · open sources (CC BY-SA)';

  @override
  String semanticsLabel(String severity, String headline) =>
      'Pre-trip safety briefing. $severity. $headline';

  @override
  String sourceLine(String sourceCaption, String hhmm) =>
      '$sourceCaption · forecast issued $hhmm';

  @override
  String get simulatedForecastCaption =>
      'Simulated forecast (demo) — offline, deterministic';
  @override
  String get liveFetchUnavailableSuffix => ' (live fetch unavailable)';

  @override
  String get simulatedFleetCaption =>
      'Simulated fleet (demo) — seeded, deterministic';

  @override
  String get destinationAreaTitle => 'Conditions in the destination area';
  @override
  String destinationAreaPlace(String label) => 'Area: $label';
  @override
  String get areaResolutionNote =>
      'Area conditions and official advisory only — not road or route status. '
      'Warnings are prefecture-level; the forecast hazard band reflects a '
      'single forecast point, not the whole area; measured visibility is the '
      'nearest station, or unavailable.';

  @override
  String get genericDestinationArea => 'destination area';

  @override
  String borderWarningCheckIncomplete(String unreachableArea) =>
      'Could not check warnings for $unreachableArea (connectivity). A warning '
      'may be in effect there that is not shown here.';

  @override
  String get jmaWarningsInForceHeader => 'JMA warnings in effect';

  @override
  String jmaWarningWithArea(String eventName, String area) =>
      '$eventName ($area)';

  @override
  String get jmaWarningsVerbatimNote =>
      'Official JMA wording, shown as issued. Warnings are prefecture-level, '
      'not road or route status.';

  @override
  String bridgeCorridorCaution(int approxCount) =>
      'About $approxCount bridge${approxCount == 1 ? '' : 's'} on your route '
      'ahead within Akita Prefecture. Bridge decks freeze before the road '
      'surface does.';

  @override
  String get bridgeDataAttribution =>
      'Bridge data © OpenStreetMap contributors (ODbL)';

  @override
  String get setDestinationAreaButton => 'Set destination area';
  @override
  String get editDestinationAreaButton => 'Change destination area';
  @override
  String get placeEntryTitle => 'Destination area';
  @override
  String get placeEntryModePrefecture => 'Pick a prefecture';
  @override
  String get placeEntryModeCoordinates => 'Type coordinates';
  @override
  String get placeEntryPrefectureHint => 'Choose a prefecture';
  @override
  String get placeEntryLatLabel => 'Latitude';
  @override
  String get placeEntryLonLabel => 'Longitude';
  @override
  String get placeEntryLabelLabel => 'Place name (optional)';
  @override
  String get placeEntryLabelHint => 'e.g. a place name you choose';
  @override
  String get placeEntrySave => 'Save';
  @override
  String get placeEntryCancel => 'Cancel';
  @override
  String get placeEntryClear => 'Remove saved area';
  @override
  String get placeEntryCoarseNote =>
      'Prefecture-level area — not a specific town.';
  @override
  String get placeEntryInvalidCoords =>
      'Enter a valid latitude (−90 to 90) and longitude (−180 to 180).';
  @override
  String get placeEntryForecastOffNote =>
      'Area conditions need the live forecast enabled for this build.';
  @override
  String get placeEntryLocalOnlyNote =>
      'This is a place, saved only on this device.';

  @override
  String prefectureName(String code) => kJmaPrefectureNames[code] ?? code;

  static String _humanStateEn(String state) {
    switch (state) {
      case 'blackIce':
        return 'black ice';
      case 'compactedSnow':
        return 'compacted snow';
      case 'slush':
        return 'slush';
      case 'wet':
        return 'wet';
      default:
        return state;
    }
  }
}

class _JaBriefingStrings extends BriefingStrings {
  const _JaBriefingStrings();

  @override
  String get beforeYouDrive => '出発前に';
  @override
  String get startDrive => '運転を開始';
  @override
  String plannedDeparture(String hhmm, int minutes) =>
      '出発予定 $hhmm · 所要 約$minutes分';

  @override
  String get severityInformationNeeded => '情報が必要';
  @override
  String get headlineNoData => '出発時間帯の予報がありません — ご自身の判断で';
  @override
  String get severityClear => '良好';
  @override
  String get headlineClear => '出発時間帯は良好な見込みです';
  @override
  String get severityCaution => '注意';
  @override
  String get headlineCaution => '注意して運転してください — 出発を遅らせる必要はありません';
  @override
  String get severityHazard => '危険';
  @override
  String headlineWaitAdvised(String delay, bool strong) =>
      '約$delay待つことを検討してください'
      '${strong ? ' — 現在危険な状況です' : ''}';
  @override
  String get headlineHazardPersists =>
      '予報期間中ずっと危険 — 本日この移動が必要かご検討ください';
  @override
  String get severityHazardYourDecision => '危険・あなたの判断';
  @override
  String get headlineRequiredTripHazard =>
      'あなたの判断です — 必須の移動として設定されています。危険があります。十分な準備を';

  @override
  String delayText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '$h時間$m分';
    if (h > 0) return '$h時間';
    return '$m分';
  }

  @override
  String get tripRequiredTitle => 'この移動は必須';
  @override
  String get tripRequiredSubtitle =>
      'オンの間は出発を遅らせることは勧めません — 判断はあなた、準備をお手伝いします。';

  @override
  String get beforeYouLeave => '出発前の準備';
  @override
  List<String> get checklist => const [
        'スタッドレスタイヤまたはチェーンを装着 — スタッドレスでもチェーンとジャッキを携行',
        '出発前に道路状況を確認(JARTIC・地域の道路情報)',
        'ブースターケーブルと充電済みの携帯電話を車内に',
        '立ち往生に備えて防寒着と毛布を車内に',
        'ホワイトアウト時の対応:ハザードランプを点灯し安全な場所に停車 — 無理に進まない',
      ];

  @override
  String winterHeader(String surfaceState) {
    switch (surfaceState) {
      case 'blackIce':
        return '路面がブラックアイス(凍結)のとき';
      case 'compactedSnow':
        return '路面が圧雪のとき';
      case 'slush':
        return '路面がシャーベット状の雪のとき';
      case 'wet':
        return '路面が濡れているとき';
      default:
        return '路面が$surfaceStateのとき';
    }
  }

  @override
  String get winterFooter =>
      'オフライン冬季運転ガイダンス · オープンソース (CC BY-SA)';

  @override
  String semanticsLabel(String severity, String headline) =>
      '出発前の安全ブリーフィング。$severity。$headline';

  @override
  String sourceLine(String sourceCaption, String hhmm) =>
      '$sourceCaption · 予報発表 $hhmm';

  @override
  String get simulatedForecastCaption => 'シミュレーション予報(デモ)— オフライン・確定的';
  @override
  String get liveFetchUnavailableSuffix => ' (ライブ取得不可)';

  @override
  String get simulatedFleetCaption => 'シミュレーション車両(デモ)— シード固定・確定的';

  @override
  String get destinationAreaTitle => '目的地周辺の状況';
  @override
  String destinationAreaPlace(String label) => '地域: $label';
  @override
  String get areaResolutionNote =>
      '地域の気象状況と公式の警報・注意報のみを示します — 道路や経路の状況ではありません。'
      '警報・注意報は県単位、予報ハザードは単一地点の予報(地域全体ではありません)、'
      '計測視程は最寄りの観測点(またはデータなし)です。';

  @override
  String get genericDestinationArea => '目的地周辺';

  @override
  String borderWarningCheckIncomplete(String unreachableArea) =>
      '$unreachableAreaの警報を確認できませんでした（通信状況により）。'
      '周辺で警報が出ている可能性があります。';

  @override
  String get jmaWarningsInForceHeader => '気象庁 発表中の警報・注意報';

  @override
  String jmaWarningWithArea(String eventName, String area) =>
      '$eventName（$area）';

  @override
  String get jmaWarningsVerbatimNote =>
      '気象庁の発表をそのまま表示しています。警報・注意報は県単位で、'
      '道路や経路の状態ではありません。';

  @override
  String bridgeCorridorCaution(int approxCount) =>
      'この先、秋田県内の経路上に橋が約${approxCount}か所あります。'
      '橋は路面より先に凍結します。';

  @override
  String get bridgeDataAttribution =>
      '橋データ © OpenStreetMap contributors (ODbL)';

  @override
  String get setDestinationAreaButton => '目的地エリアを設定';
  @override
  String get editDestinationAreaButton => '目的地エリアを変更';
  @override
  String get placeEntryTitle => '目的地エリア';
  @override
  String get placeEntryModePrefecture => '都道府県から選ぶ';
  @override
  String get placeEntryModeCoordinates => '座標を入力';
  @override
  String get placeEntryPrefectureHint => '都道府県を選択';
  @override
  String get placeEntryLatLabel => '緯度';
  @override
  String get placeEntryLonLabel => '経度';
  @override
  String get placeEntryLabelLabel => '場所の名前（任意）';
  @override
  String get placeEntryLabelHint => '例：自分で決めた場所の名前';
  @override
  String get placeEntrySave => '保存';
  @override
  String get placeEntryCancel => 'キャンセル';
  @override
  String get placeEntryClear => '保存したエリアを削除';
  @override
  String get placeEntryCoarseNote => '都道府県レベルのエリアです（特定の市町村ではありません）。';
  @override
  String get placeEntryInvalidCoords =>
      '緯度（−90〜90）と経度（−180〜180）を正しく入力してください。';
  @override
  String get placeEntryForecastOffNote =>
      'エリアの状況表示には、このビルドでライブ予報を有効にする必要があります。';
  @override
  String get placeEntryLocalOnlyNote => 'これは場所の情報で、この端末にのみ保存されます。';

  @override
  String prefectureName(String code) =>
      const <String, String>{
        '010000': '北海道',
        '020000': '青森県',
        '030000': '岩手県',
        '050000': '秋田県',
        '060000': '山形県',
        '150000': '新潟県',
      }[code] ??
      (kJmaPrefectureNames[code] ?? code);
}
