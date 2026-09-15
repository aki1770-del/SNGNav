/// Road-surface condition vocabulary, matching the upstream VSS
/// `Vehicle.Exterior.RoadSurfaceCondition` allowed-value set.
///
/// VSS PR #892 (https://github.com/COVESA/vehicle_signal_specification/pull/892)
/// adds the canonical sensor signal with allowed values:
///
///   UNKNOWN, DRY, WET, SNOW, ICE, SLUSH, WET_ICE, LOOSE_GRAVEL
///
/// The 0.3.1 patch surfaces these eight values plus a small glossary
/// keyed on driver-class. The glossary pairs each road-surface term
/// (圧雪 / アイスバーン / 凍結 / シャーベット) with the safe-driving action it is
/// meant to convey; no source is cited for what drivers know of these
/// terms or of the action each
/// implies. JAF's snow-driving page
/// (https://jaf.or.jp/common/attention/snow) uses アイスバーン and
/// ブラックアイスバーン; the glossary wording is otherwise the package's
/// own (a recorded decision).
///
/// The glossary text is informational only. It does not control the
/// vehicle and is not safety-critical in the sense of actuating any
/// behavior; it provides labels and TTS-ready phrases for consuming
/// applications that wish to surface road-surface vocabulary the
/// driver will recognize.
library;

import 'driver_profile.dart';

/// Road-surface condition aligned to VSS allowed-value set.
///
/// Round-trip helpers [vssValue] and [fromVss] preserve the upstream
/// string vocabulary verbatim so consuming code can interoperate with
/// VSS-derived telemetry without re-mapping.
enum RoadSurfaceCondition {
  /// VSS `UNKNOWN`. Sensor cannot determine current road-surface state.
  unknown,

  /// VSS `DRY`. Surface is dry.
  dry,

  /// VSS `WET`. Surface is wet (rain, melted snow, splash).
  wet,

  /// VSS `SNOW`. Surface has compacted snow (圧雪) — distinct from
  /// generic falling snow. The term 圧雪 names a road state, not falling
  /// snow (a recorded wording decision).
  snow,

  /// VSS `ICE`. Surface is iced over (凍結). Includes the sub-class
  /// commonly called "black ice" — the upstream VSS signal does not
  /// expose a separate enum value for it. See KNOWN_LIMITATIONS.md.
  ice,

  /// VSS `SLUSH`. Surface has slush (シャーベット状) — partially melted
  /// snow with high lateral-slip risk.
  slush,

  /// VSS `WET_ICE`. Surface is wet ice — ice with a water film on top
  /// (this package's gloss; VSS gives no definition). The glossary labels
  /// it アイスバーン with the parenthetical reading 濡れた凍結, a recorded
  /// wording decision meant to anchor the meaning for first-time hearers.
  /// No source cited here ranks it as the most slippery condition. The
  /// Japanese spoken strings for this value (最も滑りやすい, 最も滑ります)
  /// and AlertExplainer's wet-ice explanations still rank it so; that
  /// wording is unchanged in this release, and the ranking in it is not
  /// sourced.
  wetIce,

  /// VSS `LOOSE_GRAVEL`. Surface has loose gravel — increases stopping
  /// distance and risks projectile to following vehicles.
  looseGravel;

  /// VSS allowed-value string for this condition.
  ///
  /// One of: `UNKNOWN`, `DRY`, `WET`, `SNOW`, `ICE`, `SLUSH`, `WET_ICE`,
  /// `LOOSE_GRAVEL`. Use this when serializing to VSS-derived telemetry
  /// or when interoperating with upstream-blessed vocabulary.
  String get vssValue {
    switch (this) {
      case RoadSurfaceCondition.unknown:
        return 'UNKNOWN';
      case RoadSurfaceCondition.dry:
        return 'DRY';
      case RoadSurfaceCondition.wet:
        return 'WET';
      case RoadSurfaceCondition.snow:
        return 'SNOW';
      case RoadSurfaceCondition.ice:
        return 'ICE';
      case RoadSurfaceCondition.slush:
        return 'SLUSH';
      case RoadSurfaceCondition.wetIce:
        return 'WET_ICE';
      case RoadSurfaceCondition.looseGravel:
        return 'LOOSE_GRAVEL';
    }
  }

