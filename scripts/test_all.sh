#!/usr/bin/env bash
# test_all.sh — THE discovery runner. CI and developers run the SAME thing.
#
# LOOM A: "CI discovers, never enumerates."
#
#   run   — execute EVERY discovered suite (scripts/discover_packages.sh) + the root app
#   guard — then PROVE nothing was skipped, by re-scanning packages/*/test/ INDEPENDENTLY
#           of discovery and HALTING if any package with tests was not executed.
#
# The guard is the actual loom. Running tests is not the loom; a machine that DETECTS
# ITS OWN BLIND SPOT is. A runner that only runs what it was told about cannot know
# what it was not told about — so the guard does not ask the runner. It asks the disk.
#
# Usage:
#   ./scripts/test_all.sh                 # analyze + test everything, then GUARD (full)
#   ./scripts/test_all.sh --test-only     # tests only
#   ./scripts/test_all.sh --analyze-only  # dart analyze lib test on every package
#   ./scripts/test_all.sh --dart-only     # PARTIAL: pure-dart packages only  (GUARD DISABLED)
#   ./scripts/test_all.sh --flutter-only  # PARTIAL: flutter packages + root  (GUARD DISABLED)
#   ./scripts/test_all.sh --list          # print the discovered set and exit
#   ./scripts/test_all.sh --concurrency=1 # serialize flutter kernel compilation (OOM relief)
#
# A PARTIAL run NEVER certifies coverage and says so loudly. Only a FULL run passes the guard.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DO_ANALYZE=1
DO_TEST=1
MODE_DART=1
MODE_FLUTTER=1
FULL_RUN=1          # cleared by any package-set filter -> guard refuses to certify
DO_COVERAGE=0
CONCURRENCY=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --analyze-only)  DO_TEST=0 ;;
    --test-only)     DO_ANALYZE=0 ;;
    --dart-only)     MODE_FLUTTER=0; FULL_RUN=0 ;;
    --flutter-only)  MODE_DART=0;    FULL_RUN=0 ;;
    --coverage)      DO_COVERAGE=1 ;;
    --concurrency=*) CONCURRENCY=("$1") ;;
    --list)          exec "$ROOT_DIR/scripts/discover_packages.sh" ;;
    --help)          sed -n '1,22p' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# ── /tmp kernel cleanup (flutter test compiles 1-5 GB kernels; SIGKILL skips traps) ──
cleanup_kernels() {
  local count
  count=$(find /tmp -maxdepth 1 \( -name 'dart_test.kernel.*' -o -name 'dart_test.vm.*' \) 2>/dev/null | wc -l)
  if [[ "$count" -gt 0 ]]; then
    rm -rf /tmp/dart_test.kernel.* /tmp/dart_test.vm.* 2>/dev/null || true
    printf '[cleanup] %d kernel dir(s) removed\n' "$count"
  fi
}
trap 'cleanup_kernels' EXIT INT TERM

# ── Ledger: the record of what was ACTUALLY executed (the guard reads this, not the code) ──
LEDGER="$(mktemp)"
trap 'rm -f "$LEDGER"' EXIT
: > "$LEDGER"

FAILURES=()
TOTAL_TESTS=0
TOTAL_FAILED=0
START_TS=$(date +%s)

# Parse "+N -M" from a dart/flutter test compact-reporter tail. Emits "<passed> <failed>".
parse_counts() {
  local log="$1" line
  line="$(grep -aoE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?' "$log" | tail -1)"
  local p f
  p="$(sed -nE 's/.*\+([0-9]+).*/\1/p' <<<"$line")"
  f="$(sed -nE 's/.*-([0-9]+).*/\1/p' <<<"$line")"
  printf '%s %s' "${p:-0}" "${f:-0}"
}

