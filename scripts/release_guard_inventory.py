#!/usr/bin/env python3
"""release_guard_inventory.py -- every `assert` in a shipped lib/ is declared, or CI is red.

WHY (written BEFORE the act, OPS-070(B))
========================================
Dart strips `assert` from AOT builds AND from plain `dart run`. Measured on Dart
3.11.1, 2026-09-13, with a compiled probe rather than from memory:

    dart test                          asserts ON
    dart run file.dart                 asserts OFF
    dart compile exe                   asserts OFF
    dart compile exe --enable-asserts  asserts ON

So an integrator who ships our package, and an edge developer who merely SCRIPTS
against it with `dart run`, both get a build in which every `assert` is gone. Our
own test suite is the one place the guards exist. A suite that is green about a
guard absent from every shipped build has measured our tests, not our product.

Two guards were found this way on 2026-09-13 and converted to real throws:
  DataBudget.relax                          -- in release, an UNCONFIRMED caller
                                               got the relaxation. The
                                               driver-always-drives invariant was
                                               not unenforced; it was INVERTED.
  VehicleThresholdOverrides.applyOverride-  -- in release, a vehicle-class override
  ForToken (x5)                                that RELAXED a warning threshold or
                                               moved a score floor was accepted
                                               silently.

Neither was found by a test. Both were found by reading the shipped semantics.
This file exists so the NEXT one is found by CI instead.

WHAT THIS CHECKS -- and what it deliberately does NOT
=====================================================
It does NOT try to guess which asserts are load-bearing. That judgement failed
once already: the same day, a remedy prescribed as `if (v <= 0) throw` was found
to REGRESS the code it replaced, because `double.nan <= 0` is false and the
original assert had rejected NaN. A pattern that decides for you decides wrong
quietly.

Instead: EVERY `assert(` under a published package's `lib/` must be DECLARED in
release_guard_inventory.md with a class and a written reason. An undeclared
assert fails. A declared assert whose text has changed fails (the reason was
written about different code). A declaration for an assert that no longer exists
fails (stale exemption).

The exemptions are therefore VISIBLE in a file a person reads, not hidden inside
a regex nobody audits.

CLASSES (the inventory's `class:` field)
  REFUSAL          forbids a CALLER's request. Runs before the act. Stripped, it
                   PERMITS the forbidden thing. MUST be a real throw -- so this
                   class is a FAILURE if it is still an assert.
  POST-CONDITION   checks OUR OWN computed state, mid-drive. Throwing takes her
                   navigation away at the moment it is already degraded. Stays an
                   assert; degrade to the safe verdict and report instead.
  CONST-CTOR       an initializer-list assert in a `const` constructor. CANNOT
                   become a throw without dropping `const` -- a breaking API
                   change for every consumer using it as a default value. Named
                   honestly as an unclosed gap, not as an exemption earned.
  DEBUG-BLOCK      `assert(() { ... }())`. Documented debug-only by construction.
  UNREVIEWED       nobody has read its semantics yet. A TRUE statement of debt.
                   Counted and printed on every run so it cannot go quiet.

`--self-test` proves the detector can actually go red. A guard that cannot fail
has measured nothing.

EXIT  0 = every assert declared and matching · 1 = drift · 2 = instrument unsound
"""
import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
INVENTORY = REPO / "scripts" / "release_guard_inventory.md"
VALID = {"REFUSAL", "POST-CONDITION", "CONST-CTOR", "DEBUG-BLOCK", "UNREVIEWED"}
ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*(\S+)\s*\|\s*([0-9a-f]{12})\s*\|\s*(.*?)\s*\|$")


def norm(text):
    return re.sub(r"\s+", " ", text).strip()


def scan(root):
    """Return {key: (path, lineno, normalized_text, digest)}."""
    found = {}
    for lib in sorted(root.glob("packages/*/lib")):
        for f in sorted(lib.rglob("*.dart")):
            lines = f.read_text(encoding="utf-8").splitlines()
            rel = str(f.relative_to(root))
            seen = {}
            for i, line in enumerate(lines, 1):
                if "assert(" not in line:
                    continue
                # skip comment/doc lines -- they discuss asserts, they are not asserts
                if norm(line).startswith(("//", "///", "*", "/*")):
                    continue
                # the assert plus enough following lines to capture its condition
                chunk = norm(" ".join(lines[i - 1:i + 2]))
                start = chunk.index("assert(")
                text = chunk[start:start + 110]
                n = seen.get(text, 0)
                seen[text] = n + 1
                key = f"{rel}#{n}" if n else rel
                # de-dup identical text in one file by occurrence index
                while key in found:
                    n += 1
                    key = f"{rel}#{n}"
                found[key] = (rel, i, text, hashlib.sha1(text.encode()).hexdigest()[:12])
    return found


