/// Action-coupled alert explainer: pairs a [RoadSurfaceCondition] with
/// the recommended driver action in the language and verbosity that
/// fits the active [DriverProfile].
///
/// Why this exists: an alert that names a condition without naming an
/// action leaves the integrating app to couple each condition to an
/// action. This class ships that coupling. No source is cited for an
/// effect on compliance.
///
/// For example: "icy road" is incomplete; "icy road →
/// reduce speed to 30 km/h" is actionable.
///
/// Action-text discipline (advisory mood, not control):
///
/// - Action verbs are advisory ("reduce" / "avoid" / "maintain"),
///   never imperative-on-control ("brake now" / "the system will slow
///   you").
/// - Speed numbers (30 km/h, 20 km/h) are advisory reference points
///   chosen by the package (a recorded decision), not system-enforced
///   limits. Wording uses 「以下に減速」 ("reduce to or below") /
///   "Slow to" — the driver retains full speed authority.
/// - No action tells her to stop, to go on, or that the road is fine to
///   drive as usual. Stopping is named only as an option she may take
///   when it is safe (「安全な場所での停車も選べます」 / "is an option").
/// - No action string promises an outcome. Each is a recommendation
///   in the package's own advisory wording.
/// - No action names a path or a steering target ("keep to the centre").
///   This package sees neither the road nor the traffic, so where she
///   puts the car is her judgment. Four slush strings did name the centre
///   until 0.11.12; a test now fails if any string names it again.
///
/// This is a Pure Dart, advisory-only surface. It does not actuate the
/// vehicle. The matrix is information delivered in a particular format;
/// the consuming application owns delivery and the driver retains full
/// responsibility.
library;

import 'driver_profile.dart';
import 'road_surface_condition.dart';

/// Verbosity level for action-coupled explainer text.
///
/// Mapping per profile:
///
/// - `professional` → [terse]
/// - `snowZoneExperienced` → [brief]
/// - `noviceUrban`, `agriculturalForestry` → [standard]
/// - `ageingRural`, `foreignTouristSnowZone` → [full]
enum VerbosityLevel {
  /// Single short clause; trained / time-pressed driver.
  terse,

  /// Condition + brief action. Experienced driver vocabulary.
  brief,

  /// Condition + action + short hazard tag.
  standard,

  /// Full causal explainer with action and reference.
  full,
}

/// Action-coupled explainer for a (condition, profile) pair.
///
/// Design rationale:
///
/// - **Failure mode this prevents** — the condition-only alert ("icy
///   road") that names a hazard without naming the driver action it
///   implies. If this package shipped condition strings alone, the
///   integrating app developer would silently absorb the job of
///   coupling each condition to an action. This class prevents that by
///   shipping the (condition, action, verbosity, locale) tuple at the
///   package boundary.
/// - **How it works** — the 36-cell `_actionFor` table is the recorded
///   per-(condition, profile) decision; no source is cited for its
///   wording.
/// - **What it will not do** — it never ships half a recommendation.
///   Verbosity, locale and vocabulary are matched to each driver class,
///   so no class is forced into another class's vocabulary.
///
/// Carries the condition under which the explainer applies, the
/// pre-localized action string, the verbosity level the active profile
/// expects, and the locale tag of the action string.
class AlertExplainer {
  /// The road-surface condition the action addresses.
  final RoadSurfaceCondition condition;

  /// Action string in the language and verbosity for the active
  /// profile. Non-null for every (condition, profile) pair.
  ///
  /// Wording discipline: advisory mood, no imperative-on-control
  /// language, no outcome promises. See top-of-file class comment.
  final String action;

  /// Verbosity level the active profile expects.
  final VerbosityLevel verbosity;

  /// Locale tag of [action] (e.g. `'ja'`, `'en'`).
  ///
  /// Foreign-tourist defaults to `'en'`; other profiles default to
  /// `'ja'`.
  final String localeTag;

  const AlertExplainer({
    required this.condition,
    required this.action,
    required this.verbosity,
    required this.localeTag,
  });

  /// Look up the (condition, action) tuple for the active
  /// profile.
  ///
  /// Returns the verbosity level that profile expects and the
  /// pre-localized action string. The 36 high-action cells (6 profiles
  /// × 6 high-action conditions: WET, SNOW, ICE, SLUSH, WET_ICE,
  /// LOOSE_GRAVEL) are the package's own wording. UNKNOWN and DRY get
  /// profile-flat content (no per-profile differentiation
  /// for those two conditions in v0.4).
  factory AlertExplainer.forConditionAndProfile(
    RoadSurfaceCondition condition,
    DriverProfile profile,
  ) {
    final action = _actionFor(condition, profile);
    final verbosity = _verbosityFor(profile);
    final locale = _localeFor(profile);
    return AlertExplainer(
      condition: condition,
      action: action,
      verbosity: verbosity,
      localeTag: locale,
    );
  }

