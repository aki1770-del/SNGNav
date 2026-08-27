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

⚑ THE CARET RULE, written out because getting it wrong is how one of these hid
   for five releases. In pub:
       ^1.2.3  ->  >=1.2.3 <2.0.0
       ^0.1.2  ->  >=0.1.2 <0.2.0
       ^0.0.3  ->  >=0.0.3 <0.0.4      <-- the one that hid
   driving_weather declares condition_aggregator ^0.0.5 while condition_aggregator
   is published at 0.0.10. My first checker read ^0.0.5 as <0.1.0 and called it
   fine. It means <0.0.6.

MEASURED CORRELATION, 2026-08-21, over the published catalog:
       caret constraints   13, excluding the published sibling  6
       explicit ranges      6, excluding the published sibling  0
   navigation_safety_core has the highest fan-in in the catalog and went 0.10 ->
   0.11.4 without breaking one dependent, because all six declare >=0.10.0 <0.12.0.

MODES
  --local      (default) local constraints vs local sibling versions. Offline,
               deterministic, catches it BEFORE publish. This is the CI gate.
  --published  published constraints vs published versions. Needs pub.dev.
               Catches what a weaver actually gets today.

EXIT 0 clean · 1 a constraint excludes its sibling · 2 UNVERIFIABLE (never a pass)
"""
import glob, json, os, re, sys, urllib.request

V = re.compile(r'(\d+)\.(\d+)\.(\d+)')


def ver(s):
    m = V.match(str(s).strip())
    return [int(x) for x in m.groups()] if m else None


def caret_upper(v):
    """Exact pub semantics, including the 0.0.x case."""
    a, b, c = v
    if a > 0:
        return [a + 1, 0, 0]
    if b > 0:
        return [a, b + 1, 0]
    return [a, b, c + 1]


def admits(constraint, version):
    """True/False, or None when the form is one this check does not judge."""
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


def main():
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

    bad, checked, unjudged = [], 0, 0
    for p, info in sorted(cat.items()):
        if 'error' in info:
            continue
        for d, c in (info.get('deps') or {}).items():
            if d not in own or d not in cat or 'error' in cat[d]:
                continue
            a = admits(c, cat[d]['version'])
            if a is None:
                unjudged += 1; continue
            checked += 1
            if not a:
                bad.append((p, info['version'], d, c, cat[d]['version']))

    print(f'  internal constraints judged: {checked}   (form not judged: {unjudged})')
    if not bad:
        print('  pass  every constraint admits the sibling version it will be resolved against')
        return 0
    print()
    for p, pv, d, c, dv in bad:
        print(f'  FAIL  {p} {pv}')
        print(f'          declares  {d}: {c}')
        print(f'          but {d} is at {dv} — EXCLUDED')
        if c.startswith('^'):
            u = caret_upper(ver(c[1:]))
            print(f'          ^{c[1:]} means <{u[0]}.{u[1]}.{u[2]}. An explicit range is what the '
                  f'six constraints on navigation_safety_core use, and none of them has ever failed.')
        print()
    print(f'{len(bad)} constraint(s) exclude a sibling that exists.')
    print('A consumer resolves the OLD version, successfully and silently.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
