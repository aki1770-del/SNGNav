#!/usr/bin/env python3
"""PDS REACH ORACLE — the canonical substrate for "does this version reach the weaver?"

Owned by PDS (package-delivery-steward, D-VGC235-1). This is SUBSTRATE, not tribal
knowledge: the reach arithmetic lives here, executable and self-proving, because the
one time it lived in a human's head it was got WRONG.

THE ERROR THIS EXISTS TO END (2026-07-12): a `condition_aggregator 0.0.8` "in-range
patch" was built and staged to reach consumers pinning `^0.0.7` — but Dart's caret
on a `0.0.x` version collapses to the EXACT version: `^0.0.7` == `>=0.0.7 <0.0.8`.
`0.0.8` reaches NOBODY who pins `^0.0.7`. The patch built to reach the weaver reached
no one. PDS's bylaws had the `0.x.y` case (`^0.4.4` admits `0.4.5`) and silently
missed the `0.0.x` collapse. Substrate closes that.

DART CARET SEMANTICS (the whole point — pub.dev's own rule):
  the boundary is set by the FIRST NON-ZERO digit.
    ^1.2.3  => >=1.2.3 <2.0.0      (major)
    ^0.2.3  => >=0.2.3 <0.3.0      (minor, when major==0)
    ^0.0.3  => >=0.0.3 <0.0.4      (PATCH-EXACT, when major==minor==0)  <-- the trap
  So for a 0.0.x package there is NO in-range patch at all: any new version is
  outside every existing consumer's caret. The only way to reach them is for the
  CONSUMER to widen the constraint. (If the consumer is ours, we widen it. If it is a
  stranger's, no publish reaches them — say so; do not pretend a publish delivers.)

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
    """Exclusive upper bound of a caret constraint — first non-zero digit is the wall."""
    a, b, c = parse(v)
    if a > 0:
        return (a + 1, 0, 0)
    if b > 0:
        return (a, b + 1, 0)
    return (a, b, c + 1)          # ^0.0.7 -> <0.0.8   (the trap)


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
        if not ok and hi == (lo[0], lo[1], lo[2] + 1):
            why += '  (0.0.x caret is PATCH-EXACT — no in-range patch exists; consumer must widen)'
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
        ('^0.0.7', '0.0.8', False),  # THE TRAP: 0.0.x caret is patch-exact
        ('^0.0.7', '0.0.7', True),   # only the exact version
        ('^0.0.5', '0.0.8', False),
        ('^0.0.7', '0.1.0', False),
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