  /// Round-trip parse from a VSS allowed-value string.
  ///
  /// Throws [ArgumentError] on an unknown string. Caller is responsible
  /// for handling unknown values; silent fallback to `unknown` would
  /// hide upstream schema drift (a future VSS revision could add
  /// values that this 0.3.1 enum does not yet enumerate).
  static RoadSurfaceCondition fromVss(String value) {
    switch (value) {
      case 'UNKNOWN':
        return RoadSurfaceCondition.unknown;
      case 'DRY':
        return RoadSurfaceCondition.dry;
      case 'WET':
        return RoadSurfaceCondition.wet;
      case 'SNOW':
        return RoadSurfaceCondition.snow;
      case 'ICE':
        return RoadSurfaceCondition.ice;
      case 'SLUSH':
        return RoadSurfaceCondition.slush;
      case 'WET_ICE':
        return RoadSurfaceCondition.wetIce;
      case 'LOOSE_GRAVEL':
        return RoadSurfaceCondition.looseGravel;
      default:
        throw ArgumentError.value(
          value,
          'value',
          'Unknown VSS RoadSurfaceCondition allowed-value. Expected one '
              'of: UNKNOWN, DRY, WET, SNOW, ICE, SLUSH, WET_ICE, '
              'LOOSE_GRAVEL. If a newer VSS revision has added a value, '
              'update navigation_safety_core to match.',
        );
    }
  }
}

/// Display labels and TTS-ready phrases for a [RoadSurfaceCondition].
///
/// Each entry carries:
/// - [jaName] — formal Japanese label suitable for on-screen display.
/// - [enName] — formal English label suitable for on-screen display.
/// - [jaSpeakString] — TTS-ready Japanese phrase (full sentence).
/// - [enSpeakString] — TTS-ready English phrase (full sentence).
///
/// The strings are the package's own wording (a recorded decision);
/// wording is conservative (no specific km/h advice in the bare
/// glossary — speed advice belongs to a separate action-coupled
/// explainer surface, not the bare label).
class RoadSurfaceConditionGlossary {
  /// Formal Japanese label (e.g. 圧雪路面 for `SNOW`).
  final String jaName;

  /// Formal English label (e.g. "Compacted snow" for `SNOW`).
  final String enName;

  /// TTS-ready Japanese phrase (e.g. 「圧雪路面です」).
  final String jaSpeakString;

  /// TTS-ready English phrase (e.g. "Compacted snow on road").
  final String enSpeakString;

  const RoadSurfaceConditionGlossary({
    required this.jaName,
    required this.enName,
    required this.jaSpeakString,
    required this.enSpeakString,
  });

