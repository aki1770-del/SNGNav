#!/usr/bin/env python3
"""Does a constraint we publish exclude a sibling we publish?

Mission anchor (PHIL-001 / D3 supreme): driving_weather 0.5.0 and snow_rendering
0.3.0 are the releases carrying the measured-or-absent contract - an unmeasured
road is reported as unmeasured, never as dry. Measured 2026-08-21: a consumer
running `pub add driving_conditions` resolves driving_weather 0.4.5 and
snow_rendering 0.2.9, because four published constraints cap at ^0.4.x. The fix
we published to reach her does not reach her. She is the driver in unexpected
snow and she cannot tell the difference.
D5: Evidence -> Contribution -> Architecture -> Edge Developer -> Driver.

WHY CI DID NOT CATCH IT: the hosted-resolve lane proves a clean consumer CAN
resolve. It does not ask WHAT they resolve. A stale cap resolves perfectly - to
the wrong version - so resolution success is not the question.

================================================================================
CORRECTED 2026-08-28 (PDS) - THIS GUARD CARRIED THE ARITHMETIC IT EXISTS TO CATCH.
================================================================================
From 2026-08-21 until now this file encoded **npm** caret semantics for the
0.0.x corner and stated them in its own header:

    ~~^0.0.3  ->  >=0.0.3 <0.0.4      <-- "the one that hid"~~          FALSE
    ~~"My first checker read ^0.0.5 as <0.1.0 and called it fine.
       It means <0.0.6."~~                                              INVERTED

**That first checker was RIGHT and it was corrected into being wrong.** Struck
rather than deleted (OPS-002): a later reader must be able to see that this guard
was founded on a real defect and then mis-derived the rule while fixing it.

DART'S ACTUAL RULE, from the solver, not from belief. pub_semver's `nextBreaking`
increments MAJOR when major > 0, otherwise MINOR - the patch digit is NEVER the
wall:
    ~/.pub-cache/hosted/pub.dev/pub_semver-2.2.0/lib/src/version.dart:243
    ~/.pub-cache/hosted/pub.dev/pub_semver-2.0.0/lib/src/version.dart  (identical)
        Version get nextBreaking {
          if (major == 0) { return _incrementMinor(); }
          return _incrementMajor();
        }

    ^1.2.3   ->  >=1.2.3 <2.0.0
    ^0.1.2   ->  >=0.1.2 <0.2.0
    ^0.0.5   ->  >=0.0.5 <0.1.0      <-- admits 0.0.6 .. 0.0.10 .. ALL of 0.0.x

Proven on the real solver 2026-08-28 (`VersionConstraint.parse(c).allows(v)`):
    ^0.0.5 allows 0.0.6=true  0.0.7=true  0.0.10=true  0.1.0=false  0.0.4=false
    ^0.0.3 allows 0.0.4=true          ^0.10.0 allows 0.11.1=false
These values are anchored to pub_semver. Any change to `caret_upper` must be
re-proven against the REAL SOLVER, never against this file's own belief.

WHICH DIRECTION THE DEFECT RAN, and why no real stale cap was ever hidden by it.
For major==0 and minor==0 the npm upper bound [0,0,patch+1] is strictly SMALLER
than Dart's [0,1,0]; for every other shape the two agree. A smaller upper bound
admits FEWER versions, so the broken rule could only ever manufacture a FAIL,
never suppress one. **Every FAIL it invented was false; every FAIL it reported
outside the 0.0.x corner was real.** Measured on backport/routing_engine-0.5.x:
16 reported, 8 false, 8 real.

WHY THAT MATTERED ANYWAY (Sakichi Vision 20): a gate that over-reports is a gate
that gets routed around. Half the report being noise is enough for a reader to
start discounting the whole output - which is how a real one gets missed.

SECOND DEFECT, FOUND IN THE SAME PASS AND LARGER THAN THE FIRST: 25 of 42
internal constraints - 60% - were being SILENTLY SKIPPED. `local_catalog` keeps
the YAML value verbatim, so a quoted constraint arrived as `'>=0.10.0 <0.12.0'`
WITH the quote characters, matched no branch of `admits`, and returned None. The
old header's boast that the six explicit ranges on navigation_safety_core "have
never failed" was true and VACUOUS - they had never been JUDGED. Worse, the FAIL
message recommended migrating to explicit ranges: **the guard was steering
constraints out of its own coverage.** Quotes are now stripped before judging,
and every unjudged form is printed BY NAME instead of summed into a footnote.
Coverage on the current catalog: 17/42 -> 42/42.

MEASURED CORRELATION, 2026-08-21, over the published catalog:
       caret constraints   13, excluding the published sibling  6
       explicit ranges      6, excluding the published sibling  0
   ⚑ RETAINED IN STRIKE, NOT RELIED ON: the "6" was produced by the npm rule and
   the "0" by a parser that judged none of them. Both figures are UNVERIFIED and
   must be re-measured before citation. Re-measure with --published.

MODES
  --local      (default) local constraints vs local sibling versions. Offline,
               deterministic, catches it BEFORE publish. This is the CI gate.
  --published  published constraints vs published versions. Needs pub.dev.
               Catches what a weaver actually gets today.
  --self-test  prove the arithmetic against pub_semver-anchored cases, and prove
               the suite goes RED under each defect this file has carried.

EXIT 0 clean · 1 a constraint excludes its sibling · 2 UNVERIFIABLE (never a pass)
"""
import glob, json, os, re, sys, urllib.request