run_pkg() {
  local pkg="$1" runner="$2"
  local log; log="$(mktemp)"
  local rc=0 t0 t1
  t0=$(date +%s)
  printf '\n==> [%s] packages/%s\n' "$runner" "$pkg"
  if [[ "$runner" == "flutter" ]]; then
    local cov=()
    [[ "$DO_COVERAGE" -eq 1 ]] && cov=(--coverage)
    (cd "packages/$pkg" && flutter test --reporter compact "${CONCURRENCY[@]}" "${cov[@]+"${cov[@]}"}") 2>&1 | tee "$log" || rc=${PIPESTATUS[0]}
    cleanup_kernels
  elif [[ "$DO_COVERAGE" -eq 1 ]]; then
    # Coverage now follows DISCOVERY too. It used to be collected for a by-name subset
    # of 7 dart + 5 flutter packages; the reported "line coverage" was therefore a
    # coverage figure for a THIRD of the monorepo, presented as the monorepo's.
    # scripts/coverage_report.sh already globs packages/*/coverage/lcov.info, so simply
    # emitting lcov for every discovered package widens the report with no list.
    (
      cd "packages/$pkg"
      rm -rf coverage
      dart test --reporter compact --coverage=coverage/raw &&
      dart pub global run coverage:format_coverage \
        --packages=.dart_tool/package_config.json \
        --report-on=lib --in=coverage/raw --out=coverage/lcov.info --lcov
    ) 2>&1 | tee "$log" || rc=${PIPESTATUS[0]}
  else
    (cd "packages/$pkg" && dart test --reporter compact) 2>&1 | tee "$log" || rc=${PIPESTATUS[0]}
  fi
  t1=$(date +%s)
  read -r passed failed <<<"$(parse_counts "$log")"
  rm -f "$log"
  TOTAL_TESTS=$(( TOTAL_TESTS + passed + failed ))
  TOTAL_FAILED=$(( TOTAL_FAILED + failed ))
  local status=PASS
  if [[ $rc -ne 0 ]]; then status=FAIL; FAILURES+=("packages/$pkg"); fi
  # THE LEDGER LINE. Written whether the package passed or failed — a FAILING package
  # was still EXECUTED. The guard asks "was it run?", never "did it pass?". Conflating
  # those is how a skipped package hides inside a green run.
  printf '%s\t%s\t%s\t%s\t%s\t%ss\n' "$pkg" "$runner" "$status" "$passed" "$failed" "$((t1-t0))" >> "$LEDGER"
  printf '%s: %s (+%s -%s, %ss)\n' "$status" "$pkg" "$passed" "$failed" "$((t1-t0))"
}

