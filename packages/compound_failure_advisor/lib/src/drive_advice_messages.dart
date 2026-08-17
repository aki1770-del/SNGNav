/// Localized driver-facing text for the advisory vocabulary this package emits.
///
/// Why this exists: [Unknown]'s own dartdoc says these are "an enum, not prose,
/// so the integrator localizes for HER Japanese mother." That was right — and
/// it left every integrator to hand-roll the hardest strings in the catalog,
/// alone, in a language most of them do not read. The wording of a caution at
/// the wheel in a whiteout is not boilerplate the integrator should be inventing
/// under deadline: get one verb wrong and the package that structurally REFUSES
/// to tell her to turn back suddenly tells her to turn back.
///
/// So this table OFFERS the default wording, in English and in Japanese, with
/// the package's discipline already baked in. It does not take the enum away.
/// The enum remains the API; an integrator who wants their own words still has
/// them, exactly as before. Nothing here is imposed and nothing existing changes.
///
/// It is a hand-rolled locale table, not a generated `gen-l10n` toolchain, and
/// it deliberately copies the idiom already established by
/// `pretrip_decision_advisor`'s `PretripMessages`: pure Dart, no Flutter, no
/// network, no codegen, so this package's zero-runtime-dependency /
/// 32-bit-ARM contract is untouched. No new i18n mechanism is introduced.
///
/// ## Wording discipline (binding on every string in this file)
///
/// The strings inherit the package's honesty contract, which is stricter than
/// ordinary UI copy:
///
/// 1. **No "safe".** [DriveAction.continueDriving] is the ABSENCE of a raised
///    concern, NEVER an assertion of safety. It is worded as *continue* (she
///    was already driving), never "safe to continue" / 「安全です」. This
///    package cannot see the road, other vehicles, or her grip.
/// 2. **No turn-back, no command.** There is structurally no abort rung, and
///    the ceiling [DriveAction.considerStopping] is an INVITATION she owns —
///    「〜という選択肢もあります」, never 「停車してください」 and never
///    「引き返してください」. Advisory mood only, following the same discipline
///    as `navigation_safety_core`'s `AlertExplainer`.
/// 3. **Unknown is never "clear".** An absent visibility reading is stated as
///    an absence (「視界の情報がありません」), never as good visibility. This is
///    the whole reason the [Unknown] list is first-class.
/// 4. **Measured values pass through verbatim.** A localization may reorder
///    words but never restate a measured number.
///
/// English stays the default ([DriveAdviceMessages.en]); Japanese is offered.
library;

import 'drive_advice.dart';

/// The localized driver-facing strings for this package's advisory vocabulary.
/// Resolve one for the active language; [DriveAdviceMessages.en] is the default
/// and the fallback for any language this package does not (yet) carry.
abstract class DriveAdviceMessages {
  const DriveAdviceMessages();

  /// English — the default and the fallback.
  static const DriveAdviceMessages en = _EnDriveAdviceMessages();

  /// Japanese — for a driver who reads Japanese.
  static const DriveAdviceMessages ja = _JaDriveAdviceMessages();

  /// Locale subtag separator, compiled once (this is hot on the low-end-ARM
  /// rebuild path, where [forLanguage] may be called on every advisory tick).
  static final RegExp _localeSep = RegExp('[_-]');

  /// Pick the table for [languageCode] (e.g. `'ja'`, `'ja_JP'`, `'JA'`),
  /// falling back to English for any language not carried. Never throws — an
  /// unsupported language degrades to the English caution, never to NO caution.
  static DriveAdviceMessages forLanguage(String languageCode) {
    final base = languageCode.toLowerCase().split(_localeSep).first;
    return base == 'ja' ? ja : en;
  }

  // --- The action rung ------------------------------------------------------

  /// Short label for [action] — chip / badge length.
  String actionLabel(DriveAction action);

  /// One-sentence driver-facing statement of [action]. Advisory mood: never
  /// asserts safety, never commands, never tells her to turn back.
  String actionSentence(DriveAction action);

  // --- The statable WHY -----------------------------------------------------

  /// Driver-facing phrasing of [reason] — the WHY behind a raised action. Every
  /// raised action carries at least one; a caution she cannot explain is a
  /// caution she will learn to ignore.
  String reasonSentence(CautionReason reason);

  // --- The first-class unknowns ---------------------------------------------