V = re.compile(r'(\d+)\.(\d+)\.(\d+)')


def ver(s):
    m = V.match(str(s).strip())
    return [int(x) for x in m.groups()] if m else None


def caret_upper(v):
    """The exclusive upper bound of `^v`, exactly as pub_semver computes it.

    Mirrors Version.nextBreaking (version.dart:243): major if major > 0, else
    minor. TWO branches, not three - the third branch is the defect.
    """
    a, b, _c = v
    if a > 0:
        return [a + 1, 0, 0]
    return [a, b + 1, 0]


def _npm_caret_upper(v):
    """THE 2026-08-21 DEFECT, PRESERVED EXECUTABLY SO THE SELF-TEST CAN FAIL ON IT.

    This is npm's rule, not Dart's. It is never called by the check - it exists
    only as the negative control. A self-test that only checks the implementation
    against its author's own belief proves the belief, never the world.
    """
    a, b, c = v
    if a > 0:
        return [a + 1, 0, 0]
    if b > 0:
        return [a, b + 1, 0]
    return [a, b, c + 1]


def _strip_yaml_quotes(s):
    """`fleet_hazard: '>=0.5.0 <0.8.0'` reaches us WITH the quotes. Strip them.

    Not cosmetic: leaving them on is what silently unjudged 60% of the catalog.
    """
    c = str(s).strip()
    if len(c) >= 2 and c[0] == c[-1] and c[0] in ('"', "'"):
        c = c[1:-1].strip()
    return c


def admits(constraint, version, _upper=caret_upper):
    """True/False, or None when the form is one this check does not judge.

    `_upper` is injectable ONLY so the self-test can drive the npm reading
    through the identical code path. Production callers never pass it.
    """
    c, v = _strip_yaml_quotes(constraint), ver(version)
    if v is None or c == '':
        return None
    if c == 'any':
        return True            # admits everything; can never exclude a sibling
    if c.startswith('^'):
        lo = ver(c[1:])
        return None if lo is None else lo <= v < _upper(lo)
    m = re.match(r'>=\s*(\S+)\s*<\s*(\S+)$', c)
    if m:
        lo, hi = ver(m.group(1)), ver(m.group(2))
        return None if not (lo and hi) else lo <= v < hi
    m = re.match(r'>=\s*(\S+)$', c)
    if m:
        lo = ver(m.group(1))
        return None if lo is None else v >= lo
    if V.fullmatch(c):
        return v == ver(c)
    return None


def local_catalog(root):
    out = {}
    for pj in sorted(glob.glob(os.path.join(root, 'packages/*/pubspec.yaml'))):
        name = version = None
        deps = {}
        indep = False
        for line in open(pj, errors='replace'):
            if re.match(r'^name:', line):
                name = line.split(':', 1)[1].strip()
            if re.match(r'^version:', line):
                version = line.split(':', 1)[1].strip()
            if re.match(r'^dependencies:', line):
                indep = True; continue
            if re.match(r'^(dev_dependencies|dependency_overrides|flutter|environment):', line):
                indep = False
            if indep:
                m = re.match(r'^  ([a-z0-9_]+):\s*(\S.*)?$', line)
                if m and m.group(2):
                    deps[m.group(1)] = m.group(2).strip()
        if name:
            out[name] = {'version': version, 'deps': deps}
    return out


