/// Router-agnostic turn-by-turn instruction localizer.
///
/// Closes the gap where a routing engine emits hardcoded English even when the
/// [RouteRequest.language] asked for another locale (SNGNav defaults 'ja-JP').
/// HER — driving in Akita — asks for Japanese; this hands her Japanese.
///
/// Design note (deliberately the OPPOSITE of a crash-the-leg lookup): a missing
/// locale or an unknown maneuver type NEVER throws and NEVER blanks the
/// instruction. It gracefully degrades to a safe, correct fallback (the engine's
/// own English) rather than emit a WRONG localized instruction — a wrong turn
/// instruction is worse for a driver than an honest English one.
///
/// Keyed on the engine-agnostic canonical maneuver type (see the OSRM engine's
/// type mapping): depart, arrive, straight, left, right, slight_left,
/// slight_right, sharp_left, sharp_right, u_turn_left, u_turn_right,
/// roundabout_enter, merge, ramp_left, ramp_right.
library;

class ManeuverLocalizer {
  ManeuverLocalizer._();

  /// Locales this localizer can produce natively. Anything else degrades to
  /// the supplied English fallback.
  static const Set<String> supportedPrimaryLanguages = {'ja'};

  /// Whether [language] can be localized natively (matches on the primary
  /// subtag, so 'ja', 'ja-JP', 'ja_JP' all resolve to Japanese).
  static bool supports(String language) =>
      supportedPrimaryLanguages.contains(_primary(language));

  /// Primary language subtag, lower-cased (e.g. 'ja-JP' -> 'ja').
  static String _primary(String language) =>
      language.split(RegExp('[-_]')).first.toLowerCase();

  /// Localize one maneuver.
  ///
  /// - [language] — BCP-47-ish tag from the request (e.g. 'ja-JP').
  /// - [type] — canonical engine-agnostic maneuver type.
  /// - [streetName] — the road entered/traversed (may be empty).
  /// - [roundaboutExit] — 1-based exit ordinal for roundabout maneuvers, when
  ///   the engine supplies it (OSRM `maneuver.exit`). A multi-exit roundabout
  ///   in low visibility needs the ordinal — direction alone can send the
  ///   driver out the wrong exit.
  /// - [englishFallback] — produces the engine's own English string; used when
  ///   the language is unsupported OR the type has no localization. When null,
  ///   a minimal built-in English baseline is used so the localizer is
  ///   self-contained and independently testable.
  static String localize({
    required String language,
    required String type,
    String streetName = '',
    int? roundaboutExit,
    String Function()? englishFallback,
  }) {
    final fallback =
        englishFallback ?? () => _englishBaseline(type, streetName.trim());
    if (_primary(language) == 'ja') {
      return _japanese(type, streetName.trim(), roundaboutExit) ?? fallback();
    }
    return fallback();
  }

  /// Japanese car-navigation register. Returns `null` for an unknown type so
  /// the caller degrades to English rather than emit a wrong instruction.
  ///
  /// For turns, the street name is the road being *entered*, so the natural
  /// phrasing is "{name}方面へ〜" (toward {name}, turn …); for depart/straight
  /// the name is the road being *travelled*, so "{name}を〜".
  ///
  /// Sharp turns use 鋭角 (acute angle) — deliberately NOT 大きく, which reads
  /// as a wide/gentle sweeping arc (the inverse severity: a driver would carry
  /// too much speed into a tight turn on snow), and NOT 急な, which can read as
  /// timing urgency ("suddenly") rather than geometry. 鋭角 is unambiguous and
  /// preserves the tight-turn-slow-down cue.
  static String? _japanese(String type, String street, [int? exit]) {
    final named = street.isNotEmpty;
    switch (type) {
      case 'depart':
        return named ? '$streetを出発' : '出発';
      case 'arrive':
        return '目的地に到着';
      case 'straight':
      case 'continue':
      case 'new name':
        return named ? '$streetを直進' : '直進';
      // The road geometry is unknown/unstated — defer to the road itself
      // (道なりに = follow the road) rather than fabricate a positive 直進.
      case 'proceed':
        return '道なりに進む';
      case 'left':
        return named ? '$street方面へ左折' : '左折';
      case 'right':
        return named ? '$street方面へ右折' : '右折';
      case 'slight_left':
        return named ? '$street方面へ斜め左方向' : '斜め左方向';
      case 'slight_right':
        return named ? '$street方面へ斜め右方向' : '斜め右方向';
      case 'sharp_left':
        return named ? '$street方面へ鋭角に左折' : '鋭角に左折';
      case 'sharp_right':
        return named ? '$street方面へ鋭角に右折' : '鋭角に右折';
      case 'u_turn_left':
      case 'u_turn_right':
      case 'uturn':
        return 'Uターン';
      case 'roundabout_enter':
      case 'roundabout':
      case 'rotary':
        if (exit != null && exit > 0) {
          return named
              ? 'ロータリーに入り$exit番目の出口で$street方面へ進む'
              : 'ロータリーに入り$exit番目の出口を出る';
        }
        return named ? 'ロータリーに入り$street方面へ進む' : 'ロータリーに入る';
      case 'roundabout_exit':
        return named ? '$street方面へロータリーを出る' : 'ロータリーを出る';
      case 'merge':
        return named ? '$streetに合流' : '合流';
      case 'ramp_right':
        return named ? '$street方面へ右側の分岐を進む' : '右側の分岐を進む';
      case 'ramp_left':
        return named ? '$street方面へ左側の分岐を進む' : '左側の分岐を進む';
      // A ramp whose side the engine did not state — never fabricate a side.
      case 'ramp':
        return named ? '$street方面へ進む' : '分岐に進む';
      default:
        return null; // unknown -> caller degrades to English (never a wrong turn)
    }
  }

  /// Minimal English baseline mirroring the engine's own phrasing, used only
  /// when no [englishFallback] is supplied.
  static String _englishBaseline(String type, String street) {
    switch (type) {
      case 'depart':
        return street.isNotEmpty ? 'Depart on $street' : 'Depart';
      case 'arrive':
        return 'Arrive at destination';
      case 'proceed':
        return street.isNotEmpty
            ? 'Continue on $street'
            : 'Continue on the road';
    }
    final label = type.replaceAll('_', ' ');
    final capped =
        label.isEmpty ? '' : '${label[0].toUpperCase()}${label.substring(1)}';
    return street.isNotEmpty ? '$capped onto $street' : capped;
  }
}
