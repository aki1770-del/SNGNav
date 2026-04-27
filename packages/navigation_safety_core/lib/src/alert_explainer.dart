/// Action-coupled alert explainer: pairs a [RoadSurfaceCondition] with
/// the recommended driver action in the language and verbosity that
/// fits the active [DriverProfile].
///
/// Why this exists (literature anchors):
///
/// Alerts that name a condition without naming the implied action
/// degrade compliance. Two anchors:
///
/// - Medication-adherence literature (PMID 34111571) shows action-
///   coupled instructions improve adherence over condition-only.
/// - CGM (continuous glucose monitor) alert-design literature (MDPI
///   2024 review of CGM UX patterns) finds the same pattern in
///   ambient-monitoring contexts.
///
/// Translation to driving: "icy road" is incomplete; "icy road →
/// reduce speed to 30 km/h" is actionable.
///
/// Action-text discipline (advisory mood, not control):
///
/// - Action verbs are advisory ("reduce" / "avoid" / "maintain"),
///   never imperative-on-control ("brake now" / "the system will slow
///   you").
/// - Speed numbers (30 km/h, 20 km/h) are published reference points,
///   not system-enforced limits. Wording uses 「以下に減速」 ("reduce
///   to or below") / "Slow to" — the driver retains full speed
///   authority.
/// - "Stop in a safe place" is the strongest action; phrased "if
///   possible" / 「可能であれば」 — does not imply the system stops the
///   vehicle.
/// - No action string promises an outcome. Each is a recommendation
///   grounded in published JAF / MLIT driving-guidance vocabulary.
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

  /// Look up the AAA-designed (condition, action) tuple for the active
  /// profile.
  ///
  /// Returns the verbosity level that profile expects and the
  /// pre-localized action string. The 36 high-action cells (6 profiles
  /// × 6 high-action conditions: WET, SNOW, ICE, SLUSH, WET_ICE,
  /// LOOSE_GRAVEL) come from the AAA design brief, sourced from JAF /
  /// MLIT public driving-guidance materials. UNKNOWN and DRY get
  /// profile-flat content per the brief (no per-profile differentiation
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

  /// Verbosity level for [profile] per the AAA design brief mapping.
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
  /// 36 high-action cells from the AAA design brief table; UNKNOWN
  /// and DRY get profile-flat content (one string per profile).
  /// Sources: JAF snow-driving safety, MLIT Hokkaido snow-road guide,
  /// NEXCO public driver-guidance.
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
        // Profile-flat: routine condition; minimal advisory.
        if (profile == DriverProfile.foreignTouristSnowZone) {
          return 'Road is dry. Maintain normal driving.';
        }
        return '乾燥路面、通常運転で問題ありません';

      case RoadSurfaceCondition.wet:
        switch (profile) {
          case DriverProfile.ageingRural:
            return '路面が濡れています。ブラックアイスが形成される可能性があるため、'
                '橋やトンネル出口で速度を落としてください';
          case DriverProfile.snowZoneExperienced:
            return '濡れた路面、橋やトンネル出口で注意';
          case DriverProfile.noviceUrban:
            return '濡れた路面、危険。スピードを落としてください';
          case DriverProfile.professional:
            return '濡路、注意';
          case DriverProfile.agriculturalForestry:
            return '濡れた路面、未舗装路では泥濘に注意';
          case DriverProfile.foreignTouristSnowZone:
            return 'Wet road. Reduce speed. Watch for ice on bridges.';
        }

      case RoadSurfaceCondition.snow:
        switch (profile) {
          case DriverProfile.ageingRural:
            return '圧雪路面です。雪は固く凍結に近い状態です。'
                '低速ギアを保ち、急ブレーキ・急ハンドルを避けてください';
          case DriverProfile.snowZoneExperienced:
            return '圧雪、低速ギア、急操作回避';
          case DriverProfile.noviceUrban:
            return '圧雪路面、滑ります。スピードを大きく落とし、'
                'ゆっくり運転してください';
          case DriverProfile.professional:
            return '圧雪、低速ギア';
          case DriverProfile.agriculturalForestry:
            return '圧雪路面、トラクションタイヤ・チェーン推奨';
          case DriverProfile.foreignTouristSnowZone:
            return 'Compacted snow. Drive slowly. '
                'Avoid sudden braking or steering.';
        }

      case RoadSurfaceCondition.ice:
        switch (profile) {
          case DriverProfile.ageingRural:
            return '凍結路面です。気温0°C以下で薄氷ができています。'
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
        switch (profile) {
          case DriverProfile.ageingRural:
            return 'シャーベット状の路面です。タイヤが横に滑る危険があるため、'
                '車線変更を避け、道路中央寄りを走行してください';
          case DriverProfile.snowZoneExperienced:
            return 'シャーベット、車線変更回避、中央走行';
          case DriverProfile.noviceUrban:
            return 'シャーベット路面、ハンドルを取られやすい状態。'
                '車線変更せず、ゆっくり走行してください';
          case DriverProfile.professional:
            return 'シャーベット、中央走行';
          case DriverProfile.agriculturalForestry:
            return 'シャーベット、轍（わだち）に注意';
          case DriverProfile.foreignTouristSnowZone:
            return 'Slush. Avoid lane changes. '
                'Drive slowly in center of lane.';
        }

      case RoadSurfaceCondition.wetIce:
        switch (profile) {
          case DriverProfile.ageingRural:
            return 'アイスバーンです。最も滑りやすい路面状態です。'
                '可能であれば停車できる安全な場所を探してください。'
                '走行中は時速20km以下を目安に';
          case DriverProfile.snowZoneExperienced:
            return 'アイスバーン、最危険、20km/h以下';
          case DriverProfile.noviceUrban:
            return 'アイスバーン、極めて危険。'
                '可能なら安全な場所で停車してください。'
                '走行時は時速20km以下に';
          case DriverProfile.professional:
            return 'アイスバーン、20km/h';
          case DriverProfile.agriculturalForestry:
            return 'アイスバーン、停車できる場所まで最低速で';
          case DriverProfile.foreignTouristSnowZone:
            return 'Wet ice — most slippery condition. '
                'If possible, stop in a safe place. '
                'Otherwise drive below 20 km/h.';
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
            return 'Loose gravel. Increase following distance. Brake gently.';
        }
    }
  }
}