  /// Driver-facing phrasing of [unknown] — stated as a plain absence of
  /// knowledge, never as a benign condition.
  String unknownSentence(Unknown unknown);

  // --- The compounding note (the reason this package exists) ----------------

  /// The one non-linearity: an uncertain position AND low visibility TOGETHER
  /// is worse than either alone. Surfaced only when
  /// [DriveAdvice.compounding] is true.
  String compoundingNote();

  // --- The optional sight-stopping hint -------------------------------------

  /// "A speed at which you could stop within what you can see ahead" —
  /// [kmh] passes through verbatim. A speed to ease TOWARD, never a commanded
  /// speed, phrased so it cannot read as permission to drive that fast.
  String sightStoppingSpeedHint(int kmh);
}

class _EnDriveAdviceMessages extends DriveAdviceMessages {
  const _EnDriveAdviceMessages();

  @override
  String actionLabel(DriveAction action) {
    switch (action) {
      case DriveAction.continueDriving:
        // NOT "Safe" / "All clear".
        return 'Nothing raised';
      case DriveAction.heightenedCaution:
        return 'Heightened caution';
      case DriveAction.considerStopping:
        return 'Consider a safe pause';
    }
  }

  @override
  String actionSentence(DriveAction action) {
    switch (action) {
      case DriveAction.continueDriving:
        // The absence of a raised concern — explicitly NOT an assertion of
        // safety, and it says so, because a driver reading "nothing raised"
        // must not hear "the road is fine".
        return 'Nothing in what we can see right now has raised a concern. '
            'This is not a statement that the road is safe.';
      case DriveAction.heightenedCaution:
        return 'Conditions have degraded — ease your speed, leave more room, '
            'and watch for your next safe option.';
      case DriveAction.considerStopping:
        // The ceiling. An invitation she owns. Never a command — but it is the
        // strongest rung, and "whenever you want one" drained it of weight.
        return 'If you can do so safely, pulling over somewhere safe is an '
            'option — the decision is yours.';
    }
  }

  @override
  String reasonSentence(CautionReason reason) {
    switch (reason) {
      case CautionReason.positionUncertain:
        return 'Your position is not certain.';
      case CautionReason.lowVisibility:
        return 'Visibility is low.';
      case CautionReason.reducedVisibility:
        return 'Visibility is reduced.';
      case CautionReason.unknownVisibility:
        // Never "visibility is fine".
        return 'We have no visibility reading near you.';
      case CautionReason.staleVisibility:
        return 'The visibility reading near you is too old to rely on.';
      case CautionReason.severeAdvisory:
        return 'A severe weather advisory is in force for this area.';
      case CautionReason.moderateAdvisory:
        return 'A weather advisory is in force for this area.';
      case CautionReason.highSpeedInDegradedConditions:
        return 'You are covering uncertain ground quickly.';
    }
  }

  @override
  String unknownSentence(Unknown unknown) {
    switch (unknown) {
      case Unknown.positionCouldBeAnywhereInRadius:
        return 'You could be anywhere within the shown confidence radius.';
      case Unknown.noTrustedGpsForAWhile:
        return 'There has been no trusted GPS fix for a while.';
      case Unknown.noPositionAtAll:
        return 'We do not know where you are.';
      case Unknown.noVisibilityReading:
        return 'We have no visibility measurement — not that visibility is '
            'good, but that we do not have one.';
      case Unknown.visibilityReadingIsStale:
        return 'The visibility measurement we have is too old to trust.';
      case Unknown.speedUnknown:
        return 'Your speed is unknown to us.';
    }
  }

  @override
  String compoundingNote() =>
      'Your position is uncertain AND visibility is low at the same time. '
      'These two together are more dangerous than either one alone.';

  @override
  String sightStoppingSpeedHint(int kmh) =>
      'At about $kmh km/h you could still stop within what you can see ahead. '
      'A speed to ease toward — not a speed we are telling you is safe.';
}

class _JaDriveAdviceMessages extends DriveAdviceMessages {
  const _JaDriveAdviceMessages();

  @override
  String actionLabel(DriveAction action) {
    switch (action) {
      case DriveAction.continueDriving:
        // 「安全」とは絶対に書かない。「注意を要する事象なし」= 懸念が上がっていない、という意味。
        return '注意事項なし';
      case DriveAction.heightenedCaution:
        return '要注意';
      case DriveAction.considerStopping:
        // 命令形にしない。「検討」= 彼女が決める。
        return '安全な場所での停車も検討';
    }
  }

