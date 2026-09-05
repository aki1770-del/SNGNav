#!/usr/bin/env python3
"""Answer, before a retraction, the only question that matters: WHO BREAKS?

WHY THIS EXISTS
---------------
On 2026-08-27/28 the unit held two 7-day retraction windows open at once and the
two correct answers were OPPOSITE, for one reason that nobody had measured:

  pretrip_decision_advisor 0.6.0 -> retracting is SAFE. Every admitting range
      falls to 0.5.3, which still carries the earned-affirmative gate. Verified
      four ways before the act: 0.5.3 resolves; its gate actually FIRES
      (throws PretripAssessmentIncompleteException on an unmeasured window);
      all three published adapters co-resolve with it; and the adapter's OWN
      unpacked source analyses clean against it.

  driving_conditions 0.6.0 -> retracting is a BUILD BREAK. 0.6.0 was the only
      0.6.x, so a consumer pinning ^0.6.0 would be left with NO VERSION
      SATISFYING ITS CONSTRAINT. `pub get` fails outright. That is not a
      fallback, and calling it a recall would have been false.

⚑ THE SECOND CASE IS THE REASON THIS SCRIPT EXISTS. "Consumers fall back to the
previous version" is an ASSUMPTION, and it is false whenever the retracted
version is the only one in its caret range. Nothing in the toolchain warns you.

FOUR LIMBS, and a retraction is not safe until all four hold. Three of them were
nearly skipped on the night this was written:

  1. RESOLVES        does a version still satisfy each dependent's constraint?
  2. NOT-EMPTY       is the surviving set non-empty for CARET pins specifically?
  3. CO-RESOLVES     do the published dependents resolve alongside the fallback?
  4. COMPILES        does each dependent's OWN SHIPPED SOURCE analyse against it?

⚑ LIMB 4 IS THE ONE THAT LOOKS DONE AND IS NOT. Analysing a consumer file that
merely imports a dependent passes even when the dependent's internals are
broken, because `dart analyze` does not re-analyse a dependency's sources. This
unpacks the dependent and analyses ITS lib/ directly. On 2026-08-28 the weaker
check was run first and would have been banked as proof.

WHAT THIS DOES NOT DO. It cannot see APPLICATIONS. pub.dev's dependent list is
blind to apps, so a green result means "no PUBLISHED PACKAGE breaks", never "no
person breaks". It says so in its own output; do not let it say otherwise.

EXIT CODES
  0  every limb holds for every published dependent
  1  at least one dependent BREAKS (no satisfying version, or fails to compile)
  2  network/usage error, or a limb could not be run -- UNMEASURED IS NEVER SAFE
"""
import json, re, shutil, subprocess, sys, tempfile, urllib.error, urllib.request
from pathlib import Path

API = 'https://pub.dev/api'


def api(path):
    with urllib.request.urlopen(f'{API}/{path}', timeout=40) as r:
        return json.load(r)


def versions_of(pkg):
    d = api(f'packages/{pkg}')
    return [(v['version'], bool(v.get('retracted'))) for v in d['versions']]


def dependents(pkg):
    """Published packages that depend on pkg. BLIND TO APPLICATIONS -- see header."""
    try:
        with urllib.request.urlopen(
                f'{API}/search?q=dependency:{pkg}', timeout=40) as r:
            return [p['package'] for p in json.load(r).get('packages', [])]
    except Exception:
        return None            # None means UNMEASURED, not "no dependents"


def constraint_on(dep, target):
    d = api(f'packages/{dep}')
    ps = d['latest']['pubspec']
    for sect in ('dependencies', 'dev_dependencies'):
        c = (ps.get(sect) or {}).get(target)
        if isinstance(c, str):
            return d['latest']['version'], c
        if isinstance(c, dict):
            return d['latest']['version'], c.get('version', 'any')
    return d['latest']['version'], None


def caret_lower(c):
    """Lower bound of a caret constraint, else None."""
    m = re.match(r'^\^(\d+)\.(\d+)\.(\d+)', (c or '').strip())
    return tuple(int(x) for x in m.groups()) if m else None


def run(cmd, cwd, timeout=420):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
        return p.returncode, (p.stdout + p.stderr)
    except subprocess.TimeoutExpired:
        return 124, 'TIMEOUT'