  /// Default glossary entry for [c] (no profile-specific overrides).
  ///
  /// Use this when the consuming app does not yet know the active
  /// driver profile, or when a profile-neutral surface is desired.
  static RoadSurfaceConditionGlossary forCondition(RoadSurfaceCondition c) {
    switch (c) {
      case RoadSurfaceCondition.unknown:
        return const RoadSurfaceConditionGlossary(
          jaName: '路面状況不明',
          enName: 'Road surface unknown',
          jaSpeakString: '路面の状況が確認できません',
          enSpeakString: 'Road surface unknown',
        );
      case RoadSurfaceCondition.dry:
        return const RoadSurfaceConditionGlossary(
          jaName: '乾燥路面',
          enName: 'Dry road',
          jaSpeakString: '路面は乾燥しています',
          enSpeakString: 'Road is dry',
        );
      case RoadSurfaceCondition.wet:
        return const RoadSurfaceConditionGlossary(
          jaName: '湿潤路面',
          enName: 'Wet road',
          jaSpeakString: '路面が濡れています',
          enSpeakString: 'Road is wet',
        );
      case RoadSurfaceCondition.snow:
        // 圧雪 (compacted snow) chosen over generic 雪 — generic 雪
        // conflates falling snow with road-state.
        return const RoadSurfaceConditionGlossary(
          jaName: '圧雪路面',
          enName: 'Compacted snow',
          jaSpeakString: '圧雪路面です',
          enSpeakString: 'Compacted snow on road',
        );
      case RoadSurfaceCondition.ice:
        // 凍結 (kanji-native) is a recorded wording decision.
        return const RoadSurfaceConditionGlossary(
          jaName: '凍結路面',
          enName: 'Icy road',
          jaSpeakString: '路面が凍結しています',
          enSpeakString: 'Road is icy',
        );
      case RoadSurfaceCondition.slush:
        return const RoadSurfaceConditionGlossary(
          jaName: 'シャーベット路面',
          enName: 'Slush',
          jaSpeakString: 'シャーベット状の路面です',
          enSpeakString: 'Slush on road',
        );
      case RoadSurfaceCondition.wetIce:
        // アイスバーン with the parenthetical 濡れた凍結 labels the
        // wet-film-on-ice condition (a recorded wording decision; JAF uses
        // アイスバーン without defining it as ice with a water film).
        return const RoadSurfaceConditionGlossary(
          jaName: 'アイスバーン（濡れた凍結）',
          enName: 'Wet ice (ice with water film)',
          jaSpeakString: 'ぬれた凍結路面、アイスバーンです',
          enSpeakString: 'Wet ice on road, very slippery',
        );
      case RoadSurfaceCondition.looseGravel:
        return const RoadSurfaceConditionGlossary(
          jaName: '砂利路面',
          enName: 'Loose gravel',
          jaSpeakString: '砂利が浮いています',
          enSpeakString: 'Loose gravel on road',
        );
    }
  }

