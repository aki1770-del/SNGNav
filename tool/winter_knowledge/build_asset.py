#!/usr/bin/env python3
"""
Build the shipped winter-knowledge asset from generated λ-RLM cards.

- Reads a cards JSON (state -> {guidance, tokens, ...}) produced by
  generate_cards.py.
- EXCLUDES any card whose guidance is a refusal / "cannot answer" / "not in
  source" — those must NOT reach the app (the drive-time lookup returns null →
  honest degradation, never fabricated guidance).
- Emits assets/winter_knowledge.json: provenance + cost + only the real cards.

Usage: build_asset.py <cards.json> [<cards.json> ...]
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = Path.home() / "SNGNav" / "assets" / "winter_knowledge.json"

REFUSAL = re.compile(
    r"(cannot answer|can't answer|do(es)? not contain|not provided|please provide|"
    r"lacks? (specific|actionable)|no (coherent )?source|i would need|will not invent)",
    re.I,
)


def main():
    paths = sys.argv[1:] or ["cards_v3.json"]
    merged = {}
    for p in paths:
        fp = HERE / p if not Path(p).is_absolute() else Path(p)
        if fp.exists():
            merged.update(json.loads(fp.read_text()))

    cards, excluded = {}, {}
    tin = tout = 0
    for state, r in merged.items():
        g = (r.get("guidance") or "").strip()
        tin += r.get("in_tokens") or 0
        tout += r.get("out_tokens") or 0
        if REFUSAL.search(g) or len(g) < 60:
            excluded[state] = "refusal/empty — excluded (honest degradation)"
            continue
        cards[state] = {"guidance": g}

    # Haiku 4.5 published rate $1/$5 per Mtok (input/output).
    cost = round(tin / 1e6 * 1.0 + tout / 1e6 * 5.0, 4)
    asset = {
        "_meta": {
            "generator": "λ-RLM (lambda-calculus-LLM/lambda-RLM) long-context single-pass synthesis (context_window_chars >= corpus so the action-grounded source is reasoned over whole, not split — forced splitting starved the per-state questions and produced refusals in v1-v3), model claude-haiku-4-5",
            "purpose": "OFFLINE build-time synthesis; drive-time lookup is deterministic, no LLM/network in vehicle",
            "corpus": "corpus_v4 (CC BY-SA 4.0): Wikivoyage 'Winter driving' + 'Driving in Norway'; Wikipedia 'Black ice', 'Aquaplaning', 'Skid (automobile)', 'Cadence braking', 'Threshold braking'. Action-focused driver-guidance paragraphs; see tool/winter_knowledge/corpus_v4_manifest.json",
            "grounding": "source-grounded; refusals excluded (no fabricated driver guidance)",
            "approx_cost_usd_at_haiku45_rates": cost,
            "states_included": sorted(cards.keys()),
            "states_excluded": excluded,
        },
        "cards": cards,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(asset, indent=2))
    print(f"asset -> {OUT}")
    print(f"  included: {sorted(cards.keys())}")
    print(f"  excluded: {excluded}")
    print(f"  approx cost (these cards): ${cost}")


if __name__ == "__main__":
    main()