analyze_pkg() {
  local pkg="$1"
  local targets=()
  [[ -d "packages/$pkg/lib"  ]] && targets+=(lib)
  [[ -d "packages/$pkg/test" ]] && targets+=(test)
  [[ ${#targets[@]} -eq 0 ]] && return 0
  local rc=0
  (cd "packages/$pkg" && dart analyze "${targets[@]}") || rc=$?
  if [[ $rc -ne 0 ]]; then
    FAILURES+=("analyze:packages/$pkg")
    printf 'ANALYZE-FAIL: %s\n' "$pkg"
  fi
}

# ── Discover ──────────────────────────────────────────────────────────────────
mapfile -t DISCOVERED < <("$ROOT_DIR/scripts/discover_packages.sh")
printf '==> DISCOVERED %d testable package(s) from the filesystem (no by-name list)\n' "${#DISCOVERED[@]}"

# ── Analyze EVERY package (lib + test) ────────────────────────────────────────
if [[ "$DO_ANALYZE" -eq 1 ]]; then
  printf '\n── Analyze (dart analyze lib test — every discovered package + root app) ──\n'
  dart analyze lib test || FAILURES+=("analyze:root")
  for row in "${DISCOVERED[@]}"; do
    pkg="${row%%$'\t'*}"; runner="${row##*$'\t'}"
    [[ "$runner" == "dart"    && "$MODE_DART"    -eq 0 ]] && continue
    [[ "$runner" == "flutter" && "$MODE_FLUTTER" -eq 0 ]] && continue
    analyze_pkg "$pkg"
  done
fi

# ── Test EVERY discovered package ─────────────────────────────────────────────
if [[ "$DO_TEST" -eq 1 ]]; then
  printf '\n── Test (every discovered package) ──\n'
  for row in "${DISCOVERED[@]}"; do
    pkg="${row%%$'\t'*}"; runner="${row##*$'\t'}"
    [[ "$runner" == "dart"    && "$MODE_DART"    -eq 0 ]] && continue
    [[ "$runner" == "flutter" && "$MODE_FLUTTER" -eq 0 ]] && continue
    run_pkg "$pkg" "$runner"
  done

  if [[ "$MODE_FLUTTER" -eq 1 ]]; then
    printf '\n── Root app ──\n'
    rc=0
    rootlog="$(mktemp)"
    rootcov=()
    [[ "$DO_COVERAGE" -eq 1 ]] && rootcov=(--coverage)
    flutter test --reporter compact --exclude-tags=probe "${CONCURRENCY[@]}" "${rootcov[@]+"${rootcov[@]}"}" 2>&1 | tee "$rootlog" || rc=${PIPESTATUS[0]}
    cleanup_kernels
    read -r rp rf <<<"$(parse_counts "$rootlog")"; rm -f "$rootlog"
    TOTAL_TESTS=$(( TOTAL_TESTS + rp + rf )); TOTAL_FAILED=$(( TOTAL_FAILED + rf ))
    if [[ $rc -ne 0 ]]; then FAILURES+=("root app"); printf 'FAIL: root app\n'; else printf 'PASS: root app (+%s)\n' "$rp"; fi
  fi
fi

# ── THE GUARD ─────────────────────────────────────────────────────────────────
# Independent of discovery. Independent of the runner. It asks the DISK:
#   "which directories under packages/ contain a test/ dir?"
# and then demands that every one of them appear in the ledger of what was executed.
# If discovery's predicate (pubspec.yaml present, sdk classification) silently drops a
# package — a broken/renamed pubspec, a new package nobody wired up, a typo — this is
# the step that HALTS. The machine detects its own blind spot.
printf '\n=== GUARD: prove nothing was skipped ===\n'

if [[ "$DO_TEST" -eq 0 ]]; then
  printf 'GUARD SKIPPED — --analyze-only run. This run does NOT certify test coverage.\n'
elif [[ "$FULL_RUN" -eq 0 ]]; then
  printf 'GUARD DISABLED — PARTIAL run (--dart-only/--flutter-only).\n'
  printf 'This run does NOT certify that every suite was executed. Do not report it as coverage.\n'
else
  SKIPPED=()
  for test_dir in packages/*/test; do
    [[ -d "$test_dir" ]] || continue
    pkg="$(basename "$(dirname "$test_dir")")"
    if ! cut -f1 "$LEDGER" | grep -qxF "$pkg"; then
      SKIPPED+=("$pkg")
    fi
  done
  ON_DISK=$(find packages -maxdepth 2 -type d -name test | wc -l)
  EXECUTED=$(wc -l < "$LEDGER")
  printf 'packages with a test/ dir on disk : %s\n' "$ON_DISK"
  printf 'packages actually executed        : %s\n' "$EXECUTED"
  if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    printf '\n'
    for pkg in "${SKIPPED[@]}"; do
      printf '::error::GUARD HALT: package %s has tests and was NOT executed\n' "$pkg"
    done
    printf '\nGUARD HALT: %d package(s) with a test/ dir were never run.\n' "${#SKIPPED[@]}"
    printf 'The runner has a blind spot. A green result here would be a LIE.\n'
    printf 'Cause is usually: missing/renamed packages/<pkg>/pubspec.yaml (discovery skips it),\n'
    printf 'or a package added without being made discoverable. Fix the package, not the guard.\n'
    exit 1
  fi
  printf 'GUARD PASS: every package with a test/ dir was executed.\n'
fi

# ── Summary ───────────────────────────────────────────────────────────────────
END_TS=$(date +%s)
printf '\n=== Summary ===\n'
if [[ "$DO_TEST" -eq 1 ]]; then
  printf 'Suites executed : %s\n' "$(wc -l < "$LEDGER")"
  printf 'Tests run       : %s (failed: %s)\n' "$TOTAL_TESTS" "$TOTAL_FAILED"
fi
printf 'Wall clock      : %ss\n' "$((END_TS - START_TS))"
printf 'Failures        : %d\n' "${#FAILURES[@]}"
for f in "${FAILURES[@]+"${FAILURES[@]}"}"; do printf '  - %s\n' "$f"; done

[[ ${#FAILURES[@]} -eq 0 ]] && exit 0 || exit 1
