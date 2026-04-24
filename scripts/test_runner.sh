#!/usr/bin/env bash
# test_runner.sh — disk-bounded SNGNav monorepo test runner
#
# Root cause: flutter test compiles all test files into a single
# /tmp/dart_test.kernel.RANDOM (1-5 GB). SIGKILL (OOM) bypasses
# cleanup hooks → files accumulate across failed retries.
#
# This script bounds peak /tmp usage to O(1 package) by cleaning
# AFTER each subprocess exits — immune to SIGKILL in child.
#
# Usage:
#   ./scripts/test_runner.sh              # full suite
#   ./scripts/test_runner.sh --dart-only  # 9 pure-Dart packages only (~50 MB /tmp)
#   ./scripts/test_runner.sh --flutter-only  # Flutter packages + root app
#   ./scripts/test_runner.sh --coverage   # add --coverage to flutter tests
#   ./scripts/test_runner.sh --concurrency=1  # serialize kernel compilation (safer)
#
# Environment:
#   TMPDIR=/path/with/space  → redirect flutter kernel files off /tmp
#                               (flutter_tools resolves TMPDIR via systemTempDirectory)

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE_DART=1
MODE_FLUTTER=1
MODE_COVERAGE=0
CONCURRENCY=()  # empty = default; set to ("--concurrency=1") for serialized

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dart-only)      MODE_FLUTTER=0 ;;
    --flutter-only)   MODE_DART=0 ;;
    --coverage)       MODE_COVERAGE=1 ;;
    --concurrency=*)  CONCURRENCY=("$1") ;;
    --help)
      cat <<'EOF'
Usage: ./scripts/test_runner.sh [--dart-only|--flutter-only] [--coverage] [--concurrency=N]

  --dart-only       Only run pure-Dart packages (dart test, ~50 MB /tmp, no kernel files)
  --flutter-only    Only run Flutter packages + root app
  --coverage        Add --coverage to flutter test (increases kernel size ~30%)
  --concurrency=1   Serialize kernel compilation (prevents N parallel 1-5GB kernel files)
                    Recommended when hitting OOM. flutter test default = cpu_count-1.
  TMPDIR=/path      Export before calling to redirect kernel files to a different volume
  --help            Show this help
EOF
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1"; exit 2 ;;
  esac
  shift
done

# ── /tmp cleanup ───────────────────────────────────────────────────────────────
# Removes dart_test.kernel.* files created by flutter test.
# Called AFTER each subprocess exits (not via trap) — immune to SIGKILL in child.
# Note: trap 'cleanup' EXIT is also set as a fallback for graceful signals.
cleanup_kernels() {
  # dart_test.kernel.* and dart_test.vm.* are DIRECTORIES (not files).
  # Each contains per-test .dill files (~85 MB each). Use rm -rf, not find -delete.
  local count
  count=$(find /tmp -maxdepth 1 -name 'dart_test.kernel.*' -o -name 'dart_test.vm.*' 2>/dev/null | wc -l || echo 0)
  if [[ "$count" -gt 0 ]]; then
    local mb
    mb=$(du -sm /tmp/dart_test.kernel.* /tmp/dart_test.vm.* 2>/dev/null | \
         awk '{s+=$1}END{print s+0}')
    rm -rf /tmp/dart_test.kernel.* /tmp/dart_test.vm.* 2>/dev/null || true
    printf '[cleanup] %d kernel dir(s) removed (~%dMB freed)\n' "$count" "$mb"
  fi
}
# Fallback trap for graceful signals (SIGTERM, INT, ERR)
# Does NOT fire on SIGKILL — hence we also clean after each subprocess exits.
trap 'cleanup_kernels' EXIT INT TERM

FAILURES=()
FLUTTER_EXTRA=()
[[ "$MODE_COVERAGE" -eq 1 ]] && FLUTTER_EXTRA+=("--coverage")