def published_catalog(names):
    out = {}
    for n in names:
        try:
            d = json.load(urllib.request.urlopen(f'https://pub.dev/api/packages/{n}', timeout=15))
            out[n] = {'version': d['latest']['version'],
                      'deps': d['latest']['pubspec'].get('dependencies', {}) or {}}
        except Exception as e:
            out[n] = {'error': str(e)[:70]}
    return out


# ---------------------------------------------------------------- self-test --

# Anchored to pub_semver, re-proven on the real solver 2026-08-28.
# To re-prove: VersionConstraint.parse(c).allows(Version.parse(v)).
SOLVER_CASES = [
    ('^0.0.5', '0.0.6',  True),   # the corner that was inverted
    ('^0.0.5', '0.0.7',  True),   # the live digitraffic case, reported FAIL falsely
    ('^0.0.5', '0.0.8',  True),   # the live noaa_nws_adapter case
    ('^0.0.5', '0.0.10', True),   # double-digit patch still inside the caret
    ('^0.0.5', '0.1.0',  False),  # the wall is the MINOR
    ('^0.0.5', '0.0.4',  False),  # below the floor
    ('^0.0.3', '0.0.4',  True),   # the header's own "the one that hid" - it did not
    ('^0.0.3', '0.0.3',  True),
    ('^0.0.9', '0.0.10', True),
    ('^0.1.2', '0.1.9',  True),
    ('^0.1.2', '0.2.0',  False),
    ('^0.10.0', '0.10.9', True),
    ('^0.10.0', '0.11.1', False),  # the REAL navigation_safety_core family FAIL
    ('^1.2.3', '1.9.0',  True),
    ('^1.2.3', '2.0.0',  False),
]

# The forms that were silently skipped. Quoting is not a different constraint.
QUOTE_CASES = [
    ("'>=0.10.0 <0.12.0'", '0.11.5', True),
    ('">=0.10.0 <0.12.0"', '0.11.5', True),
    ("'>=0.10.0 <0.12.0'", '0.12.0', False),
    ("'>=0.0.5 <0.2.0'",   '0.0.10', True),
    ("'^0.0.5'",           '0.0.10', True),   # a quoted caret would have been skipped too
    ('>=0.10.0 <0.12.0',   '0.11.5', True),   # unquoted still works
]


def self_test():
    ok = n = 0

    def check(label, got, want):
        nonlocal ok, n
        n += 1
        good = got == want
        ok += good
        print(f'  {"PASS" if good else "FAIL"}  {label}  got={got} want={want}')

    print('  -- ARITHMETIC, anchored to pub_semver (solver-proven 2026-08-28) --')
    for c, v, want in SOLVER_CASES:
        check(f'{c} admits {v}', admits(c, v), want)

    print('\n  -- COVERAGE: quoted forms are the SAME constraint --')
    for c, v, want in QUOTE_CASES:
        check(f'admits({c!r}, {v})', admits(c, v), want)

    print('\n  -- NEGATIVE CONTROL 1: the npm reading must turn this suite RED --')
    # Drive the IDENTICAL code path with the defect injected. If a later hand
    # reintroduces npm semantics, these assertions are what goes red.
    npm_disagreements = [(c, v, want) for c, v, want in SOLVER_CASES
                         if admits(c, v, _upper=_npm_caret_upper) != want]
    n += 1
    if npm_disagreements:
        ok += 1
        print(f'  PASS  npm reading is DETECTED: it fails {len(npm_disagreements)} '
              f'of {len(SOLVER_CASES)} solver-anchored cases')
        for c, v, want in npm_disagreements:
            print(f'          npm says {c} admits {v} = '
                  f'{admits(c, v, _upper=_npm_caret_upper)}, solver says {want}')
    else:
        print('  FAIL  npm reading is INVISIBLE to this suite - the suite measures nothing')

    n += 1
    got = admits('^0.0.5', '0.0.10', _upper=_npm_caret_upper)
    if got is False:
        ok += 1
        print(f'  PASS  the exact live defect reproduces under npm: '
              f'^0.0.5 admits 0.0.10 = {got} (solver: True)')
    else:
        print(f'  FAIL  the live defect did not reproduce: got {got}')

    print('\n  -- NEGATIVE CONTROL 2: the quote-skip must turn this suite RED --')

    def _unstripped_admits(constraint, version):
        """The 2026-08-21 parser: judges the raw YAML value, quotes and all."""
        c, v = str(constraint).strip(), ver(version)
        if v is None or c in ('any', ''):
            return None
        if c.startswith('^'):
            lo = ver(c[1:])
            return None if lo is None else lo <= v < caret_upper(lo)
        m = re.match(r'>=\s*(\S+)\s*<\s*(\S+)', c)
        if m:
            lo, hi = ver(m.group(1)), ver(m.group(2))
            return None if not (lo and hi) else lo <= v < hi
        return None

    skipped = [(c, v) for c, v, _w in QUOTE_CASES if _unstripped_admits(c, v) is None]
    n += 1
    if len(skipped) >= 5:
        ok += 1
        print(f'  PASS  the old parser silently skips {len(skipped)} of '
              f'{len(QUOTE_CASES)} quoted forms (returns None = "not judged")')
    else:
        print(f'  FAIL  expected the old parser to skip the quoted forms; it skipped '
              f'{len(skipped)}')

    print('\n  -- caret_upper agrees with nextBreaking on both branches --')
    check('caret_upper([0,0,5]) == [0,1,0]', caret_upper([0, 0, 5]), [0, 1, 0])
    check('caret_upper([0,4,4]) == [0,5,0]', caret_upper([0, 4, 4]), [0, 5, 0])
    check('caret_upper([1,2,3]) == [2,0,0]', caret_upper([1, 2, 3]), [2, 0, 0])

    print(f'\nSELF-TEST: {ok}/{n}')
    return ok == n


