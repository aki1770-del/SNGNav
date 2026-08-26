#!/usr/bin/env python3
"""refresh_vss_authority.py — derive the VSS unit authority for the leaves our
overlay declares, straight from an upstream COVESA vehicle_signal_specification
clone at a pinned tag.

WHY (OPS-070(B), written before the act):

  On 2026-08-26 the app's KUKSA decoder was corrected to divide road friction by
  100, because Vehicle.ADAS.ESC.RoadFriction.MostProbable is PERCENT 0-100 and
  the app had been reading the wire value as a 0.0-1.0 fraction. With the wrong
  reading, `18.0 < kIcyFrictionThreshold(0.3)` was false, so the friction limb of
  the black-ice check could never fire -- the ONE limb that fires BEFORE the car
  slips. TCS and ABS only speak after grip is already gone.

  The fix landed in lib/ and in test/. It did NOT land in tool/kuksa_e2e/, which
  is the only artifact that proves the path end-to-end against a real broker, and
  which nothing in this repo runs. Both of its friction literals are still
  fractions, and its VSS overlay still tells the broker the leaf is "0.0-1.0".

  A UNIT is a contract between two parties who never meet: whoever fills the leaf
  and whoever reads it. Nothing in this repo asserted that contract, so the two
  sides drifted for as long as nobody ran them together.

WHY THIS SCRIPT AND NOT A HAND-WRITTEN TABLE:
  A table someone types is a fifth copy of the truth, and it goes stale in
  exactly the silent way this whole defect went stale. This DERIVES the table
  from upstream at a pinned tag, records the tag and commit sha it derived from,
  and refuses to guess: an ambiguous or missing leaf is an error, never a
  default. The POPULATION is read from our own overlay on disk, so a leaf added
  to the overlay is covered without anyone remembering to add it here.

USAGE:
  tool/kuksa_e2e/refresh_vss_authority.py \
      --vss-clone /path/to/vehicle_signal_specification --tag v6.0

  Writes tool/kuksa_e2e/vss_authority.json. Commit the result. The test at
  test/tool/kuksa_e2e_units_contract_test.dart reads that file and needs no
  clone, so it runs in CI offline.
"""
import argparse, json, os, re, subprocess, sys

# VSS expands `instances:` into path segments that never appear as a declaration
# key. They are removed before the lookup. Extending this list is the only
# maintenance this script needs, and a missing entry fails LOUDLY (unresolved
# leaf) rather than silently resolving to the wrong signal.
INSTANCE_TOKENS = {
    "Front", "Rear", "Left", "Right", "Row1", "Row2", "Row3", "Row4",
    "DriverSide", "PassengerSide", "Primary", "Secondary",
}
ATTRS = ("datatype", "type", "unit", "min", "max")


def git(clone, *args):
    return subprocess.run(["git", "-C", clone, *args], check=True,
                          capture_output=True, text=True).stdout


def overlay_leaves(overlay_path):
    """POPULATION: every sensor/actuator leaf our own overlay declares, read from
    disk. Not a list anyone maintains."""
    with open(overlay_path) as fh:
        tree = json.load(fh)
    out = {}

    def walk(node, path):
        for name, spec in (node.get("children") or {}).items():
            here = f"{path}.{name}" if path else name
            if spec.get("type") == "branch":
                walk(spec, here)
            else:
                out[here] = spec
    for root, spec in tree.items():
        walk(spec, root)
    return out


def parse_block(text, key):
    """Return the attribute dict for a `key:` block in a .vspec file, or None."""
    m = re.search(rf"^{re.escape(key)}:\s*$", text, re.M)
    if not m:
        return None
    attrs, seen_desc = {}, False
    for line in text[m.end():].split("\n"):
        if line and not line[0].isspace():       # next top-level key ends it
            break
        stripped = line.strip()
        if not stripped:
            continue
        am = re.match(r"^(\w+):\s*(.*)$", stripped)
        if am and not seen_desc:
            k, v = am.group(1), am.group(2).strip()
            if k == "description":
                seen_desc = True
                continue
            if k in ATTRS:
                attrs[k] = v
    return attrs or None


def resolve(clone, tag, files, vss_path):
    """Find the declaration for a full VSS path. Ambiguity is an ERROR."""
    parts = [p for p in vss_path.split(".") if p not in INSTANCE_TOKENS]
    hits = []
    for suffix_start in range(len(parts)):
        key = ".".join(parts[suffix_start:])
        for fpath, text in files.items():
            block = parse_block(text, key)
            if block is not None:
                hits.append((fpath, key, block))
        if hits:
            break
    if not hits:
        raise SystemExit(f"UNRESOLVED leaf, refusing to guess: {vss_path}")
    if len(hits) > 1:
        # disambiguate: the file's own path components must appear in the leaf's
        # VSS path. If that does not leave exactly one, fail loudly.
        narrowed = [h for h in hits
                    if any(c and c in vss_path
                           for c in re.split(r"[/.]", h[0].replace(".vspec", "")))]
        if len(narrowed) != 1:
            raise SystemExit(
                f"AMBIGUOUS leaf {vss_path}: {[h[0] for h in hits]} — refusing to guess")
        hits = narrowed
    return hits[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vss-clone", required=True)
    ap.add_argument("--tag", default="v6.0")
    ap.add_argument("--overlay", default=None)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    overlay = a.overlay or os.path.join(here, "snow_safety_vss.json")
    out = a.out or os.path.join(here, "vss_authority.json")

    sha = git(a.vss_clone, "rev-parse", f"{a.tag}^{{commit}}").strip()
    listing = git(a.vss_clone, "ls-tree", "-r", "--name-only", a.tag, "spec/")
    files = {}
    for f in listing.split("\n"):
        if f.endswith(".vspec"):
            files[f] = git(a.vss_clone, "show", f"{a.tag}:{f}")

    leaves = overlay_leaves(overlay)
    authority = {}
    for vss_path in sorted(leaves):
        fpath, key, attrs = resolve(a.vss_clone, a.tag, files, vss_path)
        authority[vss_path] = {"source": f"{fpath}:{key}", **attrs}

    doc = {
        "_provenance": {
            "upstream": "https://github.com/COVESA/vehicle_signal_specification",
            "tag": a.tag,
            "commit": sha,
            "derived_by": "tool/kuksa_e2e/refresh_vss_authority.py",
            "population": "the leaves declared by snow_safety_vss.json, read from disk",
        },
        "leaves": authority,
    }
    with open(out, "w") as fh:
        json.dump(doc, fh, indent=2, sort_keys=False)
        fh.write("\n")
    print(f"wrote {out}: {len(authority)} leaves from {a.tag} ({sha[:8]})")


if __name__ == "__main__":
    main()
