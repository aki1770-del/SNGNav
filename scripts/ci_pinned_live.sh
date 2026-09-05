#!/usr/bin/env bash
# Run every `pinned-live` defect-proof suite in the catalog, and GATE on it.
#
# WHY THIS EXISTS
# ---------------
# These are the highest-value tests we own. Each one is the record that a defect
# existed and the guard that it cannot return -- the sites where a package turned
# "I could not read this" into "nothing is wrong", which is the one error a
# safety channel must not make.
#
# Until 2026-08-28 they were run by an inline CI step that ended in `|| true`.
# Three things were wrong with it, all measured that day:
#
#   1. Its comment read "These tests assert the FIX for defects that are still
#      live. They FAIL by design." That stopped being true at nav2_safety_layer
#      0.2.0, when all four were REPAIRED. The package's own dart_test.yaml had
#      already recorded the repair; the workflow never propagated it.
#
#   2. `|| true` meant a REGRESSION in those four guards could not turn CI red.
#      dart_test.yaml said the separate job existed "so a future failure is
#      unmissable"; `|| true` made a future failure exactly missable. A warning
#      that does not interrupt is not a halt.
#
#   3. `for pkg in nav2_safety_layer` was a HARDCODED ALLOW-LIST -- the same
#      defect scripts/ci_package_tests.sh exists to kill, in the same workflow,
#      thirty lines away. Its header says it plainly: "The list itself was the
#      defect." A pinned-live suite added to any other package would never have
#      run. It was correct on the day it was written, and it was correct only
#      because one package happened to be the only one.
#
# WHAT REPLACES IT
# ----------------
# Enumerate, do not remember. Any package whose tests carry
# `@Tags(['pinned-live'])` is found and run. Exit codes measured 2026-08-28:
#
#     0  -> tagged tests ran and passed
#    79  -> NO tests matched the tag (benign for an untagged package; a DRIFT
#           signal for one whose dart_test.yaml declares the tag -- the guard
#           was deleted or the tag was renamed, and that must not read as a pass)
#   any  -> tagged tests FAILED, or a file failed to LOAD. A load error surfaces
#           here as a non-zero exit; that hole was found on 2026-08-21 when a
#           file that could not COMPILE let a gate report "All tests passed".
#
# THE ONE EXCEPTION, MADE EXPLICIT INSTEAD OF BLANKET
# ---------------------------------------------------
# A pinned-live suite may legitimately be RED: it asserts a fix for a defect that
# is still live. That was the original and honest reason for `|| true`. Blanket
# tolerance is the wrong shape for it, because it also tolerates regressions.
# Instead: a package may be listed in KNOWN_RED below, WITH a reason and a date.
# The list is empty today. Adding to it is a visible, reviewable act; leaving it
# empty is the default. A gate that can never pass gets routed around --
# and a gate that always passes was never a gate.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# pkg=reason  -- a suite expected RED because the defect it proves is still live.
# EMPTY IS THE CORRECT STATE. Every entry needs a reason and the date it was added.
declare -A KNOWN_RED=()

declare -a GREEN=() RED=() DRIFT=() EXPECTED_RED=()

for dir in packages/*/; do
  pkg="$(basename "$dir")"
  [ -d "$dir/test" ] || continue

  declares_tag=0
  [ -f "$dir/dart_test.yaml" ] && grep -q 'pinned-live' "$dir/dart_test.yaml" && declares_tag=1
  has_tagged=0
  grep -rqls "pinned-live" "$dir/test" 2>/dev/null && has_tagged=1

  # Nothing to do for a package that neither declares nor uses the tag.
  [ $declares_tag -eq 0 ] && [ $has_tagged -eq 0 ] && continue

  echo "::group::pinned-live: packages/$pkg"
  echo "=== packages/$pkg -- pinned-live defect-proof suite (GATING) ==="
  ( cd "$dir" && dart test -t pinned-live )
  rc=$?
  echo "::endgroup::"

  if [ $rc -eq 0 ]; then
    GREEN+=("$pkg")
  elif [ $rc -eq 79 ]; then
    if [ $declares_tag -eq 1 ]; then
      # Declared the tag, ran nothing. The guard is GONE, and an absent verdict
      # reads exactly like a pass. This is a failure, not a skip.
      DRIFT+=("$pkg (dart_test.yaml declares 'pinned-live' but NO test carries it)")
    fi
  elif [ -n "${KNOWN_RED[$pkg]:-}" ]; then
    EXPECTED_RED+=("$pkg -- ${KNOWN_RED[$pkg]}")
  else
    RED+=("$pkg (exit $rc)")
  fi
done

echo
echo "============== pinned-live defect-proof summary =============="
echo "  green        : ${#GREEN[@]}"
for p in "${GREEN[@]:-}"; do [ -n "$p" ] && echo "    - $p"; done
if [ ${#EXPECTED_RED[@]} -gt 0 ]; then
  echo "  expected-red : ${#EXPECTED_RED[@]}   (declared in KNOWN_RED, NOT gating)"
  for p in "${EXPECTED_RED[@]}"; do echo "    - $p"; done
fi
if [ ${#DRIFT[@]} -gt 0 ]; then
  echo "  DRIFT        : ${#DRIFT[@]}"
  for p in "${DRIFT[@]}"; do echo "    - $p"; done
fi
if [ ${#RED[@]} -gt 0 ]; then
  echo "  FAILING      : ${#RED[@]}"
  for p in "${RED[@]}"; do echo "    - $p"; done
fi
echo "=============================================================="

if [ ${#RED[@]} -gt 0 ] || [ ${#DRIFT[@]} -gt 0 ]; then
  echo
  echo "A pinned-live guard is red or missing. Each one is the record that a defect"
  echo "existed and the guard that it cannot return. Fix the defect -- do not"
  echo "silence the guard. If it is red because the defect it proves is genuinely"
  echo "still live, add it to KNOWN_RED in this script WITH a reason and a date."
  exit 1
fi

if [ ${#GREEN[@]} -eq 0 ]; then
  echo "note: no pinned-live suites found in any package."
fi
echo "  all pinned-live guards hold"