def load_inventory():
    if not INVENTORY.exists():
        return None
    rows = {}
    for line in INVENTORY.read_text(encoding="utf-8").splitlines():
        m = ROW.match(line.strip())
        if m:
            rows[m.group(1)] = (m.group(2), m.group(3), m.group(4))
    return rows


def check(root=REPO, quiet=False):
    onDisk = scan(root)
    declared = load_inventory()
    if declared is None:
        print(f"INSTRUMENT-UNSOUND: no inventory at {INVENTORY}", file=sys.stderr)
        return 2
    if not declared:
        print("INSTRUMENT-UNSOUND: inventory parsed to ZERO rows -- the table "
              "format changed and this check is now silently clearing "
              "everything.", file=sys.stderr)
        return 2

    undeclared, changed, stale, bad_class, refusal_left = [], [], [], [], []
    for key, (rel, ln, text, dig) in sorted(onDisk.items()):
        if key not in declared:
            undeclared.append((key, ln, text))
            continue
        cls, d_dig, _reason = declared[key]
        if cls not in VALID:
            bad_class.append((key, cls))
        if cls == "REFUSAL":
            refusal_left.append((key, ln))
        if d_dig != dig:
            changed.append((key, ln, d_dig, dig, text))
    for key in sorted(declared):
        if key not in onDisk:
            stale.append(key)

    counts = {}
    for key in onDisk:
        if key in declared:
            counts[declared[key][0]] = counts.get(declared[key][0], 0) + 1

    if not quiet:
        print(f"asserts under packages/*/lib : {len(onDisk)}")
        print(f"declared in inventory        : {len(declared)}")
        for c in sorted(counts):
            print(f"    {c:<15} {counts[c]}")
        if counts.get("UNREVIEWED"):
            print(f"  >> {counts['UNREVIEWED']} assert(s) have NOT been read for "
                  f"release semantics. This is debt, not a clearance.")

    rc = 0
    for label, items, hint in (
        ("UNDECLARED assert in a shipped lib/", undeclared,
         "add a row to scripts/release_guard_inventory.md with a class and a reason"),
        ("DECLARED assert whose TEXT CHANGED", changed,
         "the written reason was about different code -- re-read it and update the digest"),
        ("STALE declaration (assert no longer on disk)", stale,
         "remove the row"),
        ("INVALID class", bad_class, f"use one of {sorted(VALID)}"),
        ("class REFUSAL but still an assert -- it is ABSENT from every shipped "
         "build", refusal_left, "convert it to a real throw"),
    ):
        if items:
            rc = 1
            print(f"\nFAIL -- {label} ({len(items)}):")
            for it in items:
                print(f"    {it}")
            print(f"    -> {hint}")

    if rc == 0 and not quiet:
        print("\npass  every assert under a shipped lib/ is declared and unchanged")
    return rc


def self_test():
    """Prove this detector can go red. Injects a synthetic assert into a real
    package lib/, expects a non-zero exit, then removes it and expects zero."""
    print("SELF-TEST -- a guard that cannot fail has measured nothing")
    base = check(quiet=True)
    if base != 0:
        print(f"  SKIP verdict: the tree is ALREADY red (rc={base}). Self-test "
              f"cannot distinguish its own injection from the standing failure.")
        return 2
    print("  baseline: rc=0 (clean tree)")
    victim = REPO / "packages" / "kalman_dr" / "lib" / "_selftest_injected.dart"
    victim.write_text("void _f(int x) {\n  assert(x > 0, 'SELF-TEST INJECTION');\n}\n")
    try:
        hot = check(quiet=True)
    finally:
        victim.unlink()
    after = check(quiet=True)
    print(f"  with an undeclared assert injected: rc={hot} (must be 1)")
    print(f"  after removing it:                  rc={after} (must be 0)")
    if hot == 1 and after == 0:
        print("  PASS -- the detector detects. Two-sided: it went red on the "
              "defect and green without it.")
        return 0
    print("  FAIL -- INSTRUMENT-UNSOUND. This check reports nothing about the repo.")
    return 2


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else check())
