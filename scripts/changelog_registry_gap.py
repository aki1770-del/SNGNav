#!/usr/bin/env python3
"""Find published versions that the tree's CHANGELOG has no entry for.

WHY THIS EXISTS
---------------
Measured 2026-08-28 on vehicle_condition_fusion:

    in-tree CHANGELOG : 0.5.0  0.4.0  0.3.1  0.3.0  0.2.0  0.1.0
    pub.dev versions  : 0.3.4  0.3.3  0.3.2  0.3.1  0.3.0  0.2.0  0.1.0

0.3.2/0.3.3/0.3.4 were LIVE -- 0.3.4 is what every consumer resolves today --
and none had an entry in the tree. They were not unwritten: the CHANGELOG.md
inside the published 0.3.4 archive carries all three in full. They were written,
shipped, and then lost from the tree.

Publishing from that tree would have shipped a changelog ERASING the recorded
history of three live versions -- a consumer on 0.3.4 would open the changelog
of the version they were being asked to upgrade to and find no record that their
own version ever existed.

That was found by hand while checking one package for publish-readiness. Nothing
would have found it for the other 36. This does.

THE INVERSE GAP IS ALSO REPORTED, and it is not the same fault.
A version documented in the tree but ABSENT from pub.dev is either unpublished
work (fine, but a reader hunting pub.dev will not find it -- say so in the entry,
as vehicle_condition_fusion 0.4.0 now does) or a version that was retracted.
Reported as NOTE, never as a failure.

EXIT CODES
  0  no published version lacks an entry
  1  at least one published version has NO CHANGELOG entry  <- the defect
  2  usage / network error (NOT a pass: unmeasured is never clean)
"""
import json, re, subprocess, sys, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEAD = re.compile(r'^##\s+v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)', re.M)


def published(pkg):
    """Return the pub.dev version list, or None if the package is not published."""
    url = f'https://pub.dev/api/packages/{pkg}'
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return [v['version'] for v in json.load(r)['versions']]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None          # never published -- not a defect
        raise


def main():
    only = sys.argv[1:] or None
    missing_total, pkgs_hit, unmeasured = 0, [], []
    rows = []

    for d in sorted((ROOT / 'packages').iterdir()):
        pubspec = d / 'pubspec.yaml'
        if not pubspec.is_file():
            continue
        pkg = d.name
        if only and pkg not in only:
            continue
        text = pubspec.read_text()
        if re.search(r'^publish_to:\s*[\'"]?none', text, re.M):
            continue             # internal package, no registry to compare against

        cl = d / 'CHANGELOG.md'
        entries = set(HEAD.findall(cl.read_text())) if cl.is_file() else set()

        try:
            pub = published(pkg)
        except Exception as exc:                      # noqa: BLE001
            unmeasured.append(f'{pkg}: {exc}')
            continue
        if pub is None:
            continue

        gap = [v for v in pub if v not in entries]        # PUBLISHED, undocumented
        extra = sorted(entries - set(pub))                # documented, unpublished
        if gap or extra:
            rows.append((pkg, gap, extra, pub[-1] if pub else '-'))
        if gap:
            missing_total += len(gap)
            pkgs_hit.append(pkg)

    print('=========== CHANGELOG vs registry ===========')
    for pkg, gap, extra, latest in rows:
        print(f'  {pkg}   (latest published {latest})')
        if gap:
            flag = '  <- INCLUDES THE LATEST' if latest in gap else ''
            print(f'     MISSING ENTRY for published: {", ".join(gap)}{flag}')
        if extra:
            print(f'     NOTE documented but not on pub.dev: {", ".join(extra)}')
    if not rows:
        print('  every published version of every package has a CHANGELOG entry')

    if unmeasured:
        print('\n  UNMEASURED (never read as clean):')
        for u in unmeasured:
            print(f'    - {u}')
    print('=============================================')

    if unmeasured:
        return 2
    if missing_total:
        print(f'\n{missing_total} published version(s) across {len(pkgs_hit)} package(s) have no')
        print('CHANGELOG entry. Restore them from the PUBLISHED archive --')
        print('  https://pub.dev/api/archives/<pkg>-<version>.tar.gz')
        print('-- not from memory. They were written once; do not rewrite them.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
