#!/usr/bin/env python3
"""
Build an ACTION-FOCUSED winter-driving corpus for the λ-RLM card generator.

The v1-v3 corpora were dominated by tyre-construction / regulation / road-
maintenance prose, so λ-RLM honestly REFUSED to synthesise driver-action
cards (no fabrication of safety-critical guidance — the correct failure).
This builder pulls the action-rich, openly-licensed (CC BY-SA) source
articles that actually describe what a DRIVER should DO on ice / snow / slush
/ wet — skid recovery, braking technique, following distance, speed.

Raw plaintext extracts only (MediaWiki `prop=extracts&explaintext`) — no
paraphrase, so the generator's "grounded ONLY in the source text" discipline
has real source to stand on. Each section is attributed; the asset _meta
carries the source list + licence.

Usage: build_corpus.py            # writes corpus_v4.txt
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "corpus_v4.txt"

# (wiki host, page title). Chosen for DRIVER-ACTION density, CC BY-SA.
# Wikivoyage "Winter driving" is the primary prescriptive source (speed,
# stopping distance, skid recovery, black-ice/slush/deep-snow handling);
# the Wikipedia articles supply braking-technique + aquaplaning + skid
# mechanics the cards cite. Generic "Driving" / "Winter service vehicle"
# / "Snow tire" were dropped — they diluted the corpus with travel-culture
# and equipment prose, starving the per-state action questions (the v1-v3
# refusal cause).
SOURCES = [
    ("en.wikivoyage.org", "Winter driving"),
    ("en.wikivoyage.org", "Driving in Norway"),
    ("en.wikipedia.org", "Black ice"),
    ("en.wikipedia.org", "Aquaplaning"),
    ("en.wikipedia.org", "Skid (automobile)"),
    ("en.wikipedia.org", "Cadence braking"),
    ("en.wikipedia.org", "Threshold braking"),
]


def fetch(host: str, title: str) -> str:
    params = urllib.parse.urlencode({
        "action": "query",
        "format": "json",
        "prop": "extracts",
        "explaintext": "1",
        "redirects": "1",
        "titles": title,
    })
    url = f"https://{host}/w/api.php?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "SNGNav-winter-corpus/1.0 (offline build tool)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode())
    pages = data["query"]["pages"]
    page = next(iter(pages.values()))
    return page.get("extract", "") or ""


def main():
    chunks, manifest = [], []
    for host, title in SOURCES:
        try:
            text = fetch(host, title)
        except Exception as e:  # noqa: BLE001
            print(f"  ! {title} ({host}): {e}", file=sys.stderr)
            continue
        wiki = "Wikivoyage" if "wikivoyage" in host else "Wikipedia"
        chars = len(text)
        print(f"  + {wiki} — {title}: {chars} chars")
        manifest.append({"wiki": wiki, "title": title, "chars": chars})
        chunks.append(f"=== SOURCE: {wiki} — {title} (CC BY-SA 4.0) ===\n{text.strip()}\n")
        time.sleep(0.3)
    OUT.write_text("\n".join(chunks))
    (HERE / "corpus_v4_manifest.json").write_text(json.dumps(manifest, indent=2))
    total = sum(m["chars"] for m in manifest)
    print(f"\ncorpus_v4.txt -> {OUT}  ({total} chars from {len(manifest)} sources)")


if __name__ == "__main__":
    main()
