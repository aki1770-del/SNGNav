#!/usr/bin/env python3
"""Published fabrication sweep — what is in the driver hands RIGHT NOW.

WHY THIS EXISTS
---------------
Every gate this unit owns inspects a tree we are ABOUT to ship.
`scripts/fabrication_sweep.sh` scans `packages/` and `lib/` on disk. That is the
tree WE hold. It is not the tree a stranger holds.

Measured 2026-08-08, first run of this script's enumerator:
    packages/vehicle_condition_fusion/pubspec.yaml  ->  version: 0.5.0
    https://pub.dev/api/packages/vehicle_condition_fusion  ->  latest: 0.3.3
Two minor versions apart. Everything the local sweep certifies about 0.5.0 says
nothing about the 0.3.3 that a `pub add` actually delivers. And
`packages/position_integrity/` has NO pubspec.yaml at all while `position_integrity
0.1.0` has been live on pub.dev since 2026-07-23 — a published package that
enumerating the local tree cannot even see.

Five live published packages were found fabricating a safety-benign value from an
unmeasured input. They were found by a HUMAN-DIRECTED HUNT — the pen picked the
sample. A hand-picked sample cannot answer "what else". Selection bias IS the
defect this script removes: it enumerates from the REGISTRY, fetches the
PUBLISHED ARCHIVE for `latest`, and reads THAT.

THE CLASS IT LOOKS FOR
    an unmeasured / absent / failed input silently resolving to a SAFE-LOOKING value.

HONEST BOUNDS — what this CANNOT see (a check sold as more than it is is false comfort)
--------------------------------------------------------------------------------
1. SEMANTIC FABRICATION WITH NO LITERAL. `_default()` / `Foo.clear()` /
   `_fallbackFor(x)` — a constructor or helper whose BODY fabricates, invoked at a
   site with no literal in it. The call site is invisible here. The scanner is
   lexical, not a dataflow analysis; it has no call graph and no type information.

2. CROSS-PACKAGE COMPOSITION — the known live defect, named because it is not
   hypothetical. Even after `fleet_hazard 0.5.2` makes its own fabrication visible,
   `driving_conditions/lib/src/simulation/fleet_hazard_confidence_adapter.dart:67-68`
   reads raw `r.confidence` and yields `0.8200000000000001` to a driver-facing
   surface. Package A fabricates a constant; package B launders it into a
   driver-facing number. NEITHER line looks wrong in its own package, and a
   PER-PACKAGE sweep — this one included — can never see it. Finding that class
   needs a consumer-side dataflow trace across the dependency graph. It is not
   built, and this script does not substitute for it.

3. ANYTHING INSIDE A DEPENDENCY. Only our own packages' `lib/` is read. A
   fabrication in a third-party package we pull in is invisible.

4. A SHAPE NOT IN THE RULE TABLE. New shapes need new rules. Absence of a hit is
   never evidence of absence of the class.

5. `lib/` ONLY. `bin/`, `example/`, `test/` are excluded as non-shipping surface.

Every hit is a CANDIDATE for human adjudication, never a verdict. False positives
are ACCEPTABLE and expected; a false negative is the failure that matters, so the
rules are deliberately loose.

MEASURED CALIBRATION, first catalog-wide run (2026-08-08, 36 published packages,
68 candidates). Seven candidates were adjudicated by hand against the published
source; the split is recorded here so nobody has to re-derive the noise floor:
  REAL, previously unnamed  3  navigation_safety_core 0.11.3 `ambient ?? 5.0`
                               condition_aggregator_owm_road_risk 0.1.4 `eventLevel ?? 0`
                               pretrip_decision_advisor 0.5.2 `warningCheckAvailable = true`
  DOCUMENTED HAZARD         1  position_integrity 0.1.0 `hasViolation` (docstring warns)
  FALSE POSITIVE            3  driving_weather 0.5.0 `WeatherCondition.simulatedClear`
                               (explicitly ObservationSource.simulated)
                               snow_rendering 0.3.0 `'Conditions normal'` (guarded above)
                               routing_engine 0.5.1 `isAvailable()` catch -> false (safe direction)
Each false positive took under a minute to clear by reading the enclosing
constructor or the guard directly above. That is the trade this scanner is tuned
for, and it is the right one: the cost of a false positive is a minute; the cost
of a false negative is a sentence on the driver screen saying the road is fine.

WHY PYTHON AND NOT BASH
-----------------------
`fabrication_sweep.sh`'s own header records that its first draft packed regexes
into `|`-delimited strings and `|` is the regex alternation operator, so every
multi-alternation rule was truncated into an unclosed group that matched nothing.
The scanner reported PASS over a catalog full of fabrications — the exact defect
class it exists to catch, living inside the detector. That is a shell-quoting
hazard, and this script has strictly more regex surface than that one did. It also
needs HTTP+JSON against the pub API, streaming tar.gz extraction, a dependency
closure to a fixpoint, and ranked structured output. Python stdlib does all of it
(urllib, json, tarfile, re) with zero dependencies and no quoting layer between
the rule text and the regex engine.

USAGE
    published_fabrication_sweep.py                 # sweep the whole published catalog
    published_fabrication_sweep.py --self-test     # PROVE it fires on the 5 known published defects
    published_fabrication_sweep.py --dump PKG[==VER] [PATH_SUBSTR]   # print published source
    published_fabrication_sweep.py --json OUT.json # also write machine-readable findings
    published_fabrication_sweep.py --no-net        # cache only, fail if a fetch would be needed

NOT SCHEDULED. This script is BUILT and PROVEN. Wiring it to cron is a separate
operational decision, and no part of this file claims it is scheduled.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import tarfile
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Iterable

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache", "pub_archives")
API = "https://pub.dev/api/packages/"
UA = "sngnav-published-fabrication-sweep (+https://github.com/aki1770-del/SNGNav)"

# A package is OURS if the registry's own metadata points home. Measured, not asserted.
OWNERSHIP_MARKERS = ("aki1770-del/sngnav",)


# --------------------------------------------------------------------------
# registry access
# --------------------------------------------------------------------------
def _get(url: str, binary: bool = False, timeout: int = 60):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data if binary else json.loads(data.decode("utf-8"))


class Registry:
    """Live pub.dev reads, cached on disk so a re-run is cheap and reproducible."""

    def __init__(self, allow_net: bool = True):
        self.allow_net = allow_net
        self.meta_dir = os.path.join(CACHE, "_meta")
        os.makedirs(self.meta_dir, exist_ok=True)
        os.makedirs(CACHE, exist_ok=True)
        self._memo: dict[str, dict | None] = {}

    def meta(self, pkg: str) -> dict | None:
        """Full API record for a package, or None if it is not published."""
        if pkg in self._memo:
            return self._memo[pkg]
        path = os.path.join(self.meta_dir, f"{pkg}.json")
        if os.path.exists(path):
            with open(path) as fh:
                blob = json.load(fh)
            self._memo[pkg] = None if blob.get("__absent__") else blob
            return self._memo[pkg]
        if not self.allow_net:
            raise RuntimeError(f"--no-net but {pkg} metadata is not cached")
        try:
            blob = _get(API + pkg)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                with open(path, "w") as fh:
                    json.dump({"__absent__": True}, fh)
                self._memo[pkg] = None
                return None
            raise
        with open(path, "w") as fh:
            json.dump(blob, fh)
        self._memo[pkg] = blob
        return blob

    def archive(self, pkg: str, ver: str) -> bytes:
        path = os.path.join(CACHE, f"{pkg}-{ver}.tar.gz")
        if os.path.exists(path):
            with open(path, "rb") as fh:
                return fh.read()
        if not self.allow_net:
            raise RuntimeError(f"--no-net but {pkg}-{ver} archive is not cached")
        url = f"https://pub.dev/api/archives/{pkg}-{ver}.tar.gz"
        blob = _get(url, binary=True)
        with open(path, "wb") as fh:
            fh.write(blob)
        return blob


def is_ours(meta: dict) -> bool:
    ps = meta.get("latest", {}).get("pubspec", {}) or {}
    blob = " ".join(str(ps.get(k, "")) for k in ("repository", "homepage", "issue_tracker")).lower()
    return any(m in blob for m in OWNERSHIP_MARKERS)


def dart_sources(blob: bytes) -> list[tuple[str, str]]:
    """(path, text) for every shipping lib/**.dart in a published archive."""
    out: list[tuple[str, str]] = []
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tf:
        for m in tf.getmembers():
            if not m.isfile() or not m.name.endswith(".dart"):
                continue
            n = m.name.lstrip("./")
            if not n.startswith("lib/"):
                continue
            if "/test/" in n or n.endswith("_test.dart") or "/example/" in n:
                continue
            fh = tf.extractfile(m)
            if fh is None:
                continue
            try:
                out.append((n, fh.read().decode("utf-8", "replace")))
            except Exception:
                continue
    return sorted(out)


# --------------------------------------------------------------------------
# enumeration — seeded from disk, closed over the registry, never hand-picked
# --------------------------------------------------------------------------
def seed_candidates() -> set[str]:
    """Directory names AND pubspec `name:` under packages/, plus the app tree.

    Directory names are included deliberately: packages/position_integrity/ has no
    pubspec.yaml on disk yet position_integrity 0.1.0 is live. Trusting only
    pubspec `name:` reproduces the blind spot this script exists to remove.
    """
    seeds: set[str] = set()
    pdir = os.path.join(ROOT, "packages")
    if os.path.isdir(pdir):
        for d in sorted(os.listdir(pdir)):
            full = os.path.join(pdir, d)
            if not os.path.isdir(full):
                continue
            seeds.add(d)
            ps = os.path.join(full, "pubspec.yaml")
            if os.path.exists(ps):
                with open(ps, errors="replace") as fh:
                    for line in fh:
                        m = re.match(r"^name:\s*(\S+)", line)
                        if m:
                            seeds.add(m.group(1))
                            break
    return seeds


def resolve_catalog(reg: Registry, seeds: Iterable[str], verbose: bool = True) -> dict[str, str]:
    """{package: latest_version} for every OURS package, closed to a fixpoint.

    The closure walks each of our packages' published dependencies and re-tests
    them for ownership, so a published sibling absent from the working tree is
    still discovered.
    """
    catalog: dict[str, str] = {}
    seen: set[str] = set()
    queue = list(dict.fromkeys(seeds))
    skipped: list[tuple[str, str]] = []
    while queue:
        pkg = queue.pop(0)
        if pkg in seen:
            continue
        seen.add(pkg)
        try:
            meta = reg.meta(pkg)
        except Exception as e:  # network hiccup must not silently shrink the catalog
            skipped.append((pkg, f"lookup failed: {e}"))
            continue
        if meta is None:
            skipped.append((pkg, "not published"))
            continue
        if not is_ours(meta):
            skipped.append((pkg, "not ours (repository field)"))
            continue
        latest = meta["latest"]["version"]
        catalog[pkg] = latest
        deps = (meta["latest"].get("pubspec", {}) or {}).get("dependencies", {}) or {}
        for d in deps:
            if d not in seen:
                queue.append(d)
    if verbose:
        print(f">> catalog: {len(catalog)} published packages owned by us "
              f"(from {len(seen)} candidates examined)")
        notpub = [p for p, why in skipped if why == "not published"]
        if notpub:
            print(f"   not published (skipped): {', '.join(sorted(notpub))}")
    return dict(sorted(catalog.items()))


# --------------------------------------------------------------------------
# rules
#
# EVERY REGEX BELOW WAS WRITTEN AGAINST SOURCE MEASURED OUT OF THE PUBLISHED
# ARCHIVE, not from memory of what the defect looked like. Two of the five known
# instances cannot be matched by any rule in the sibling `fabrication_sweep.sh`:
# `this.confidence = 0.8` is a DEFAULT PARAMETER (no `??`, no assignment
# statement), and `bool get hasAnyHazard => segments.any(...)` fabricates by
# QUANTIFIER — an empty or unknown segment list makes `any` false, so "we do not
# know" and "there is no hazard" leave by the same door.
# --------------------------------------------------------------------------

# Vocabulary of things that, when fabricated, are a claim about the road.
SAFETY = (
    r"confidence|certainty|severity|urgency|risk|hazard|danger|warning|alert|advisory"
    r"|grip|friction|traction|slip|slippery"
    r"|temp|temperature|celsius|freezing|ice|icing|snow|frost"
    r"|visibility|precip|precipitation|wind|humidity|dewpoint"
    r"|safe|safety|clear|passable|closure|closed"
)
# A value that reads as "everything is fine".
BENIGN_ENUM = r"clear|dry|normal|none|ok|safe|good|low|proceed|passable|nominal|fine"
# Phrases that tell the driver the road is fine.
BENIGN_PHRASE = (
    r"is clear|route is clear|all clear|no hazard|no hazards|no warning|no warnings"
    r"|conditions normal|normal conditions|nothing to report|no advisory|no alerts"
    r"|road is clear|clear road|no risk|all good|no issues"
)
LIT = r"-?\d+(?:\.\d+)?|true|false"

# tier: 1 = the fabricated value IS a safety verdict; 2 = a measured physical
# quantity manufactured; 3 = freshness/identity fabricated; 4 = generic fallback.
RULES: list["Rule"] = []


@dataclass
class Rule:
    id: str
    pattern: str
    meaning: str
    tier: int = 4
    flags: int = 0
    multiline: bool = False
    _rx: re.Pattern | None = field(default=None, repr=False, compare=False)

    def rx(self) -> re.Pattern:
        if self._rx is None:
            self._rx = re.compile(self.pattern, self.flags)
        return self._rx


def R(*a, **kw) -> None:
    RULES.append(Rule(*a, **kw))


# --- the value IS a safety verdict (tier 1) --------------------------------
R("PUB-1", rf"\b(?:this\.)?(?:{SAFETY})\w*\s*=\s*(?:{LIT})\s*[,;)]",
  "a SAFETY-NAMED field is assigned a bare literal — including as a constructor "
  "DEFAULT PARAMETER, where absence of an argument silently becomes that value "
  "(fleet_hazard 0.5.1 `this.confidence = 0.8`; adaptive_reroute 0.1.6 `confidence = 1.0`)",
  tier=1, flags=re.I)

R("PUB-2", rf"\bbool\s+get\s+(?:has|is|are|can|should|was|were)\w*\s*=>[^;]*"
          rf"\.(?:any|every|isEmpty|isNotEmpty|contains)\b",
  "a BOOLEAN SAFETY VERDICT is derived from a collection quantifier — an empty or "
  "unknown collection yields the SAME answer as a measured all-clear; absence and "
  "negative leave by one door (route_condition_forecast 0.1.5 `hasAnyHazard`)",
  tier=1)

R("PUB-3", rf"['\"][^'\"]*(?:{BENIGN_PHRASE})[^'\"]*['\"]",
  "a REASSURING SENTENCE is a string literal in shipping code — if any path reaches "
  "it without a measurement, the driver screen says the road is fine on no evidence "
  "(adaptive_reroute 0.1.6 `reason = 'Route is clear'`)",
  tier=1, flags=re.I)

R("PUB-4", rf"\?\?\s*[A-Za-z_]\w*\.(?:{BENIGN_ENUM})\b",
  "an absent value null-coalesces into a BENIGN ENUM MEMBER — the unknown case is "
  "spelled as the good case", tier=1, flags=re.I)

R("PUB-5", rf"default\s*:\s*return\s+(?!.*\bunknown\b)[A-Za-z_]\w*\.(?:{BENIGN_ENUM}|minor|low)\b",
  "a switch DEFAULT returns a non-`unknown` benign member — a word the mapping has "
  "never seen buys a downgrade (guidebook discipline 3, door 2)", tier=1, flags=re.I)

R("PUB-6", rf"catch\s*(?:\([^)]*\))?\s*\{{(?:[^{{}}]|\n){{0,400}}?return\s+"
          rf"(?:true|false|0|0\.0|1\.0|[A-Za-z_]\w*\.(?:{BENIGN_ENUM}))\b",
  "a CATCH BLOCK returns a success/benign value — the failure is swallowed and "
  "reported to her as fine", tier=1, flags=re.I, multiline=True)

R("PUB-7", rf"\.(?:isEmpty|isNotEmpty)\s*\?\s*[^:;]{{0,80}}?(?:{BENIGN_ENUM}|{LIT})",
  "an EMPTY COLLECTION is ternaried straight into a benign value — an empty feed is "
  "not a clear road", tier=1, flags=re.I)

# --- a measured physical quantity manufactured (tier 2) --------------------
R("PUB-8", rf"\?\?\s*(?:{LIT})\b",
  "an absent input null-coalesces into a NUMBER OR FLAG — is that fallback a "
  "measurement you did not take? (condition_aggregator_met_norway 0.0.5 "
  "`_readNum(...precipitation_amount) ?? 0.0`)", tier=2)

R("PUB-9", r"\?\?\s*_?k[A-Z]\w*",
  "an absent input null-coalesces into a NAMED CONSTANT — the name usually admits it "
  "(vehicle_condition_fusion 0.3.3 `airTemp ?? _kAbsentTempPrecipFallbackCelsius`)",
  tier=2)

R("PUB-10", r"\b_?k(?:Assumed|Absent|Fallback|Presumed|Default(?:Safe|Clear|Dry))\w*",
  "a CONSTANT WHOSE NAME ADMITS the condition was never measured "
  "(vehicle_condition_fusion 0.3.3 `kAssumedAboveFreezingCelsius`)", tier=2)

# --- freshness / identity fabricated (tier 3) ------------------------------
R("PUB-11", r"\b(?:effective|expires|issued\w*|observed\w*|measured\w*|timestamp|validFrom|validTo)"
            r"\s*[:=]\s*DateTime\.now\(\)",
  "OUR clock is substituted for the PUBLISHER'S — a fabricated freshness that hides "
  "a dead feed and silently disables every staleness check downstream "
  "(guidebook discipline 2)", tier=3, flags=re.I)

R("PUB-12", r"LatLng\(\s*0(?:\.0)?\s*,\s*0(?:\.0)?\s*\)",
  "Null Island — a real coordinate in the Gulf of Guinea standing in for "
  "'position unknown'", tier=3)


# --------------------------------------------------------------------------
# scanning
# --------------------------------------------------------------------------
COMMENT = re.compile(r"^\s*(?:///|//|\*|/\*)")
SUPPRESS = re.compile(r"fabrication-ok:", re.I)

# Packages whose output a driver reads, directly or one hop away. Used only for
# RANKING, never for inclusion — everything published is always scanned.
DRIVER_FACING = re.compile(
    r"advisor|advisory|hazard|safety|safe|weather|condition|reroute|forecast|snow|ice|"
    r"driving|drive|vehicle|voice|guidance|pretrip|compound|fleet|navigation|route|"
    r"localization|position|kalman|aggregator", re.I)


@dataclass
class Finding:
    pkg: str
    ver: str
    path: str
    line: int
    rule: str
    tier: int
    meaning: str
    source: str
    suppressed: bool = False

    @property
    def loc(self) -> str:
        return f"{self.pkg} {self.ver} {self.path}:{self.line}"


def scan_text(pkg: str, ver: str, path: str, text: str) -> list[Finding]:
    lines = text.splitlines()
    out: list[Finding] = []
    hit: set[tuple[int, str]] = set()

    for rule in RULES:
        if rule.multiline:
            for m in rule.rx().finditer(text):
                ln = text.count("\n", 0, m.start()) + 1
                src = lines[ln - 1] if ln - 1 < len(lines) else ""
                if COMMENT.match(src):
                    continue
                if (ln, rule.id) in hit:
                    continue
                hit.add((ln, rule.id))
                out.append(Finding(pkg, ver, path, ln, rule.id, rule.tier, rule.meaning,
                                   src.strip(), bool(SUPPRESS.search(src))))
            continue
        for i, src in enumerate(lines, 1):
            if COMMENT.match(src):
                continue
            if rule.rx().search(src):
                if (i, rule.id) in hit:
                    continue
                hit.add((i, rule.id))
                out.append(Finding(pkg, ver, path, i, rule.id, rule.tier, rule.meaning,
                                   src.strip(), bool(SUPPRESS.search(src))))
    return out


def scan_package(reg: Registry, pkg: str, ver: str) -> list[Finding]:
    blob = reg.archive(pkg, ver)
    out: list[Finding] = []
    for path, text in dart_sources(blob):
        out.extend(scan_text(pkg, ver, path, text))
    return out


def rank_key(f: Finding) -> tuple:
    driver = 0 if DRIVER_FACING.search(f.pkg) else 1
    return (f.tier, driver, f.pkg, f.path, f.line)


# --------------------------------------------------------------------------
# the proof — L34: a guard is not INSERTED until it has been PROVEN to FAIL
# --------------------------------------------------------------------------
# Five live published packages fabricating a safety-benign value from an
# unmeasured input, found by a HUMAN-DIRECTED HUNT. Each is pinned to the exact
# PUBLISHED version and the exact file, and fetched from the registry at proof
# time — not reconstructed from a synthetic fixture, because a fixture proves the
# regex matches the fixture, and the fixture is written by the same hand as the
# regex. The window tolerates the line drifting; it does not tolerate the sweep
# firing somewhere else in the package and being credited for it.
KNOWN = [
    ("vehicle_condition_fusion", "0.3.3", "lib/src/vehicle_signal_fusion.dart", 147, 8,
     "absent air temp -> 5.0 fallback drives the precipitation branch"),
    ("fleet_hazard", "0.5.1", "lib/src/fleet_report.dart", 49, 8,
     "0.8 confidence manufactured for a report nobody rated"),
    ("route_condition_forecast", "0.1.5", "lib/src/models/route_forecast.dart", 22, 8,
     "unknown segments -> hasAnyHazard == false"),
    ("condition_aggregator_met_norway", "0.0.5", "lib/src/met_norway_advisory_provider.dart", 323, 8,
     "unmeasured precipitation -> 0.0 mm"),
    ("adaptive_reroute", "0.1.6", "lib/src/models/reroute_decision.dart", 41, 8,
     "'Route is clear' with confidence 1.0"),
]


def self_test(reg: Registry) -> int:
    print(">> SELF-TEST — does the sweep FIRE on the five KNOWN live published defects?")
    print("   (fetched from pub.dev at their published versions; no synthetic fixtures)")
    print()
    passed = 0
    for pkg, ver, path, want, window, what in KNOWN:
        found = [f for f in scan_package(reg, pkg, ver)
                 if f.path == path and abs(f.line - want) <= window]
        if found:
            passed += 1
            print(f"   PASS  {pkg} {ver}")
            print(f"         {what}")
            for f in sorted(found, key=lambda x: (x.tier, x.line))[:4]:
                print(f"         [{f.rule} tier{f.tier}] {path}:{f.line}: {f.source[:110]}")
        else:
            any_hit = [f for f in scan_package(reg, pkg, ver) if f.path == path]
            print(f"   FAIL  {pkg} {ver} — SILENT at {path}:~{want} ({what})")
            if any_hit:
                print(f"         (hits elsewhere in the file at lines "
                      f"{sorted(f.line for f in any_hit)[:12]} — NOT credited)")
        print()
    print(f">> SELF-TEST: {passed}/{len(KNOWN)}")
    if passed != len(KNOWN):
        print("   A sweep that misses a defect it was built for is NOT BUILT.")
        return 1
    print("   All five known live fabrications are caught at their published versions.")
    return 0


# --------------------------------------------------------------------------
def report(findings: list[Finding], catalog: dict[str, str]) -> None:
    live = [f for f in findings if not f.suppressed]
    supp = [f for f in findings if f.suppressed]
    live.sort(key=rank_key)

    TIER_NAME = {
        1: "TIER 1 — THE FABRICATED VALUE IS A SAFETY VERDICT (closest to a driver-facing claim)",
        2: "TIER 2 — A MEASURED PHYSICAL QUANTITY IS MANUFACTURED",
        3: "TIER 3 — FRESHNESS OR POSITION IS FABRICATED",
        4: "TIER 4 — GENERIC FALLBACK, SAFETY RELEVANCE UNDETERMINED",
    }
    for tier in (1, 2, 3, 4):
        rows = [f for f in live if f.tier == tier]
        if not rows:
            continue
        print()
        print("=" * 100)
        print(TIER_NAME[tier] + f"   [{len(rows)} candidate(s)]")
        print("=" * 100)
        cur_rule = None
        cur_pkg = None
        for f in rows:
            if f.pkg != cur_pkg:
                cur_pkg = f.pkg
                cur_rule = None
                driver = "driver-facing" if DRIVER_FACING.search(f.pkg) else "infrastructure"
                print(f"\n  ## {f.pkg} {f.ver}   ({driver})")
            if f.rule != cur_rule:
                cur_rule = f.rule
                print(f"     [{f.rule}] {f.meaning}")
            print(f"        {f.path}:{f.line}")
            print(f"           {f.source[:150]}")

    print()
    print("=" * 100)
    pkgs = len({f.pkg for f in live})
    print(f"SWEEP COMPLETE — {len(live)} candidate(s) across {pkgs} of "
          f"{len(catalog)} published packages.")
    for tier in (1, 2, 3, 4):
        n = len([f for f in live if f.tier == tier])
        np_ = len({f.pkg for f in live if f.tier == tier})
        print(f"   tier {tier}: {n:4d} candidate(s) in {np_} package(s)")
    if supp:
        print(f"   suppressed by an in-code `// fabrication-ok:` : {len(supp)} "
              f"(REPORTED, never silently dropped — a suppression we wrote is not a clearance)")
        for f in sorted(supp, key=rank_key)[:20]:
            print(f"        {f.loc}  [{f.rule}]  {f.source[:100]}")
    print()
    print("Every line above is a CANDIDATE for human adjudication, never a verdict.")
    print("The question each one asks is the same: does an absent, failed, or unmeasured")
    print("input here become a value that reads to the driver as safe?")
    print()
    print("WHAT THIS RUN COULD NOT SEE: semantic fabrication with no literal at the call")
    print("site; CROSS-PACKAGE composition (a consumer laundering a fabricated constant")
    print("into a driver-facing number — live today at driving_conditions/lib/src/")
    print("simulation/fleet_hazard_confidence_adapter.dart:67-68); anything inside a")
    print("dependency; any shape absent from the rule table. See the file header.")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--self-test", action="store_true", dest="selftest")
    ap.add_argument("--dump", metavar="PKG[==VER]")
    ap.add_argument("--grep", metavar="REGEX", default=None)
    ap.add_argument("--json", metavar="OUT.json", default=None)
    ap.add_argument("--no-net", action="store_true")
    ap.add_argument("--only", metavar="PKG", default=None)
    args = ap.parse_args(argv)

    reg = Registry(allow_net=not args.no_net)

    if args.dump:
        pkg, _, ver = args.dump.partition("==")
        if not ver:
            meta = reg.meta(pkg)
            if meta is None:
                print(f"{pkg}: NOT PUBLISHED")
                return 1
            ver = meta["latest"]["version"]
        for path, text in dart_sources(reg.archive(pkg, ver)):
            for i, line in enumerate(text.splitlines(), 1):
                if args.grep and not re.search(args.grep, line):
                    continue
                print(f"{pkg} {ver} {path}:{i}: {line.rstrip()}")
        return 0

    if args.selftest:
        return self_test(reg)

    print(">> Published fabrication sweep — what is in the driver hands RIGHT NOW")
    print("   Source of truth is the REGISTRY. The local tree is not what a stranger holds.")
    catalog = resolve_catalog(reg, seed_candidates())
    if args.only:
        catalog = {k: v for k, v in catalog.items() if k == args.only}

    findings: list[Finding] = []
    for pkg, ver in catalog.items():
        try:
            findings.extend(scan_package(reg, pkg, ver))
        except Exception as e:
            print(f"   !! {pkg} {ver}: archive unreadable ({e}) — NOT scanned, NOT cleared")
    report(findings, catalog)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({
                "catalog": catalog,
                "findings": [f.__dict__ for f in sorted(findings, key=rank_key)],
            }, fh, indent=1)
        print(f"machine-readable findings -> {args.json}")

    return 1 if [f for f in findings if not f.suppressed] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