# ── Pure-Dart packages: dart test ─────────────────────────────────────────────
# These packages have NO flutter: sdk dependency and NO dart:ui imports.
# dart test uses per-file VM JIT — no /tmp kernel files, no flutter_build dir.
# Verified: adaptive_reroute, driving_conditions, driving_consent, driving_weather,
#           fleet_hazard, kalman_dr, route_condition_forecast, routing_engine, snow_rendering
DART_PACKAGES=(
  adaptive_reroute
  driving_conditions
  driving_consent
  driving_weather
  fleet_hazard
  kalman_dr
  route_condition_forecast
  routing_engine
  snow_rendering
)

# ── Flutter-dependent packages: flutter test ──────────────────────────────────
# These packages require the Flutter test runner (dart:ui, WidgetTester, etc.)
FLUTTER_PACKAGES=(
  map_viewport_bloc
  navigation_safety
  offline_tiles
  routing_bloc
  voice_guidance
)

run_dart_pkg() {
  local pkg="$1"
  printf '\n==> dart test: %s\n' "$pkg"
  local exit_code=0
  # Subprocess: dart test. No /tmp kernel files generated.
  (cd "packages/$pkg" && dart test --reporter compact) || exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    printf 'PASS: %s\n' "$pkg"
  else
    FAILURES+=("pkg:$pkg")
    printf 'FAIL: %s (exit %d)\n' "$pkg" "$exit_code"
  fi
}

run_flutter_pkg() {
  local pkg="$1"
  printf '\n==> flutter test: %s\n' "$pkg"
  local exit_code=0
  # --concurrency=1: serializes kernel compilation within this package.
  # Prevents (cpu_count-1) parallel kernel files coexisting in /tmp.
  # Subprocess exits completely before cleanup_kernels is called — safe vs SIGKILL.
  (cd "packages/$pkg" && flutter test --reporter compact \
    "${CONCURRENCY[@]}" "${FLUTTER_EXTRA[@]+"${FLUTTER_EXTRA[@]}"}") \
    || exit_code=$?
  # Cleanup AFTER subprocess exits. This is the SIGKILL-safe pattern:
  # even if the child was OOM-killed, it has fully exited here.
  cleanup_kernels
  if [[ $exit_code -eq 0 ]]; then
    printf 'PASS: %s\n' "$pkg"
  else
    FAILURES+=("pkg:$pkg")
    printf 'FAIL: %s (exit %d)\n' "$pkg" "$exit_code"
  fi
}

# ── Pre-run: clean existing orphaned kernels ──────────────────────────────────
printf '==> Pre-run: checking for orphaned /tmp/dart_test.kernel.* files\n'
cleanup_kernels

# ── Execute ───────────────────────────────────────────────────────────────────

if [[ "$MODE_DART" -eq 1 ]]; then
  printf '\n── Pure-Dart packages (dart test — zero /tmp kernel footprint) ──\n'
  for pkg in "${DART_PACKAGES[@]}"; do
    run_dart_pkg "$pkg"
  done
fi

if [[ "$MODE_FLUTTER" -eq 1 ]]; then
  printf '\n── Flutter packages (flutter test + per-package kernel cleanup) ──\n'
  for pkg in "${FLUTTER_PACKAGES[@]}"; do
    run_flutter_pkg "$pkg"
  done

  printf '\n── Root app ──────────────────────────────────────────────────────\n'
  printf '==> flutter test: root app\n'
  local_exit=0
  flutter test --reporter compact --exclude-tags=probe \
    "${CONCURRENCY[@]}" "${FLUTTER_EXTRA[@]+"${FLUTTER_EXTRA[@]}"}" \
    || local_exit=$?
  cleanup_kernels
  if [[ $local_exit -eq 0 ]]; then
    printf 'PASS: root app\n'
  else
    FAILURES+=("root app")
    printf 'FAIL: root app (exit %d)\n' "$local_exit"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n=== Summary ===\n'
printf 'Failures: %d\n' "${#FAILURES[@]}"
for f in "${FAILURES[@]}"; do
  printf '  - %s\n' "$f"
done

[[ ${#FAILURES[@]} -eq 0 ]] && exit 0 || exit 1