  /// Verbosity level for [profile].
  static VerbosityLevel _verbosityFor(DriverProfile profile) {
    switch (profile) {
      case DriverProfile.professional:
        return VerbosityLevel.terse;
      case DriverProfile.snowZoneExperienced:
        return VerbosityLevel.brief;
      case DriverProfile.noviceUrban:
      case DriverProfile.agriculturalForestry:
        return VerbosityLevel.standard;
      case DriverProfile.ageingRural:
      case DriverProfile.foreignTouristSnowZone:
        return VerbosityLevel.full;
    }
  }

  /// Locale tag for [profile]. EN for foreign-tourist; JA for others.
  static String _localeFor(DriverProfile profile) {
    if (profile == DriverProfile.foreignTouristSnowZone) {
      return 'en';
    }
    return 'ja';
  }

  /// Per-(condition, profile) action string.
  ///
  /// 36 high-action cells; UNKNOWN
  /// and DRY get profile-flat content (one string per profile).
  /// JAF's snow-driving page (https://jaf.or.jp/common/attention/snow)
  /// also uses ブラックアイスバーン and names windy bridges, overpasses
  /// and tunnel entrances/exits as the most dangerous places
  /// (「風通しのよい橋の上や陸橋、トンネル出入口付近がもっとも危険」). The
  /// rest of the wording is the package's.
  static String _actionFor(
    RoadSurfaceCondition condition,
    DriverProfile profile,
  ) {
    switch (condition) {
      case RoadSurfaceCondition.unknown:
        // Profile-flat: condition not yet determined; brief acknowledgement.
        if (profile == DriverProfile.foreignTouristSnowZone) {
          return 'Road surface unknown. Drive carefully.';
        }
        return '路面状況不明。慎重に運転してください';

      case RoadSurfaceCondition.dry:
        // Profile-flat: the condition, and nothing after it. Until
        // 2026-09-25 this cell added 「通常運転で問題ありません」 /
        // "Maintain normal driving.": an all-clear this package cannot
        // know. It sees neither the road nor the traffic, and black ice
        // can look dry.
        if (profile == DriverProfile.foreignTouristSnowZone) {
          return 'Road is dry.';
        }
        return '乾燥路面';

      case RoadSurfaceCondition.wet:
        switch (profile) {
          case DriverProfile.ageingRural:
            // Black ice (ブラックアイスバーン, JAF's term) can form while the
            // air is above 0°C: radiative cooling "can cause frost or black
            // ice to form on surfaces exposed to the clear night sky, even
            // when the ambient temperature does not fall below freezing"
            // (Wikipedia, "Radiative cooling"). JAF names bridges and tunnel
            // entrances/exits among the most dangerous places. The string
            // must not condition ice on sub-zero air temperature.
            return '路面が濡れています。気温が0°Cより高くても路面は先に冷えて凍り、'
                'ブラックアイスバーンになることがあります。'
                '橋やトンネル出口で速度を落としてください';
          case DriverProfile.snowZoneExperienced:
            return '濡れた路面、橋やトンネル出口で注意';
          case DriverProfile.noviceUrban:
            return '濡れた路面、危険。スピードを落としてください';
          case DriverProfile.professional:
            // 「濡路」was the one outlier among six profiles that all otherwise
            // say 「濡れた路面」— and it is the one that reaches her EARS as
            // nothing: measured through open_jtalk it renders as SILENCE, so a
            // professional driver hears 「（無音）、注意」— a caution with no
            // hazard named. Terse is right for this profile; unpronounceable is
            // not.
            return '濡れた路面、注意';
          case DriverProfile.agriculturalForestry:
            return '濡れた路面、未舗装路では泥濘に注意';
          case DriverProfile.foreignTouristSnowZone:
            return 'Wet road. Reduce speed. Watch for ice on bridges.';
        }

      case RoadSurfaceCondition.snow:
        switch (profile) {
          case DriverProfile.ageingRural:
            return '圧雪路面です。雪は固く凍結に近い状態です。'
                '速度を落とし、急ブレーキ・急ハンドルを避けてください';
          case DriverProfile.snowZoneExperienced:
            return '圧雪、減速、急操作回避';
          case DriverProfile.noviceUrban:
            return '圧雪路面、滑ります。スピードを大きく落とし、'
                'ゆっくり運転してください';
          case DriverProfile.professional:
            return '圧雪、減速';
          case DriverProfile.agriculturalForestry:
            return '圧雪路面、トラクションタイヤ・チェーン推奨';
          case DriverProfile.foreignTouristSnowZone:
            return 'Compacted snow. Drive slowly. '
                'Avoid sudden braking or steering.';
        }

      case RoadSurfaceCondition.ice:
        switch (profile) {
          case DriverProfile.ageingRural:
            // The previous string asserted 「気温0°C以下で薄氷ができています」
            // — false: thin ice forms with air above 0°C too. Radiative
            // cooling "can cause frost or black ice to form on surfaces
            // exposed to the clear night sky, even when the ambient
            // temperature does not fall below freezing" (Wikipedia,
            // "Radiative cooling"), and black ice
            // "forms first on bridges and overpasses" (Wikipedia,
            // "Black ice"); JAF names bridges among the most dangerous
            // places. Ice existence must never be conditioned on sub-zero
            // air.
            return '凍結路面です。気温が0°Cより高くても路面は空気より冷え、'
                '薄氷ができることがあります。橋の上は特に凍りやすい場所です。'
                '時速30km以下に減速し、急ブレーキは避けてください';
          case DriverProfile.snowZoneExperienced:
            return '凍結路面。30km/h以下に減速';
          case DriverProfile.noviceUrban:
            return '凍結、危険です。時速30kmまで減速し、車間距離を倍に';
          case DriverProfile.professional:
            return '凍結、30km/h';
          case DriverProfile.agriculturalForestry:
            return '凍結路面、未舗装路ではグリップ大幅低下';
          case DriverProfile.foreignTouristSnowZone:
            return 'Icy road. Slow to 30 km/h. Avoid sudden braking.';
        }

      case RoadSurfaceCondition.slush:
        // Until 0.11.12 four of these cells told her to keep to the centre
        // (「道路中央寄りを走行」, 「中央走行」 twice, and "center of lane" -- the
        // Japanese said the road, the English said the lane). A steering
        // target is control, not advice, and on a two-way road without marked
        // lanes the centre is toward oncoming traffic: Japan's Road Traffic
        // Act, Art. 18(1), has vehicles keep to the left (「道路の左側に寄つて」).
        // The risk these strings name is sliding sideways; the request that
        // fits it is to slow down, in the words the noviceUrban cell uses.
        switch (profile) {
          case DriverProfile.ageingRural:
            return 'シャーベット状の路面です。タイヤが横に滑る危険があるため、'
                '車線変更を避け、ゆっくり走行してください';
          case DriverProfile.snowZoneExperienced:
            return 'シャーベット、車線変更回避、減速';
          case DriverProfile.noviceUrban:
            return 'シャーベット路面、ハンドルを取られやすい状態。'
                '車線変更せず、ゆっくり走行してください';
          case DriverProfile.professional:
            return 'シャーベット、減速';
          case DriverProfile.agriculturalForestry:
            return 'シャーベット、轍（わだち）に注意';
          case DriverProfile.foreignTouristSnowZone:
            return 'Slush. Avoid lane changes. '
                'Drive slowly.';
        }

      case RoadSurfaceCondition.wetIce:
        switch (profile) {
          case DriverProfile.ageingRural:
            return 'アイスバーンです。最も滑りやすい路面の一つです。'
                '安全にできるときは、安全な場所での停車も選べます。'
                '走行中は時速20km以下を目安に';
          case DriverProfile.snowZoneExperienced:
            return 'アイスバーン、極めて危険、20km/h以下';
          case DriverProfile.noviceUrban:
            return 'アイスバーン、極めて危険。'
                '安全にできるときは、安全な場所での停車も選べます。'
                '走行時は時速20km以下に';
          case DriverProfile.professional:
            return 'アイスバーン、20km/h';
          case DriverProfile.agriculturalForestry:
            return 'アイスバーン、最低速で。安全な場所での停車も選べます';
          case DriverProfile.foreignTouristSnowZone:
            return 'Wet ice — among the most slippery road surfaces. '
                'If you can do so safely, pausing at a safe place is an '
                'option. While driving, stay below 20 km/h.';
        }

      case RoadSurfaceCondition.looseGravel:
        switch (profile) {
          case DriverProfile.ageingRural:
            return '砂利が浮いています。急ブレーキで滑る可能性があるため、'
                '十分な車間距離をとってください';
          case DriverProfile.snowZoneExperienced:
            return '砂利、車間距離注意';
          case DriverProfile.noviceUrban:
            return '砂利路面、ブレーキ距離が伸びます。車間を空けてください';
          case DriverProfile.professional:
            return '砂利、車間注意';
          case DriverProfile.agriculturalForestry:
            return '砂利路面（通常運用範囲）、後続車に小石注意';
          case DriverProfile.foreignTouristSnowZone:
            return 'Loose gravel. Sudden braking may cause a skid. '
                'Increase following distance.';
        }
    }
  }
}
