/// Offline winter-guidance lookup — the DRIVE-TIME consumer of the λ-RLM asset.
///
/// The companion build-time tool (`tool/winter_knowledge/generate_cards.py`)
/// uses λ-RLM (typed recursive long-context reasoning) to digest a large, real
/// winter-driving corpus into one compact, source-grounded guidance card per
/// [RoadSurfaceState]. That LLM step runs OFFLINE on a dev machine and bakes a
/// JSON asset the app ships.
///
/// At drive-time this class does a PURE, DETERMINISTIC lookup by surface state —
/// **no LLM, no network**. That is the whole point: the worst-case path (network
/// and GPS gone) stays typed and offline. The live KUKSA/VSS gRPC signals decide
/// *which* card via [DrivingConditionAssessment.surfaceState]; this class only
/// returns the pre-baked text for that state, or `null` when there is no card
/// (the caller then keeps its existing typed advisory — never fabricates).
library;

import 'dart:convert';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One pre-baked, source-grounded guidance card.
class WinterCard {
  const WinterCard({
    required this.state,
    required this.guidance,
    this.guidanceJa,
  });

  /// The [RoadSurfaceState] name this card applies to (e.g. `blackIce`).
  final String state;

  /// English markdown guidance synthesised offline by λ-RLM from the corpus.
  /// This is the default and the fallback for any language without a card.
  final String guidance;

  /// Optional Japanese guidance — a faithful, adversarially-verified
  /// translation of [guidance] (see the asset `_meta.translation_ja`). `null`
  /// when no verified Japanese exists for this state, in which case
  /// [guidanceForLanguage] honestly falls back to the English [guidance]
  /// rather than show nothing or an unverified translation.
  final String? guidanceJa;

  /// The guidance text for [lang], falling back to English. the driver's mother in
  /// Akita gets Japanese when a verified card exists; otherwise she gets the
  /// grounded English — never a blank, never an unverified rendering.
  String guidanceForLanguage(String lang) =>
      (lang == 'ja' && guidanceJa != null && guidanceJa!.trim().isNotEmpty)
          ? guidanceJa!
          : guidance;
}

/// Deterministic, offline lookup of [WinterCard]s keyed by [RoadSurfaceState].
class WinterKnowledge {
  WinterKnowledge(this._cards);

  final Map<String, WinterCard> _cards;

  /// Build from the baked asset JSON string
  /// (`{ "cards": { "<state>": { "guidance": "...", "guidance_ja": "..." } } }`).
  /// `guidance` (English) is required per card; `guidance_ja` is optional and
  /// only present for states whose Japanese passed the offline adversarial
  /// safety verification.
  factory WinterKnowledge.fromJsonString(String jsonStr) {
    final root = jsonDecode(jsonStr) as Map<String, dynamic>;
    final raw = (root['cards'] as Map<String, dynamic>? ?? const {});
    final cards = <String, WinterCard>{};
    raw.forEach((state, v) {
      final m = v as Map<String, dynamic>;
      final g = (m['guidance'] as String?)?.trim();
      final ja = (m['guidance_ja'] as String?)?.trim();
      if (g != null && g.isNotEmpty) {
        cards[state] = WinterCard(
          state: state,
          guidance: g,
          guidanceJa: (ja != null && ja.isNotEmpty) ? ja : null,
        );
      }
    });
    return WinterKnowledge(cards);
  }

  /// Default bundled-asset location (registered in `pubspec.yaml`).
  static const String assetPath = 'assets/winter_knowledge.json';

  /// Load the baked asset from the app bundle — a pure offline read (no
  /// network, no LLM). The card synthesis already happened at build time;
  /// this only deserialises the shipped JSON. Returns an empty
  /// [WinterKnowledge] (every [cardFor] → `null`, honest degradation) if the
  /// asset is missing or malformed, so a packaging slip can never crash the
  /// drive-time surface.
  static Future<WinterKnowledge> fromAsset([String path = assetPath]) async {
    try {
      final jsonStr = await rootBundle.loadString(path);
      return WinterKnowledge.fromJsonString(jsonStr);
    } catch (_) {
      return WinterKnowledge(const {});
    }
  }

  /// The pre-baked card for [state], or `null` if none was baked for it
  /// (caller keeps its typed advisory — honest degradation, no fabrication).
  ///
  /// When [lang] is `'ja'` and the state has a verified Japanese card, the
  /// returned card's [WinterCard.guidance] is the Japanese text (resolved
  /// here so the rendering surface stays language-oblivious); otherwise the
  /// English guidance is returned unchanged.
  WinterCard? cardFor(RoadSurfaceState state, {String lang = 'en'}) {
    final c = _cards[state.name];
    if (c == null) return null;
    final g = c.guidanceForLanguage(lang);
    return identical(g, c.guidance)
        ? c
        : WinterCard(state: c.state, guidance: g, guidanceJa: c.guidanceJa);
  }

  /// Convenience: the card for a live assessment's surface state.
  ///
  /// `null` when the surface could not be classified (snow_rendering 0.3.0:
  /// `DrivingConditionAssessment.surfaceState` is nullable). There is no winter
  /// card for a road nobody measured — and inventing the `dry` card, which is
  /// what the old non-nullable path did, is exactly the defect.
  WinterCard? cardForAssessment(DrivingConditionAssessment a,
      {String lang = 'en'}) {
    final surface = a.surfaceState;
    if (surface == null) return null;
    return cardFor(surface, lang: lang);
  }

  /// States that have a baked card.
  Iterable<String> get states => _cards.keys;
}