def main():
    if '--self-test' in sys.argv:
        return 0 if self_test() else 1

    mode = 'published' if '--published' in sys.argv else 'local'
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    local = local_catalog(root)
    if not local:
        print('no packages/*/pubspec.yaml found'); return 2
    own = set(local)

    if mode == 'local':
        cat = local
        print(f'sibling-constraint check — LOCAL ({len(own)} packages)')
    else:
        cat = published_catalog(sorted(own))
        errs = [n for n, v in cat.items() if 'error' in v]
        print(f'sibling-constraint check — PUBLISHED ({len(own) - len(errs)} of {len(own)} reachable)')
        if errs and len(errs) == len(own):
            print(f'  UNVERIFIABLE — pub.dev unreachable for every package.')
            print('  This is not a clean bill. It is the absence of a check.')
            return 2
        for n in errs:
            print(f'  UNVERIFIABLE  {n}: not on pub.dev or unreachable ({cat[n]["error"]})')

    bad, checked, unjudged = [], 0, []
    for p, info in sorted(cat.items()):
        if 'error' in info:
            continue
        for d, c in (info.get('deps') or {}).items():
            if d not in own or d not in cat or 'error' in cat[d]:
                continue
            a = admits(c, cat[d]['version'])
            if a is None:
                unjudged.append((p, d, c, cat[d]['version'])); continue
            checked += 1
            if not a:
                bad.append((p, info['version'], d, c, cat[d]['version']))

    print(f'  internal constraints judged: {checked}   (not judged: {len(unjudged)})')

    # An unjudged constraint is an UNCHECKED one. It was a bare count until
    # 2026-08-28, and 25 of 42 hid inside that count for a week. Never again:
    # print every one BY NAME, and never report it as a pass.
    if unjudged:
        print()
        print('  UNJUDGED — these were NOT checked. This is not a clean bill.')
        for p, d, c, dv in unjudged:
            print(f'    ?     {p}  declares  {d}: {c}   (sibling at {dv})')
            print(f'            the form is one `admits()` does not read. Widen the '
                  f'parser or state the constraint in a form it reads.')

    if not bad:
        if unjudged:
            print(f'\n{len(unjudged)} constraint(s) UNVERIFIABLE. '
                  f'Every judged constraint admits its sibling.')
            return 2
        print('  pass  every constraint admits the sibling version it will be resolved against')
        return 0
    print()
    for p, pv, d, c, dv in bad:
        print(f'  FAIL  {p} {pv}')
        print(f'          declares  {d}: {c}')
        print(f'          but {d} is at {dv} — EXCLUDED')
        cs = _strip_yaml_quotes(c)
        if cs.startswith('^'):
            u = caret_upper(ver(cs[1:]))
            print(f'          ^{cs[1:]} means <{u[0]}.{u[1]}.{u[2]} (pub_semver nextBreaking: '
                  f'major if major>0, else minor). Widen to an explicit '
                  f'>= <  range — a form this check now judges.')
        print()
    print(f'{len(bad)} constraint(s) exclude a sibling that exists.')
    print('A consumer resolves the OLD version, successfully and silently.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
