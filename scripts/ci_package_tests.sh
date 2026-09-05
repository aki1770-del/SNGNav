#!/usr/bin/env bash
# Run EVERY publishable package's test suite, choosing the runner by package type.
#
# WHY THIS EXISTS
# ---------------
# CI previously carried TWO hardcoded allow-lists — seven names for `dart test`
# and five for `flutter test` — totalling 12 of 35 publishable packages. The
# other 23 all had test/ directories that never once executed.
#
# The workflow already knew this failure mode, in its own comment:
#
#   "nav2_safety_layer ADDED 2026-08-21. Measured that day: this package's tests
#    had NEVER run in CI -- it was in neither allow-list -- which is why four
#    live defects and one STALE pin sat unreported since publication. A package
#    whose tests never run is not passing; it is unmeasured."
#
# The remedy applied then was to add ONE NAME. The list itself was the defect.
# Measured 2026-08-28 before this change: all 23 unlisted packages pass locally,
# so enabling them is nearly free -- what was missing was not test quality, it
# was anything that fires the tests we already have.
#
# THE RUNNER TRAP THIS ENCODES
# ----------------------------
# `dart test` on a Flutter package does not fail with a clear message -- it
# fails to LOAD, and the output reads like failing tests. On 2026-08-28 that
# produced a confident, wrong report of "13 live failures" in three packages
# that were in fact green (78 / 111 / 51) under `flutter test`. Detecting the
# type mechanically means no one has to remember which is which.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

is_flutter_package() {
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1] + '/pubspec.yaml').read()
d = re.search(r'^dependencies:(.*?)(?=^\S|\Z)', t, re.M | re.S)
sys.exit(0 if d and re.search(r'^\s+flutter:\s*$', d.group(1), re.M) else 1)
PY
}

declare -a PASSED=() FAILED=() SKIPPED=() NOCOV=()

# Coverage tooling is OPTIONAL and its absence is NOT a test failure.
# Conflating the two is how this script first reported "31 failed" on a run
# where all 36 packages printed "All tests passed!" -- `coverage` simply was not
# globally activated on that machine. A tooling gap and a broken package are
# different facts and must not share an exit code.
HAVE_COVERAGE=0
if dart pub global list 2>/dev/null | grep -q '^coverage '; then HAVE_COVERAGE=1; fi
[ $HAVE_COVERAGE -eq 1 ] || echo "note: dart 'coverage' not globally activated -- running tests WITHOUT coverage collection"


for dir in packages/*/; do
  pkg="$(basename "$dir")"
  [ -f "$dir/pubspec.yaml" ] || continue
  # publish_to:none packages are internal; still test them if they have tests.
  if [ ! -d "$dir/test" ]; then SKIPPED+=("$pkg (no test/)"); continue; fi

  echo "::group::packages/$pkg"
  if is_flutter_package "$dir"; then
    echo "--- packages/$pkg [flutter test] ---"
    if [ $HAVE_COVERAGE -eq 1 ]; then ( cd "$dir" && flutter test --coverage )
    else ( cd "$dir" && flutter test ); fi
  else
    echo "--- packages/$pkg [dart test] ---"
    # -x pinned-live: gate on REGRESSIONS. The pinned-live suite asserts fixes
    # for defects that are still live, so it fails by design; it is run and
    # reported separately, never silently skipped. A gate that can never pass is
    # a gate that gets routed around.
    if [ $HAVE_COVERAGE -eq 1 ]; then
      ( cd "$dir" && rm -rf coverage && dart test -x pinned-live --coverage=coverage/raw )
      rc=$?
      if [ $rc -eq 0 ]; then
        ( cd "$dir" && dart pub global run coverage:format_coverage \
            --packages=.dart_tool/package_config.json \
            --report-on=lib --in=coverage/raw --out=coverage/lcov.info --lcov ) \
          || NOCOV+=("$pkg")
      fi
      ( exit $rc )
    else
      ( cd "$dir" && dart test -x pinned-live )
    fi
  fi
  rc=$?
  echo "::endgroup::"
  if [ $rc -eq 0 ]; then PASSED+=("$pkg"); else FAILED+=("$pkg"); fi
done

echo
echo "================ package test summary ================"
echo "  passed : ${#PASSED[@]}"
echo "  failed : ${#FAILED[@]}"
echo "  skipped: ${#SKIPPED[@]}   (no test/ directory)"
if [ ${#NOCOV[@]} -gt 0 ]; then
  echo "  coverage-format failed (TESTS STILL PASSED) in ${#NOCOV[@]}:"
  for c in "${NOCOV[@]}"; do echo "    - $c"; done
fi
for s in "${SKIPPED[@]:-}"; do [ -n "$s" ] && echo "    - $s"; done
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "  FAILING:"
  for f in "${FAILED[@]}"; do echo "    - $f"; done
  exit 1
fi
echo "  all package suites green"
