#!/usr/bin/env python3
"""stale-pin-check.py — a repaired defect must not leave its warning standing.

WHY (2026-08-21):

  `nav2_safety_layer` shipped SAFETY_BOUNDARY.md to consumers with two Assumptions of
  Use that had become FALSE:

    AoU-5  "This package will drop [STOP] under load (D-07)."   -> repaired; it does not
    AoU-6  "the advisory text names road ice regardless of what the monitor reported"
                                                                -> repaired; it does not

  Both defects were fixed and three artifacts kept asserting the old world: the two AoUs
  and the `reason:` of a test that was PASSING — which is the worse case, because green
  means nobody reads it. AoU-5 told integrators the package swallows the most severe
  signal nav2 can publish. That is a false safety claim, in the conservative direction,
  shipped to edge developers, for as long as nobody re-read it.

  ⚑ The absent primitive: NOTHING DETECTS THAT A PINNED DEFECT HAS BEEN REPAIRED. A stale
  pin and a live pin are both red, and are indistinguishable. This is the session's own
  defect family turned around: not an absent measurement wearing a definite value, but a
  STALE measurement wearing a current one.

  Counterfactual: run against the tree of 2026-08-20, this reports D-07 as REPAIRED-BUT-
  STILL-WARNED. Re-entrancy (§11 test 3): `absent-value-outbound-check.py` reads a diff for
  absent values; this reads a boundary document against live test results. Different
  surface, different question. Not duplication.

⚑ KNOWN LIMITATION, measured on its first real run and stated rather than hidden:
  a "pinned defect" test can be written two ways, and this checker cannot tell them apart.

    (a) assert-the-FIX     — fails while the defect is live, passes once repaired
    (b) assert-the-DEFECT  — PASSES while the defect is live (BI-8 is written this way)

  This rule assumes (a). On style (b) it reports a live defect as a stale claim. First real
  run: 5 flags on the repaired tree — 1 genuine (the D-07 row in §3.1, which the pen missed
  an hour after amending AoU-5 for the same repair) and 4 false positives on D-08, which is
  genuinely LIVE and guarded style-(b).

  Therefore this is WIRED AS REPORTING, NOT AS A GATE. A gate at a 4-in-5 false-positive rate
  would be routed around inside a week (a check costing more than the defect it catches
  gets bypassed), and a routed-around gate is worse than none.

  The convention that would close it, PROPOSED not imposed: name style-(b) tests with a
  `PINNED-LIVE:` prefix, and this rule skips them. That is a suite-wide change and belongs to
  whoever owns the suite, not to this script.

USAGE
  stale-pin-check.py <package-dir> [...]      # check each package
  stale-pin-check.py --self-test              # controls

EXIT: 0 consistent · 1 stale claim found · 2 self-test failure
"""
import json, re, subprocess, sys, os

DEFECT_ID = re.compile(r"\b((?:D|PI|BI)-\d+)\b")
REPAIRED  = re.compile(r"\b(REPAIRED|AMENDED|was FALSE|no longer)\b", re.I)
LIVE_CLAIM = re.compile(r"\b(will |does |names |accepts?|is silently|are byte-identical|"
                        r"performs \*\*none\*\*|has no )", re.I)

def test_results(pkg):
    """Return {test-name: passed?} from `dart test --reporter json`, or None if unrunnable."""
    try:
        r = subprocess.run(["dart", "test", "--reporter", "json"], cwd=pkg,
                           capture_output=True, text=True, timeout=600)
    except Exception:
        return None
    tests, out = {}, {}
    for line in r.stdout.splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "testStart":
            t = ev["test"]
            if not t.get("name", "").startswith("loading "):
                tests[t["id"]] = t["name"]
        elif ev.get("type") == "testDone" and ev.get("testID") in tests:
            out[tests[ev["testID"]]] = (ev.get("result") == "success" and not ev.get("hidden"))
    return out or None

def check(pkg):
    doc = os.path.join(pkg, "SAFETY_BOUNDARY.md")
    if not os.path.isfile(doc):
        return []
    res = test_results(pkg)
    if res is None:
        # ⚑ fail-closed: an unrunnable suite is UNVERIFIED, never "consistent".
        return [(doc, 0, "UNVERIFIABLE — the test suite could not be run, so no claim in "
                         "this document has been checked. This is not a pass.")]
    findings = []
    for i, line in enumerate(open(doc, encoding="utf-8"), 1):
        ids = set(DEFECT_ID.findall(line))
        if not ids or not LIVE_CLAIM.search(line) or REPAIRED.search(line):
            continue
        for d in sorted(ids):
            guards = {n: ok for n, ok in res.items() if d in n}
            if guards and all(guards.values()):
                findings.append((doc, i,
                    f"{d} is asserted as CURRENT here, but every test naming {d} PASSES "
                    f"({len(guards)} test(s)). Either the defect was repaired and this "
                    f"warning is stale, or the guarding test no longer proves it."))
    return findings

CONTROLS = [
 ("S1 live claim + all-green guard -> FLAG",
  "| AoU-5 | This package will drop it under load (D-07). |",
  {"BI-9 — D-07: a STOP survives": True}, True),
 ("S2 same line marked AMENDED -> clean",
  "| AoU-5 | ⚑ AMENDED — the previous text was FALSE. D-07 is repaired. |",
  {"BI-9 — D-07: a STOP survives": True}, False),
 ("S3 live claim + still-failing guard -> clean (the pin is honest)",
  "| AoU-2 | This package performs **none** of these checks (PI-01). |",
  {"DEFECT 1 — PI-01 absent action_type": False}, False),
 ("S4 no defect id -> clean", "| AoU-8 | You own the transport. |", {}, False),
]

def self_test():
    ok = True
    for name, line, res, must in CONTROLS:
        ids = set(DEFECT_ID.findall(line))
        got = False
        if ids and LIVE_CLAIM.search(line) and not REPAIRED.search(line):
            for d in ids:
                g = {n: v for n, v in res.items() if d in n}
                if g and all(g.values()):
                    got = True
        good = got == must; ok &= good
        print(f"  {'pass' if good else 'FAIL'}  {name}  (expect={'FLAG' if must else 'clean'} got={'FLAG' if got else 'clean'})")
    # failing control
    saved = globals()['LIVE_CLAIM']; globals()['LIVE_CLAIM'] = re.compile(r"$^")
    line, res = CONTROLS[0][1], CONTROLS[0][2]
    still = bool(set(DEFECT_ID.findall(line)) and LIVE_CLAIM.search(line))
    globals()['LIVE_CLAIM'] = saved
    fc = not still; ok &= fc
    print(f"  {'pass' if fc else 'FAIL'}  S5 mutated rule stops detecting S1 (a self-test that cannot fail has measured nothing)")
    print(f"\n{'SELF-TEST PASS' if ok else 'SELF-TEST FAIL'} — {len(CONTROLS)+1} controls")
    return 0 if ok else 2

if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    pkgs = [a for a in sys.argv[1:] if not a.startswith("-")]
    all_f = [f for p in pkgs for f in check(p)]
    if not all_f:
        print("stale-pin-check: consistent — no repaired defect leaves a standing warning")
        sys.exit(0)
    print(f"⚑ stale-pin-check: {len(all_f)} stale claim(s)\n")
    for d, i, w in all_f:
        print(f"  {d}:{i}\n    {w}\n")
    print("A repaired defect must not leave its warning standing. Amend the document, or "
          "restore the test that proves the defect is still live.")
    sys.exit(1)
