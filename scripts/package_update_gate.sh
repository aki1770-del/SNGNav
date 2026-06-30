#!/usr/bin/env bash
# package_update_gate.sh — the DETERMINISTIC gates of the multi-gate package-update method.
#
# A package update is never "tested" by a single pass (OPS-RULE-068). The full method has
# five gates; this script runs the mechanically-checkable ones so every update candidate —
# these and every FUTURE one — passes the same battery before a republish is even proposed:
#
#   G1  build+resolve     dart pub get          (does it still resolve?)
#   G2  static analysis   dart analyze          (lint clean?)
#   G3  tests             dart test             (suite green?)
#   G4  publish-ready     dart pub publish -n   (0 pub.dev warnings?)
#   G5  coherence         catalog_census.sh     (after publish: live==committed==local?)
#
# The JUDGMENT gate — adversarial verify, advocate!=verifier (OPS-068 §B) — is conducted by
# the `multi-gate-package-update` workflow, NOT this script (free-text judgment is not
# mechanically gateable; claiming it is would be the narration-over-reading failure, OPS-062).
# The REPUBLISH gate is the Chair's voice (§1). This script reads only; it never publishes,
# commits, or pushes.
#
# Usage:
#   ./scripts/package_update_gate.sh <pkg> [<pkg> ...]     # gate the named update candidates
#   ./scripts/package_update_gate.sh --coherence-only      # just the catalog-wide G5
#   PKG_ROOT=/path ./scripts/package_update_gate.sh <pkg>
#
# Exit 0 only if every gate passed for every named package (and coherence is clean).

set -u
PKG_ROOT="${PKG_ROOT:-/home/komada/SNGNav/packages}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail=0
gate() { # gate <label> <cmd...> ; prints PASS/FAIL, sets fail on error
  local label="$1"; shift
  if "$@" >/tmp/_pkg_gate_out 2>&1; then
    printf '    %-14s PASS\n' "$label"
  else
    printf '    %-14s FAIL\n' "$label"; fail=1
    sed 's/^/        /' /tmp/_pkg_gate_out | tail -6
  fi
}

# G4 publish-readiness, staging-aware: a STAGED update has uncommitted package files,
# so pub's "N checked-in files are modified in git" warning is EXPECTED (not a defect).
# PASS = 0 warnings; STAGED = the only warning is the git-modified one; FAIL = any real
# content warning (missing example, bad pubspec, oversized, etc.).
dryrun_gate() { # dryrun_gate <pkgdir>
  local out; out="$(cd "$1" && dart pub publish --dry-run 2>&1)"
  if echo "$out" | grep -qiE "Package has 0 warnings"; then
    printf '    %-14s PASS\n' "G4 dry-run"
  elif echo "$out" | grep -qiE "checked-in files are modified in git"; then
    local nw; nw="$(echo "$out" | grep -oiE "Package has [0-9]+ warning" | grep -oE '[0-9]+')"
    if [[ "${nw:-1}" -le 1 ]]; then
      local nf; nf="$(echo "$out" | grep -oE "[0-9]+ checked-in files are modified" | grep -oE '^[0-9]+')"
      printf '    %-14s STAGED (%s files modified; publish-ready once committed)\n' "G4 dry-run" "${nf:-?}"
    else
      printf '    %-14s FAIL (real warning beyond git-modified)\n' "G4 dry-run"; echo "$out" | grep -iE "warning|missing|error" | sed 's/^/        /' | head -5; fail=1
    fi
  else
    printf '    %-14s FAIL\n' "G4 dry-run"; echo "$out" | grep -iE "warning|missing|error" | sed 's/^/        /' | head -5; fail=1
  fi
}

# G5 coherence, staging-aware: a LOCAL-AHEAD on a package UNDER TEST (its staged version
# bump) is EXPECTED and reported STAGED; any DRIFT, or LOCAL-AHEAD on a package NOT under
# test, is a real FAIL. Pass the tested package names as args; none = strict mode.
coherence() {
  echo ">> G5 coherence (live == committed == local; staged updates expected-ahead)"
  bash "$HERE/catalog_census.sh" coherence >/tmp/_coh 2>&1
  local bad=0 staged=0
  while IFS= read -r line; do
    local pname; pname="$(echo "$line" | awk '{print $1}')"
    if echo "$line" | grep -q "LOCAL-AHEAD" && ! echo "$line" | grep -q "DRIFT"; then
      if [[ " $* " == *" $pname "* ]]; then echo "    $pname  STAGED (expected-ahead — under test)"; staged=1; else echo "    $pname  FAIL (LOCAL-AHEAD, not under test)"; bad=1; fi
    else
      echo "    $pname  FAIL"; bad=1
    fi
  done < <(grep -E "DRIFT|LOCAL-AHEAD" /tmp/_coh)
  if [[ "$bad" -eq 1 ]]; then fail=1
  elif [[ "$staged" -eq 1 ]]; then echo "    coherence     STAGED — only expected-ahead drift on packages under test"
  else echo "    coherence     PASS — every publishable package coherent"; fi
}

if [[ "${1:-}" == "--coherence-only" ]]; then coherence; exit "$fail"; fi
if [[ $# -lt 1 ]]; then echo "usage: $0 <pkg> [<pkg> ...]  |  --coherence-only" >&2; exit 2; fi

for name in "$@"; do
  pkg="$PKG_ROOT/$name"
  if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE ($pkg/pubspec.yaml missing)"; fail=1; continue; fi
  ver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
  echo ">> $name  (v$ver)"
  # gates run in the PARENT shell (cd is inside the command) so fail propagates.
  gate "G1 pub-get"   bash -c "cd '$pkg' && dart pub get"
  gate "G2 analyze"   bash -c "cd '$pkg' && dart analyze"
  if [[ -d "$pkg/test" ]]; then gate "G3 test" bash -c "cd '$pkg' && dart test"; else printf '    %-14s NONE (no test/ dir)\n' "G3 test"; fi
  dryrun_gate "$pkg"
done

echo
coherence "$@"
echo
if [[ "$fail" -eq 0 ]]; then
  echo "ALL GATES PASS — candidates are build/test/publish-ready (STAGED items land on commit+republish)."
  echo "Next: adversarial-verify (multi-gate-package-update workflow) + Chair republish gate (§1)."
else
  echo "GATE FAILURE — do not propose a republish until red gates are green."
fi
exit "$fail"