  /// Profile-aware glossary entry for [c] under [profile].
  ///
  /// Per-profile speak-string overrides apply ONLY for the high-risk
  /// conditions where vocabulary precision matters most: `ICE`, `SNOW`,
  /// `WET_ICE`, and (added 0.7.1) `SLUSH`. Other conditions (`UNKNOWN`,
  /// `DRY`, `WET`, `LOOSE_GRAVEL`) fall through to the default
  /// speak-strings from [forCondition].
  ///
  /// SLUSH (シャーベット) was added to the high-risk subset in 0.7.1 for
  /// the lateral-slip risk of partially-melted snow (a recorded decision;
  /// no source is cited for how drivers judge that risk).
  ///
  /// Profile-specific design rules:
  /// - `ageingRural` — full kanji-native phrasing with a brief action cue.
  /// - `snowZoneExperienced` — terse single-token (matches expert
  ///   driver vocabulary; minimum cognitive load).
  /// - `noviceUrban` — explicit hazard wording (less low-vis / icy-road
  ///   experience; phrasing surfaces the danger explicitly).
  /// - `professional` — terse single-token (commercial drivers value
  ///   minimum-distraction phrasing; trained vocabulary).
  /// - `agriculturalForestry` — terse formal label (matches off-road
  ///   operating context; no speed cues since speeds are off-road
  ///   work-pace, not highway).
  /// - `foreignTouristSnowZone` — English by default for TTS; simplified
  ///   Japanese available via [jaSpeakString] for apps that surface
  ///   both. Avoid kanji-only output for this profile — non-native
  ///   readers cannot parse mid-drive.
  static RoadSurfaceConditionGlossary forConditionAndProfile(
    RoadSurfaceCondition c,
    DriverProfile profile,
  ) {
    final defaults = forCondition(c);

    // Per-profile overrides apply only for ICE, SNOW, WET_ICE, SLUSH.
    if (c != RoadSurfaceCondition.ice &&
        c != RoadSurfaceCondition.snow &&
        c != RoadSurfaceCondition.wetIce &&
        c != RoadSurfaceCondition.slush) {
      return defaults;
    }

    switch (profile) {
      case DriverProfile.ageingRural:
        switch (c) {
          case RoadSurfaceCondition.ice:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '凍結路面です。スピードを落としてください',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.snow:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '圧雪路面です。慎重に運転してください',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.wetIce:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'アイスバーンです。最も滑りやすい状態です',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.slush:
            // Full kanji-native phrasing with brief action cue.
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'シャーベット路面です。横滑りに注意してください',
              enSpeakString: defaults.enSpeakString,
            );
          default:
            return defaults;
        }
      case DriverProfile.snowZoneExperienced:
        switch (c) {
          case RoadSurfaceCondition.ice:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '凍結',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.snow:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '圧雪',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.wetIce:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'アイスバーン',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.slush:
            // Terse single-token (matches expert driver vocabulary;
            // minimum cognitive load).
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'シャーベット',
              enSpeakString: defaults.enSpeakString,
            );
          default:
            return defaults;
        }
      case DriverProfile.noviceUrban:
        switch (c) {
          case RoadSurfaceCondition.ice:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '路面が凍結しています、危険です',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.snow:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '圧雪、滑りやすい路面です',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.wetIce:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'アイスバーンです、最大限注意してください',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.slush:
            // Explicit hazard wording (less low-vis / icy-road
            // experience; phrasing surfaces the danger explicitly).
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'シャーベット路面、横滑りの危険があります',
              enSpeakString: defaults.enSpeakString,
            );
          default:
            return defaults;
        }
      case DriverProfile.professional:
        switch (c) {
          case RoadSurfaceCondition.ice:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '凍結',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.snow:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '圧雪',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.wetIce:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'アイスバーン',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.slush:
            // Terse single-token (commercial drivers value
            // minimum-distraction phrasing; trained vocabulary).
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'シャーベット',
              enSpeakString: defaults.enSpeakString,
            );
          default:
            return defaults;
        }
      case DriverProfile.agriculturalForestry:
        switch (c) {
          case RoadSurfaceCondition.ice:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '凍結路面',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.snow:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: '圧雪路面',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.wetIce:
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'アイスバーンあり',
              enSpeakString: defaults.enSpeakString,
            );
          case RoadSurfaceCondition.slush:
            // Terse formal label (matches off-road operating context).
            return RoadSurfaceConditionGlossary(
              jaName: defaults.jaName,
              enName: defaults.enName,
              jaSpeakString: 'シャーベット路面',
              enSpeakString: defaults.enSpeakString,
            );
          default:
            return defaults;
        }
      case DriverProfile.foreignTouristSnowZone:
        // English-default policy: TTS uses EN string; simplified JA
        // available via jaSpeakString for apps that surface both.
        // Avoid kanji-only output — non-native readers cannot parse
        // mid-drive.
        switch (c) {
          case RoadSurfaceCondition.ice:
            return const RoadSurfaceConditionGlossary(
              jaName: '凍結路面',
              enName: 'Icy road',
              jaSpeakString: '氷の道、ゆっくり',
              enSpeakString: 'Icy road, slow down',
            );
          case RoadSurfaceCondition.snow:
            return const RoadSurfaceConditionGlossary(
              jaName: '圧雪路面',
              enName: 'Compacted snow',
              jaSpeakString: '雪道、注意',
              enSpeakString: 'Snow on road, drive carefully',
            );
          case RoadSurfaceCondition.wetIce:
            return const RoadSurfaceConditionGlossary(
              jaName: 'アイスバーン（濡れた凍結）',
              enName: 'Wet ice (ice with water film)',
              jaSpeakString: 'ぬれた凍結路面、最も滑ります',
              enSpeakString: 'Wet ice, very slippery, drive very slowly',
            );
          case RoadSurfaceCondition.slush:
            // Simplified vocabulary; explicit slip-class warning.
            return const RoadSurfaceConditionGlossary(
              jaName: 'シャーベット路面',
              enName: 'Slush',
              jaSpeakString: 'シャーベット、滑ります',
              enSpeakString: 'Slush on road, slippery',
            );
          default:
            return defaults;
        }
    }
  }
}
