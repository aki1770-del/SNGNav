#!/usr/bin/env bash
# Reconstruct pristine condition_aggregator 0.0.9 and prove the frozen-feed
# defect is REAL in it — by requiring the reproduction tests to FAIL there.
#
# Exit 0  = the defect reproduced (4 assertion failures). This is the success
#           case for a RED proof.
# Exit 1  = the tests PASSED against 0.0.9, i.e. the defect is not present in
#           whatever was reconstructed. Then the claim in CHANGELOG 0.0.10 and
#           in SOTIF_INSUFFICIENCIES.md SOTIF-CA-001 is WRONG and must be
#           withdrawn.
# Exit 2  = could not reconstruct 0.0.9 at all -> UNVERIFIED, never "cleared".
#
# Why this script exists: the guard test (`test/frozen_feed_test.dart`) cannot
# compile against 0.0.9, because five of its eight tests reference symbols
# 0.0.10 introduced. Saying "it failed 4/4 on 0.0.9" was therefore not
# re-derivable from the repository. DIA caught that in audit 2026-08-16. This
# script makes the claim reproducible by anyone, forever.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d -t ca009-red-proof-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "== reconstructing pristine condition_aggregator 0.0.9 =="

SRC=""
# Preference 1: the published tarball in the pub cache. This is literally what
# an edge developer downloads, which is the substrate the claim is about.
for c in "${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/condition_aggregator-0.0.9"; do
  [ -d "$c" ] && SRC="$c" && echo "   source: pub cache  $c" && break
done

# Preference 2: git history of this package.
if [ -z "$SRC" ]; then
  REPO="$(cd "$HERE/../../../.." && pwd)"
  REF="$(git -C "$REPO" log --format=%H -S'return n > 0; // zero sources asked' \
        -1 -- packages/condition_aggregator/lib/src/advisory_aggregator.dart 2>/dev/null || true)"
  if [ -n "$REF" ]; then
    SRC="$WORK/from-git"
    mkdir -p "$SRC"
    git -C "$REPO" archive "$REF" packages/condition_aggregator \
      | tar -x -C "$SRC" --strip-components=2 2>/dev/null \
      && echo "   source: git $REF"
  fi
fi

if [ -z "$SRC" ] || [ ! -f "$SRC/pubspec.yaml" ]; then
  echo "UNVERIFIED: could not reconstruct 0.0.9 from pub cache or git." >&2
  echo "Do NOT read this as 'no defect'. It is a dead check." >&2
  exit 2
fi

PKG="$WORK/pkg"
mkdir -p "$PKG"
cp -r "$SRC"/. "$PKG"/
rm -rf "$PKG/.dart_tool" "$PKG/test" "$PKG/example"
mkdir -p "$PKG/test"
cp "$HERE/defect_proof_0_0_9_test.dart" "$PKG/test/"

# The published tarball ships no dev_dependencies; the reproduction needs test.
python3 - "$PKG/pubspec.yaml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
if 'dev_dependencies:' not in s:
    s += "\ndev_dependencies:\n  test: ^1.25.0\n"
elif not re.search(r'^\s+test:', s, re.M):
    s = s.replace('dev_dependencies:', 'dev_dependencies:\n  test: ^1.25.0', 1)
open(p, 'w').write(s)
PY

VER="$(grep -m1 '^version:' "$PKG/pubspec.yaml")"
echo "   reconstructed: $VER"
grep -q 'staleSources' "$PKG/lib/src/advisory_aggregator.dart" && {
  echo "ABORT: reconstructed tree already contains the 0.0.10 fix." >&2
  echo "That is not 0.0.9 and proves nothing. UNVERIFIED." >&2
  exit 2
}
echo "   confirmed: no 'staleSources' in the reconstructed predicate"

echo
echo "== running the reproduction (expecting FAILURES) =="
( cd "$PKG" && dart pub get >/dev/null 2>&1 && dart test test/defect_proof_0_0_9_test.dart 2>&1 ) | tee "$WORK/out.txt"
echo

FAILED="$(grep -cE '^[0-9:]+ \+[0-9]+ -[0-9]+: RED [1-4]/4' "$WORK/out.txt" || true)"
if grep -q 'All tests passed' "$WORK/out.txt"; then
  echo "RESULT: tests PASSED against 0.0.9 — the defect did NOT reproduce."
  echo "The SOTIF-CA-001 claim is unsupported and must be withdrawn."
  exit 1
fi
if [ "${FAILED:-0}" -ge 4 ]; then
  echo "RESULT: RED CONFIRMED — 4/4 honesty surfaces fail on pristine 0.0.9."
  echo "canAssertNoAdvisory / fold / requireCompleteLookup / toLookup."
  exit 0
fi

echo "RESULT: inconclusive — expected 4 named failures, saw ${FAILED:-0}."
echo "UNVERIFIED, not cleared. Read the transcript above."
exit 2
