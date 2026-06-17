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
  const WinterCard({required this.state, required this.guidance});

  /// The [RoadSurfaceState] name this card applies to (e.g. `blackIce`).
  final String state;

  /// Markdown guidance text synthesised offline by λ-RLM from the corpus.
  final String guidance;
}

/// Deterministic, offline lookup of [WinterCard]s keyed by [RoadSurfaceState].
class WinterKnowledge {
  WinterKnowledge(this._cards);

  final Map<String, WinterCard> _cards;

  /// Build from the baked asset JSON string
  /// (`{ "cards": { "<state>": { "guidance": "..." }, ... } }`).
  factory WinterKnowledge.fromJsonString(String jsonStr) {
    final root = jsonDecode(jsonStr) as Map<String, dynamic>;
    final raw = (root['cards'] as Map<String, dynamic>? ?? const {});
    final cards = <String, WinterCard>{};
    raw.forEach((state, v) {
      final m = v as Map<String, dynamic>;
      final g = (m['guidance'] as String?)?.trim();
      if (g != null && g.isNotEmpty) {
        cards[state] = WinterCard(state: state, guidance: g);
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
  WinterCard? cardFor(RoadSurfaceState state) => _cards[state.name];

  /// Convenience: the card for a live assessment's surface state.
  WinterCard? cardForAssessment(DrivingConditionAssessment a) =>
      cardFor(a.surfaceState);

  /// States that have a baked card.
  Iterable<String> get states => _cards.keys;
}
