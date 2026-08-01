#!/usr/bin/env python3
"""PDS REACH ORACLE — the canonical substrate for "does this version reach the weaver?"

Owned by PDS (package-delivery-steward, D-VGC235-1). This is SUBSTRATE, not tribal
knowledge: the reach arithmetic lives here, executable and self-proving, because the
one time it lived in a human's head it was got WRONG.

CORRECTED 2026-08-01 — THIS ORACLE WAS ITSELF WRONG FOR THREE WEEKS.
From 2026-07-12 until now it encoded **npm** caret semantics, not **Dart's**, and
asserted that `^0.0.7` == `>=0.0.7 <0.0.8`. That is false. Dart's `pub_semver` special-
cases major==0 by incrementing the MINOR, never the patch:
  ~/.pub-cache/hosted/pub.dev/pub_semver-2.0.0/lib/src/version.dart:236
    Version get nextBreaking { if (major == 0) { return _incrementMinor(); } ... }
Proven on the real solver 2026-08-01: `^0.0.5` admits 0.0.6, 0.0.7 AND 0.0.8; excludes
0.1.0. So the old header's founding story is inverted — `condition_aggregator 0.0.8`
reached ALL of the `^0.0.7` consumers, not none of them.

WHY THIS MATTERED (the harm the defect actually did): a false "DOES NOT REACH" biases
the unit toward BREAKING MAJOR bumps as the supposed only vehicle — and a breaking bump
is the one thing a caret-pinned consumer can never receive. An oracle built to stop us
shipping fixes nobody gets was, for three weeks, the reason we shipped fixes nobody got.
It looked like substrate, so nobody re-derived it. A self-test that only checks the
implementation against its author's own belief proves the belief, never the world:
these cases are now anchored to `pub_semver`, and any change must be re-proven against
the real solver, not against this file.

DART CARET SEMANTICS (pub.dev's own rule — verified, not recalled):
  the boundary is the next BREAKING version, where "breaking" means major+1 if major>0,
  else minor+1. The patch digit is NEVER the wall.
    ^1.2.3  => >=1.2.3 <2.0.0      (major>0  -> major+1)
    ^0.2.3  => >=0.2.3 <0.3.0      (major==0 -> minor+1)
    ^0.0.3  => >=0.0.3 <0.1.0      (major==0 -> minor+1; ALL of 0.0.x is in range)
  A `0.0.x` package therefore has the WIDEST in-range corridor in the catalog, not the
  narrowest: every `0.0.*` patch reaches every `^0.0.*` consumer. Reach for a 0.0.x fix
  is the easy case. The hard case is `^0.N.x` -> `0.(N+1).0`, which reaches no one.

Usage:
  scripts/pds_reach.py --self-test
  scripts/pds_reach.py <constraint> <new_version>          # one check, exit 0=reaches 1=not
  scripts/pds_reach.py --scan <pkg>=<new_version> [...]     # scan vs real monorepo consumers
"""
import re
import sys
import os
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse(v):
    m = re.match(r'^(\d+)\.(\d+)\.(\d+)', v.strip().lstrip('^><=~ '))
    if not m:
        raise ValueError(f'unparseable version: {v!r}')
    return tuple(int(x) for x in m.groups())


def caret_upper(v):
    """Exclusive upper bound of a caret constraint == pub_semver's `nextBreaking`.

    major>0 -> major+1; major==0 -> minor+1. The patch digit is never the wall.
    Mirrors pub_semver-2.0.0/lib/src/version.dart:236 exactly; do not "simplify" this
    to first-non-zero-digit — that is npm's rule and it is what made this oracle wrong.
    """
    a, b, c = parse(v)
    if a > 0:
        return (a + 1, 0, 0)
    return (a, b + 1, 0)          # ^0.0.7 -> <0.1.0 ; ^0.2.3 -> <0.3.0


def reaches(constraint, new_version):
    """Does `new_version` satisfy `constraint`? Handles caret, exact, and simple ranges.

    Returns (bool, human_reason).
    """
    con = constraint.strip()
    nv = parse(new_version)

    if con.startswith('^'):
        lo = parse(con)
        hi = caret_upper(con)
        ok = lo <= nv < hi
        why = f'{con} == >={".".join(map(str,lo))} <{".".join(map(str,hi))}'
        if not ok and nv >= hi:
            why += ('  (the new version crosses the caret wall — a caret-pinned consumer'
                    ' can NEVER receive it; an in-range patch below the wall is the only vehicle)')
        return ok, why

    # range: ">=a <b", ">=a", "<b", or exact "a.b.c"
    lo = hi_excl = None
    for tok in con.split():
        if tok.startswith('>='):
            lo = parse(tok)
        elif tok.startswith('<'):
            hi_excl = parse(tok)
        elif re.match(r'^\d', tok):          # bare exact
            lo = parse(tok); hi_excl = (lo[0], lo[1], lo[2] + 1)
    if lo is None and hi_excl is None:
        return False, f'unrecognised constraint {con!r}'
    ok = (lo is None or nv >= lo) and (hi_excl is None or nv < hi_excl)
    return ok, con


