#!/usr/bin/env bash
# discover_packages.sh — THE single source of truth for "what does this monorepo test?"
#
# WHY THIS EXISTS (Loom A):
#   Before this script there were THREE mutually-inconsistent BY-NAME lists:
#     .github/workflows/ci.yml  "test" job         -> 12 packages
#     .github/workflows/ci.yml  "hosted-resolve"   ->  6 packages
#     scripts/test_runner.sh                       -> 15 packages
#   No two agreed, and they disagreed in BOTH directions. 36 packages have a test/
#   suite. 23 of them were NEVER EXECUTED by CI — including navigation_safety_core
#   (309 tests), compound_failure_advisor, every condition_aggregator adapter, and
#   pretrip_decision_advisor. They all passed. Nobody knew, because nobody ran them.
#
#   A by-name list can only ever test what somebody REMEMBERED to write down.
#   A machine must DISCOVER what exists, not be told.
#
# CONTRACT:
#   Emits one line per testable package:  <name><TAB><runner>
#   where <runner> is 'dart' or 'flutter'.
#
#   A package is TESTABLE iff:
#     packages/<name>/pubspec.yaml exists  AND  packages/<name>/test/ exists
#
#   It is a FLUTTER package iff its pubspec declares `sdk: flutter` (dart:ui,
#   WidgetTester &c. require the flutter test runner); otherwise it is pure dart.
#
# NOTE (the guard's whole reason for being):
#   This script's TESTABLE predicate requires pubspec.yaml. A package with a test/
#   dir but a missing/renamed/broken pubspec is INVISIBLE here — it would be silently
#   skipped. That is exactly the blind-spot class scripts/test_all.sh's GUARD detects
#   by scanning packages/*/test/ INDEPENDENTLY of this script and refusing to pass if
#   anything with tests went unexecuted. Discovery is not trusted; it is CHECKED.

# MODES:
#   (default)     testable packages   -> "<name>\t<dart|flutter>"
#   --overrides   override-bearing    -> "<name>"        (the hosted-resolve / G7 set)
#   --json <mode> same, as a JSON array (for a GitHub Actions matrix)
#
# THE THIRD LIST: ci.yml's hosted-resolve job also carried a by-name matrix of SIX
# packages — the ones shipping monorepo-only `dependency_overrides: path:` on siblings,
# whose PUBLISHED constraints therefore go unresolved by every other lane. TEN packages
# actually ship such overrides. Four (pretrip_decision_advisor, route_condition_forecast,
# snow_rendering, vehicle_condition_fusion) were never hosted-resolve-checked. So the
# lane built to catch resolution blind spots HAD a resolution blind spot. `--overrides`
# derives that set from the pubspecs, so it cannot drift again.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AS_JSON=0
MODE=testable
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overrides) MODE=overrides ;;
    --testable)  MODE=testable ;;
    --json)      AS_JSON=1 ;;
    *) printf 'discover_packages.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

emit_testable() {
  for pkg_dir in "$ROOT_DIR"/packages/*/; do
    name="$(basename "$pkg_dir")"
    [[ -f "$pkg_dir/pubspec.yaml" ]] || continue
    [[ -d "$pkg_dir/test" ]] || continue

    if grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter[[:space:]]*$' "$pkg_dir/pubspec.yaml"; then
      printf '%s\tflutter\n' "$name"
    else
      printf '%s\tdart\n' "$name"
    fi
  done | sort
}

emit_overrides() {
  for pkg_dir in "$ROOT_DIR"/packages/*/; do
    name="$(basename "$pkg_dir")"
    [[ -f "$pkg_dir/pubspec.yaml" ]] || continue
    grep -qE '^dependency_overrides:' "$pkg_dir/pubspec.yaml" && printf '%s\n' "$name"
  done | sort
}

if [[ "$MODE" == overrides ]]; then rows="$(emit_overrides)"; else rows="$(emit_testable)"; fi

if [[ "$AS_JSON" -eq 1 ]]; then
  # names only, as a compact JSON array for `fromJSON` in a workflow matrix
  printf '%s\n' "$rows" | cut -f1 | grep -v '^$' \
    | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1 ? "," : ""), $0} END{printf "]\n"}'
else
  printf '%s\n' "$rows"
fi
