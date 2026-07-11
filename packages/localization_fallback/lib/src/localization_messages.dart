/// Localized driver-facing text for the honesty states this package emits.
///
/// Why this exists: [LocalizationMode] and [EstimateBasis] are honesty labels
/// first and status second — they exist to tell the driver, through the app,
/// how much to believe the dot on the map. An honesty label the driver cannot
/// read does not reach her. This package's whole point is that it never emits a
/// confidently-wrong fix; if the moment it says `lost` it says so only in
/// English, then for a mother in Akita who reads Japanese it has said nothing
/// at all, and the silence reads exactly like confidence.
///
/// It is a hand-rolled locale table, not a generated `gen-l10n` toolchain, on
/// purpose, and it deliberately copies the idiom already established by
/// `pretrip_decision_advisor`'s `PretripMessages`: this is pure Dart with no
/// Flutter, no network, and no codegen, so the worst-case offline path stays
/// dependency-light on a low-end ARM head unit. No new i18n mechanism is
/// introduced — this is the catalog's existing pattern applied to one more
/// package.
///
/// English stays the default ([LocalizationMessages.en]) and nothing about the
/// existing API changes, so every existing caller and test is byte-for-byte
/// unchanged. Japanese is OFFERED, never imposed.
///
/// Measured values (radius in metres, seconds since a trusted fix) are passed
/// through verbatim — a localization may reorder words but never restate a
/// measured number, so a faithful translation cannot drift a safety figure.
///
/// CLAIM CEILING (binding on every string in this file): these strings describe
/// *what we know about the position*. Not one of them makes a claim about the
/// ROAD, the WEATHER, or whether it is safe to proceed — this package measures
/// none of those and must never appear to. "We do not know where you are" is
/// the strongest thing it may say, and it is never dressed as "you are safe".
library;

import 'estimate_basis.dart';
import 'localization_estimate.dart';
import 'localization_mode.dart';

/// The localized driver-facing strings for this package's honesty states.
/// Resolve one for the active language; [LocalizationMessages.en] is the
/// default and the fallback for any language this package does not (yet) carry.
abstract class LocalizationMessages {
  const LocalizationMessages();

  /// English — the default and the fallback.
  static const LocalizationMessages en = _EnLocalizationMessages();

  /// Japanese — for a driver who reads Japanese.
  static const LocalizationMessages ja = _JaLocalizationMessages();

  /// Locale subtag separator, compiled once (this is hot on the low-end-ARM
  /// rebuild path, where [forLanguage] may be called on every position tick).
  static final RegExp _localeSep = RegExp('[_-]');

  /// Pick the table for [languageCode] (e.g. `'ja'`, `'ja_JP'`, `'JA'`),
  /// falling back to English for any language not carried. Never throws — an
  /// unsupported language degrades to the English honesty label, never to NO
  /// honesty label. Degrading to silence is the one thing this package may not
  /// do: silence reads as confidence.
  static LocalizationMessages forLanguage(String languageCode) {
    final base = languageCode.toLowerCase().split(_localeSep).first;
    return base == 'ja' ? ja : en;
  }

  // --- Mode: the honesty label itself ---------------------------------------

  /// Short label for [mode] — chip / badge length, safe to show beside the dot.
  String modeLabel(LocalizationMode mode);

  /// One-sentence driver-facing explanation of what [mode] means for the dot.
  /// Speaks only about POSITION KNOWLEDGE — never about the road or the weather.
  String modeExplanation(LocalizationMode mode);

  // --- Basis: where the dot actually came from -------------------------------

  /// Short driver-facing provenance label for [basis] — which input produced
  /// the position being shown.
  String basisLabel(EstimateBasis basis);

  // --- The uncertainty, in numbers she can act on ---------------------------

  /// "Your position could be anywhere within about [meters] m." The number
  /// passes through verbatim.
  String positionWithinRadius(int meters);

  /// No trusted GPS fix for about [seconds] s. The number passes through
  /// verbatim.
  String noTrustedFixFor(int seconds);

  /// No plottable position at all — the bootstrap "nothing seen yet" state
  /// (`!hasPosition`). This is the honest 現在地不明: we are not showing a dot
  /// because we do not have one, NOT because everything is fine.
  String noPositionAtAll();

  /// What [describeEstimate] puts BETWEEN two composed sentences. A space in
  /// English; empty in Japanese, which does not space-separate sentences that
  /// already close with 。 — a stray ASCII space is the visible fingerprint of
  /// text translated by someone who never looked at the rendered result.
  String get sentenceSeparator => ' ';

  // --- The one-line summary an integrator can show without re-deriving -------

  /// A single driver-facing line describing [estimate]: its honesty label, and
  /// — when the position is not trusted — the radius the dot could be anywhere
  /// within. Composed from the members above; an integrator that wants a
  /// different shape may compose its own and is expected to.
  ///
  /// Never claims safety, never mentions the road. Rounds the radius and the
  /// elapsed seconds for display only; the underlying values are untouched.
  String describeEstimate(LocalizationEstimate estimate) {
    if (!estimate.hasPosition) return noPositionAtAll();
    if (estimate.mode == LocalizationMode.gpsTrusted) {
      return modeExplanation(estimate.mode);
    }
    final radius = estimate.confidenceRadiusMeters;
    final parts = <String>[modeExplanation(estimate.mode)];
    if (radius.isFinite && radius >= 0) {
      parts.add(positionWithinRadius(radius.round()));
    }
    return parts.join(sentenceSeparator);
  }
}