def monorepo_consumers(pkg):
    """Every constraint on `pkg` declared by a sibling in the monorepo (file:line, constraint)."""
    out = []
    for pub in glob.glob(f'{ROOT}/packages/*/pubspec.yaml') + [f'{ROOT}/sngnav-app/pubspec.yaml']:
        if not os.path.exists(pub):
            continue
        for i, line in enumerate(open(pub), 1):
            m = re.match(rf'\s+{re.escape(pkg)}:\s*(\S.*)$', line)
            if m and not line.strip().startswith(pkg + '_'):
                con = m.group(1).strip().strip('"\'')
                if con and not con.startswith('#'):
                    out.append((pub.replace(ROOT + '/', ''), i, con))
    return out


def self_test():
    cases = [
        # (constraint, version, expected_reaches)
        ('^0.3.0', '0.3.1', True),   # 0.x.y minor caret admits patch
        ('^0.4.4', '0.4.5', True),
        ('^0.4.4', '0.5.0', False),  # major-line bump escapes minor caret
        # 0.0.x: ALL of 0.0.* is in range (pub_semver nextBreaking, major==0 -> minor+1).
        # Solver-proven 2026-08-01; these three cases previously asserted the opposite.
        ('^0.0.7', '0.0.8', True),
        ('^0.0.7', '0.0.7', True),
        ('^0.0.5', '0.0.8', True),
        ('^0.0.5', '0.0.6', True),   # the live case: digitraffic 0.0.7 DOES reach ^0.0.5
        ('^0.0.5', '0.0.7', True),
        ('^0.0.7', '0.1.0', False),  # the wall is the MINOR, and 0.1.0 crosses it
        ('^0.2.0', '0.2.10', True),  # double-digit patch, in range (snow_rendering)
        ('^0.2.0', '0.3.0', False),  # the real wall she is behind
        ('^0.4.0', '0.4.5', True),
        ('^0.4.0', '0.5.0', False),
        ('^1.2.3', '1.9.9', True),
        ('^1.2.3', '2.0.0', False),
        ('>=0.0.7 <0.1.0', '0.0.8', True),   # a WIDENED range does admit 0.0.8
        ('>=0.4.4 <0.5.0', '0.4.9', True),
    ]
    ok = 0
    for con, v, exp in cases:
        got, why = reaches(con, v)
        mark = 'PASS' if got == exp else 'FAIL'
        if got == exp:
            ok += 1
        print(f'  {mark}  {con:16s} {v:8s} reaches={got}  ({why})')
    print(f'\nSELF-TEST: {ok}/{len(cases)}')
    return ok == len(cases)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == '--self-test':
        sys.exit(0 if self_test() else 1)

    if len(sys.argv) >= 2 and sys.argv[1] == '--scan':
        specs = sys.argv[2:]
        broken = 0
        print('>> PDS reach scan — does each new version reach its real monorepo consumers?\n')
        for spec in specs:
            pkg, nv = spec.split('=')
            consumers = monorepo_consumers(pkg)
            if not consumers:
                print(f'  {pkg} {nv}: no monorepo consumer pins it (external-only reach — check pub.dev)')
                continue
            for src, ln, con in consumers:
                ok, why = reaches(con, nv)
                tag = 'REACHES' if ok else '*** DOES NOT REACH ***'
                if not ok:
                    broken += 1
                print(f'  {pkg} {nv}  <- {src}:{ln} pins {con}: {tag}')
                if not ok:
                    print(f'       {why}')
        print(f'\n{"BROKEN: " + str(broken) + " consumer(s) unreached — DO NOT PUBLISH as-is." if broken else "ALL CONSUMERS REACHED."}')
        sys.exit(1 if broken else 0)

    if len(sys.argv) == 3:
        ok, why = reaches(sys.argv[1], sys.argv[2])
        print(f'{"REACHES" if ok else "DOES NOT REACH"}: {why}')
        sys.exit(0 if ok else 1)

    print(__doc__)
    sys.exit(2)


if __name__ == '__main__':
    main()