  @override
  String actionSentence(DriveAction action) {
    switch (action) {
      case DriveAction.continueDriving:
        // 「安全です」と読まれてはならないため、明示的に否定する一文を付ける。
        return '現在わかっている範囲では、注意を要する事象はありません。'
            'これは路面が安全であることを示すものではありません。';
      case DriveAction.heightenedCaution:
        return '状況が悪化しています。速度を落とし、車間距離を十分にとり、'
            '安全に停車できる場所に注意してください。';
      case DriveAction.considerStopping:
        // 上限。あくまで提案であり、命令ではない。「引き返す」表現は構造上存在しない。
        //
        // 「休憩」ではなく「停車」。休憩 is the FATIGUE word (休憩所、2時間ごとに
        // 休憩) — a coffee stop. It does not carry "get off this road, the
        // conditions are dangerous", and it is materially weaker than the
        // English "pause". It also contradicted this class's own actionLabel
        // for the same enum value, which correctly says 停車. A driver in a
        // whiteout told 「休憩するという選択肢もあります」 hears an optional
        // comfort break, not a safety escalation. This is the CEILING rung —
        // the strongest thing this package may say — and it must not be
        // softened.
        return '安全に行える場合は、安全な場所に停車するという選択肢もあります。'
            '判断はあなたが行ってください。';
    }
  }

  @override
  String reasonSentence(CautionReason reason) {
    switch (reason) {
      case CautionReason.positionUncertain:
        return '現在地が確かではありません。';
      case CautionReason.lowVisibility:
        // 視界不良 — 気象・道路分野の標準語。
        return '視界不良です。';
      case CautionReason.reducedVisibility:
        return '視界が低下しています。';
      case CautionReason.unknownVisibility:
        // 「視界は良好」と絶対に読ませない。
        return '付近の視界の情報がありません。';
      case CautionReason.staleVisibility:
        return '付近の視界の情報が古く、信頼できません。';
      case CautionReason.severeAdvisory:
        // 警報 = warning (severe/extreme). 注意報 = advisory (moderate).
        // この区別は気象庁の用語であり、取り違えは安全上の誤りになる。
        //
        // CautionReason.severeAdvisory covers BOTH AdvisoryLevel.severe and
        // AdvisoryLevel.extreme, and in Japan 警報 (warning) and 特別警報
        // (emergency warning — the once-in-decades band, a real thing in Akita
        // snow) are distinct terms of art. Rendering both as 警報 alone lets a
        // driver under-react while a 大雪特別警報 is in force. Splitting the
        // enum is the honest fix and belongs to the advisor, not to this
        // message table; until then the band word must not under-name the top.
        return 'この地域に重大な気象警報（特別警報を含む場合があります）が'
            '発表されています。';
      case CautionReason.moderateAdvisory:
        return 'この地域に気象注意報が発表されています。';
      case CautionReason.highSpeedInDegradedConditions:
        return '状況が不確かな中で速度が出ています。';
    }
  }

  @override
  String unknownSentence(Unknown unknown) {
    switch (unknown) {
      case Unknown.positionCouldBeAnywhereInRadius:
        return '実際の現在地は、表示している誤差範囲内のどこかにある可能性があります。';
      case Unknown.noTrustedGpsForAWhile:
        return 'しばらくの間、信頼できるGPS測位がありません。';
      case Unknown.noPositionAtAll:
        return '現在地が分かりません。';
      case Unknown.noVisibilityReading:
        // 「視界が良い」ではなく「情報がない」— この区別がこのパッケージの核心。
        return '視界の観測データがありません。視界が良いという意味ではなく、'
            'データ自体がないという意味です。';
      case Unknown.visibilityReadingIsStale:
        return '手元にある視界の観測データは古く、信頼できません。';
      case Unknown.speedUnknown:
        return '現在の速度が取得できていません。';
    }
  }

  @override
  String compoundingNote() => '現在地が不確かであると同時に、視界不良です。'
      'この二つが重なると、それぞれ単独の場合よりも危険が高まります。';

  @override
  String sightStoppingSpeedHint(int kmh) => '時速約${kmh}kmであれば、'
      '見えている範囲内で停車できる見込みです。'
      'これは目安であり、この速度が安全であると保証するものではありません。';
}