class _EnLocalizationMessages extends LocalizationMessages {
  const _EnLocalizationMessages();

  @override
  String modeLabel(LocalizationMode mode) {
    switch (mode) {
      case LocalizationMode.gpsTrusted:
        return 'GPS OK';
      case LocalizationMode.gpsSuspect:
        return 'GPS doubtful';
      case LocalizationMode.deadReckoning:
        return 'No GPS — estimating';
      case LocalizationMode.lost:
        return 'Position unknown';
    }
  }

  @override
  String modeExplanation(LocalizationMode mode) {
    switch (mode) {
      case LocalizationMode.gpsTrusted:
        return 'Your position is from a current GPS fix.';
      case LocalizationMode.gpsSuspect:
        // Never "you are here anyway" — the suspect fix is NOT being used.
        return 'The GPS signal cannot be trusted right now, so this dot is '
            'being estimated, not taken from GPS.';
      case LocalizationMode.deadReckoning:
        return 'No usable GPS. Your position is being estimated from your last '
            'known fix, and it becomes less certain every second.';
      case LocalizationMode.lost:
        // The strongest thing this package may say. It is about the DOT, and
        // it is stated plainly — no hedging that could read as reassurance.
        return 'We do not know where you are. The dot shown is a guess, not '
            'your position.';
    }
  }

  @override
  String basisLabel(EstimateBasis basis) {
    switch (basis) {
      case EstimateBasis.trustedGpsFix:
        return 'From a trusted GPS fix';
      case EstimateBasis.deadReckoning:
        return 'Estimated from your movement, not GPS';
      case EstimateBasis.lastKnownPosition:
        return 'Held at your last known position';
      case EstimateBasis.unanchoredGuess:
        return 'A coarse guess — no position has ever been confirmed';
    }
  }

  @override
  String positionWithinRadius(int meters) =>
      'You could be anywhere within about $meters m of the dot.';

  @override
  String noTrustedFixFor(int seconds) =>
      'No trusted GPS fix for about $seconds s.';

  @override
  String noPositionAtAll() =>
      'We do not have your position. Nothing is being shown, because there is '
      'nothing we can honestly show.';
}

class _JaLocalizationMessages extends LocalizationMessages {
  const _JaLocalizationMessages();

  /// Japanese sentences already close with 。 — no separator is added.
  @override
  String get sentenceSeparator => '';

  @override
  String modeLabel(LocalizationMode mode) {
    switch (mode) {
      case LocalizationMode.gpsTrusted:
        return 'GPS受信中';
      case LocalizationMode.gpsSuspect:
        return 'GPS信号が不確か';
      case LocalizationMode.deadReckoning:
        return 'GPSなし（推定中）';
      case LocalizationMode.lost:
        // The task-named term. 現在地不明 is the plain, standard Japanese for
        // "current position unknown" — it is what a Japanese driver expects to
        // read on a car navigation screen, and it does not soften.
        return '現在地不明';
    }
  }

  @override
  String modeExplanation(LocalizationMode mode) {
    switch (mode) {
      case LocalizationMode.gpsTrusted:
        return '現在地はGPSの最新の測位に基づいています。';
      case LocalizationMode.gpsSuspect:
        // 「GPSの位置は使っていない」ことを明言する。使っているかのような表現は禁止。
        return 'GPS信号が信頼できない状態です。この地点はGPSの値ではなく、'
            '推定によって表示しています。';
      case LocalizationMode.deadReckoning:
        return 'GPSが利用できません。直前の測位をもとに現在地を推定しています。'
            '時間が経つほど誤差が大きくなります。';
      case LocalizationMode.lost:
        // 最も強い表明。断定的に、やわらげずに述べる。
        // 「安全です」と読めてはならない。
        return '現在地が分かりません。表示している地点は推定であり、'
            '実際の現在地ではありません。';
    }
  }

  @override
  String basisLabel(EstimateBasis basis) {
    switch (basis) {
      case EstimateBasis.trustedGpsFix:
        return '信頼できるGPS測位による';
      case EstimateBasis.deadReckoning:
        // 自律航法 is the established Japanese term for dead reckoning; the
        // katakana is given once in parentheses for the reader who knows it
        // by the English name.
        return 'GPSではなく、自律航法（デッドレコニング）による推定';
      case EstimateBasis.lastKnownPosition:
        return '最後に測位できた地点で停止表示中';
      case EstimateBasis.unanchoredGuess:
        return 'おおまかな推定：一度も現在地を確定できていません';
    }
  }

  @override
  String positionWithinRadius(int meters) =>
      '実際の現在地は、表示地点から半径約${meters}mの範囲内のどこかにある可能性があります。';

  @override
  String noTrustedFixFor(int seconds) => '約$seconds秒間、信頼できるGPS測位がありません。';

  @override
  String noPositionAtAll() => '現在地を取得できていません。'
      '確かな情報がないため、現在地は表示していません。';
}
