#!/usr/bin/env python3
"""Does a constraint we publish exclude a sibling we publish?

Why this matters: driving_weather 0.5.0 and snow_rendering
0.3.0 are the releases carrying the measured-or-absent contract - an unmeasured
road is reported as unmeasured, never as dry. Measured 2026-08-21: a consumer
running `pub add driving_conditions` resolves driving_weather 0.4.5 and
snow_rendering 0.2.9, because four published constraints cap at ^0.4.x. The fix
we published to reach her does not reach her. She is the driver in unexpected
snow and she cannot tell the difference.
The chain: Evidence -> Contribution -> Architecture -> Edge Developer -> Driver.

WHY CI DID NOT CATCH IT: the hosted-resolve lane proves a clean consumer CAN
resolve. It does not ask WHAT they resolve. A stale cap resolves perfectly - to
the wrong version - so resolution success is not the question.

================================================================================
CORRECTED 2026-08-28 - THIS GUARD CARRIED THE ARITHMETIC IT EXISTS TO CATCH.
================================================================================
From 2026-08-21 until now this file encoded **npm** caret semantics for the
0.0.x corner and stated them in its own header:

    ~~^0.0.3  ->  >=0.0.3 <0.0.4      <-- "the one that hid"~~          FALSE
    ~~"My first checker read ^0.0.5 as <0.1.0 and called it fine.
       It means <0.0.6."~~                                              INVERTED

**That first checker was RIGHT and it was corrected into being wrong.** Struck
rather than deleted: a later reader must be able to see that this guard
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

WHY THAT MATTERED ANYWAY: a gate that over-reports is a gate
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
               Catches what a consumer actually gets today.
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


# ===========================================================================
# EXAMPLE LANE — added 2026-09-12 (FDD).
#
# WHY: this guard ran GREEN — "pass  every constraint admits the sibling
# version it will be resolved against", 37 packages, 43 constraints — on the
# same day that ALL SIX published packages shipping an example/ failed
# `pub get` INSIDE that example with exit 66. It globs
# `packages/*/pubspec.yaml`. It never looked one directory deeper, so the
# example surface was invisible to it. That is a scope gap in an existing
# loom, not a missing loom: the question below is the question this file was
# founded on, asked of `example/`.
#
# Three things are judged, each measured on the real catalog on 2026-09-12:
#
#   1. SHIPS-PATH-OVERRIDES — pub does NOT strip `dependency_overrides` when
#      publishing. vehicle_condition_fusion 0.5.0 shipped
#      `driving_conditions: path: ../../driving_conditions` plus three more
#      inside its archive. A reader who extracted it and ran `dart pub get` in
#      example/ got exit 66, "path which doesn't exist", and NEVER REACHED the
#      version constraint at all. 6 of 6 examples carried this shape.
#      Remedy: move them to `example/pubspec_overrides.yaml` (pub honours it
#      for local development) and exclude that file via `.pubignore`.
#
#   2. NARROWER-THAN-PARENT — vehicle_condition_fusion's example pinned
#      `driving_conditions: ^0.6.0` (= >=0.6.0 <0.7.0) while the package it
#      demonstrates declares ">=0.6.0 <0.8.0". The example refused the
#      BREAKING 0.7.0 that its own parent accepts. An example must never be
#      narrower than the package it exists to demonstrate.
#
#   3. EXCLUDES-SIBLING — routing_bloc's and voice_guidance's examples pin
#      `navigation_safety: ^0.5.0`. pub.dev has never carried a 0.5.x; the
#      published line goes 0.4.0 -> 0.7.0. That constraint could not have
#      resolved on any day it existed.
# ===========================================================================


def example_catalog(root):
    """parent-package-dir -> {path, deps, inline_overrides}."""
    out = {}
    for pj in sorted(glob.glob(os.path.join(root, 'packages/*/example/pubspec.yaml'))):
        pkgdir = os.path.basename(os.path.dirname(os.path.dirname(pj)))
        deps, inline_ov, blk = {}, [], None
        for line in open(pj, errors='replace'):
            if re.match(r'^dependencies:', line):
                blk = 'deps'; continue
            if re.match(r'^dependency_overrides:', line):
                blk = 'ov'; continue
            if re.match(r'^[A-Za-z_]', line):
                blk = None; continue
            if blk == 'deps':
                m = re.match(r'^  ([a-z0-9_]+):\s*(\S.*)?$', line)
                if m and m.group(2):
                    deps[m.group(1)] = m.group(2).strip()
            elif blk == 'ov':
                m = re.match(r'^  ([a-z0-9_]+):\s*$', line)
                if m:
                    inline_ov.append(m.group(1))
        out[pkgdir] = {'path': pj, 'deps': deps, 'inline_overrides': inline_ov}
    return out


def example_lane(root, cat, own):
    ex = example_catalog(root)
    if not ex:
        print('\nexample lane: no packages/*/example/pubspec.yaml found — '
              'nothing judged. This is not a clean bill.')
        return 2
    print(f'\nsibling-constraint check — EXAMPLES ({len(ex)} example pubspecs)')
    bad, judged, unjudged = [], 0, []
    for pkg, info in sorted(ex.items()):
        if info['inline_overrides']:
            bad.append(('SHIPS-PATH-OVERRIDES', pkg,
                        ', '.join(info['inline_overrides']), '', ''))
        pdeps = (cat.get(pkg) or {}).get('deps') or {}
        for d, c in sorted(info['deps'].items()):
            if d not in own or d not in cat or 'error' in cat[d]:
                continue
            dv = cat[d]['version']
            a = admits(c, dv)
            if a is None:
                unjudged.append((pkg, d, c, dv)); continue
            judged += 1
            if a:
                continue
            if d in pdeps and admits(pdeps[d], dv) is True:
                bad.append(('NARROWER-THAN-PARENT', pkg, d, c, pdeps[d]))
            else:
                bad.append(('EXCLUDES-SIBLING', pkg, d, c, dv))
    print(f'  example constraints judged: {judged}   (not judged: {len(unjudged)})')
    for pkg, d, c, dv in unjudged:
        print(f'    ?     {pkg}/example  declares  {d}: {c}   (sibling at {dv})')
    if not bad:
        if unjudged:
            print('  UNVERIFIABLE — some example constraints were not judged.')
            return 2
        print('  pass  every example resolves the way the package it demonstrates does')
        return 0
    print()
    for kind, pkg, d, c, extra in bad:
        if kind == 'SHIPS-PATH-OVERRIDES':
            print(f'  FAIL  {pkg}/example/pubspec.yaml SHIPS path dependency_overrides: {d}')
            print('          pub does NOT strip these when publishing. A consumer who')
            print('          runs `dart pub get` in the published example/ gets exit 66,')
            print('          "path which doesn\'t exist", and never reaches any constraint.')
            print('          Move them to example/pubspec_overrides.yaml and exclude that')
            print('          file in .pubignore.')
        elif kind == 'NARROWER-THAN-PARENT':
            print(f'  FAIL  {pkg}/example  declares  {d}: {c}')
            print(f'          but {pkg} itself declares  {d}: {extra}  — the example is')
            print('          NARROWER than the package it demonstrates. A reader whose app')
            print(f'          already resolves a {d} the parent accepts cannot run it.')
        else:
            print(f'  FAIL  {pkg}/example  declares  {d}: {c}')
            print(f'          but {d} is at {extra} — EXCLUDED')
        print()
    print(f'{len(bad)} example defect(s). An example that cannot resolve is worse')
    print('than one pinned wrong: it is the first thing an edge developer copies.')
    return 1


def example_self_test():
    """Prove-it-fails: every case below is REAL, measured 2026-09-12."""
    ok = True

    def check(label, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print(f'  {"PASS" if good else "FAIL"}  {label}  got={got} want={want}')

    print('\n  -- example lane, on the defects actually found --')
    # routing_bloc + voice_guidance examples, measured: pub.dev navigation_safety
    # goes 0.4.0 -> 0.7.0, so ^0.5.0 matched no version that ever existed.
    check('^0.5.0 does NOT admit navigation_safety 0.9.6',
          admits('^0.5.0', '0.9.6'), False)
    # vehicle_condition_fusion example, the B-2 defect.
    check('^0.6.0 does NOT admit driving_conditions 0.7.1',
          admits('^0.6.0', '0.7.1'), False)
    # ...while its parent DOES — which is what makes it NARROWER-THAN-PARENT.
    check('parent ">=0.6.0 <0.8.0" DOES admit 0.7.1',
          admits('">=0.6.0 <0.8.0"', '0.7.1'), True)
    # the fix, verified end-to-end at both ends of the range.
    check('fixed example ">=0.6.0 <0.8.0" admits floor 0.6.0',
          admits('">=0.6.0 <0.8.0"', '0.6.0'), True)
    # navigation_safety example: routing_engine ^0.4.0 vs published 0.6.3.
    check('^0.4.0 does NOT admit routing_engine 0.6.3',
          admits('^0.4.0', '0.6.3'), False)
    return ok



def _sibling_main():

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


# ===========================================================================
# ARCHIVE-PATH LANE — added 2026-09-19.
#
# WHY: the example lane above asks whether a shipped example/pubspec.yaml
# carries inline path overrides. It never asks the same question of the
# package ROOT, and it never asks whether a pubspec_overrides.yaml actually
# stays out of the archive -- so it ran green while, measured 2026-09-19
# against the 36 published archives, SEVEN package roots shipped
# `dependency_overrides` with a `path:` that leaves the archive:
# adaptive_reroute 0.2.1, driving_conditions 0.7.1, driving_weather 0.5.0,
# route_condition_forecast 0.2.1, routing_bloc 0.4.6, snow_rendering 0.3.0,
# vehicle_condition_fusion 0.5.0. `pub get` inside each extracted archive:
# exit 66, "path which doesn't exist".
#
# This lane asks every pubspec.yaml AND pubspec_overrides.yaml the archive
# would carry, and judges the PATH (does it leave the archive?), not the
# section it sits in.
#
# Which files the archive carries is decided the way pub decides it. Rules
# measured with `dart pub publish --dry-run`, Dart 3.11.1, 2026-09-19:
#   * a path with any segment starting with '.' never ships;
#   * a pubspec.lock never ships, at any depth;
#   * the package-ROOT pubspec_overrides.yaml never ships (a nested one,
#     e.g. example/pubspec_overrides.yaml, DOES unless an ignore file names it);
#   * in each directory from the repository root down, pub reads .pubignore if
#     present, else .gitignore -- a .pubignore REPLACES that directory's
#     .gitignore; the repository root's .gitignore still applies.
# The pattern matching itself is git's (`git check-ignore --no-index` in a
# scratch repository that mirrors those ignore files), so gitignore syntax is
# not re-implemented here. This models publishing from inside the git work
# tree, which is how this catalog publishes.
# ===========================================================================


def _path_values(text):
    """Every `path:` value in a pubspec-shaped text, block or flow style."""
    out = []
    for line in text.split('\n'):
        code = line.split('#', 1)[0]
        for m in re.finditer(r'(?:^|[\s{,])path:\s*([^\s,}]+)', code):
            out.append(m.group(1).strip().strip('"').strip("'"))
    return out


def _leaves_archive(rel_file, value):
    target = os.path.normpath(os.path.join(os.path.dirname(rel_file), value))
    return os.path.isabs(value) or target == '..' or target.startswith('..' + os.sep)


def _shipped_subset(repo, pkgdir, rels):
    """The package-relative paths in `rels` that pub would put in the archive.
    Returns None when git is unavailable (UNVERIFIABLE, never a pass)."""
    import shutil, subprocess, tempfile
    todo = []
    for r in rels:
        parts = r.split('/')
        if any(p.startswith('.') for p in parts):
            continue
        if parts[-1] == 'pubspec.lock' or r == 'pubspec_overrides.yaml':
            continue
        todo.append(r)
    if not todo:
        return []
    repo = os.path.realpath(repo)
    pkg_rel = os.path.relpath(os.path.realpath(pkgdir), repo)
    tmp = tempfile.mkdtemp()
    try:
        try:
            subprocess.run(['git', 'init', '-q', tmp], check=True, capture_output=True)
        except (OSError, subprocess.CalledProcessError):
            return None
        queries, dirs = [], {''}
        for r in todo:
            full = os.path.join(pkg_rel, r).replace(os.sep, '/')
            parts = full.split('/')
            for k in range(1, len(parts)):
                dirs.add('/'.join(parts[:k]))
                queries.append('/'.join(parts[:k]) + '/')   # a leading dir can exclude it too
            queries.append(full)
        for d in dirs:
            for name in ('.pubignore', '.gitignore'):       # .pubignore REPLACES .gitignore
                src = os.path.join(repo, d, name)
                if os.path.isfile(src):
                    os.makedirs(os.path.join(tmp, d), exist_ok=True)
                    shutil.copyfile(src, os.path.join(tmp, d, '.gitignore'))
                    break
        p = subprocess.run(['git', '-c', 'core.excludesFile=/dev/null', '-C', tmp,
                            'check-ignore', '--no-index', '--stdin'],
                           input='\n'.join(queries) + '\n', capture_output=True, text=True)
        if p.returncode not in (0, 1):
            return None
        ignored = {l.strip().rstrip('/') for l in p.stdout.splitlines() if l.strip()}
        shipped = []
        for r in todo:
            full = os.path.join(pkg_rel, r).replace(os.sep, '/')
            parts = full.split('/')
            lead = ['/'.join(parts[:k]) for k in range(1, len(parts))]
            if full in ignored or any(x in ignored for x in lead):
                continue
            shipped.append(r)
        return shipped
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def archive_path_lane(root, quiet=False):
    """FAIL on any pubspec the archive would carry whose path leaves the archive."""
    findings, judged, skipped, unverifiable = [], 0, [], []
    for pkgdir in sorted(glob.glob(os.path.join(root, 'packages/*'))):
        pj = os.path.join(pkgdir, 'pubspec.yaml')
        if not os.path.isfile(pj):
            continue
        name = os.path.basename(pkgdir)
        if re.search(r'^publish_to:\s*["\']?none', open(pj, errors='replace').read(), re.M):
            skipped.append(name)
            continue
        cands = []
        for base, dnames, fnames in os.walk(pkgdir):
            dnames[:] = [d for d in dnames if not d.startswith('.')]
            for f in fnames:
                if f in ('pubspec.yaml', 'pubspec_overrides.yaml'):
                    cands.append(os.path.relpath(os.path.join(base, f), pkgdir).replace(os.sep, '/'))
        ships = _shipped_subset(root, pkgdir, sorted(cands))
        if ships is None:
            unverifiable.append(name)
            continue
        for rel in ships:
            judged += 1
            text = open(os.path.join(pkgdir, rel), errors='replace').read()
            for v in _path_values(text):
                if _leaves_archive(rel, v):
                    findings.append((name, rel, v))
    if quiet:
        return 1 if findings else (2 if unverifiable else 0)
    print('\nsibling-constraint check — ARCHIVE PATHS (%d shipped pubspec files judged)' % judged)
    for name in skipped:
        print('  -     %s: publish_to none -- nothing of it is published, not judged' % name)
    for name in unverifiable:
        print('  ?     %s: UNVERIFIABLE -- git unavailable to decide what ships' % name)
    if not findings:
        if unverifiable:
            print('  UNVERIFIABLE — not every package was judged. This is not a clean bill.')
            return 2
        print('  pass  no pubspec file the archive would carry has a path that leaves it')
        return 0
    for name, rel, v in findings:
        print('  FAIL  %s/%s  path: %s' % (name, rel, v))
        print('          ships in the archive and resolves OUTSIDE it. pub does not strip')
        print('          dependency_overrides from a published pubspec; a stranger\'s')
        print('          `pub get` inside the package exits 66 ("path which doesn\'t')
        print('          exist"). Move root overrides to pubspec_overrides.yaml (pub never')
        print('          publishes the root one); name any other in the package .pubignore.')
    print('%d shipped path(s) a stranger cannot resolve.' % len(findings))
    return 1


def archive_path_self_test():
    """Prove-it-fails, on the defects actually found and the rules measured."""
    import shutil, subprocess, tempfile
    ok = True

    def case(label, files, want):
        nonlocal ok
        tmp = tempfile.mkdtemp()
        try:
            subprocess.run(['git', 'init', '-q', tmp], check=True, capture_output=True)
            for rel, body in files.items():
                path = os.path.join(tmp, rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, 'w').write(body)
            got = archive_path_lane(tmp, quiet=True)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        good = got == want
        ok = ok and good
        print('  %s  %s  got=%s want=%s' % ('PASS' if good else 'FAIL', label, got, want))

    root_gi = '.dart_tool/\n**/build/\npackages/*/coverage/\npackages/*/pubspec.lock\n'
    ov_root = 'dependency_overrides:\n  sib:\n    path: ../sib\n'
    ov_ex = 'dependency_overrides:\n  sib:\n    path: ../../sib\n'
    ex = 'name: p_example\npublish_to: none\ndependencies:\n  p:\n    path: ../\n'
    P = 'packages/p/'
    print('\n  -- archive-path lane, on the defects actually found --')
    case('CLASS-B: root pubspec.yaml inline override (driving_conditions 0.7.1 shape)',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n' + ov_root}, 1)
    case('CLASS-B, flow style: sib: {path: ../sib}',
         {'.gitignore': root_gi,
          P + 'pubspec.yaml': 'name: p\ndependency_overrides:\n  sib: {path: ../sib}\n'}, 1)
    case('CLASS-A: example/pubspec.yaml inline override (offline_tiles 0.5.8 shape)',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + 'example/pubspec.yaml': ex + ov_ex}, 1)
    case('example/pubspec_overrides.yaml with NO ignore file SHIPS (measured)',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + 'example/pubspec.yaml': ex, P + 'example/pubspec_overrides.yaml': ov_ex}, 1)
    case('.pubignore REPLACES the package .gitignore: .gitignore names the file, .pubignore does not',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + '.gitignore': 'example/pubspec_overrides.yaml\n', P + '.pubignore': 'build/\n',
          P + 'example/pubspec.yaml': ex, P + 'example/pubspec_overrides.yaml': ov_ex}, 1)
    print('\n  -- and it passes the real fixes --')
    case('THE FIX, root: overrides in the ROOT pubspec_overrides.yaml (pub never ships it)',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + 'pubspec_overrides.yaml': ov_root}, 0)
    case("THE FIX, example (main's mechanism): example/pubspec_overrides.yaml named in .pubignore",
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + '.pubignore': 'pubspec_overrides.yaml\nexample/pubspec_overrides.yaml\n',
          P + 'example/pubspec.yaml': ex, P + 'example/pubspec_overrides.yaml': ov_ex}, 0)
    case('example parent via `path: ../` stays INSIDE the archive',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + 'example/pubspec.yaml': ex}, 0)
    case('publish_to: none package is not judged (nothing of it ships)',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\npublish_to: none\n' + ov_root}, 0)
    case('a pubspec under a directory the root .gitignore excludes (**/build/) does not ship',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + 'build/x/pubspec.yaml': 'name: junk\ndependency_overrides:\n  sib:\n'
                                      '    path: ../../../sib\n'}, 0)
    case('...and the same file outside build/ is judged and FAILS (the case above can fail)',
         {'.gitignore': root_gi, P + 'pubspec.yaml': 'name: p\n',
          P + 'kept/x/pubspec.yaml': 'name: junk\ndependency_overrides:\n  sib:\n'
                                     '    path: ../../../sib\n'}, 1)
    return ok


def main():
    if '--self-test' in sys.argv:
        return 0 if (self_test() and example_self_test()
                     and archive_path_self_test()) else 1
    rc_sib = _sibling_main()
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    mode = 'published' if '--published' in sys.argv else 'local'
    local = local_catalog(root)
    own = set(local)
    cat = local if mode == 'local' else published_catalog(sorted(own))
    rc_ex = example_lane(root, cat, own)
    rc_arch = archive_path_lane(root)
    # A FAIL is louder than an UNVERIFIABLE: 1 wins over 2.
    if 1 in (rc_sib, rc_ex, rc_arch):
        return 1
    if 2 in (rc_sib, rc_ex, rc_arch):
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
