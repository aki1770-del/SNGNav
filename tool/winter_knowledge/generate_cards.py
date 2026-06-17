#!/usr/bin/env python3
"""
OFFLINE λ-RLM winter-knowledge generator (build-time, NOT in the car).

Uses λ-RLM (typed recursive long-context reasoning) to digest a large, real
winter-driving corpus (Wikipedia plaintext extracts) into a COMPACT, typed,
pre-baked driver-guidance card per RoadSurfaceState. The recursion (Split →
Map(Φ) → Reduce) only calls the LLM on bounded leaf subproblems.

This LLM step runs OFFLINE on a dev/build machine. The car ships the resulting
JSON asset and does a DETERMINISTIC lookup by surfaceState at drive-time — no
LLM, no network in the vehicle. That keeps the worst-case (net + GPS gone)
safety path typed and offline, while grounding the guidance in real sources.

Usage:
  generate_cards.py <state> [<state> ...]     # default: the 4 winter-hazard states
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, "/tmp/lambda-RLM")
from rlm import LambdaRLM  # noqa: E402

HERE = Path(__file__).resolve().parent
CORPUS = (HERE / os.environ.get("CORPUS_FILE", "corpus.txt")).read_text()

# Source the key inline from the authorised .env (never printed).
ENV = Path.home() / "Documents/LLMnotebooks/dr.reikoizumi/.env"
API_KEY = next(
    (ln.split("=", 1)[1].strip().strip('"').strip("'")
     for ln in ENV.read_text().splitlines()
     if ln.startswith("ANTHROPIC_API_KEY=")),
    None,
)
assert API_KEY, "no ANTHROPIC_API_KEY in .env"

MODEL = "claude-haiku-4-5"
# Low context window so a 178KB corpus genuinely SPLITS into several leaves
# (exercises the real recursive path, like bentocall's --force-lambda).
CTX_CHARS = int(os.environ.get("CTX_CHARS", "40000"))

# RoadSurfaceState (snow_rendering) -> the question each card answers.
QUESTIONS = {
    "blackIce": "What is black ice and what concrete actions should a driver take when the road surface is black ice? Give 2-4 specific, actionable steps grounded ONLY in the source text.",
    "compactedSnow": "What should a driver do when driving on compacted snow? Give 2-4 specific, actionable steps (tyres, speed, braking, distance) grounded ONLY in the source text.",
    "slush": "What should a driver do on slush (melting/mixed snow), including the aquaplaning-like risk? Give 2-4 specific actionable steps grounded ONLY in the source text.",
    "wet": "What should a driver do on wet roads to avoid aquaplaning and loss of grip? Give 2-4 specific actionable steps grounded ONLY in the source text.",
}

INSTRUCTION = (" Respond as: one short sentence of WHAT IT IS, then a bullet list"
               " of the actions. Be concise (a glanceable in-car card). Do NOT"
               " invent facts beyond the source.")


def run(state: str) -> dict:
    q = QUESTIONS[state] + INSTRUCTION
    prompt = f"Context:\n{CORPUS}\n\nQuestion: {q}\n\nAnswer:"
    rlm = LambdaRLM(
        backend="anthropic",
        backend_kwargs={"api_key": API_KEY, "model_name": MODEL, "max_tokens": 900},
        context_window_chars=CTX_CHARS,
        verbose=True,
    )
    t0 = time.perf_counter()
    res = rlm.completion(prompt)
    dt = time.perf_counter() - t0
    u = res.usage_summary
    print(f"\n--- [{state}] done in {dt:.1f}s "
          f"in={u.total_input_tokens} out={u.total_output_tokens} "
          f"cost=${(u.total_cost or 0):.4f} ---")
    return {
        "state": state,
        "guidance": res.response.strip(),
        "in_tokens": u.total_input_tokens,
        "out_tokens": u.total_output_tokens,
        "cost_usd": u.total_cost,
        "seconds": round(dt, 1),
    }


def main():
    states = sys.argv[1:] or list(QUESTIONS.keys())
    out_path = HERE / os.environ.get("OUT_FILE", "cards_raw.json")
    out = json.loads(out_path.read_text()) if out_path.exists() else {}  # MERGE, not clobber
    tot_in = tot_out = 0
    tot_cost = 0.0
    for s in states:
        r = run(s)
        out[s] = r
        tot_in += r["in_tokens"] or 0
        tot_out += r["out_tokens"] or 0
        tot_cost += r["cost_usd"] or 0.0
    out_path.write_text(json.dumps(out, indent=2))
    print(f"\n==== TOTAL: {len(states)} states  in={tot_in} out={tot_out} "
          f"cost=${tot_cost:.4f}  -> cards_raw.json ====")


if __name__ == "__main__":
    main()
