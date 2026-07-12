#!/usr/bin/env bash
# test_runner.sh — COMPATIBILITY SHIM. The real runner is scripts/test_all.sh.
#
# WHY THIS FILE IS NOW DELEGATION ONLY:
#
#   This script used to carry its own BY-NAME list of 15 packages (10 dart + 5 flutter).
#   ci.yml carried a DIFFERENT by-name list of 12. They disagreed in BOTH directions:
#     - only in test_runner : adaptive_reroute, navigation_safety_core,
#                             route_condition_forecast, snow_rendering
#     - only in ci.yml      : vehicle_condition_fusion
#   and NEITHER covered the 36 packages that actually have test/ suites — 23 were never
#   run by CI at all, including navigation_safety_core's 309 tests.
#
#   A developer running this script green therefore did NOT run what CI runs, and CI
#   green did NOT mean the monorepo was green. Two lists that disagree are worse than
#   one list, because each looks like corroboration of the other.
#
#   There is now exactly ONE source of truth — scripts/discover_packages.sh — consumed
#   by exactly ONE runner, scripts/test_all.sh, which CI and this shim both call.
#   If a by-name list ever reappears in this repo, the divergence has merely relocated.
#
# Every flag is forwarded (--dart-only / --flutter-only / --coverage / --concurrency=N).
# The /tmp kernel-cleanup that was this script's original reason for existing (flutter
# test compiles 1-5 GB kernels; an OOM SIGKILL bypasses cleanup traps, so they
# accumulate across retries) lives on in test_all.sh's cleanup_kernels().

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# stderr, not stdout — otherwise this banner corrupts pipeable output like `--list`.
printf '[test_runner.sh] delegating to scripts/test_all.sh (single discovery-driven runner)\n\n' >&2

# --coverage was accepted by the old script; test_all.sh does not add coverage flags
# (CI collects coverage in its own step). Accept and drop it rather than fail a
# developer's muscle memory.
ARGS=()
for a in "$@"; do
  [[ "$a" == "--coverage" ]] && continue
  ARGS+=("$a")
done

exec "$ROOT_DIR/scripts/test_all.sh" "${ARGS[@]+"${ARGS[@]}"}"