def compiles_against(dep, dep_version, target, exclude_version, workdir):
    """LIMB 4: unpack the dependent and analyse ITS OWN lib/ with the target pinned
    below exclude_version. Returns (ok|None, detail); None means UNMEASURED."""
    rc, out = run(['dart', 'pub', 'unpack', f'{dep}:{dep_version}'], workdir)
    if rc != 0:
        return None, f'unpack failed: {out.strip()[-160:]}'
    d = next((p for p in Path(workdir).iterdir()
              if p.is_dir() and p.name.startswith(dep)), None)
    if d is None:
        return None, 'unpack produced no directory'
    ps = d / 'pubspec.yaml'
    maj, minor, patch = exclude_version
    txt = ps.read_text()
    if not re.search(rf'^\s+{re.escape(target)}\s*:', txt, re.M):
        return None, 'target not a direct dependency of this dependent'
    txt = re.sub(rf'^(\s+{re.escape(target)}\s*:).*$',
                 rf"\1 '>=0.0.0 <{maj}.{minor}.{patch}'", txt, flags=re.M)
    ps.write_text(txt)
    rc, out = run(['dart', 'pub', 'get'], str(d))
    if rc != 0:
        return False, f'pub get FAILED: {out.strip()[-200:]}'
    rc, out = run(['dart', 'analyze', 'lib'], str(d))
    if rc != 0:
        return False, f'analyze FAILED: {out.strip()[-300:]}'
    return True, 'analyze clean'


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        print('usage: retraction_preflight.py <package> <version-to-retract>')
        return 2
    target, ver = sys.argv[1], sys.argv[2]
    tv = tuple(int(x) for x in ver.split('.')[:3])

    try:
        vs = versions_of(target)
    except Exception as e:                                     # noqa: BLE001
        print(f'  UNMEASURED: could not read {target}: {e}')
        return 2
    live = [v for v, r in vs if not r]
    if ver not in live:
        print(f'  {target} {ver} is not a live published version. Nothing to do.')
        return 2

    survivors = [v for v in live if v != ver]
    print(f'=== retraction pre-flight: {target} {ver} ===')
    print(f'  published live versions: {live}')
    print(f'  would survive retraction: {survivors or "NONE"}')

    # ── LIMB 2b: THE CARET-ON-ITSELF CHECK ──────────────────────────────────
    # Added 2026-08-28 because this script's OWN discriminating control failed.
    # It was built from the driving_conditions 0.6.0 case, where review found that
    # retracting would leave `^0.6.0` holders with no satisfying version -- and
    # the first version of this script returned exit 0 (SAFE) on exactly that
    # case. Why: the only PUBLISHED dependent pinned ^0.5.2 and survived, and
    # nobody published pins ^0.6.0. The endangered cohort -- our own app, and
    # every unpublished consumer -- is invisible to pub.dev's dependent list.
    #
    # ⚑ So a dependent-driven check STRUCTURALLY CANNOT see this. The emptiness
    # of `^<retracted>` is a property of the VERSION LIST ALONE and needs no
    # dependent at all. It is checked here, unconditionally, and it is the
    # limb most likely to be the true answer.
    if tv[0] == 0:
        upper = (tv[0], tv[1] + 1, 0)
    else:
        upper = (tv[0] + 1, 0, 0)

    def _t(v):
        return tuple(int(x) for x in v.split('.')[:3])

    caret_survivors = [v for v in survivors if tv <= _t(v) < upper]
    caret_str = f'^{ver}'
    print(f'\n  --- CARET-ON-ITSELF: anyone pinning {caret_str}')
    if not caret_survivors:
        print(f'      ⚑ BREAKS: retracting leaves NO version satisfying {caret_str}.')
        print('        `pub get` FAILS OUTRIGHT for every such consumer. That is a')
        print('        BUILD BREAK, not a fallback -- and it is INVISIBLE to the')
        print('        published-dependent list below if no published package pins it.')
        caret_break = True
    else:
        print(f'      survives on: {caret_survivors}')
        caret_break = False

    deps = dependents(target)
    if deps is None:
        print('  UNMEASURED: dependent search failed. An empty result is never absence.')
        return 2
    print(f'  published dependents: {deps or "none found"}')
    print('  ⚑ pub.dev dependents is BLIND TO APPLICATIONS. A green result below')
    print('    means no published PACKAGE breaks -- never that no PERSON breaks.')

    broken, unmeasured = [], []
    work = tempfile.mkdtemp(prefix='retract-preflight-')
    try:
        for dep in deps:
            try:
                dver, c = constraint_on(dep, target)
            except Exception as e:                             # noqa: BLE001
                unmeasured.append(f'{dep}: constraint unreadable ({e})')
                continue
            if c is None:
                continue
            print(f'\n  --- {dep} {dver}  constrains {target}: {c}')

            lo = caret_lower(c)
            if lo is not None:
                # LIMB 2: caret pins the leading non-zero. Does anything survive?
                if lo[0] == 0:
                    ok = [v for v in survivors
                          if tuple(int(x) for x in v.split('.')[:3])[:2] == lo[:2]
                          and tuple(int(x) for x in v.split('.')[:3]) >= lo]
                else:
                    ok = [v for v in survivors
                          if tuple(int(x) for x in v.split('.')[:3])[0] == lo[0]
                          and tuple(int(x) for x in v.split('.')[:3]) >= lo]
                if not ok:
                    print(f'      ⚑ BREAKS: caret {c} would have NO SATISFYING VERSION.')
                    print('        This is a BUILD BREAK, not a fallback. `pub get` fails.')
                    broken.append(f'{dep} (caret {c} -> empty)')
                    continue
                print(f'      survives on: {ok}')

            ok, detail = compiles_against(dep, dver, target, tv, work)
            if ok is None:
                print(f'      UNMEASURED (limb 4): {detail}')
                unmeasured.append(f'{dep}: {detail}')
            elif ok:
                print(f'      compiles against the fallback: {detail}')
            else:
                print(f'      ⚑ BREAKS (limb 4): {detail}')
                broken.append(f'{dep}: {detail}')
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print('\n=============== verdict ===============')
    if caret_break:
        print(f'  BREAKS: anyone pinning ^{ver} has NO satisfying version after retraction.')
        print('  This is independent of the dependent list and is usually decisive.')
        print('  DO NOT RETRACT on this evidence.')
        return 1
    if broken:
        for b in broken:
            print(f'  BREAKS: {b}')
        print('  DO NOT RETRACT on this evidence.')
        return 1
    if unmeasured:
        for u in unmeasured:
            print(f'  UNMEASURED: {u}')
        print('  A limb could not be run. Unmeasured is never safe.')
        return 2
    print('  every published dependent resolves and compiles against the fallback.')
    print('  ⚑ applications remain unmeasured and always will be.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
